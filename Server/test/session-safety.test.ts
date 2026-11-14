import { afterEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../src/contracts";
import { setLive } from "../src/community";
import { beginSessionIfIdle, checkIn, controlSession, endSession, SessionConflictError } from "../src/session";
import { endAfterDua, relayLive, relayZikrCue, dispatchZikrCues } from "../src/groupZikrStages";
import { sqliteD1 } from "./sqlite-d1";
import worker from "../src/index";
import { sha256 } from "../src/util";

function setup() {
  const { db, raw } = sqliteD1();
  for (const [id, role] of [["admin", "admin"], ["member", "member"]]) {
    raw.prepare("INSERT INTO members(id,apple_subject,created_at,last_seen_at) VALUES(?,?,?,?)").run(id!, id!, "now", "now");
    raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('usa',?,'now','test',?)").run(id!, role!);
  }
  raw.prepare(`INSERT INTO group_live(group_id,state,kind,title,session_id,started_at,updated_at,auto_end_at)
    VALUES('usa','live','zikr','Current','session-current','2026-11-06T12:00:00.000Z','now','2026-11-06T13:00:00.000Z')`).run();
  return { raw, env: { DB: db } as Env };
}
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

describe("session mutation safety", () => {
  it("does not interpret a malformed admin state as End", async () => {
    const { env, raw } = setup();
    for (const state of [undefined, null, "offlien", false]) {
      expect((await setLive(env, "admin", "usa", { state })).status).toBe(400);
    }
    expect(raw.prepare("SELECT state,session_id FROM group_live WHERE group_id='usa'").get())
      .toEqual({ state: "live", session_id: "session-current" });
  });

  it("rejects old-screen End and playback requests without changing the current session", async () => {
    const { env, raw } = setup();
    expect((await setLive(env, "admin", "usa", { state: "offline", sessionID: "session-old" })).status).toBe(409);
    expect((await controlSession(env, "admin", "usa", { action: "pause", sessionID: "session-old" })).status).toBe(409);
    expect(raw.prepare("SELECT state,paused FROM group_live WHERE group_id='usa'").get()).toEqual({ state: "live", paused: 0 });
  });

  it("rejects an old-screen Start before opening a room", async () => {
    const { env, raw } = setup();
    const fetch = vi.fn(); vi.stubGlobal("fetch", fetch);
    expect((await setLive(env, "admin", "usa", { state: "live", room: true, sessionID: "session-old" })).status).toBe(409);
    fetch.mock.calls.forEach(() => { throw new Error("No provider operation expected"); });
    expect(raw.prepare("SELECT session_id FROM group_live WHERE group_id='usa'").get()).toEqual({ session_id: "session-current" });
  });

  it("does not replace a newer session that starts while a room is being created", async () => {
    const { env, raw } = setup();
    Object.assign(env, { REALTIME_ACCOUNT_ID: "test", REALTIME_APP_ID: "test", REALTIME_API_TOKEN: "test" });
    vi.stubGlobal("fetch", async () => {
      raw.prepare("UPDATE group_live SET session_id='session-newer',started_at='2026-11-06T12:01:00.000Z' WHERE group_id='usa'").run();
      return Response.json({ data: { id: "unused-room" } }, { status: 201 });
    });
    await expect(setLive(env, "admin", "usa", { state: "live", room: true })).rejects.toBeInstanceOf(SessionConflictError);
    expect(raw.prepare("SELECT state,session_id FROM group_live WHERE group_id='usa'").get())
      .toEqual({ state: "live", session_id: "session-newer" });
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_live_history").get()).toEqual({ n: 0 });
  });

  it("rejects an intervening same-session queue edit even when timestamps are unchanged", async () => {
    const { env, raw } = setup();
    const prepare = env.DB.prepare.bind(env.DB);
    const newerQueue = JSON.stringify([{ kind: "video", id: "abcdefghijk", title: "New queue" }]);
    vi.spyOn(env.DB, "prepare").mockImplementation((sql: string) => {
      const statement = prepare(sql);
      if (sql.startsWith("UPDATE group_live SET queue_json=")) {
        const run = statement.run.bind(statement);
        vi.spyOn(statement, "run").mockImplementationOnce(async () => {
          raw.prepare("UPDATE group_live SET queue_json=? WHERE group_id='usa'").run(newerQueue);
          return run();
        });
      }
      return statement;
    });
    await expect(controlSession(env, "admin", "usa", { action: "pause", sessionID: "session-current" }))
      .rejects.toBeInstanceOf(SessionConflictError);
    expect(raw.prepare("SELECT queue_json,paused,updated_at FROM group_live WHERE group_id='usa'").get())
      .toEqual({ queue_json: newerQueue, paused: 0, updated_at: "now" });
  });

  it("keeps a committed End successful when recording cleanup fails", async () => {
    const { env, raw } = setup();
    raw.prepare("UPDATE group_live SET room_id='old-room',room_recording=1 WHERE group_id='usa'").run();
    const prepare = env.DB.prepare.bind(env.DB);
    vi.spyOn(env.DB, "prepare").mockImplementation((sql: string) => {
      if (sql.startsWith("UPDATE group_live SET room_recording=0")) throw new Error("cleanup unavailable");
      return prepare(sql);
    });
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    expect(await endSession(env, "usa", "admin", { sessionID: "session-current" })).toBe(true);
    expect(raw.prepare("SELECT state FROM group_live WHERE group_id='usa'").get()).toEqual({ state: "offline" });
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_live_history").get()).toEqual({ n: 1 });
    expect(error).toHaveBeenCalled();
  });

  it("rejects malformed live options instead of turning a test into a public session", async () => {
    const { env } = setup();
    expect((await setLive(env, "admin", "usa", { state: "live", test: "true" })).status).toBe(400);
    expect((await relayLive(env, "usa", { state: "live", test: "true" })).status).toBe(400);
  });

  it("returns400 for non-object JSON at admin and relay mutation routes", async () => {
    const { env } = setup();
    const token = "a".repeat(64);
    await env.DB.prepare("INSERT INTO member_sessions(token_hash,member_id,created_at,expires_at,last_seen_at) VALUES(?,?,?,?,?)")
      .bind(await sha256(token), "admin", "now", "2099-01-01T00:00:00.000Z", "now").run();
    Object.assign(env, { RELAY_TOKEN: "relay-test" });
    for (const value of [null, [], true, "live"]) {
      for (const [path, bearer] of [["/v1/groups/usa/live", token], ["/v1/service/groups/usa/live", "relay-test"]]) {
        const response = await worker.fetch(new Request(`https://test.invalid${path}`, {
          method: "POST", headers: { authorization: `Bearer ${bearer}`, "content-type": "application/json" }, body: JSON.stringify(value),
        }), env);
        expect(response.status).toBe(400);
      }
    }
  });

  it("fences the final close and history write if a new session arrives after the read", async () => {
    const { env, raw } = setup();
    const batch = env.DB.batch.bind(env.DB);
    vi.spyOn(env.DB, "batch").mockImplementationOnce(async (statements) => {
      raw.prepare("UPDATE group_live SET session_id='session-new',title='New' WHERE group_id='usa'").run();
      return batch(statements);
    });
    expect(await endSession(env, "usa", "admin", { sessionID: "session-current" })).toBe(false);
    expect(raw.prepare("SELECT state,session_id FROM group_live WHERE group_id='usa'").get())
      .toEqual({ state: "live", session_id: "session-new" });
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_live_history").get()).toEqual({ n: 0 });
  });

  it("archives and closes a matching session once", async () => {
    const { env, raw } = setup();
    expect(await endSession(env, "usa", "admin", { sessionID: "session-current" })).toBe(true);
    expect(await endSession(env, "usa", "admin", { sessionID: "session-current" })).toBe(false);
    expect(raw.prepare("SELECT session_id,title FROM group_live_history").all()).toEqual([{ session_id: "session-current", title: "Current" }]);
  });

  it("allows only one concurrent automated start from an idle group", async () => {
    const { env, raw } = setup();
    raw.prepare("UPDATE group_live SET state='offline' WHERE group_id='usa'").run();
    // The automated start is beginSessionIfIdle: the start that lost is told so with null.
    const session = { kind: "zikr" as const, title: "Start", videoID: null, roomID: null, queue: [] };
    const results = await Promise.all([beginSessionIfIdle(env, "usa", "admin", session), beginSessionIfIdle(env, "usa", "admin", session)]);
    expect(results.filter(id => id !== null)).toHaveLength(1);
    expect(results).toContain(null);
    expect(raw.prepare("SELECT session_id FROM group_live WHERE group_id='usa'").get()).toEqual({ session_id: results.find(id => id !== null) });
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_live_history").get()).toEqual({ n: 0 });
  });

  it("does not count regular members in an admin-only test", async () => {
    const { env, raw } = setup();
    raw.prepare("UPDATE group_live SET is_test=1 WHERE group_id='usa'").run();
    expect((await checkIn(env, "member", "usa")).status).toBe(409);
    expect((await checkIn(env, "admin", "usa")).status).toBe(200);
    expect(raw.prepare("SELECT member_id FROM group_live_presence").all()).toEqual([{ member_id: "admin" }]);
  });
});

describe("relay session and deadline fencing", () => {
  it("never reuses a meeting or a test as a public relay session", async () => {
    const { env, raw } = setup();
    raw.prepare("UPDATE group_live SET kind='meeting' WHERE group_id='usa'").run();
    expect((await relayLive(env, "usa", { state: "live" })).status).toBe(409);
    expect(raw.prepare("SELECT session_id,auto_end_at FROM group_live WHERE group_id='usa'").get())
      .toEqual({ session_id: "session-current", auto_end_at: "2026-11-06T13:00:00.000Z" });
    // A Test Zikr is not reused either: it ends, kept in history as a test, and
    // the real Zikr starts as a session of its own.
    raw.prepare("UPDATE group_live SET kind='zikr',is_test=1 WHERE group_id='usa'").run();
    const started = await relayLive(env, "usa", { state: "live" });
    expect(started.status).toBe(201);
    const { sessionID } = await started.json() as { sessionID: string };
    expect(sessionID).not.toBe("session-current");
    expect(raw.prepare("SELECT session_id,is_test,auto_end_at FROM group_live WHERE group_id='usa'").get())
      .toEqual({ session_id: sessionID, is_test: 0, auto_end_at: null });
    expect(raw.prepare("SELECT session_id,is_test FROM group_live_history").all()).toEqual([{ session_id: "session-current", is_test: 1 }]);
  });

  it("cancels the matching deadline on resumed live and ignores the cancelled alarm", async () => {
    const { env, raw } = setup();
    expect((await relayLive(env, "usa", { state: "live", sessionID: "session-current" })).status).toBe(200);
    expect(await endSession(env, "usa", "relay", { sessionID: "session-current", autoEndAt: "2026-11-06T13:00:00.000Z" })).toBe(false);
    await endAfterDua(env, new Date("2026-11-06T14:00:00.000Z"));
    expect(raw.prepare("SELECT state,auto_end_at FROM group_live WHERE group_id='usa'").get()).toEqual({ state: "live", auto_end_at: null });
  });

  it("rejects a delayed dua or stage from an earlier session", async () => {
    const { env, raw } = setup();
    expect((await relayLive(env, "usa", { state: "dua", sessionID: "session-old" })).status).toBe(409);
    expect((await relayZikrCue(env, "usa", { id: "11111111-2222-4333-8444-555555555555", stageID: "latifa-4", sessionID: "session-old" })).status).toBe(409);
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_zikr_cues").get()).toEqual({ n: 0 });
  });

  it("answers a dua already pending with its deadline and keeps one card across retries", async () => {
    const { env, raw } = setup();
    const input = { state: "dua", sessionID: "session-current" };
    // The deadline the session already carries is answered again, unchanged.
    const pending = await relayLive(env, "usa", input);
    expect(pending.status).toBe(200);
    expect(await pending.json()).toMatchObject({ endsAt: "2026-11-06T13:00:00.000Z" });
    // The card goes up with the deadline, once: a fresh dua writes both, its retries neither.
    raw.prepare("UPDATE group_live SET auto_end_at=NULL WHERE group_id='usa'").run();
    const first = await relayLive(env, "usa", input);
    expect(first.status).toBe(200);
    const { endsAt } = await first.json() as { endsAt: string };
    const retry = await relayLive(env, "usa", input);
    expect(retry.status).toBe(200);
    expect(await retry.json()).toMatchObject({ endsAt });
    expect(raw.prepare("SELECT auto_end_at FROM group_live WHERE group_id='usa'").get()).toEqual({ auto_end_at: endsAt });
    expect(raw.prepare("SELECT stage_id,author_id FROM group_zikr_cues").all())
      .toEqual([{ stage_id: "dua", author_id: "service-paltalk-relay" }]);
  });

  it("does not acknowledge a Dua whose session was replaced during the request", async () => {
    const { env, raw } = setup();
    raw.prepare("UPDATE group_live SET auto_end_at=NULL WHERE group_id='usa'").run();
    const prepare = env.DB.prepare.bind(env.DB);
    vi.spyOn(env.DB, "prepare").mockImplementation((sql: string) => {
      const statement = prepare(sql);
      // The write that sets the deadline names the session it read.
      if (sql.startsWith("UPDATE group_live SET auto_end_at=?")) {
        const run = statement.run.bind(statement);
        vi.spyOn(statement, "run").mockImplementationOnce(async () => {
          raw.prepare("UPDATE group_live SET session_id='session-newer' WHERE group_id='usa'").run();
          return run();
        });
      }
      return statement;
    });
    expect((await relayLive(env, "usa", { state: "dua", sessionID: "session-current" })).status).toBe(409);
    expect(raw.prepare("SELECT session_id,auto_end_at FROM group_live WHERE group_id='usa'").get())
      .toEqual({ session_id: "session-newer", auto_end_at: null });
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_zikr_cues").get()).toEqual({ n: 0 });
  });

  it("ignores a due alarm cancelled after the cron read", async () => {
    const { env, raw } = setup();
    const prepare = env.DB.prepare.bind(env.DB);
    vi.spyOn(env.DB, "prepare").mockImplementation((sql: string) => {
      const statement = prepare(sql);
      if (sql.startsWith("SELECT group_id,session_id FROM group_live WHERE state='live' AND session_id IS NOT NULL AND auto_end_at")) {
        const all = statement.all.bind(statement);
        vi.spyOn(statement, "all").mockImplementationOnce(async () => {
          const result = await all();
          raw.prepare("UPDATE group_live SET auto_end_at=NULL WHERE group_id='usa'").run();
          return result;
        });
      }
      return statement;
    });
    await endAfterDua(env, new Date("2026-11-06T14:00:00.000Z"));
    expect(raw.prepare("SELECT state FROM group_live WHERE group_id='usa'").get()).toEqual({ state: "live" });
  });

  it("expires undelivered cues from the previous session even if a newer Zikr is live", async () => {
    const { env, raw } = setup();
    raw.prepare(`INSERT INTO group_zikr_cues(group_id,event_id,stage_id,title,author_id,created_at,notification_state)
      VALUES('usa','old-cue','latifa-1','1st Latifa','admin','2026-11-06T11:59:00.000Z','pending')`).run();
    await dispatchZikrCues(env, new Date("2026-11-06T12:01:00.000Z"));
    expect(raw.prepare("SELECT notification_state FROM group_zikr_cues").get()).toEqual({ notification_state: "expired" });
  });
});
