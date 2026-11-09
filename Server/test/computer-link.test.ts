// The desktop app's sign-in (2026-11-09): the computer shows a code, a member
// approves it in the app on a signed-in phone, and the computer gets a session
// of its own for that same account and role.
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { formatLinkCode, isLinkCode, LINK_ALPHABET, newLinkCode, normaliseLinkCode } from "../src/computerLinks";
import { sqliteD1 } from "./sqlite-d1";

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

const ADMIN = "a".repeat(32), MEMBER = "m".repeat(32), OTHER = "o".repeat(32);
const TOKENS = { [ADMIN]: "3".repeat(64), [MEMBER]: "4".repeat(64), [OTHER]: "5".repeat(64) };

async function setup() {
  const { db, raw } = sqliteD1();
  vi.stubGlobal("fetch", async () => new Response("", { status: 200 }));
  const now = new Date().toISOString(), later = new Date(Date.now() + 86_400_000).toISOString();
  for (const [id, name] of [[ADMIN, "Ameer"], [MEMBER, "Ali"], [OTHER, "Bilal"]] as const) {
    raw.prepare("INSERT INTO members(id,apple_subject,display_name,created_at,last_seen_at) VALUES(?,?,?,?,?)").run(id, `apple:${id}`, name, now, now);
    raw.prepare("INSERT INTO member_sessions(token_hash,member_id,created_at,expires_at,last_seen_at) VALUES(?,?,?,?,?)")
      .run(await sha256(TOKENS[id]!), id, now, later, now);
  }
  raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('usa',?,?,'test','administrator')").run(ADMIN, now);
  raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('usa',?,?,'test','member')").run(MEMBER, now);
  const env = { DB: db, PUBLIC_BASE_URL: "https://api.example.com" } as unknown as Env;
  const call = (token: string | null, method: string, path: string, body?: unknown, ip = "7.7.7.7") =>
    worker.fetch(new Request(`https://api.example.com${path}`, {
      method,
      headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), "cf-connecting-ip": ip, ...(body ? { "content-type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    }), env);
  /** The desktop app: no sign-in, its own address. */
  const desktop = (path: string, body?: unknown, ip = "8.8.8.8") => call(null, "POST", path, body ?? {}, ip);
  const start = async (deviceName = "Ali's laptop", platform = "windows") =>
    await (await desktop("/v1/members/computer-link", { deviceName, platform })).json() as { code: string; pollToken: string; expiresAt: string; qr: string };
  /** A computer signed in as `memberID`, through the whole flow. */
  const signIn = async (memberID: string, deviceName = "Ali's laptop", platform = "windows") => {
    const link = await start(deviceName, platform);
    expect((await call(TOKENS[memberID]!, "POST", "/v1/members/computer-link/approve", { code: link.code })).status).toBe(200);
    return await (await desktop("/v1/members/computer-link/poll", { pollToken: link.pollToken })).json() as { status: string; token: string; expiresAt: string; memberID: string };
  };
  return { raw, env, call, desktop, start, signIn };
}

afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

describe("computer sign-in codes", () => {
  it("are eight unambiguous symbols, shown as ABCD-EFGH, and read back however they are typed", () => {
    for (let i = 0; i < 200; i += 1) {
      const code = newLinkCode();
      expect(code).toHaveLength(8);
      expect([...code].every(symbol => LINK_ALPHABET.includes(symbol))).toBe(true);
      expect(isLinkCode(code)).toBe(true);
    }
    expect(LINK_ALPHABET).not.toMatch(/[01OIL8B]/);
    expect(formatLinkCode("ACDEFGHJ")).toBe("ACDE-FGHJ");
    expect(normaliseLinkCode(" acde-fghj ")).toBe("ACDEFGHJ");
    expect(normaliseLinkCode("ac de fg hj")).toBe("ACDEFGHJ");
    expect(normaliseLinkCode(42)).toBe("");
    expect(isLinkCode("ACDEFGH")).toBe(false);
    expect(isLinkCode("ACDEFGH0")).toBe(false);
  });
});

describe("desktop sign-in", () => {
  it("lets a computer in once a signed-in member approves its code, as that member, with every member route", async () => {
    const { call, desktop, start } = await setup();
    const link = await start();
    expect(link.code).toMatch(/^[A-Z0-9]{4}-[A-Z0-9]{4}$/);
    expect(link.qr).toBe(`darulirfan://approve-computer?code=${link.code}`);
    expect(link.expiresAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
    expect(Date.parse(link.expiresAt) - Date.now()).toBeGreaterThan(4 * 60_000);
    expect(await (await desktop("/v1/members/computer-link/poll", { pollToken: link.pollToken })).json()).toEqual({ status: "pending" });

    // The phone sees which computer is asking before it confirms, typed any way.
    const typed = link.code.toLowerCase().replace("-", " ");
    const preview = await call(TOKENS[ADMIN]!, "POST", "/v1/members/computer-link/preview", { code: typed });
    expect(preview.status).toBe(200);
    expect(await preview.json()).toMatchObject({ deviceName: "Ali's laptop", platform: "windows" });

    const approved = await call(TOKENS[ADMIN]!, "POST", "/v1/members/computer-link/approve", { code: typed });
    expect(approved.status).toBe(200);
    expect(await approved.json()).toEqual({ ok: true, deviceName: "Ali's laptop", platform: "windows" });

    const session = await (await desktop("/v1/members/computer-link/poll", { pollToken: link.pollToken })).json() as Record<string, string>;
    expect(session).toMatchObject({ status: "approved", memberID: ADMIN });
    expect(session.token).toMatch(/^[0-9a-f]{64}$/);
    expect(Date.parse(session.expiresAt!) - Date.now()).toBeGreaterThan(29 * 86_400_000);
    // Once only.
    expect(await (await desktop("/v1/members/computer-link/poll", { pollToken: link.pollToken })).json()).toEqual({ status: "expired" });

    // The same account and role as on the phone: the Halqah admin's own routes work.
    expect((await call(session.token!, "GET", "/v1/members/me")).status).toBe(200);
    expect((await call(session.token!, "GET", "/v1/groups")).status).toBe(200);
    expect((await call(session.token!, "GET", "/v1/groups/usa/people")).status).toBe(200);
    expect((await call(session.token!, "GET", "/v1/markaz/access")).status).toBe(200);
  });

  it("refuses an unusable request to start", async () => {
    const { desktop } = await setup();
    expect((await desktop("/v1/members/computer-link", { platform: "windows" })).status).toBe(400);
    expect((await desktop("/v1/members/computer-link", { deviceName: "   ", platform: "windows" })).status).toBe(400);
    expect((await desktop("/v1/members/computer-link", { deviceName: "PC", platform: "linux" })).status).toBe(400);
    expect((await desktop("/v1/members/computer-link", { deviceName: "PC" })).status).toBe(400);
    expect((await desktop("/v1/members/computer-link/poll", { pollToken: "nope" })).status).toBe(400);
    expect(await (await desktop("/v1/members/computer-link/poll", { pollToken: "f".repeat(64) })).json()).toEqual({ status: "expired" });
  });

  it("keeps a computer's name to one plain line, without direction tricks", async () => {
    const { call, start } = await setup();
    const link = await start("‮exe.\nOffice   PC" + "x".repeat(100), "macos");
    const preview = await (await call(TOKENS[MEMBER]!, "POST", "/v1/members/computer-link/preview", { code: link.code })).json() as { deviceName: string; platform: string };
    expect(preview.deviceName).not.toMatch(/[‮\n]/);
    expect(preview.deviceName.startsWith("exe. Office PCxx")).toBe(true);
    expect(preview.deviceName.length).toBeLessThanOrEqual(60);
    expect(preview.platform).toBe("macos");
  });

  it("expires a code nobody approved, and a code approved too late", async () => {
    const { call, desktop, start } = await setup();
    const link = await start();
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(Date.now() + 5 * 60_000 + 1_000);
    expect(await (await desktop("/v1/members/computer-link/poll", { pollToken: link.pollToken })).json()).toEqual({ status: "expired" });
    expect((await call(TOKENS[MEMBER]!, "POST", "/v1/members/computer-link/preview", { code: link.code })).status).toBe(404);
    expect((await call(TOKENS[MEMBER]!, "POST", "/v1/members/computer-link/approve", { code: link.code })).status).toBe(404);
  });

  it("is approved by any signed-in member, once, and never by a code typed wrong", async () => {
    const { call, start } = await setup();
    const link = await start();
    expect((await call(null, "POST", "/v1/members/computer-link/approve", { code: link.code })).status).toBe(401);
    expect((await call(TOKENS[MEMBER]!, "POST", "/v1/members/computer-link/approve", { code: "WXYZ-WXYZ" })).status).toBe(404);
    expect((await call(TOKENS[MEMBER]!, "POST", "/v1/members/computer-link/approve", { code: "SHORT" })).status).toBe(400);
    expect((await call(TOKENS[MEMBER]!, "POST", "/v1/members/computer-link/approve", { code: link.code })).status).toBe(200);
    // A second phone cannot take over a computer someone already approved.
    expect((await call(TOKENS[OTHER]!, "POST", "/v1/members/computer-link/approve", { code: link.code })).status).toBe(404);
    expect((await call(TOKENS[OTHER]!, "POST", "/v1/members/computer-link/preview", { code: link.code })).status).toBe(404);
  });

  it("is never approved from a computer: not the desktop app, not the reporting website", async () => {
    const { call, desktop, start, signIn, raw } = await setup();
    const computer = await signIn(MEMBER);
    const link = await start("Second PC");
    expect((await call(computer.token, "POST", "/v1/members/computer-link/approve", { code: link.code })).status).toBe(403);
    expect((await call(computer.token, "POST", "/v1/members/computer-link/preview", { code: link.code })).status).toBe(403);
    // Nor can the desktop app approve the reporting website.
    expect((await call(computer.token, "POST", "/v1/markaz/reporting-link/approve", { code: link.code })).status).toBe(403);

    const reporting = "9".repeat(64);
    raw.prepare("INSERT INTO member_sessions(token_hash,member_id,created_at,expires_at,last_seen_at,client) VALUES(?,?,?,?,?,'reporting')")
      .run(await sha256(reporting), MEMBER, new Date().toISOString(), new Date(Date.now() + 3_600_000).toISOString(), new Date().toISOString());
    expect((await call(reporting, "POST", "/v1/members/computer-link/approve", { code: link.code })).status).toBe(401);
    expect((await call(reporting, "GET", "/v1/members/computers")).status).toBe(401);
    // The code is still open for the phone.
    expect((await call(TOKENS[MEMBER]!, "POST", "/v1/members/computer-link/approve", { code: link.code })).status).toBe(200);
    expect((await (await desktop("/v1/members/computer-link/poll", { pollToken: link.pollToken })).json() as { status: string }).status).toBe("approved");
  });

  it("keeps the reporting website's codes and the desktop app's apart", async () => {
    const { call, desktop, start, raw } = await setup();
    raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('silsila-markaz',?,?,'test','admin')").run(ADMIN, new Date().toISOString());
    const website = await (await desktop("/v1/reporting/link")).json() as { code: string; pollToken: string };
    const computer = await start();
    // A desktop code cannot be approved as a reporting one, and the other way round.
    expect((await call(TOKENS[ADMIN]!, "POST", "/v1/markaz/reporting-link/approve", { code: computer.code })).status).toBe(404);
    expect((await call(TOKENS[ADMIN]!, "POST", "/v1/members/computer-link/approve", { code: website.code })).status).toBe(404);
    // Nor polled through the other's door.
    expect((await call(TOKENS[ADMIN]!, "POST", "/v1/members/computer-link/approve", { code: computer.code })).status).toBe(200);
    expect(await (await desktop("/v1/reporting/link/poll", { pollToken: computer.pollToken })).json()).toEqual({ status: "expired" });
    expect(await (await desktop("/v1/members/computer-link/poll", { pollToken: website.pollToken })).json()).toEqual({ status: "expired" });
    expect((await (await desktop("/v1/members/computer-link/poll", { pollToken: computer.pollToken })).json() as { status: string }).status).toBe("approved");
  });

  it("lists a member's computers and signs them out, one or all, and a signed-out computer gets 401", async () => {
    const { call, signIn } = await setup();
    const laptop = await signIn(MEMBER, "Ali's laptop", "windows");
    const mac = await signIn(MEMBER, "Ali's Mac", "macos");
    const other = await signIn(OTHER, "Bilal's PC");

    const list = await (await call(TOKENS[MEMBER]!, "GET", "/v1/members/computers")).json() as { computers: Record<string, unknown>[] };
    expect(list.computers).toHaveLength(2);
    expect(list.computers.map(row => row.name).sort()).toEqual(["Ali's Mac", "Ali's laptop"]);
    for (const row of list.computers) {
      expect(row).toMatchObject({ current: false });
      expect(row.id).toMatch(/^[0-9a-f]{12}$/);
      expect(row.createdAt).toMatch(/:\d{2}Z$/);
    }
    // The computer itself sees which entry it is.
    const fromMac = await (await call(mac.token, "GET", "/v1/members/computers")).json() as { computers: { id: string; name: string; platform: string; current: boolean }[] };
    const self = fromMac.computers.find(row => row.current)!;
    expect(self).toMatchObject({ name: "Ali's Mac", platform: "macos" });

    // Another member's computer is not this member's to sign out.
    const others = await (await call(TOKENS[OTHER]!, "GET", "/v1/members/computers")).json() as { computers: { id: string }[] };
    expect((await call(TOKENS[MEMBER]!, "DELETE", `/v1/members/computers/${others.computers[0]!.id}`)).status).toBe(404);
    expect((await call(other.token, "GET", "/v1/members/me")).status).toBe(200);
    expect((await call(TOKENS[MEMBER]!, "DELETE", "/v1/members/computers/not-an-id")).status).toBe(404);

    expect((await call(TOKENS[MEMBER]!, "DELETE", `/v1/members/computers/${self.id}`)).status).toBe(204);
    expect((await call(mac.token, "GET", "/v1/members/me")).status).toBe(401);
    expect((await call(laptop.token, "GET", "/v1/members/me")).status).toBe(200);

    expect((await call(TOKENS[MEMBER]!, "DELETE", "/v1/members/computers")).status).toBe(204);
    expect((await call(laptop.token, "GET", "/v1/members/me")).status).toBe(401);
    // The phone itself stays signed in, and so does the other member's computer.
    expect((await call(TOKENS[MEMBER]!, "GET", "/v1/members/me")).status).toBe(200);
    expect((await call(other.token, "GET", "/v1/members/me")).status).toBe(200);
  });

  it("signs a computer out by itself, and with the account when it is deleted", async () => {
    const { call, signIn } = await setup();
    const first = await signIn(MEMBER);
    expect((await call(first.token, "POST", "/v1/members/signout", {})).status).toBe(204);
    expect((await call(first.token, "GET", "/v1/members/me")).status).toBe(401);

    const second = await signIn(MEMBER);
    expect((await call(TOKENS[MEMBER]!, "DELETE", "/v1/members/me")).status).toBe(204);
    expect((await call(second.token, "GET", "/v1/members/me")).status).toBe(401);
    expect((await call(second.token, "GET", "/v1/members/computers")).status).toBe(401);
  });

  it("stays signed in while it is used", async () => {
    const { call, signIn, raw } = await setup();
    const computer = await signIn(MEMBER);
    const hash = await sha256(computer.token);
    const read = () => raw.prepare("SELECT expires_at,last_seen_at FROM member_sessions WHERE token_hash=?").get(hash) as { expires_at: string; last_seen_at: string };
    const before = read();
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(Date.now() + 10 * 86_400_000);
    expect((await call(computer.token, "GET", "/v1/members/me")).status).toBe(200);
    const after = read();
    expect(Date.parse(after.expires_at) - Date.parse(before.expires_at)).toBeGreaterThan(9 * 86_400_000);
    expect(Date.parse(after.last_seen_at)).toBeGreaterThan(Date.parse(before.last_seen_at));
    // And lapses after 30 days unused.
    vi.setSystemTime(Date.parse(after.expires_at) + 1_000);
    expect((await call(computer.token, "GET", "/v1/members/me")).status).toBe(401);
  });

  it("limits each address: starting, polling and wrong codes", async () => {
    const { call, desktop, start } = await setup();
    for (let i = 0; i < 30; i += 1) expect((await desktop("/v1/members/computer-link", { deviceName: "PC", platform: "windows" }, "9.9.9.9")).status).toBe(201);
    expect((await desktop("/v1/members/computer-link", { deviceName: "PC", platform: "windows" }, "9.9.9.9")).status).toBe(429);

    const link = await start();
    for (let i = 0; i < 20; i += 1) {
      expect((await call(TOKENS[OTHER]!, "POST", "/v1/members/computer-link/approve", { code: "WXYZ-WXYZ" }, "6.6.6.6")).status).toBe(404);
    }
    // Twenty wrong codes in the hour and even the right one waits.
    expect((await call(TOKENS[OTHER]!, "POST", "/v1/members/computer-link/approve", { code: link.code }, "6.6.6.6")).status).toBe(429);
    expect((await call(TOKENS[OTHER]!, "POST", "/v1/members/computer-link/preview", { code: link.code }, "6.6.6.6")).status).toBe(429);
    // Another address is unaffected.
    expect((await call(TOKENS[OTHER]!, "POST", "/v1/members/computer-link/approve", { code: link.code }, "5.5.5.5")).status).toBe(200);
  });
});
