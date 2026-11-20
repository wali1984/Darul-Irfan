// The websites: anyone may join a Halqah's live Zikr from the browser with a
// name and a place, and listens with no controls (owner 2026-11-04).
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { sqliteD1 } from "./sqlite-d1";
import { endAfterDua } from "../src/groupZikrStages";

const SECRET = "a".repeat(64);

function setup(room = false) {
  const { db, raw } = sqliteD1();
  const sent: { url: string; body: any }[] = [];
  vi.stubGlobal("fetch", async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    sent.push({ url, body: init?.body ? JSON.parse(String(init.body)) : undefined });
    return Response.json({ success: true, data: { token: "listener-token" } });
  });
  raw.prepare(`INSERT INTO group_live(group_id,state,kind,title,video_id,room_id,started_at,updated_at,session_id,queue_json)
    VALUES('usa','live','zikr','Thursday Zikr',NULL,?,'2026-11-04T00:00:00.000Z','now','session-1','[]')`).run(room ? "room-1" : null);
  raw.prepare("INSERT INTO members(id,apple_subject,email,created_at,last_seen_at) VALUES('x','x',NULL,'now','now')").run();
  raw.prepare(`INSERT INTO group_zikr_cues(group_id,event_id,stage_id,title,title_ur,author_id,created_at,notification_state)
    VALUES('usa','e1','latifa-3','3rd Latifa','تیسرا لطیفہ','x','2026-11-04T00:10:00.000Z','complete')`).run();
  const env = { DB: db, PUBLIC_BASE_URL: "https://api.example.com", REALTIME_ACCOUNT_ID: "a", REALTIME_APP_ID: "b",
    REALTIME_API_TOKEN: "t", RELAY_TOKEN: "relay-secret" } as unknown as Env;
  const post = (path: string, body: unknown, ip = "8.8.8.8") => worker.fetch(new Request(`https://api.example.com${path}`, {
    method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": ip }, body: JSON.stringify(body) }), env);
  const get = (path: string) => worker.fetch(new Request(`https://api.example.com${path}`), env);
  return { raw, env, post, get, sent };
}

afterEach(() => vi.unstubAllGlobals());

describe("joining a live Zikr from the websites", () => {
  it("lists what is live with its stage, without members", async () => {
    const { get } = setup();
    const body = await (await get("/v1/public/live?ids=usa,canada")).json() as any;
    expect(body.halqahs.find((h: any) => h.id === "usa")).toMatchObject({
      live: { kind: "zikr", title: "Thursday Zikr" }, stage: { stageID: "latifa-3", titleUr: "تیسرا لطیفہ" } });
    expect(body.halqahs.find((h: any) => h.id === "canada").live).toBeNull();
    expect(JSON.stringify(body)).not.toContain("member");
  });

  it("asks for a name and a place, then counts the visitor for the admins", async () => {
    const { post, raw } = setup();
    expect((await post("/v1/public/halqahs/usa/join", { name: "Ahmed", guestSecret: SECRET })).status).toBe(400);
    const joined = await post("/v1/public/halqahs/usa/join", { name: "Ahmed", city: "Boston", countryCode: "us", guestSecret: SECRET });
    expect(joined.status).toBe(200);
    expect(await joined.json()).toMatchObject({ live: { title: "Thursday Zikr" }, stage: { title: "3rd Latifa" } });
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_live_presence WHERE session_id='session-1'").get()).toEqual({ n: 1 });
    // Not made a member of the Halqah.
    expect(raw.prepare("SELECT COUNT(*) AS n FROM member_group_members WHERE group_id='usa' AND member_id IN (SELECT member_id FROM group_live_presence)").get()).toEqual({ n: 0 });
    expect((await post("/v1/public/halqahs/usa/presence", { guestSecret: SECRET })).status).toBe(200);
    expect((await post("/v1/public/halqahs/usa/presence", { guestSecret: "b".repeat(64) })).status).toBe(401);
  });

  it("never seats a visitor in the room (RealtimeKit bills per listener) and refuses when nothing is live", async () => {
    const { post, sent, raw } = setup(true);
    const joined = await (await post("/v1/public/halqahs/usa/join", { name: "Sara", city: "Leeds", countryCode: "GB", guestSecret: SECRET })).json() as any;
    // Live only: no room seat, no recording or video is ever handed to a website.
    expect(joined.room).toBeUndefined();
    expect(JSON.stringify(joined)).not.toMatch(/queue|playback|url|videoID/);
    expect(sent.filter(s => s.url.includes("/participants"))).toEqual([]);
    raw.prepare("UPDATE group_live SET state='offline'").run();
    expect((await post("/v1/public/halqahs/usa/join", { name: "Nadia", city: "York", countryCode: "GB", guestSecret: "d".repeat(64) })).status).toBe(409);
    expect(raw.prepare("SELECT COUNT(*) AS n FROM sheikh_public_profiles WHERE display_name='Nadia'").get()).toEqual({ n: 0 });
  });

  it("the live relay posts the stage called in Paltalk with its token; nobody else can", async () => {
    const { env, raw } = setup();
    const cue = (token: string | null, body: unknown) => worker.fetch(new Request("https://api.example.com/v1/service/groups/usa/zikr-cues", {
      method: "POST", headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(body) }), env);
    const body = { id: "11111111-2222-4333-8444-555555555555", stageID: "latifa-4" };
    expect((await cue(null, body)).status).toBe(401);
    expect((await cue("wrong", body)).status).toBe(401);
    expect((await cue("relay-secret", body)).status).toBe(201);
    expect((await cue("relay-secret", body)).status).toBe(200);
    expect(raw.prepare("SELECT author_id,stage_id FROM group_zikr_cues WHERE event_id=?").get(body.id)).toEqual({ author_id: "service-paltalk-relay", stage_id: "latifa-4" });
    raw.prepare("UPDATE group_live SET state='offline'").run();
    expect((await cue("relay-secret", { ...body, id: "11111111-2222-4333-8444-666666666666" })).status).toBe(409);
  });

  it("the relay starts the Zikr, calls the dua, and the session ends by itself five minutes later", async () => {
    const { env, raw } = setup();
    raw.prepare("UPDATE group_live SET state='offline'").run();
    const live = (token: string, body: unknown) => worker.fetch(new Request("https://api.example.com/v1/service/groups/usa/live", {
      method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${token}` }, body: JSON.stringify(body) }), env);
    expect((await live("wrong", { state: "live" })).status).toBe(401);
    expect((await live("relay-secret", { state: "dua" })).status).toBe(409);
    const started = await live("relay-secret", { state: "live", title: "Daily Zikr" });
    expect(started.status).toBe(201);
    expect((await live("relay-secret", { state: "live" })).status).toBe(200);
    const dua = await (await live("relay-secret", { state: "dua" })).json() as any;
    const endsAt = Date.parse(dua.endsAt);
    expect(endsAt - Date.now()).toBeGreaterThan(4 * 60_000);
    expect(raw.prepare("SELECT stage_id FROM group_zikr_cues ORDER BY sequence DESC LIMIT 1").get()).toEqual({ stage_id: "dua" });
    // A second dua call keeps the first end time.
    expect((await (await live("relay-secret", { state: "dua" })).json() as any).endsAt).toBe(dua.endsAt);
    await endAfterDua(env, new Date(endsAt - 1000));
    expect(raw.prepare("SELECT state FROM group_live WHERE group_id='usa'").get()).toEqual({ state: "live" });
    await endAfterDua(env, new Date(endsAt + 1000));
    expect(raw.prepare("SELECT state,auto_end_at FROM group_live WHERE group_id='usa'").get()).toEqual({ state: "offline", auto_end_at: null });
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_live_history WHERE group_id='usa'").get()).toEqual({ n: 1 });
  });

  it("the relay's test start is a Test Zikr: marked as a test, for admins only", async () => {
    const { env, raw } = setup();
    raw.prepare("UPDATE group_live SET state='offline'").run();
    const started = await worker.fetch(new Request("https://api.example.com/v1/service/groups/usa/live", {
      method: "POST", headers: { "content-type": "application/json", authorization: "Bearer relay-secret" },
      body: JSON.stringify({ state: "live", title: "Simulation", test: true }) }), env);
    expect(started.status).toBe(201);
    expect(((await started.json()) as any).test).toBe(true);
    expect(raw.prepare("SELECT state,is_test FROM group_live WHERE group_id='usa'").get()).toEqual({ state: "live", is_test: 1 });
  });
});

describe("north-america.: Zikr times and who is in the Zikr (owner 2026-11-17)", () => {
  it("gives a Halqah's Zikr times only when asked", async () => {
    const { get, raw } = setup();
    raw.prepare(`INSERT INTO group_zikr_sessions(id,group_id,title,weekdays_json,start_hour,start_minute,time_zone,anchor,duration_minutes,is_active,updated_at)
      VALUES('z1','usa','Halqah Zikr','[1,2,3,4,5,6,7]',19,0,'America/Los_Angeles',NULL,30,1,'now'),
            ('z2','usa','Old Zikr','[1]',5,0,'America/New_York',NULL,30,0,'now')`).run();
    const plain = await (await get("/v1/public/live?ids=usa")).json() as any;
    expect(plain.halqahs[0].times).toBeUndefined();
    const timed = await (await get("/v1/public/live?ids=usa&times=1")).json() as any;
    expect(timed.halqahs[0].times).toEqual([{ title: "Halqah Zikr", weekdays: [1, 2, 3, 4, 5, 6, 7], hour: 19, minute: 0,
      timeZone: "America/Los_Angeles", durationMinutes: 30 }]);
  });

  it("names website visitors and the admin who started it, counts app members, never a city", async () => {
    const { post, raw } = setup();
    const admin = "0123456789abcdef0123456789abcdef";
    raw.prepare("INSERT INTO members(id,apple_subject,display_name,email,created_at,last_seen_at) VALUES(?,?,?,NULL,'now','now')").run(admin, "apple-admin", "Halqah Admin");
    raw.prepare("INSERT INTO members(id,apple_subject,display_name,email,created_at,last_seen_at) VALUES('app1','apple-1','App Member',NULL,'now','now')").run();
    raw.prepare("UPDATE group_live SET started_by=? WHERE group_id='usa'").run(admin);
    const now = new Date().toISOString();
    raw.prepare("INSERT INTO group_live_presence(session_id,group_id,member_id,first_seen_at,last_seen_at) VALUES('session-1','usa','app1',?,?)").run(now, now);
    await post("/v1/public/halqahs/usa/join", { name: "Fatima", city: "Boston", countryCode: "US", guestSecret: "b".repeat(64) });
    const plain = await (await post("/v1/public/halqahs/usa/join", { name: "Omar", city: "Toronto", countryCode: "CA", guestSecret: SECRET })).json() as any;
    expect(plain.participants).toBeUndefined();
    const body = await (await post("/v1/public/halqahs/usa/presence", { guestSecret: SECRET, participants: true })).json() as any;
    expect(body.participants).toEqual({ people: [{ name: "Halqah Admin", admin: true }, { name: "Fatima" }, { name: "Omar", you: true }], inApp: 1, total: 4 });
    const text = JSON.stringify(body);
    for (const hidden of ["App Member", "Boston", "Toronto", admin]) expect(text).not.toContain(hidden);
  });
});

describe("north-america.: the YouTube video a Halqah plays (owner 2026-11-17)", () => {
  it("gives the video and where it is only when asked, never an audio recording", async () => {
    const { get, raw } = setup();
    const startedAt = new Date(Date.now() - 125_000).toISOString();
    raw.prepare("UPDATE group_live SET queue_json=?,queue_index=0,position_seconds=0,position_at=?,paused=0 WHERE group_id='usa'")
      .run(JSON.stringify([{ kind: "video", id: "yuQSH_D2iMo", title: "Online Zikr", durationSeconds: 2695 }]), startedAt);
    const plain = await (await get("/v1/public/live?ids=usa")).json() as any;
    expect(plain.halqahs[0].playing).toBeUndefined();
    const body = await (await get("/v1/public/live?ids=usa&playback=1")).json() as any;
    expect(body.halqahs[0].playing).toMatchObject({ videoID: "yuQSH_D2iMo", title: "Online Zikr", paused: false });
    expect(body.halqahs[0].playing.positionSeconds).toBeGreaterThanOrEqual(124);
    expect(body.halqahs[0].playing.positionSeconds).toBeLessThan(140);
    expect(body.halqahs[0].playing).not.toHaveProperty("startSeconds");
    // A clip from 3:41 to 44:02: the place is the video's own time, and it says where it stops.
    raw.prepare("UPDATE group_live SET queue_json=? WHERE group_id='usa'")
      .run(JSON.stringify([{ kind: "video", id: "yuQSH_D2iMo", title: "Online Zikr", durationSeconds: 2421, startSeconds: 221, endSeconds: 2642 }]));
    const clip = ((await (await get("/v1/public/live?ids=usa&playback=1")).json()) as any).halqahs[0].playing;
    expect(clip).toMatchObject({ startSeconds: 221, endSeconds: 2642 });
    expect(clip.positionSeconds).toBeGreaterThanOrEqual(221 + 124);
    expect(clip.positionSeconds).toBeLessThan(221 + 140);
    raw.prepare("UPDATE group_live SET queue_json=? WHERE group_id='usa'")
      .run(JSON.stringify([{ kind: "recording", id: "rec-1", title: "Audio", durationSeconds: 900 }]));
    expect(((await (await get("/v1/public/live?ids=usa&playback=1")).json()) as any).halqahs[0].playing).toBeNull();
    expect(((await (await get("/v1/public/live?ids=canada&playback=1")).json()) as any).halqahs.find((h: any) => h.id === "canada")?.playing ?? null).toBeNull();
  });
});

describe("north-america.: waiting for the Zikr (owner 2026-11-17)", () => {
  it("lists visitors who wait before the Zikr is live, and only when they ask to wait", async () => {
    const { post, raw } = setup();
    raw.prepare("UPDATE group_live SET state='offline',session_id=NULL WHERE group_id='usa'").run();
    expect((await post("/v1/public/halqahs/usa/join", { name: "Ahmed", city: "Boston", countryCode: "US", guestSecret: SECRET })).status).toBe(409);
    await post("/v1/public/halqahs/usa/join", { name: "Fatima", city: "Boston", countryCode: "US", guestSecret: "b".repeat(64), waiting: true });
    const body = await (await post("/v1/public/halqahs/usa/join", { name: "Omar", city: "Toronto", countryCode: "CA", guestSecret: SECRET, waiting: true, participants: true })).json() as any;
    expect(body).toMatchObject({ live: null, waiting: true });
    expect(body.participants).toEqual({ people: [{ name: "Fatima" }, { name: "Omar", you: true }], inApp: 0, total: 2 });
    const still = await (await post("/v1/public/halqahs/usa/presence", { guestSecret: SECRET, waiting: true, participants: true })).json() as any;
    expect(still.participants.total).toBe(2);
    expect(JSON.stringify(body)).not.toMatch(/Boston|Toronto/);
    // Never a session: no history row, and the waiting list is not the live session's attendance.
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_live_history").get()).toEqual({ n: 0 });
    raw.prepare("UPDATE group_live SET state='live',session_id='session-2' WHERE group_id='usa'").run();
    const live = await (await post("/v1/public/halqahs/usa/presence", { guestSecret: SECRET, waiting: true, participants: true })).json() as any;
    expect(live.live).toMatchObject({ title: "Thursday Zikr" });
    expect(live.participants.people).toEqual([{ name: "Omar", you: true }]);
  });
});
