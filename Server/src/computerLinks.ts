import type { Env } from "./contracts";
import { cleanText, isoSeconds, json, sha256, wholeSeconds } from "./util";

/** "Approve this computer from your phone".
 *
 *  A computer that cannot sign in with Apple or Google itself - the reporting
 *  website, the Darul Irfan desktop app for Windows and macOS - asks for a
 *  short code and shows it. The member types it (or scans its QR) in the app on
 *  a phone that is already signed in, and the computer, polling with a secret
 *  only it holds, receives a session of its own for that same account.
 *
 *  Both clients share one table (reporting_links, with its `client` column) and
 *  the helpers below; they differ in who may approve and what the session is:
 *    reporting - Markaz officers only, 12 hours, /v1/markaz/* only (markaz.ts);
 *    desktop   - any signed-in member, 30 days kept fresh by use, every member
 *                route, with the member's own role (this file). */

/** Codes are read off a screen and typed by hand, so the alphabet leaves out
 *  the characters people confuse: no 0/O, no 1/I/L, no 8/B. */
export const LINK_ALPHABET = "ACDEFGHJKMNPQRSTUVWXYZ2345679";
/** How long a code stays open for approval. */
export const LINK_MINUTES = 5;
const LINK_LENGTH = 8;
const DESKTOP_DAYS = 30;
/** A desktop session's expiry moves forward with use, at most this often (one write). */
const DESKTOP_REFRESH_MS = 300_000;
const DAY = 86_400_000;
const PLATFORMS = new Set(["windows", "macos"]);

export const randomHex = (bytes = 32): string =>
  [...crypto.getRandomValues(new Uint8Array(bytes))].map(byte => byte.toString(16).padStart(2, "0")).join("");

/** Eight symbols from the alphabet, without the modulo bias: a byte at or
 *  above the largest multiple of the alphabet's length is drawn again. */
export function newLinkCode(): string {
  const limit = 256 - (256 % LINK_ALPHABET.length);
  let code = "";
  while (code.length < LINK_LENGTH) {
    for (const byte of crypto.getRandomValues(new Uint8Array(16))) {
      if (byte < limit && code.length < LINK_LENGTH) code += LINK_ALPHABET[byte % LINK_ALPHABET.length];
    }
  }
  return code;
}

/** What a person actually types: any case, spaces, dashes. */
export const normaliseLinkCode = (raw: unknown): string =>
  typeof raw === "string" ? raw.toUpperCase().replace(/[^A-Z0-9]/g, "") : "";

/** "ABCD-EFGH", as computers show it. */
export const formatLinkCode = (code: string): string => `${code.slice(0, 4)}-${code.slice(4)}`;

/** A code worth looking up: exactly eight symbols from the alphabet. */
export const isLinkCode = (code: string): boolean =>
  code.length === LINK_LENGTH && [...code].every(symbol => LINK_ALPHABET.includes(symbol));

/** A new open link for a client. Old ones are cleared out on the way. */
export async function openLink(
  env: Env, client: "reporting" | "desktop", device: { name: string; platform: string } | null = null,
): Promise<{ code: string; pollToken: string; expiresAt: string }> {
  const code = newLinkCode();
  const pollToken = randomHex();
  const now = new Date();
  const expires = new Date(now.getTime() + LINK_MINUTES * 60_000);
  await env.DB.prepare("DELETE FROM reporting_links WHERE expires_at<?").bind(new Date(now.getTime() - DAY).toISOString()).run();
  await env.DB.prepare(`INSERT INTO reporting_links(code_hash,poll_hash,created_at,expires_at,client,device_name,platform)
    VALUES(?,?,?,?,?,?,?)`)
    .bind(await sha256(code), await sha256(pollToken), now.toISOString(), expires.toISOString(), client, device?.name ?? null, device?.platform ?? null).run();
  return { code: formatLinkCode(code), pollToken, expiresAt: wholeSeconds(expires) };
}

// MARK: - The desktop app

const badRequest = (error: string) => json({ error }, { status: 400 });
/** One answer for a wrong, used and expired code alike, so the endpoint is no oracle. */
const unknownCode = () => json({ error: "That code is not valid or has expired. Start again on the computer for a new one." }, { status: 404 });

/** Bidirectional controls would let a computer's name pretend to be something
 *  else on the phone that approves it ("‮swodniw"), so they are removed. */
const deviceName = (value: unknown): string | undefined =>
  cleanText(typeof value === "string" ? value.replace(/[‎‏‪-‮⁦-⁩]/g, "") : value, 60);

/** POST /v1/members/computer-link {deviceName, platform: "windows"|"macos"} - no sign-in.
 *  201 {code: "ABCD-EFGH", pollToken, expiresAt, pollInterval, qr}. */
export async function startComputerLink(request: Request, env: Env): Promise<Response> {
  const input = await request.json<Record<string, unknown>>().catch(() => null);
  if (!input || typeof input !== "object" || Array.isArray(input)) return badRequest("Invalid request");
  const name = deviceName(input.deviceName);
  if (!name) return badRequest("Name this computer.");
  const platform = typeof input.platform === "string" ? input.platform.trim().toLowerCase() : "";
  if (!PLATFORMS.has(platform)) return badRequest("platform must be \"windows\" or \"macos\".");
  const link = await openLink(env, "desktop", { name, platform });
  // The QR carries the same code, in a form the phone's camera recognises.
  return json({ ...link, pollInterval: 3, qr: `darulirfan://approve-computer?code=${link.code}` }, { status: 201 });
}

/** POST /v1/members/computer-link/poll {pollToken} - no sign-in; the poll token is the secret.
 *  {status: "pending"} | {status: "expired"} | {status: "approved", token, expiresAt, memberID} (once). */
export async function pollComputerLink(request: Request, env: Env): Promise<Response> {
  const input = await request.json<Record<string, unknown>>().catch(() => null);
  const token = input && typeof input.pollToken === "string" && /^[0-9a-f]{64}$/.test(input.pollToken) ? input.pollToken : "";
  if (!token) return badRequest("Invalid request");
  const hash = await sha256(token);
  const row = await env.DB.prepare(`SELECT expires_at,approved_by,consumed_at,device_name,platform FROM reporting_links
    WHERE poll_hash=? AND client='desktop'`).bind(hash)
    .first<{ expires_at: string; approved_by: string | null; consumed_at: string | null; device_name: string | null; platform: string | null }>();
  const now = new Date();
  const open = !!row && !row.consumed_at && Date.parse(row.expires_at) > now.getTime();
  if (!row || !open) return json({ status: "expired" });
  if (!row.approved_by) return json({ status: "pending" });
  // Approved: the computer gets its session, once. The claim repeats every
  // condition, so two polls racing cannot both get one.
  const claimed = await env.DB.prepare(`UPDATE reporting_links SET consumed_at=?
      WHERE poll_hash=? AND client='desktop' AND consumed_at IS NULL AND expires_at>? AND approved_by=?`)
    .bind(now.toISOString(), hash, now.toISOString(), row.approved_by).run();
  if ((claimed.meta?.changes ?? 0) === 0) return json({ status: "expired" });
  const session = randomHex();
  const expires = new Date(now.getTime() + DESKTOP_DAYS * DAY);
  await env.DB.prepare(`INSERT INTO member_sessions(token_hash,member_id,created_at,expires_at,last_seen_at,client,device_name,platform)
    VALUES(?,?,?,?,?,'desktop',?,?)`)
    .bind(await sha256(session), row.approved_by, now.toISOString(), expires.toISOString(), now.toISOString(), row.device_name, row.platform).run();
  return json({ status: "approved", token: session, expiresAt: wholeSeconds(expires), memberID: row.approved_by });
}

/** An open desktop link by its code, or null. */
async function openDesktopLink(env: Env, code: string): Promise<{ code_hash: string; device_name: string; platform: string; expires_at: string } | null> {
  return env.DB.prepare(`SELECT code_hash,device_name,platform,expires_at FROM reporting_links
      WHERE code_hash=? AND client='desktop' AND expires_at>? AND approved_by IS NULL AND consumed_at IS NULL`)
    .bind(await sha256(code), new Date().toISOString())
    .first<{ code_hash: string; device_name: string; platform: string; expires_at: string }>();
}

/** POST /v1/members/computer-link/preview {code} - the phone shows which computer
 *  is asking before the member confirms. {deviceName, platform, expiresAt}. */
export async function previewComputerLink(env: Env, input: Record<string, unknown>): Promise<Response> {
  const code = normaliseLinkCode(input.code);
  if (!isLinkCode(code)) return badRequest("Type the 8 characters shown on the computer.");
  const link = await openDesktopLink(env, code);
  if (!link) return unknownCode();
  return json({ deviceName: link.device_name, platform: link.platform, expiresAt: isoSeconds(link.expires_at) });
}

/** POST /v1/members/computer-link/approve {code} - from the app on a signed-in
 *  phone only (index.ts refuses a computer's own session). {ok, deviceName, platform}. */
export async function approveComputerLink(env: Env, memberID: string, input: Record<string, unknown>): Promise<Response> {
  const code = normaliseLinkCode(input.code);
  if (!isLinkCode(code)) return badRequest("Type the 8 characters shown on the computer.");
  const now = new Date().toISOString();
  const result = await env.DB.prepare(`UPDATE reporting_links SET approved_by=?,approved_at=?
      WHERE code_hash=? AND client='desktop' AND expires_at>? AND approved_by IS NULL AND consumed_at IS NULL`)
    .bind(memberID, now, await sha256(code), now).run();
  if ((result.meta?.changes ?? 0) === 0) return unknownCode();
  const link = await env.DB.prepare("SELECT device_name,platform FROM reporting_links WHERE code_hash=?")
    .bind(await sha256(code)).first<{ device_name: string; platform: string }>();
  await env.DB.prepare("INSERT INTO audit_log(actor_email,action,entity_type,entity_id,before_json,after_json,created_at) VALUES(?,?,?,?,?,?,?)")
    .bind(`member:${memberID}`, "approve", "computer-link", code.slice(0, 2) + "******", null,
      JSON.stringify({ platform: link?.platform ?? null }), now).run();
  return json({ ok: true, deviceName: link?.device_name ?? "", platform: link?.platform ?? "" });
}

/** GET /v1/members/computers - this member's signed-in computers, newest first.
 *  The id is the start of the session's hash: enough to name it, useless to sign in with. */
export async function listComputers(env: Env, memberID: string, currentHash: string | null): Promise<Response> {
  const rows = await env.DB.prepare(`SELECT token_hash,device_name,platform,created_at,last_seen_at,expires_at FROM member_sessions
      WHERE member_id=? AND client='desktop' AND expires_at>? ORDER BY created_at DESC`)
    .bind(memberID, new Date().toISOString())
    .all<{ token_hash: string; device_name: string | null; platform: string | null; created_at: string; last_seen_at: string; expires_at: string }>();
  return json({
    computers: (rows.results ?? []).map(row => ({
      id: row.token_hash.slice(0, 12), name: row.device_name ?? "Computer", platform: row.platform ?? "windows",
      createdAt: isoSeconds(row.created_at), lastSeenAt: isoSeconds(row.last_seen_at), expiresAt: isoSeconds(row.expires_at),
      current: row.token_hash === currentHash,
    })),
  });
}

/** DELETE /v1/members/computers/{id} signs one computer out; DELETE /v1/members/computers, all of them. */
export async function signOutComputers(env: Env, memberID: string, id: string | null): Promise<Response> {
  if (id !== null && !/^[0-9a-f]{12}$/.test(id)) return json({ error: "Not found" }, { status: 404 });
  const result = id === null
    ? await env.DB.prepare("DELETE FROM member_sessions WHERE member_id=? AND client='desktop'").bind(memberID).run()
    : await env.DB.prepare("DELETE FROM member_sessions WHERE member_id=? AND client='desktop' AND substr(token_hash,1,12)=?").bind(memberID, id).run();
  if (id !== null && (result.meta?.changes ?? 0) === 0) return json({ error: "Not found" }, { status: 404 });
  return new Response(null, { status: 204 });
}

/** A desktop session in use stays signed in: its 30 days start again, written at
 *  most every five minutes. The reporting website's sessions only note the use. */
export async function noteComputerUse(env: Env, hash: string, client: string | null, lastSeenAt: string): Promise<void> {
  if (client !== "desktop" && client !== "reporting") return;
  const now = Date.now();
  if (now - Date.parse(lastSeenAt) <= DESKTOP_REFRESH_MS) return;
  if (client === "desktop") {
    await env.DB.prepare("UPDATE member_sessions SET last_seen_at=?,expires_at=? WHERE token_hash=?")
      .bind(new Date(now).toISOString(), new Date(now + DESKTOP_DAYS * DAY).toISOString(), hash).run();
  } else {
    await env.DB.prepare("UPDATE member_sessions SET last_seen_at=? WHERE token_hash=?").bind(new Date(now).toISOString(), hash).run();
  }
}
