import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";
import type { Env } from "./contracts";
import { cleanText, json, sha256, validHTTPURL } from "./util";

/** Private regional groups. Members sign in with Apple, admins publish, members
 * read; there is no member-to-member messaging, so nothing a member writes is
 * ever shown to another member.
 *
 * The security property here is isolation: a post belongs to exactly one group
 * and reading it requires a membership row for that group. A member of one
 * region must never learn what another region was told, nor even that a group
 * exists, which is why a group the caller does not belong to answers exactly as
 * a group that does not exist. */

const APPLE_ISSUER = "https://appleid.apple.com";
const SESSION_DAYS = 90;
let appleKeys: ReturnType<typeof createRemoteJWKSet> | undefined;

/** The audience of an Apple identity token is the app's bundle identifier,
 * which is also what APNs calls its topic. */
const clientID = (env: Env): string => env.APPLE_CLIENT_ID ?? env.APNS_TOPIC;

function hexOf(bytes: Uint8Array): string {
  return [...bytes].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

/** Verifies Apple's signed identity token. An unverified subject from the
 * client would let anyone claim any member's identity, so this is the whole
 * basis of membership. */
export async function appleSubject(
  token: string,
  env: Env,
  resolveKey?: JWTVerifyGetKey,
): Promise<{ subject: string; email?: string } | null> {
  const audience = clientID(env);
  if (!audience || !token) return null;
  try {
    let keys = resolveKey ?? appleKeys;
    if (!keys) {
      appleKeys = createRemoteJWKSet(new URL(`${APPLE_ISSUER}/auth/keys`));
      keys = appleKeys;
    }
    const { payload } = await jwtVerify(token, keys, {
      issuer: APPLE_ISSUER,
      audience,
      algorithms: ["RS256"],
      requiredClaims: ["exp", "iat", "sub"],
    });
    const subject = typeof payload.sub === "string" ? payload.sub.trim() : "";
    if (!subject) return null;
    const email = typeof payload.email === "string" ? payload.email.trim().toLowerCase() : undefined;
    return { subject, email };
  } catch {
    return null;
  }
}

/** Exchanges an Apple identity token for one of our bearer tokens.
 *
 * Signing in creates the member but grants no access on its own: a new member
 * belongs to no group until an admin adds them, so an uninvited sign-in sees
 * nothing at all. */
export async function createSession(request: Request, env: Env, resolveKey?: JWTVerifyGetKey): Promise<Response> {
  const input = await request.json<{ identityToken?: string; displayName?: string }>();
  const verified = await appleSubject(String(input?.identityToken ?? ""), env, resolveKey);
  if (!verified) return json({ error: "Apple identity could not be verified" }, { status: 401 });

  const now = new Date();
  const nowISO = now.toISOString();
  const expires = new Date(now.getTime() + SESSION_DAYS * 86_400_000).toISOString();
  const subjectHash = await sha256(`member:${verified.subject}`);
  const memberID = subjectHash.slice(0, 32);

  // Apple discloses a name only on the first authorisation, so a later sign-in
  // must not overwrite a known name with nothing.
  await env.DB.prepare(`INSERT INTO members(id,apple_subject,display_name,email,created_at,last_seen_at)
    VALUES(?,?,?,?,?,?)
    ON CONFLICT(apple_subject) DO UPDATE SET
      last_seen_at=excluded.last_seen_at,
      display_name=COALESCE(excluded.display_name,members.display_name),
      email=COALESCE(excluded.email,members.email)`)
    .bind(memberID, verified.subject, cleanText(input?.displayName, 80) ?? null,
      verified.email ?? null, nowISO, nowISO).run();

  const row = await env.DB.prepare("SELECT id FROM members WHERE apple_subject=?")
    .bind(verified.subject).first<{ id: string }>();
  const id = row?.id ?? memberID;
  // Groups an admin added this email to before the person signed in.
  if (verified.email) await claimEmailGrants(env, id, verified.email);

  const token = hexOf(crypto.getRandomValues(new Uint8Array(32)));
  await env.DB.prepare("INSERT INTO member_sessions(token_hash,member_id,created_at,expires_at,last_seen_at) VALUES(?,?,?,?,?)")
    .bind(await sha256(token), id, nowISO, expires, nowISO).run();

  return json({ token, expiresAt: expires, memberID: id }, { status: 201 });
}

/** Resolves the bearer token to a member, or null. Only the hash is compared,
 * and an expired session is treated as absent. */
export async function authenticatedMember(request: Request, env: Env): Promise<string | null> {
  const header = request.headers.get("authorization") ?? "";
  if (!header.toLowerCase().startsWith("bearer ")) return null;
  const token = header.slice(7).trim();
  if (!/^[0-9a-f]{64}$/.test(token)) return null;
  const row = await env.DB.prepare("SELECT member_id,expires_at FROM member_sessions WHERE token_hash=?")
    .bind(await sha256(token)).first<{ member_id: string; expires_at: string }>();
  if (!row || Date.parse(row.expires_at) <= Date.now()) return null;
  return row.member_id;
}

/** The groups this member belongs to, and nothing else: the catalogue of groups
 * is itself private. */
export async function listGroups(env: Env, memberID: string): Promise<Response> {
  const result = await env.DB.prepare(`SELECT g.id,g.name,g.description,g.meeting_url,g.meeting_note
    FROM member_groups g JOIN member_group_members m ON m.group_id=g.id
    WHERE m.member_id=? AND g.is_active=1 ORDER BY g.name`).bind(memberID).all();
  return json({
    groups: (result.results ?? []).map(row => ({
      id: row.id, name: row.name, description: row.description ?? undefined,
      meetingURL: row.meeting_url ?? undefined, meetingNote: row.meeting_note ?? undefined,
    })),
  });
}

/** Posts for one group, refused unless the caller belongs to it.
 *
 * A group the caller is not in answers 404, exactly as an unknown group does,
 * so the response never reveals that another region's group exists. */
export async function groupPosts(env: Env, memberID: string, groupID: string, limit: number): Promise<Response> {
  const member = await env.DB.prepare("SELECT 1 AS ok FROM member_group_members WHERE group_id=? AND member_id=?")
    .bind(groupID, memberID).first<{ ok: number }>();
  if (!member) return json({ error: "Not found" }, { status: 404 });

  const result = await env.DB.prepare(`SELECT id,kind,title,body,youtube_video_id,link_url,published_at
    FROM member_group_posts WHERE group_id=? AND is_hidden=0
    ORDER BY published_at DESC, id DESC LIMIT ?`).bind(groupID, limit).all();
  return json({
    groupID,
    posts: (result.results ?? []).map(row => ({
      id: row.id, kind: row.kind, title: row.title, body: row.body ?? undefined,
      youtubeVideoID: row.youtube_video_id ?? undefined,
      linkURL: row.link_url ?? undefined, publishedAt: row.published_at,
    })),
  });
}

/** Deletes the member, their sessions and their memberships.
 *
 * Apple requires an account created in the app to be deletable from inside it.
 * Posts belong to the organisation, not the member, so nothing published is
 * lost; the cascades remove everything that is about this person. */
export async function deleteMember(env: Env, memberID: string): Promise<Response> {
  await env.DB.prepare("DELETE FROM member_sessions WHERE member_id=?").bind(memberID).run();
  await env.DB.prepare("DELETE FROM member_devices WHERE member_id=?").bind(memberID).run();
  await env.DB.prepare("DELETE FROM member_group_members WHERE member_id=?").bind(memberID).run();
  await env.DB.prepare("DELETE FROM members WHERE id=?").bind(memberID).run();
  return new Response(null, { status: 204 });
}

/** Admin: publish to one group. Staff are authenticated by Cloudflare Access
 * upstream; the group is validated here so a typo cannot create an orphan. */
export async function publishGroupPost(
  env: Env, actor: string, groupID: string, postID: string, input: Record<string, unknown>,
): Promise<Response> {
  const group = await env.DB.prepare("SELECT 1 AS ok FROM member_groups WHERE id=?")
    .bind(groupID).first<{ ok: number }>();
  if (!group) return json({ error: "Unknown group" }, { status: 404 });

  const kind = String(input.kind ?? "announcement");
  if (!["announcement", "zikr"].includes(kind)) return json({ error: "Invalid kind" }, { status: 400 });
  const title = cleanText(input.title, 300);
  if (!title) return json({ error: "A title is required" }, { status: 400 });
  const video = typeof input.youtubeVideoID === "string" && /^[\w-]{11}$/.test(input.youtubeVideoID)
    ? input.youtubeVideoID : undefined;
  if (kind === "zikr" && !video) return json({ error: "A recorded zikr needs a YouTube video id" }, { status: 400 });

  const now = new Date().toISOString();
  await env.DB.prepare(`INSERT INTO member_group_posts(id,group_id,kind,title,body,youtube_video_id,link_url,published_at,author_email,is_hidden,updated_at)
    VALUES(?,?,?,?,?,?,?,?,?,?,?)
    ON CONFLICT(id) DO UPDATE SET title=excluded.title,body=excluded.body,
      youtube_video_id=excluded.youtube_video_id,link_url=excluded.link_url,
      is_hidden=excluded.is_hidden,updated_at=excluded.updated_at`)
    .bind(postID, groupID, kind, title, cleanText(input.body, 8_000) ?? null, video ?? null,
      validHTTPURL(input.linkURL) ?? null, now, actor, input.isHidden ? 1 : 0, now).run();
  return json({ ok: true, id: postID, groupID });
}

/** Gives a member a place in a group, or changes the role of the place they
 *  have. `promoteOnly` never lowers an admin to member (a member code handed
 *  to an admin must not demote them). */
export async function upsertMembership(
  env: Env, groupID: string, memberID: string, role: "member" | "admin", addedBy: string, promoteOnly: boolean,
): Promise<void> {
  const update = promoteOnly
    ? "role=CASE WHEN excluded.role='admin' THEN 'admin' ELSE member_group_members.role END"
    : "role=excluded.role";
  await env.DB.prepare(`INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES(?,?,?,?,?)
    ON CONFLICT(group_id,member_id) DO UPDATE SET ${update}`)
    .bind(groupID, memberID, new Date().toISOString(), addedBy, role).run();
}

/** Admits a member to every group an admin added their email to. */
export async function claimEmailGrants(env: Env, memberID: string, email: string): Promise<void> {
  const address = email.trim().toLowerCase();
  const grants = await env.DB.prepare("SELECT id,group_id,role,created_by FROM member_group_grants WHERE email=? AND claimed_at IS NULL")
    .bind(address).all<{ id: string; group_id: string; role: string; created_by: string }>();
  for (const grant of grants.results ?? []) {
    await upsertMembership(env, grant.group_id, memberID, grant.role === "admin" ? "admin" : "member", grant.created_by, true);
    await env.DB.prepare("UPDATE member_group_grants SET claimed_by=?,claimed_at=? WHERE id=?")
      .bind(memberID, new Date().toISOString(), grant.id).run();
  }
}

/** Admin: add or remove one member's place in a group. */
export async function setGroupMembership(
  env: Env, actor: string, groupID: string, memberID: string, isMember: boolean,
): Promise<Response> {
  const group = await env.DB.prepare("SELECT 1 AS ok FROM member_groups WHERE id=?")
    .bind(groupID).first<{ ok: number }>();
  if (!group) return json({ error: "Unknown group" }, { status: 404 });
  if (!isMember) {
    await env.DB.prepare("DELETE FROM member_group_members WHERE group_id=? AND member_id=?")
      .bind(groupID, memberID).run();
    return json({ ok: true, groupID, memberID, member: false });
  }
  const known = await env.DB.prepare("SELECT 1 AS ok FROM members WHERE id=?")
    .bind(memberID).first<{ ok: number }>();
  if (!known) return json({ error: "That member has not signed in yet" }, { status: 404 });
  await env.DB.prepare("INSERT OR IGNORE INTO member_group_members(group_id,member_id,added_at,added_by) VALUES(?,?,?,?)")
    .bind(groupID, memberID, new Date().toISOString(), actor).run();
  return json({ ok: true, groupID, memberID, member: true });
}

// MARK: - Invite codes

/** Codes read aloud or typed by hand, so the alphabet omits the characters
 *  people confuse: no 0/O, no 1/I/L, no 8/B. Ten symbols from this 26-letter
 *  alphabet is about 47 bits, which a rate-limited endpoint makes unguessable. */
const CODE_ALPHABET = "ACDEFGHJKMNPQRSTUVWXYZ2345679";

/** Accepts what a member actually types: lower case, spaces, dashes. */
function normaliseCode(raw: string): string {
  return raw.toUpperCase().replace(/[^A-Z0-9]/g, "");
}

function formatCode(code: string): string {
  return `${code.slice(0, 5)}-${code.slice(5)}`;
}

export function generateInviteCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(10));
  return [...bytes].map(byte => CODE_ALPHABET[byte % CODE_ALPHABET.length]).join("");
}

/** Mints a single-use code admitting one person to one group, optionally as
 *  its admin. The code is returned once and never stored - only its hash is
 *  kept, so a leaked database cannot admit anyone. */
export async function mintInvite(
  env: Env, actor: string, groupID: string, days: number, label: string | null, grantsRole: "admin" | "superadmin" | null,
): Promise<{ code: string; expiresAt: string }> {
  const code = generateInviteCode();
  const now = new Date();
  const expiresAt = new Date(now.getTime() + days * 86_400_000).toISOString();
  await env.DB.prepare(`INSERT INTO member_invites(code_hash,group_id,label,created_by,created_at,expires_at,grants_role)
    VALUES(?,?,?,?,?,?,?)`)
    .bind(await sha256(code), groupID, label, actor, now.toISOString(), expiresAt, grantsRole).run();
  return { code: formatCode(code), expiresAt };
}

/** Staff admin page: mint a code for a group. */
export async function createInvite(
  env: Env, actor: string, groupID: string, input: Record<string, unknown>,
): Promise<Response> {
  const group = await env.DB.prepare("SELECT 1 AS ok FROM member_groups WHERE id=?")
    .bind(groupID).first<{ ok: number }>();
  if (!group) return json({ error: "Unknown group" }, { status: 404 });

  const days = Number(input.expiresInDays ?? 30);
  if (!Number.isInteger(days) || days < 1 || days > 365) {
    return json({ error: "expiresInDays must be a whole number from 1 to 365" }, { status: 400 });
  }
  const grantsRole = input.grantsRole === "admin" || input.grantsRole === "superadmin" ? input.grantsRole : null;
  const { code } = await mintInvite(env, actor, groupID, days, cleanText(input.label, 120) ?? null, grantsRole);
  // Shown to the admin once, to pass to the person it is for.
  return json({ ok: true, groupID, code, expiresInDays: days, grantsRole: grantsRole ?? undefined }, { status: 201 });
}

/** Redeems a code: creates the member if needed, starts a session, and admits
 *  them to exactly the group the code was minted for.
 *
 *  Unlike signing in, redeeming IS admission - an administrator already decided
 *  that by issuing the code. It stays single-use so a forwarded code cannot let
 *  a second person in. */
export async function redeemInvite(request: Request, env: Env): Promise<Response> {
  const input = await request.json<{ code?: string; displayName?: string }>();
  const code = normaliseCode(String(input?.code ?? ""));
  if (code.length < 8 || code.length > 20) return json({ error: "That invitation code is not valid." }, { status: 400 });

  const row = await env.DB.prepare(`SELECT group_id,expires_at,redeemed_at,grants_role FROM member_invites WHERE code_hash=?`)
    .bind(await sha256(code)).first<{ group_id: string; expires_at: string; redeemed_at: string | null; grants_role?: string | null }>();
  // One message for every failure: a wrong code must not be distinguishable
  // from a used or expired one, or the endpoint becomes an oracle.
  const refusal = json({ error: "That invitation code is not valid, or has already been used." }, { status: 403 });
  if (!row || row.redeemed_at || Date.parse(row.expires_at) <= Date.now()) return refusal;

  const now = new Date();
  const nowISO = now.toISOString();
  // Someone already signed in who is given a second code (another group, or
  // an admin role) stays one member rather than becoming two.
  const existing = await authenticatedMember(request, env);
  // Invite members have no platform identity, so the external-identity column
  // carries a random one of ours. It stays unique and non-null without needing
  // the members table rebuilt.
  const subject = `invite:${crypto.randomUUID()}`;
  const memberID = existing ?? (await sha256(`member:${subject}`)).slice(0, 32);
  if (!existing) {
    await env.DB.prepare(`INSERT INTO members(id,apple_subject,display_name,email,created_at,last_seen_at)
      VALUES(?,?,?,NULL,?,?)`)
      .bind(memberID, subject, cleanText(input?.displayName, 80) ?? null, nowISO, nowISO).run();
  }

  // Mark redeemed only if still open, so two simultaneous redemptions cannot
  // both succeed on one code.
  const claim = await env.DB.prepare(`UPDATE member_invites SET redeemed_by=?,redeemed_at=?
    WHERE code_hash=? AND redeemed_at IS NULL`)
    .bind(memberID, nowISO, await sha256(code)).run();
  if ((claim.meta?.changes ?? 0) === 0) {
    if (!existing) await env.DB.prepare("DELETE FROM members WHERE id=?").bind(memberID).run();
    return refusal;
  }
  // An admin code makes them admin of this group only. A role only ever goes
  // up through a code: a member code given to an admin does not demote them.
  if (row.grants_role === "superadmin") {
    await env.DB.prepare("UPDATE members SET role='superadmin' WHERE id=?").bind(memberID).run();
  }
  await upsertMembership(env, row.group_id, memberID, row.grants_role === "admin" ? "admin" : "member", "invite", true);

  const token = hexOf(crypto.getRandomValues(new Uint8Array(32)));
  const expires = new Date(now.getTime() + SESSION_DAYS * 86_400_000).toISOString();
  await env.DB.prepare("INSERT INTO member_sessions(token_hash,member_id,created_at,expires_at,last_seen_at) VALUES(?,?,?,?,?)")
    .bind(await sha256(token), memberID, nowISO, expires, nowISO).run();

  return json({ token, expiresAt: expires, memberID, groupID: row.group_id }, { status: 201 });
}
