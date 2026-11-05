// The websites: anyone may join a Halqah's live Zikr from the browser with a
// name and a place, and listens with no controls (owner 2026-11-04).
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { sqliteD1 } from "./sqlite-d1";

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
    REALTIME_API_TOKEN: "t" } as unknown as Env;
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
      live: { kind: "zikr", title: "Thursday Zikr", hasRoom: false }, stage: { stageID: "latifa-3", titleUr: "تیسرا لطیفہ" } });
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
    expect(joined.live).toMatchObject({ hasRoom: true });
    expect(joined.room).toBeUndefined();
    expect(sent.filter(s => s.url.includes("/participants"))).toEqual([]);
    raw.prepare("UPDATE group_live SET state='offline'").run();
    expect((await post("/v1/public/halqahs/usa/join", { name: "Nadia", city: "York", countryCode: "GB", guestSecret: "d".repeat(64) })).status).toBe(409);
    expect(raw.prepare("SELECT COUNT(*) AS n FROM sheikh_public_profiles WHERE display_name='Nadia'").get()).toEqual({ n: 0 });
  });
});
