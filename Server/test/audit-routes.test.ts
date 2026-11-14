// The audit of 6 November as it is reached over the routes: content reports and
// the Markaz's review of them, admin controls fenced by the session they were
// made for, request bodies that are refused when they are not an object, and
// the community terms kept as a record nobody is asked for.
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { sqliteD1 } from "./sqlite-d1";

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

const OFFICER = "o".repeat(32), ADMIN = "a".repeat(32), MEMBER = "m".repeat(32), OUTSIDER = "x".repeat(32);
const TOKENS = { [OFFICER]: "1".repeat(64), [ADMIN]: "2".repeat(64), [MEMBER]: "3".repeat(64), [OUTSIDER]: "4".repeat(64) };

async function setup() {
  const { db, raw } = sqliteD1();
  vi.stubGlobal("fetch", async () => new Response("{}", { status: 200 }));
  const now = new Date().toISOString(), later = new Date(Date.now() + 86_400_000).toISOString();
  for (const [id, name] of [[OFFICER, "Officer"], [ADMIN, "Ameer"], [MEMBER, "Ali"], [OUTSIDER, "Bilal"]] as const) {
    raw.prepare("INSERT INTO members(id,apple_subject,display_name,created_at,last_seen_at) VALUES(?,?,?,?,?)").run(id, `apple:${id}`, name, now, now);
    raw.prepare("INSERT INTO member_sessions(token_hash,member_id,created_at,expires_at,last_seen_at) VALUES(?,?,?,?,?)")
      .run(await sha256(TOKENS[id]!), id, now, later, now);
  }
  raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('silsila-markaz',?,?,'test','admin')").run(OFFICER, now);
  raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('usa',?,?,'test','administrator')").run(ADMIN, now);
  raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('usa',?,?,'test','member')").run(MEMBER, now);
  raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('canada',?,?,'test','member')").run(OUTSIDER, now);
  const env = { DB: db, PUBLIC_BASE_URL: "https://api.example.com" } as unknown as Env;
  /** `body` as an object is sent as JSON; as a string it is sent as it is, still called JSON. */
  const call = (memberID: string, method: string, path: string, body?: unknown) =>
    worker.fetch(new Request(`https://api.example.com${path}`, {
      method,
      headers: { authorization: `Bearer ${TOKENS[memberID]}`, "cf-connecting-ip": "7.7.7.7", ...(body !== undefined ? { "content-type": "application/json" } : {}) },
      body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body),
    }), env);
  const live = (sessionID: string) => raw.prepare(`INSERT INTO group_live(group_id,state,kind,title,started_at,updated_at,session_id,queue_json)
    VALUES('usa','live','zikr','Halqah Zikr',?,?,?,'[]')
    ON CONFLICT(group_id) DO UPDATE SET state='live',kind='zikr',session_id=excluded.session_id,started_at=excluded.started_at`).run(now, now, sessionID);
  return { raw, env, call, live };
}

afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

describe("reporting content to the Markaz", () => {
  const REQUEST = "11111111-2222-4333-8444-555555555555";

  it("takes a member's report once, however often it is sent, and only for a Halqah they are in", async () => {
    const { raw, call } = await setup();
    raw.prepare(`INSERT INTO member_group_posts(id,group_id,kind,title,body,published_at,author_email,updated_at)
      VALUES('post-1','usa','announcement','Notice','Its text','now','member:x','now')`).run();
    const report = { requestID: REQUEST, targetKind: "post", targetID: "post-1", reason: "inappropriate", details: "Not for this Halqah." };
    const first = await call(MEMBER, "POST", "/v1/groups/usa/reports", report);
    expect(first.status).toBe(201);
    const { id } = await first.json() as { id: string };
    // The same request again (a lost answer) is the same report.
    expect(await (await call(MEMBER, "POST", "/v1/groups/usa/reports", report)).json()).toEqual({ ok: true, id });
    expect(raw.prepare("SELECT reporter_id,target_kind,target_id,reason,details,status FROM community_reports").all()).toEqual([
      { reporter_id: MEMBER, target_kind: "post", target_id: "post-1", reason: "inappropriate", details: "Not for this Halqah.", status: "open" }]);
    // The same request ID with other contents is refused, not silently merged.
    expect((await call(MEMBER, "POST", "/v1/groups/usa/reports", { ...report, reason: "spam" })).status).toBe(409);
    // What cannot be a report.
    for (const bad of [{ ...report, reason: "dislike" }, { ...report, targetKind: "member" }, { ...report, requestID: "1" },
      { ...report, targetID: "" }, { ...report, details: 5 }, {}]) {
      expect((await call(MEMBER, "POST", "/v1/groups/usa/reports", bad)).status).toBe(400);
    }
    // Another Halqah stays indistinguishable from nothing.
    expect((await call(OUTSIDER, "POST", "/v1/groups/usa/reports", { ...report, requestID: "99999999-2222-4333-8444-555555555555" })).status).toBe(404);
    expect(raw.prepare("SELECT COUNT(*) AS n FROM community_reports").get()).toEqual({ n: 1 });
  });

  it("shows the open reports to the Markaz's officers only, and closes each once with a note", async () => {
    const { raw, call } = await setup();
    raw.prepare(`INSERT INTO member_group_posts(id,group_id,kind,title,body,published_at,author_email,updated_at)
      VALUES('post-1','usa','announcement','Notice','Its text','now','member:x','now')`).run();
    const sent = await (await call(MEMBER, "POST", "/v1/groups/usa/reports",
      { requestID: REQUEST, targetKind: "post", targetID: "post-1", reason: "privacy" })).json() as { id: string };
    for (const person of [MEMBER, ADMIN]) {
      expect((await call(person, "GET", "/v1/markaz/moderation")).status).toBe(403);
      expect((await call(person, "POST", `/v1/markaz/moderation/${sent.id}`, { status: "resolved", note: "Mine" })).status).toBe(403);
    }
    const queue = await (await call(OFFICER, "GET", "/v1/markaz/moderation")).json() as { reports: Record<string, unknown>[] };
    expect(queue.reports).toMatchObject([{ id: sent.id, groupID: "usa", reporterName: "Ali", targetKind: "post", targetID: "post-1",
      reason: "privacy", status: "open", targetPreview: "Notice: Its text", targetUnavailable: false }]);
    expect((await call(OFFICER, "GET", "/v1/markaz/moderation?status=everything")).status).toBe(400);
    // An outcome needs a note.
    expect((await call(OFFICER, "POST", `/v1/markaz/moderation/${sent.id}`, { status: "resolved" })).status).toBe(400);
    expect((await call(OFFICER, "POST", `/v1/markaz/moderation/${sent.id}`, { status: "open", note: "Back" })).status).toBe(400);
    expect((await call(OFFICER, "POST", "/v1/markaz/moderation/unknown", { status: "resolved", note: "Post removed." })).status).toBe(404);
    expect((await call(OFFICER, "POST", `/v1/markaz/moderation/${sent.id}`, { status: "resolved", note: "Post removed." })).status).toBe(200);
    // The same outcome again is the same answer; another outcome is refused.
    expect((await call(OFFICER, "POST", `/v1/markaz/moderation/${sent.id}`, { status: "resolved", note: "Post removed." })).status).toBe(200);
    expect((await call(OFFICER, "POST", `/v1/markaz/moderation/${sent.id}`, { status: "dismissed", note: "Nothing wrong." })).status).toBe(409);
    expect(raw.prepare("SELECT status,reviewer_id,review_note FROM community_reports").get())
      .toEqual({ status: "resolved", reviewer_id: OFFICER, review_note: "Post removed." });
    expect((await (await call(OFFICER, "GET", "/v1/markaz/moderation")).json() as { reports: unknown[] }).reports).toEqual([]);
    expect((await (await call(OFFICER, "GET", "/v1/markaz/moderation?status=resolved")).json() as { reports: unknown[] }).reports).toHaveLength(1);
  });
});

describe("admin controls made for a session that has changed", () => {
  const changed = { error: "The live session changed. Refresh and try again.", code: "session_changed" };

  it("are answered 409 session_changed and change nothing", async () => {
    const { raw, call, live } = await setup();
    live("session-new");
    for (const [path, body] of [
      ["/v1/groups/usa/control", { action: "pause", sessionID: "session-old" }],
      ["/v1/groups/usa/control", { action: "notice", text: "Late", sessionID: "session-old" }],
      ["/v1/groups/usa/live", { state: "offline", sessionID: "session-old" }],
      ["/v1/groups/usa/live", { state: "live", videoID: "abcdefghijk", sessionID: "session-old" }],
    ] as const) {
      const refused = await call(ADMIN, "POST", path, body);
      expect(refused.status).toBe(409);
      expect(await refused.json()).toEqual(changed);
    }
    expect(raw.prepare("SELECT state,session_id,paused,notice FROM group_live WHERE group_id='usa'").get())
      .toEqual({ state: "live", session_id: "session-new", paused: 0, notice: null });
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_live_history").get()).toEqual({ n: 0 });
  });

  it("go through when they name the live session, and when they name none, as the apps in use do", async () => {
    const { raw, call, live } = await setup();
    live("session-new");
    expect((await call(ADMIN, "POST", "/v1/groups/usa/control", { action: "notice", text: "Welcome", sessionID: "session-new" })).status).toBe(200);
    expect((await call(ADMIN, "POST", "/v1/groups/usa/control", { action: "pause" })).status).toBe(200);
    expect(raw.prepare("SELECT paused,notice FROM group_live WHERE group_id='usa'").get()).toEqual({ paused: 1, notice: "Welcome" });
    expect(await (await call(ADMIN, "POST", "/v1/groups/usa/live", { state: "offline", sessionID: "session-new" })).json()).toEqual({ ok: true, state: "offline" });
    live("session-next");
    expect(await (await call(ADMIN, "POST", "/v1/groups/usa/live", { state: "offline" })).json()).toEqual({ ok: true, state: "offline" });
    expect(raw.prepare("SELECT session_id FROM group_live_history ORDER BY session_id").all()).toEqual([{ session_id: "session-new" }, { session_id: "session-next" }]);
    // Ending when nothing is live is still not an error.
    expect((await call(ADMIN, "POST", "/v1/groups/usa/live", { state: "offline" })).status).toBe(200);
  });

  it("are answered 409 session_changed when the session is replaced while the control is being written", async () => {
    const { raw, env, call, live } = await setup();
    live("session-new");
    const prepare = env.DB.prepare.bind(env.DB);
    vi.spyOn(env.DB, "prepare").mockImplementation((sql: string) => {
      const statement = prepare(sql);
      if (sql.startsWith("UPDATE group_live SET queue_json=")) {
        const run = statement.run.bind(statement);
        vi.spyOn(statement, "run").mockImplementationOnce(async () => {
          raw.prepare("UPDATE group_live SET session_id='session-newer' WHERE group_id='usa'").run();
          return run();
        });
      }
      return statement;
    });
    const refused = await call(ADMIN, "POST", "/v1/groups/usa/control", { action: "pause" });
    expect(refused.status).toBe(409);
    expect(await refused.json()).toEqual(changed);
    expect(raw.prepare("SELECT session_id,paused FROM group_live WHERE group_id='usa'").get()).toEqual({ session_id: "session-newer", paused: 0 });
  });

  it("start a new session over the one the admin saw, keeping that one in history", async () => {
    const { raw, call, live } = await setup();
    live("session-seen");
    const started = await call(ADMIN, "POST", "/v1/groups/usa/live", { state: "live", videoID: "abcdefghijk", sessionID: "session-seen" });
    expect(started.status).toBe(200);
    const { sessionID } = await started.json() as { sessionID: string };
    expect(raw.prepare("SELECT state,session_id,video_id FROM group_live WHERE group_id='usa'").get())
      .toEqual({ state: "live", session_id: sessionID, video_id: "abcdefghijk" });
    expect(raw.prepare("SELECT session_id,ended_by FROM group_live_history").all()).toEqual([{ session_id: "session-seen", ended_by: ADMIN }]);
  });
});

describe("request bodies on member routes", () => {
  it("are objects: anything else is refused, and no body at all still reads as an empty one", async () => {
    const { raw, call, live } = await setup();
    live("session-new");
    for (const body of ["null", "[]", "true", "\"offline\"", "{state:", "not json"]) {
      const refused = await call(ADMIN, "POST", "/v1/groups/usa/live", body);
      expect(refused.status).toBe(400);
      expect(await refused.json()).toEqual({ error: "Invalid JSON" });
    }
    // An unreadable body never ends the session, as an empty object once did.
    expect((await call(ADMIN, "POST", "/v1/groups/usa/live", {})).status).toBe(400);
    expect(raw.prepare("SELECT state,session_id FROM group_live WHERE group_id='usa'").get()).toEqual({ state: "live", session_id: "session-new" });
    // No body, or an empty one, where none is needed.
    expect((await call(MEMBER, "POST", "/v1/members/signout")).status).toBe(204);
    expect((await call(ADMIN, "POST", "/v1/members/signout", "")).status).toBe(204);
  });
});

describe("the community terms", () => {
  it("are kept when a client sends them, once per member, and nobody is refused without them", async () => {
    const { raw, call } = await setup();
    const accepted = { adult: true, termsVersion: "2026-11-06" };
    for (let i = 0; i < 2; i += 1) {
      const response = await call(MEMBER, "POST", "/v1/members/community-consent", accepted);
      expect(response.status).toBe(200);
      expect(await response.json()).toEqual({ ok: true, termsVersion: "2026-11-06" });
    }
    expect(raw.prepare("SELECT member_id,terms_version FROM member_community_consent").all()).toEqual([{ member_id: MEMBER, terms_version: "2026-11-06" }]);
    // An incomplete declaration is a bad request, never a refusal of the member.
    for (const bad of [{}, { adult: false, termsVersion: "2026-11-06" }, { adult: true }, { adult: true, termsVersion: "2020-01-01" }, { adult: "true", termsVersion: "2026-11-06" }]) {
      const response = await call(ADMIN, "POST", "/v1/members/community-consent", bad);
      expect(response.status).toBe(400);
      expect(await response.text()).not.toContain("community_consent_required");
    }
    expect(raw.prepare("SELECT COUNT(*) AS n FROM member_community_consent").get()).toEqual({ n: 1 });
    // The admin, who has accepted nothing, writes as before.
    expect((await call(ADMIN, "PUT", "/v1/members/me", { displayName: "Ameer Sahib" })).status).toBe(200);
    // Deleting the account removes the record with it.
    expect((await call(MEMBER, "DELETE", "/v1/members/me")).status).toBe(204);
    expect(raw.prepare("SELECT COUNT(*) AS n FROM member_community_consent").get()).toEqual({ n: 0 });
  });
});
