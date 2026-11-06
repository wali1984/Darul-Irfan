// The relay's hold on a Zikr session (audit 2026-11-06, F02 and F05): one
// session however many times the start arrives, the dua's end bound to the
// session it was called in, live again within the dua window resuming it, a
// Test Zikr replaced explicitly, a meeting never taken over, a session the
// relay abandoned ended once it is five hours old and its stage has been still
// for an hour, and every write the relay names a session for refused as stale
// when that session is not the live one.
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { resetAPNSToken } from "../src/apns";
import { endAfterDua, endStaleRelaySessions, relayLive, RELAY_AUTHOR } from "../src/groupZikrStages";
import { endSession } from "../src/session";
import { sqliteD1 } from "./sqlite-d1";

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

async function p256pem(): Promise<string> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey) as ArrayBuffer);
  let binary = ""; der.forEach(byte => binary += String.fromCharCode(byte));
  return `-----BEGIN PRIVATE KEY-----${btoa(binary)}-----END PRIVATE KEY-----`;
}

const PHONE = "55555555-5555-4555-8555-555555555555";
const MEMBER = "c".repeat(32), MEMBER_TOKEN = "3".repeat(64);
const RELAY = "relay-secret";
const event = (n: number) => `11111111-2222-4333-8444-${String(n).padStart(12, "0")}`;

async function setup() {
  resetAPNSToken();
  const { db, raw } = sqliteD1();
  const pushes: string[] = [];
  vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
    const url = String(input instanceof Request ? input.url : input);
    if (url.includes("push.apple.com")) pushes.push(url);
    return new Response("", { status: 200 });
  });
  const now = new Date().toISOString(), later = new Date(Date.now() + 86_400_000).toISOString();
  raw.prepare("INSERT INTO members(id,apple_subject,display_name,email,created_at,last_seen_at) VALUES(?,?,?,?,?,?)")
    .run(MEMBER, `apple:${MEMBER}`, "Member", null, now, now);
  raw.prepare("INSERT INTO member_sessions(token_hash,member_id,created_at,expires_at,last_seen_at) VALUES(?,?,?,?,?)")
    .run(await sha256(MEMBER_TOKEN), MEMBER, now, later, now);
  raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('usa',?,?,'test','member')").run(MEMBER, now);
  const env = {
    DB: db, APNS_TOPIC: "us.naqshbaniaowaisiah", PUBLIC_BASE_URL: "https://api.example.com", RELAY_TOKEN: RELAY,
    APNS_KEY_ID: "KEY", APNS_TEAM_ID: "TEAM", APNS_PRIVATE_KEY: await p256pem(),
  } as unknown as Env;
  const post = (path: string, body: unknown, token: string) => worker.fetch(new Request(`https://api.example.com${path}`, {
    method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json", "cf-connecting-ip": "7.7.7.7" },
    body: JSON.stringify(body) }), env);
  // The member's phone, so a start's notice is observable.
  await worker.fetch(new Request("https://api.example.com/v1/devices", {
    method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": "6.6.6.6" },
    body: JSON.stringify({ installationID: PHONE, apnsToken: "e".repeat(64), locale: "en", timeZone: "UTC", topics: [],
      environment: "production", appVersion: "1.12", keepTopics: true }) }), env);
  await post("/v1/members/devices", { installationID: PHONE }, MEMBER_TOKEN);
  const live = (body: Record<string, unknown>) => post("/v1/service/groups/usa/live", body, RELAY);
  const cue = (stageID: string, n: number) => post("/v1/service/groups/usa/zikr-cues", { id: event(n), stageID }, RELAY);
  const row = () => raw.prepare("SELECT state,kind,session_id,auto_end_at,is_test,started_by FROM group_live WHERE group_id='usa'").get() as any;
  const history = () => raw.prepare("SELECT session_id,is_test,ended_by FROM group_live_history WHERE group_id='usa' ORDER BY started_at").all() as any[];
  return { raw, env, live, cue, row, history, pushes };
}

afterEach(() => vi.unstubAllGlobals());

describe("the relay's hold on a Zikr session", () => {
  it("the websites' live view carries the session id", async () => {
    const { env, live } = await setup();
    const started = await (await live({ state: "live", title: "Daily Zikr" })).json() as any;
    expect(started.sessionID).toMatch(/^session-/);
    const body = await (await worker.fetch(new Request("https://api.example.com/v1/public/live?ids=usa"), env)).json() as any;
    expect(body.halqahs[0].live).toMatchObject({ kind: "zikr", title: "Daily Zikr", sessionID: started.sessionID });
  });

  it("live again within the dua window resumes the session: the end is cancelled, the dua leaves the stage, nobody is notified again", async () => {
    const { env, raw, live, cue, row, history, pushes } = await setup();
    const started = await (await live({ state: "live", title: "Daily Zikr" })).json() as any;
    expect(pushes.length).toBe(1);
    expect((await cue("shajra", 1)).status).toBe(201);
    const dua = await (await live({ state: "dua" })).json() as any;
    expect(row().auto_end_at).toBe(dua.endsAt);
    const sent = pushes.length;
    const resumed = await live({ state: "live" });
    expect(resumed.status).toBe(200);
    expect(await resumed.json()).toEqual({ state: "live", sessionID: started.sessionID, started: false, resumed: true });
    expect(row()).toMatchObject({ state: "live", session_id: started.sessionID, auto_end_at: null });
    // The dua left the stage; the Shajra shows again.
    expect(raw.prepare("SELECT stage_id,hidden_at IS NOT NULL AS hidden FROM group_zikr_cues ORDER BY sequence").all()).toEqual([
      { stage_id: "shajra", hidden: 0 }, { stage_id: "dua", hidden: 1 }]);
    expect(pushes.length).toBe(sent);
    expect(history()).toEqual([]);
    // The cancelled end never fires, even once its time has passed.
    await endAfterDua(env, new Date(Date.parse(dua.endsAt) + 60_000));
    expect(row()).toMatchObject({ state: "live", session_id: started.sessionID });
    // A later dua schedules a fresh end for the same session.
    const again = await (await live({ state: "dua" })).json() as any;
    expect(Date.parse(again.endsAt)).toBeGreaterThanOrEqual(Date.parse(dua.endsAt));
    expect(row()).toMatchObject({ session_id: started.sessionID, auto_end_at: again.endsAt });
  });

  it("a stage cue during the dua window keeps the end; only {state: live} cancels it", async () => {
    const { env, raw, live, cue, row, history } = await setup();
    const started = await (await live({ state: "live", title: "Daily Zikr" })).json() as any;
    const dua = await (await live({ state: "dua" })).json() as any;
    expect((await cue("latifa-7", 2)).status).toBe(201);
    expect(row().auto_end_at).toBe(dua.endsAt);
    // Two people listened; the record counts them when the session ends.
    const seen = new Date().toISOString(), guest = "d".repeat(32);
    raw.prepare("INSERT INTO members(id,apple_subject,display_name,email,created_at,last_seen_at) VALUES(?,?,'Guest',NULL,?,?)")
      .run(guest, `web-guest:${guest}`, seen, seen);
    for (const member of [MEMBER, guest]) {
      raw.prepare("INSERT INTO group_live_presence(session_id,group_id,member_id,first_seen_at,last_seen_at) VALUES(?,'usa',?,?,?)")
        .run(started.sessionID, member, seen, seen);
    }
    await endAfterDua(env, new Date(Date.parse(dua.endsAt) + 1000));
    expect(row()).toMatchObject({ state: "offline", auto_end_at: null, session_id: null });
    expect(history()).toMatchObject([{ is_test: 0, ended_by: RELAY_AUTHOR }]);
    // The record is taken from the row as it ended: its title, who started it, and the attendance.
    expect(raw.prepare("SELECT session_id,kind,title,started_by,attendees FROM group_live_history WHERE group_id='usa'").get())
      .toEqual({ session_id: started.sessionID, kind: "zikr", title: "Daily Zikr", started_by: RELAY_AUTHOR, attendees: 2 });
  });

  it("a real start while a Test Zikr runs replaces the test; a test start while a test runs does not", async () => {
    const { live, row, history, pushes } = await setup();
    const test = await live({ state: "live", title: "Rehearsal", test: true });
    expect(test.status).toBe(201);
    const testID = ((await test.json()) as any).sessionID as string;
    expect(pushes).toEqual([]);
    const sameTest = await live({ state: "live", title: "Rehearsal", test: true });
    expect(sameTest.status).toBe(200);
    expect(await sameTest.json()).toMatchObject({ sessionID: testID, started: false });
    const real = await live({ state: "live", title: "Daily Zikr" });
    expect(real.status).toBe(201);
    const body = await real.json() as any;
    expect(body).toMatchObject({ state: "live", started: true, replacedTest: true });
    expect(body.sessionID).not.toBe(testID);
    expect(row()).toMatchObject({ state: "live", kind: "zikr", is_test: 0, session_id: body.sessionID });
    expect(history()).toEqual([{ session_id: testID, is_test: 1, ended_by: RELAY_AUTHOR }]);
    // The real Zikr is announced; the test never was.
    expect(pushes.length).toBe(1);
  });

  it("a meeting live in the Halqah is never taken over", async () => {
    const { raw, live, row, pushes } = await setup();
    const now = new Date().toISOString();
    raw.prepare(`INSERT INTO group_live(group_id,state,kind,title,started_at,started_by,updated_at,session_id)
      VALUES('usa','live','meeting','Monthly meeting',?,'admin-1',?,'session-meeting')`).run(now, now);
    const refused = await live({ state: "live", title: "Daily Zikr" });
    expect(refused.status).toBe(409);
    expect(await refused.json()).toEqual({ error: "A meeting is live in this Halqah" });
    expect((await live({ state: "dua" })).status).toBe(409);
    expect(row()).toMatchObject({ state: "live", kind: "meeting", session_id: "session-meeting" });
    expect(pushes).toEqual([]);
  });

  it("two starts at once make one session and one notice", async () => {
    const { env, row, history, pushes } = await setup();
    const input = { state: "live", title: "Daily Zikr" };
    const [first, second] = await Promise.all([relayLive(env, "usa", input), relayLive(env, "usa", input)]);
    expect([first.status, second.status].sort()).toEqual([200, 201]);
    const bodies = [await first.json(), await second.json()] as any[];
    const winner = bodies.find(body => body.started === true), loser = bodies.find(body => body.started === false);
    expect(winner.sessionID).toMatch(/^session-/);
    expect(loser).toMatchObject({ state: "live", sessionID: winner.sessionID, started: false });
    expect(row()).toMatchObject({ state: "live", session_id: winner.sessionID, started_by: RELAY_AUTHOR });
    expect(history()).toEqual([]);
    expect(pushes.length).toBe(1);
  });

  it("a late end alarm never ends a newer session", async () => {
    const { env, raw, live, row, history } = await setup();
    const started = await (await live({ state: "live", title: "Daily Zikr" })).json() as any;
    const dua = await (await live({ state: "dua" })).json() as any;
    // The cron picks this session; before it ends it, an admin's start has replaced it.
    const db = env.DB as any;
    let replaced = false;
    (env as any).DB = { ...db, prepare(sql: string) {
      const statement = db.prepare(sql);
      if (!replaced && sql.trimStart().startsWith("SELECT") && sql.includes("auto_end_at<=?")) {
        const all = statement.all.bind(statement);
        statement.all = async () => {
          const result = await all();
          replaced = true;
          raw.prepare("UPDATE group_live SET session_id='session-newer',auto_end_at=NULL,started_at=?,started_by='admin-1' WHERE group_id='usa'")
            .run(new Date().toISOString());
          return result;
        };
      }
      return statement;
    } };
    await endAfterDua(env, new Date(Date.parse(dua.endsAt) + 1000));
    expect(replaced).toBe(true);
    expect(row()).toMatchObject({ state: "live", session_id: "session-newer", auto_end_at: null });
    expect(history()).toEqual([]);
    // A guarded end for the old session is a no-op too.
    expect(await endSession(env, "usa", RELAY_AUTHOR, { sessionID: started.sessionID })).toBe(false);
    expect(row()).toMatchObject({ state: "live", session_id: "session-newer" });
    // The newer session still ends when its own dua is due.
    raw.prepare("UPDATE group_live SET auto_end_at=? WHERE group_id='usa'").run(new Date(Date.now() - 1000).toISOString());
    await endAfterDua(env);
    expect(row()).toMatchObject({ state: "offline", session_id: null });
    expect(history()).toEqual([{ session_id: "session-newer", is_test: 0, ended_by: RELAY_AUTHOR }]);
  });

  it("a Zikr the relay started ends by itself after five hours and an hour of stillness; four hours, a recent cue, or an admin's session do not", async () => {
    const { env, raw, live, row, history, pushes } = await setup();
    const started = await (await live({ state: "live", title: "Daily Zikr" })).json() as any;
    const now = new Date();
    const ago = (minutes: number) => new Date(now.getTime() - minutes * 60_000).toISOString();
    raw.prepare("UPDATE group_live SET started_at=? WHERE group_id='usa'").run(ago(4 * 60));
    await endStaleRelaySessions(env, now);
    expect(row()).toMatchObject({ state: "live", session_id: started.sessionID });
    raw.prepare("UPDATE group_live SET started_at=? WHERE group_id='usa'").run(ago(5 * 60 + 1));
    // The stage moved ten minutes ago: the Zikr is still going, however long it has run.
    raw.prepare(`INSERT INTO group_zikr_cues(group_id,event_id,stage_id,title,author_id,created_at,notification_state)
      VALUES('usa',?,'shajra','Shajra Sharif',?,?,'complete')`).run(event(3), RELAY_AUTHOR, ago(10));
    await endStaleRelaySessions(env, now);
    expect(row()).toMatchObject({ state: "live", session_id: started.sessionID });
    // Nothing on the stage for two hours: abandoned, and ended.
    raw.prepare("UPDATE group_zikr_cues SET created_at=? WHERE event_id=?").run(ago(2 * 60), event(3));
    await endStaleRelaySessions(env, now);
    expect(row()).toMatchObject({ state: "offline", session_id: null });
    expect(history()).toEqual([{ session_id: started.sessionID, is_test: 0, ended_by: RELAY_AUTHOR }]);
    // Only the start was announced; the quiet end notifies nobody.
    expect(pushes.length).toBe(1);
    // A session an admin started six hours ago is theirs to end.
    raw.prepare(`UPDATE group_live SET state='live',kind='zikr',title='Admin Zikr',session_id='session-admin',started_by='admin-1',started_at=?
      WHERE group_id='usa'`).run(ago(6 * 60));
    await endStaleRelaySessions(env, now);
    expect(row()).toMatchObject({ state: "live", session_id: "session-admin" });
  });
  it("a dua that names a session no longer live is refused and schedules nothing", async () => {
    const { raw, live, row } = await setup();
    const first = await (await live({ state: "live", title: "Daily Zikr" })).json() as any;
    // An admin ended that session and started another in its place.
    raw.prepare("UPDATE group_live SET session_id='session-newer',started_by='admin-1',auto_end_at=NULL WHERE group_id='usa'").run();
    const stale = await live({ state: "dua", sessionID: first.sessionID });
    expect(stale.status).toBe(409);
    expect(await stale.json()).toEqual({ error: "stale session" });
    expect(row()).toMatchObject({ state: "live", session_id: "session-newer", auto_end_at: null });
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_zikr_cues WHERE stage_id='dua'").get()).toEqual({ n: 0 });
    // Without a session id the dua binds to whatever is live, as before.
    const dua = await (await live({ state: "dua" })).json() as any;
    expect(row()).toMatchObject({ session_id: "session-newer", auto_end_at: dua.endsAt });
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_zikr_cues WHERE stage_id='dua'").get()).toEqual({ n: 1 });
    // The live session's own id is accepted, and the pending end answered again.
    expect(await (await live({ state: "dua", sessionID: "session-newer" })).json()).toEqual({ state: "dua", endsAt: dua.endsAt });
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_zikr_cues WHERE stage_id='dua'").get()).toEqual({ n: 1 });
  });

  it("a dua whose session is replaced between its read and its write schedules nothing and records no cue", async () => {
    const { env, raw, row } = await setup();
    await relayLive(env, "usa", { state: "live", title: "Daily Zikr" });
    const db = env.DB as any;
    let replaced = false;
    (env as any).DB = { ...db, prepare(sql: string) {
      const statement = db.prepare(sql);
      if (!replaced && sql.startsWith("SELECT state,kind,session_id,auto_end_at")) {
        const first = statement.first.bind(statement);
        statement.first = async () => {
          const result = await first();
          replaced = true;
          raw.prepare("UPDATE group_live SET session_id='session-newer',started_by='admin-1' WHERE group_id='usa'").run();
          return result;
        };
      }
      return statement;
    } };
    const dua = await relayLive(env, "usa", { state: "dua" });
    expect(replaced).toBe(true);
    expect(dua.status).toBe(409);
    expect(await dua.json()).toEqual({ error: "stale session" });
    expect(row()).toMatchObject({ state: "live", session_id: "session-newer", auto_end_at: null });
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_zikr_cues WHERE stage_id='dua'").get()).toEqual({ n: 0 });
  });

  it("live again names its session: another id is stale, the live id resumes, an id no longer live is a plain start", async () => {
    const { env, live, row, history } = await setup();
    const started = await (await live({ state: "live", title: "Daily Zikr" })).json() as any;
    const dua = await (await live({ state: "dua" })).json() as any;
    const wrong = await live({ state: "live", sessionID: "session-other" });
    expect(wrong.status).toBe(409);
    expect(await wrong.json()).toEqual({ error: "stale session" });
    expect(row()).toMatchObject({ session_id: started.sessionID, auto_end_at: dua.endsAt });
    const right = await live({ state: "live", sessionID: started.sessionID });
    expect(right.status).toBe(200);
    expect(await right.json()).toMatchObject({ sessionID: started.sessionID, resumed: true });
    expect(row()).toMatchObject({ session_id: started.sessionID, auto_end_at: null });
    // Once that session has ended, a start that still names it is a normal start.
    await endSession(env, "usa", "admin-1");
    const fresh = await live({ state: "live", title: "Daily Zikr", sessionID: started.sessionID });
    expect(fresh.status).toBe(201);
    const body = await fresh.json() as any;
    expect(body).toMatchObject({ state: "live", started: true });
    expect(body.sessionID).not.toBe(started.sessionID);
    expect(row()).toMatchObject({ state: "live", session_id: body.sessionID });
    expect(history()).toEqual([{ session_id: started.sessionID, is_test: 0, ended_by: "admin-1" }]);
  });

  it("a test start never resumes a real Zikr in its dua window, nor a real start a test", async () => {
    const { env, live, row, history, pushes } = await setup();
    const real = await (await live({ state: "live", title: "Daily Zikr" })).json() as any;
    const dua = await (await live({ state: "dua" })).json() as any;
    const test = await live({ state: "live", title: "Rehearsal", test: true });
    expect(test.status).toBe(200);
    expect(await test.json()).toEqual({ state: "live", sessionID: real.sessionID, started: false });
    expect(row()).toMatchObject({ session_id: real.sessionID, is_test: 0, auto_end_at: dua.endsAt });
    // The end stands, and the real Zikr ends on time.
    await endAfterDua(env, new Date(Date.parse(dua.endsAt) + 1000));
    expect(row()).toMatchObject({ state: "offline", session_id: null });
    // A test in its dua window is replaced by a real start, never resumed.
    const rehearsal = await (await live({ state: "live", title: "Rehearsal", test: true })).json() as any;
    const testDua = await (await live({ state: "dua" })).json() as any;
    expect(row()).toMatchObject({ session_id: rehearsal.sessionID, is_test: 1, auto_end_at: testDua.endsAt });
    const started = await live({ state: "live", title: "Daily Zikr" });
    expect(started.status).toBe(201);
    const body = await started.json() as any;
    expect(body).toMatchObject({ started: true, replacedTest: true });
    expect(body.sessionID).not.toBe(rehearsal.sessionID);
    expect(row()).toMatchObject({ session_id: body.sessionID, is_test: 0, auto_end_at: null });
    expect(history().map(entry => entry.session_id).sort()).toEqual([real.sessionID, rehearsal.sessionID].sort());
    expect(history().find(entry => entry.session_id === rehearsal.sessionID)).toMatchObject({ is_test: 1, ended_by: RELAY_AUTHOR });
    // Two real starts were announced; the test was not.
    expect(pushes.length).toBe(2);
  });

  it("a start that loses the race to an admin's meeting is refused like any meeting", async () => {
    const { env, raw, row, history, pushes } = await setup();
    const db = env.DB as any;
    let raced = false;
    (env as any).DB = { ...db, prepare(sql: string) {
      const statement = db.prepare(sql);
      // The relay has read an idle row; the admin's meeting lands before its start.
      if (!raced && sql.startsWith("SELECT state,kind,session_id,auto_end_at")) {
        const first = statement.first.bind(statement);
        statement.first = async () => {
          const result = await first();
          raced = true;
          const now = new Date().toISOString();
          raw.prepare(`INSERT INTO group_live(group_id,state,kind,title,started_at,started_by,updated_at,session_id)
            VALUES('usa','live','meeting','Monthly meeting',?,'admin-1',?,'session-meeting')
            ON CONFLICT(group_id) DO UPDATE SET state='live',kind='meeting',title='Monthly meeting',started_at=excluded.started_at,
              started_by='admin-1',updated_at=excluded.updated_at,session_id='session-meeting'`).run(now, now);
          return result;
        };
      }
      return statement;
    } };
    const refused = await relayLive(env, "usa", { state: "live", title: "Daily Zikr" });
    expect(raced).toBe(true);
    expect(refused.status).toBe(409);
    expect(await refused.json()).toEqual({ error: "A meeting is live in this Halqah" });
    expect(row()).toMatchObject({ state: "live", kind: "meeting", session_id: "session-meeting" });
    expect(history()).toEqual([]);
    expect(pushes).toEqual([]);
  });

  it("a resume between the alarm's read and its write wins: the alarm ends nothing", async () => {
    const { env, raw, live, row, history, pushes } = await setup();
    const started = await (await live({ state: "live", title: "Daily Zikr" })).json() as any;
    const dua = await (await live({ state: "dua" })).json() as any;
    const sent = pushes.length;
    const db = env.DB as any;
    const race: { resumed?: Response } = {};
    let hooked = false;
    (env as any).DB = { ...db, prepare(sql: string) {
      const statement = db.prepare(sql);
      // The alarm has read the row it means to end; the relay's live again lands before its write.
      if (!hooked && sql.includes("room_recording,is_test FROM group_live WHERE group_id=?")) {
        hooked = true;
        const first = statement.first.bind(statement);
        statement.first = async () => {
          const result = await first();
          race.resumed = await live({ state: "live", sessionID: started.sessionID });
          return result;
        };
      }
      return statement;
    } };
    await endAfterDua(env, new Date(Date.parse(dua.endsAt) + 1000));
    expect(race.resumed?.status).toBe(200);
    expect(await race.resumed!.json()).toEqual({ state: "live", sessionID: started.sessionID, started: false, resumed: true });
    // The write-level fence: the row no longer carries the end the alarm read, so nothing ends.
    expect(row()).toMatchObject({ state: "live", session_id: started.sessionID, auto_end_at: null });
    expect(history()).toEqual([]);
    expect(raw.prepare("SELECT hidden_at IS NOT NULL AS hidden FROM group_zikr_cues WHERE stage_id='dua'").get()).toEqual({ hidden: 1 });
    expect(pushes.length).toBe(sent);
  });

  it("an end between the resume's read and its write wins: the relay starts a fresh session", async () => {
    const { env, live, row, history, pushes } = await setup();
    const started = await (await live({ state: "live", title: "Daily Zikr" })).json() as any;
    const dua = await (await live({ state: "dua" })).json() as any;
    const db = env.DB as any;
    let ended = false;
    (env as any).DB = { ...db, prepare(sql: string) {
      const statement = db.prepare(sql);
      // The relay has read a row in its dua window; the alarm's end lands before its resume.
      if (!ended && sql.startsWith("SELECT state,kind,session_id,auto_end_at")) {
        ended = true;
        const first = statement.first.bind(statement);
        statement.first = async () => {
          const result = await first();
          await endAfterDua(env, new Date(Date.parse(dua.endsAt) + 1000));
          return result;
        };
      }
      return statement;
    } };
    const again = await live({ state: "live", title: "Daily Zikr" });
    expect(ended).toBe(true);
    // The resume's write found no end to cancel; the guarded start made a new session.
    expect(again.status).toBe(201);
    const body = await again.json() as any;
    expect(body).toMatchObject({ state: "live", started: true });
    expect(body.sessionID).not.toBe(started.sessionID);
    expect(row()).toMatchObject({ state: "live", session_id: body.sessionID, auto_end_at: null });
    expect(history()).toEqual([{ session_id: started.sessionID, is_test: 0, ended_by: RELAY_AUTHOR }]);
    expect(pushes.length).toBe(2);
  });
});
