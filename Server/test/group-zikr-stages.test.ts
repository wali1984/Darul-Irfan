import * as apns from "../src/apns";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../src/contracts";
import { addZikrStage, zikrStages, broadcastZikrCue, zikrCues, dispatchZikrCues, relayLive, relayZikrCue, endAfterDua,
  endStaleRelaySessions, zikrStage, RELAY_AUTHOR } from "../src/groupZikrStages";
import worker from "../src/index";
import { sqliteD1 } from "./sqlite-d1";

function setup() {
  const { db, raw } = sqliteD1();
  raw.prepare("INSERT INTO member_groups(id,name,updated_at) VALUES('our-sheikh','Renamed Sheikh Halqa','now')").run();
  for (const [id, role] of [["member", "member"], ["admin", "admin"], ["outsider", "member"], ["owner", "member"]] as const) {
    raw.prepare("INSERT INTO members(id,apple_subject,email,created_at,last_seen_at) VALUES(?,?,?,?,?)")
      .run(id, id, id + "@example.com", "now", "now");
    if (id !== "outsider" && id !== "owner") raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('our-sheikh',?,'now','test',?)").run(id, role);
  }
  raw.prepare("INSERT INTO group_live(group_id,state,kind,updated_at) VALUES('our-sheikh','live','zikr','now')").run();
  return { raw, env: { DB: db, SUPER_ADMIN_EMAILS: "owner@example.com" } as Env };
}
const draft = { id: "custom-12345678-1234-1234-1234-123456789abc", title: "Additional Muraqaba", titleUr: "???? ??????" };

describe("Our Sheikh stage catalogue", () => {
  it("hides controls and rejects stage writes offline or in a meeting, retaining history", async () => {
    const { env, raw } = setup();
    for (const [state, kind] of [["offline", "zikr"], ["live", "meeting"]] as const) {
      raw.prepare("UPDATE group_live SET state=?,kind=?").run(state, kind);
      expect((await (await zikrStages(env, "admin", "our-sheikh")).json() as any).canBroadcast).toBe(false);
      expect((await broadcastZikrCue(env, "admin", "our-sheikh", cue)).status).toBe(409);
      expect((await addZikrStage(env, "admin", "our-sheikh", draft)).status).toBe(409);
      expect((await zikrCues(env, "member", "our-sheikh", null)).status).toBe(200);
    }
  });
  it("uses stable group identity and exposes 14 ordered defaults with member read-only access", async () => {
    const { env } = setup();
    const response = await zikrStages(env, "member", "our-sheikh");
    const body = await response.json() as any;
    expect(response.status).toBe(200);
    expect(body.canBroadcast).toBe(false);
    expect(body.stages.map((s: any) => s.id)).toEqual([
      "latifa-1", "latifa-2", "latifa-3", "latifa-4", "latifa-5", "latifa-6", "latifa-7", "ahadiyat", "maiyyat", "aqrabiyyat",
      "sair-kaaba", "rauza-athar", "masjid-nabawi", "shajra",
    ]);
    expect(body.stages.every((s: any) => s.titleUr && !s.isCustom)).toBe(true);
  });
  it("refuses outsiders and member writes, including a spoofed manager field", async () => {
    const { env, raw } = setup();
    expect((await zikrStages(env, "outsider", "our-sheikh")).status).toBe(404);
    expect((await addZikrStage(env, "outsider", "our-sheikh", draft)).status).toBe(404);
    expect((await addZikrStage(env, "member", "our-sheikh", { ...draft, canManage: true })).status).toBe(403);
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_zikr_stages").get()).toEqual({ n: 0 });
  });
  it("persists custom stages after defaults and treats retries as one creation", async () => {
    const { env } = setup();
    expect((await addZikrStage(env, "admin", "our-sheikh", draft)).status).toBe(201);
    expect((await addZikrStage(env, "admin", "our-sheikh", draft)).status).toBe(200);
    expect((await addZikrStage(env, "admin", "our-sheikh", { ...draft, title: "Different" })).status).toBe(409);
    const body = await (await zikrStages(env, "member", "our-sheikh")).json() as any;
    expect(body.stages).toHaveLength(15);
    expect(body.stages[14]).toEqual({ ...draft, isCustom: true });
  });
  it("does not let custom input replace a built-in; every Halqah's stage is its own", async () => {
    const { env } = setup();
    expect((await addZikrStage(env, "owner", "our-sheikh", { ...draft, id: "latifa-1" })).status).toBe(400);
    // Other Halqahs have a stage too (owner 2026-11-04); USA has no live Zikr here, so it is closed.
    expect((await addZikrStage(env, "owner", "usa", draft)).status).toBe(409);
    expect((await addZikrStage(env, "admin", "usa", draft)).status).toBe(404);
    expect((await addZikrStage(env, "owner", "our-sheikh", { ...draft, title: " " })).status).toBe(400);
    expect((await addZikrStage(env, "owner", "our-sheikh", { ...draft, title: "a".repeat(101) })).status).toBe(400);
    expect((await addZikrStage(env, "owner", "our-sheikh", draft)).status).toBe(201);
    const body = await (await zikrStages(env, "owner", "our-sheikh")).json() as any;
    expect(body.canBroadcast).toBe(true);
  });
});


const cue = { id: "98765432-1234-1234-1234-123456789abc", stageID: "latifa-1" };
describe("Sheikh stage chat events", () => {
  it("records one event across concurrent retries and rejects conflicting reuse", async () => {
    const { env, raw } = setup();
    const replies = await Promise.all([broadcastZikrCue(env, "admin", "our-sheikh", cue), broadcastZikrCue(env, "admin", "our-sheikh", cue)]);
    expect(replies.map(r => r.status).sort()).toEqual([200, 201]);
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_zikr_cues").get()).toEqual({ n: 1 });
    expect((await broadcastZikrCue(env, "admin", "our-sheikh", { ...cue, stageID: "latifa-2" })).status).toBe(409);
    expect((await broadcastZikrCue(env, "owner", "our-sheikh", cue)).status).toBe(409);
    const body = await (await zikrCues(env, "member", "our-sheikh", null)).json() as any;
    expect(body.cues).toHaveLength(1);
    expect(body.cues[0]).toMatchObject({ id: cue.id, stageID: "latifa-1", title: "1st Latifa", authorID: "admin", notificationState: "complete" });
  });
  it("permits a deliberate repeat using a new event ID and keeps server ordering", async () => {
    const { env } = setup();
    const first = await (await broadcastZikrCue(env, "admin", "our-sheikh", cue)).json() as any;
    await broadcastZikrCue(env, "admin", "our-sheikh", { ...cue, id: "11111111-1234-1234-1234-123456789abc" });
    const body = await (await zikrCues(env, "member", "our-sheikh", String(first.cue.sequence))).json() as any;
    expect(body.cues).toHaveLength(1);
    expect(body.cues[0].sequence).toBeGreaterThan(first.cue.sequence);
    expect(body.nextSequence).toBe(body.cues[0].sequence);
    const empty = await (await zikrCues(env, "member", "our-sheikh", String(body.nextSequence))).json() as any;
    expect(empty.cues).toEqual([]);
    expect(empty.nextSequence).toBe(body.nextSequence);
  });
  it("rejects unauthorized writes, outsiders, invalid cursors and unknown stages", async () => {
    const { env, raw } = setup();
    expect((await broadcastZikrCue(env, "member", "our-sheikh", cue)).status).toBe(403);
    expect((await broadcastZikrCue(env, "outsider", "our-sheikh", cue)).status).toBe(404);
    expect((await zikrCues(env, "outsider", "our-sheikh", null)).status).toBe(404);
    expect((await broadcastZikrCue(env, "admin", "our-sheikh", { ...cue, stageID: "missing" })).status).toBe(404);
    expect((await zikrCues(env, "member", "our-sheikh", "-1")).status).toBe(400);
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_zikr_cues").get()).toEqual({ n: 0 });
  });
  it("snapshots custom names from the server and ignores spoofed titles", async () => {
    const { env } = setup();
    await addZikrStage(env, "admin", "our-sheikh", draft);
    const response = await broadcastZikrCue(env, "admin", "our-sheikh", { ...cue, stageID: draft.id, title: "Spoofed" });
    const body = await response.json() as any;
    expect(response.status).toBe(201);
    expect(body.cue).toMatchObject({ title: draft.title, titleUr: draft.titleUr, stageID: draft.id });
  });
});


afterEach(() => vi.restoreAllMocks());
function linkedDevices(raw: ReturnType<typeof sqliteD1>["raw"]) {
  for (const [id, member, locale] of [["EN", "member", "en"], ["UR", "admin", "ur-PK"], ["OUT", "outsider", "en"]] as const) {
    raw.prepare("INSERT INTO devices(installation_id,apns_token,locale,timezone,topics_json,environment,app_version,created_at,last_seen_at) VALUES(?,?,?,'UTC','[]','production','1','now','now')").run(id, id, locale);
    raw.prepare("INSERT INTO member_devices(member_id,installation_id,updated_at) VALUES(?,?,'now')").run(member, id);
  }
}
function pendingCue(raw: ReturnType<typeof sqliteD1>["raw"], id: string, date: Date) {
  raw.prepare("INSERT INTO group_zikr_cues(group_id,event_id,stage_id,title,title_ur,author_id,created_at) VALUES('our-sheikh',?,'latifa-1','1st Latifa','????? 1','admin',?)").run(id, date.toISOString());
}
function acceptPushes(raw: ReturnType<typeof sqliteD1>["raw"]) {
  return vi.spyOn(apns, "sendPushToInstallations").mockImplementation(async (_env, event, topic, ids) => {
    for (const id of ids) raw.prepare("INSERT OR REPLACE INTO notification_deliveries(event_id,installation_id,topic,status,created_at) VALUES(?,?,?,'accepted','now')").run(event, id, topic);
    return ids.length;
  });
}

describe("stage delivery retry and recipient isolation", () => {
  it("localizes only member devices, serializes concurrent dispatch and does not resend completion", async () => {
    const { env, raw } = setup(); linkedDevices(raw);
    const now = new Date(); pendingCue(raw, cue.id, now);
    const sender = acceptPushes(raw);
    await Promise.all([dispatchZikrCues(env, now), dispatchZikrCues(env, now)]);
    expect(sender).toHaveBeenCalledTimes(2); // English and Urdu cohorts, each once.
    expect(sender.mock.calls.flatMap(call => call[3]).sort()).toEqual(["EN", "UR"]);
    expect(sender.mock.calls.map(call => call[4])).toEqual(["1st Latifa", "????? 1"]);
    expect(sender.mock.calls.map(call => call[5])).toEqual(["Our Sheikh: current Zikr stage", "ہمارے شیخ: ذکر کا موجودہ مرحلہ"]);
    expect(sender.mock.calls[0]?.[7]).toMatchObject({ sound: "zikr_soft_chime", collapseID: "sheikh-zikr-stage" });
    expect(raw.prepare("SELECT notification_state FROM group_zikr_cues").get()).toEqual({ notification_state: "complete" });
    await dispatchZikrCues(env, now);
    expect(sender).toHaveBeenCalledTimes(2);
  });
  it("keeps provider failures pending and releases the lease for retry", async () => {
    const { env, raw } = setup(); linkedDevices(raw);
    const now = new Date(); pendingCue(raw, cue.id, now);
    vi.spyOn(apns, "sendPushToInstallations").mockRejectedValue(new Error("offline"));
    await expect(dispatchZikrCues(env, now)).rejects.toThrow("offline");
    expect(raw.prepare("SELECT notification_state,notification_lease_until FROM group_zikr_cues").get())
      .toEqual({ notification_state: "pending", notification_lease_until: null });
    vi.restoreAllMocks(); const sender = acceptPushes(raw);
    await dispatchZikrCues(env, now);
    expect(sender).toHaveBeenCalledTimes(2);
    expect(raw.prepare("SELECT notification_state FROM group_zikr_cues").get()).toEqual({ notification_state: "complete" });
  });
  it("expires old or superseded cues without deleting their chat records", async () => {
    const { env, raw } = setup(); linkedDevices(raw);
    const now = new Date(); pendingCue(raw, "old", new Date(now.getTime() - 360_000));
    pendingCue(raw, "superseded", now); pendingCue(raw, "current", now);
    const sender = acceptPushes(raw);
    await dispatchZikrCues(env, now);
    expect(sender.mock.calls.every(call => call[1] === "halqah-cue:current")).toBe(true);
    expect(raw.prepare("SELECT notification_state FROM group_zikr_cues ORDER BY sequence").all())
      .toEqual([{ notification_state: "expired" }, { notification_state: "expired" }, { notification_state: "complete" }]);
  });
  it("does not send a pending chime after the Halqa ends its Zikr", async () => {
    const { env, raw } = setup(); linkedDevices(raw);
    const now = new Date(); pendingCue(raw, cue.id, now);
    raw.prepare("UPDATE group_live SET state='offline'").run();
    const sender = acceptPushes(raw);
    await dispatchZikrCues(env, now);
    expect(sender).not.toHaveBeenCalled();
    expect(raw.prepare("SELECT notification_state FROM group_zikr_cues").get()).toEqual({ notification_state: "expired" });
    // The record is kept, but once the Zikr ends its stage leaves every screen.
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_zikr_cues").get()).toEqual({ n: 1 });
    expect((await (await zikrCues(env, "member", "our-sheikh", null)).json() as any).cues).toHaveLength(0);
  });
});


// What viewers see while the relay follows the Zikr (audit 2026-11-13): one dua
// card, an end soon after the room closes, the quiet end after the Shajra, the
// return to the 1st Latifa named as such, and the stage never sent backwards.
describe("the relay's stage as viewers see it", () => {
  afterEach(() => vi.unstubAllGlobals());
  async function relaySetup() {
    const { env, raw } = setup();
    vi.stubGlobal("fetch", async () => new Response("", { status: 200 }));
    let n = 0;
    const id = () => `22222222-2222-4222-8222-${String(++n).padStart(12, "0")}`;
    const relay = (stageID: string, extra: Record<string, unknown> = {}) => relayZikrCue(env, "usa", { id: id(), stageID, ...extra });
    const shown = () => raw.prepare("SELECT stage_id AS id FROM group_zikr_cues WHERE group_id='usa' AND hidden_at IS NULL ORDER BY sequence").all()
      .map((row: any) => row.id);
    const row = () => raw.prepare("SELECT state,session_id,auto_end_at FROM group_live WHERE group_id='usa'").get() as any;
    const started = await (await relayLive(env, "usa", { state: "live", title: "Daily Zikr" })).json() as any;
    return { env, raw, relay, shown, row, id, sessionID: started.sessionID as string };
  }

  it("the return to the 1st Latifa is shown as the 1st Latifa, never 'Raabta'", async () => {
    const { raw, relay } = await relaySetup();
    await relay("latifa-7");
    const back = await relay("raabta");
    expect(back.status).toBe(201);
    expect((await back.json() as any).cue).toMatchObject({ stageID: "latifa-1", title: "1st Latifa", titleUr: "پہلا لطیفہ" });
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_zikr_cues WHERE stage_id='raabta'").get()).toEqual({ n: 0 });
  });

  it("refuses a relay stage behind the one shown; the return to the 1st Latifa, phases and admins' taps pass", async () => {
    const { env, relay, shown, id } = await relaySetup();
    for (const stage of ["latifa-1", "latifa-4", "latifa-7"]) expect((await relay(stage)).status).toBe(201);
    expect((await relay("latifa-1")).status).toBe(201);
    expect((await relay("ahadiyat")).status).toBe(201);
    // The 12 Nov double reading: the 1st Latifa a second after Ahadiyat.
    const behind = await relay("latifa-1");
    expect(behind.status).toBe(409);
    expect(await behind.json()).toEqual({ error: "behind", stageID: "ahadiyat" });
    expect((await relay("raabta")).status).toBe(409);
    expect((await relay("bayan-after")).status).toBe(201);
    expect((await relay("tasbih")).status).toBe(201);
    // A retry of a cue saved before the stage moved on is answered as saved.
    const early = id();
    expect((await relayZikrCue(env, "usa", { id: early, stageID: "maiyyat" })).status).toBe(201);
    expect((await relay("aqrabiyyat")).status).toBe(201);
    expect((await relayZikrCue(env, "usa", { id: early, stageID: "maiyyat" })).status).toBe(200);
    // The Super admin may set the stage back by hand.
    const tap = await broadcastZikrCue(env, "owner", "usa", { id: id(), stageID: "latifa-3" });
    expect(tap.status).toBe(201);
    expect(shown().at(-1)).toBe("latifa-3");
  });

  it("a relay cue names its session: another session's is refused, the live one's and an unnamed one are taken", async () => {
    const { relay, sessionID, shown } = await relaySetup();
    const stale = await relay("latifa-1", { sessionID: "session-other" });
    expect(stale.status).toBe(409);
    expect(await stale.json()).toEqual({ error: "stale session" });
    expect(shown()).toEqual([]);
    expect((await relay("latifa-1", { sessionID })).status).toBe(201);
    expect((await relay("latifa-2")).status).toBe(201);
  });

  it("the relay repeating the stage shown keeps it alive without a second notification", async () => {
    const { raw, relay } = await relaySetup();
    await relay("latifa-3");
    await relay("latifa-3");
    await relay("bayan-after");
    await relay("bayan-after");
    const states = raw.prepare("SELECT notification_state AS s FROM group_zikr_cues WHERE group_id='usa' ORDER BY sequence").all().map((row: any) => row.s);
    // The first Latifa notifies (sent, or expired once superseded); the repeat and the phases never do.
    expect(states.slice(1)).toEqual(["complete", "complete", "complete"]);
  });

  it("one dua card: the room closing after the aameen adds none, and ends the session within a minute", async () => {
    const { env, relay, shown, row } = await relaySetup();
    await relay("shajra");
    const aameen = await (await relayLive(env, "usa", { state: "dua" })).json() as any;
    expect(Date.parse(aameen.endsAt) - Date.now()).toBeGreaterThan(4 * 60_000);
    const closed = await (await relayLive(env, "usa", { state: "dua", closed: true })).json() as any;
    expect(Date.parse(closed.endsAt) - Date.now()).toBeLessThanOrEqual(60_000);
    expect(row().auto_end_at).toBe(closed.endsAt);
    expect(shown()).toEqual(["shajra", "dua"]);
    // Another closed report keeps the sooner end.
    expect(await (await relayLive(env, "usa", { state: "dua", closed: true })).json()).toEqual({ state: "dua", endsAt: closed.endsAt });
    await endAfterDua(env, new Date(Date.parse(closed.endsAt) + 1000));
    expect(row()).toMatchObject({ state: "offline", session_id: null });
  });

  it("the room closing with no dua shown says the Zikr has ended; a resume takes it off again", async () => {
    const { env, raw, relay, shown, row, sessionID } = await relaySetup();
    await relay("shajra");
    const closed = await (await relayLive(env, "usa", { state: "dua", closed: true })).json() as any;
    expect(Date.parse(closed.endsAt) - Date.now()).toBeLessThanOrEqual(60_000);
    expect(shown()).toEqual(["shajra", "ended"]);
    expect(raw.prepare("SELECT title,title_ur,notification_state FROM group_zikr_cues WHERE stage_id='ended'").get())
      .toEqual({ title: "The Zikr has ended", title_ur: "ذکر ختم ہو گیا", notification_state: "complete" });
    expect((await relayLive(env, "usa", { state: "live", sessionID })).status).toBe(200);
    expect(row()).toMatchObject({ state: "live", session_id: sessionID, auto_end_at: null });
    expect(shown()).toEqual(["shajra"]);
  });

  it("a resume hides every dua card after the last stage, not only the newest", async () => {
    const { env, raw, relay, shown, sessionID } = await relaySetup();
    await relay("bayan-after");
    // Two dua cards, as on 13 Nov (the server put up one per report).
    for (const n of [1, 2]) raw.prepare(`INSERT INTO group_zikr_cues(group_id,event_id,stage_id,title,author_id,created_at,notification_state)
      VALUES('usa',?,'dua','Dua',?,?,'complete')`).run(`dua-${n}`, RELAY_AUTHOR, new Date().toISOString());
    raw.prepare("UPDATE group_live SET auto_end_at=? WHERE group_id='usa'").run(new Date(Date.now() + 300_000).toISOString());
    expect((await relayLive(env, "usa", { state: "live", sessionID })).status).toBe(200);
    expect(shown()).toEqual(["bayan-after"]);
    // A dua called again puts up one card, however often it is reported.
    await relayLive(env, "usa", { state: "dua" });
    await relayLive(env, "usa", { state: "dua" });
    expect(shown()).toEqual(["bayan-after", "dua"]);
  });

  it("a Zikr that reached its end and went quiet for half an hour ends, however young; a still Latifa or a recent Bayan does not", async () => {
    const { env, raw, relay, row } = await relaySetup();
    const now = new Date();
    const age = (minutes: number) => raw.prepare("UPDATE group_zikr_cues SET created_at=? WHERE group_id='usa'")
      .run(new Date(now.getTime() - minutes * 60_000).toISOString());
    raw.prepare("UPDATE group_live SET started_at=? WHERE group_id='usa'").run(new Date(now.getTime() - 90 * 60_000).toISOString());
    await relay("latifa-5"); age(45);
    await endStaleRelaySessions(env, now);
    expect(row().state).toBe("live");
    await relay("bayan-after"); age(20);
    await endStaleRelaySessions(env, now);
    expect(row().state).toBe("live");
    age(31);
    await endStaleRelaySessions(env, now);
    expect(row()).toMatchObject({ state: "offline", session_id: null });
  });

  it("the stage carries its session id, and the public live view is cached two seconds at most", async () => {
    const { env, sessionID } = await relaySetup();
    const stage = await (await zikrStage(env, "owner", "usa", new URL("https://api.example.com/x"))).json() as any;
    expect(stage.live.sessionID).toBe(sessionID);
    const reply = await worker.fetch(new Request("https://api.example.com/v1/public/live?ids=usa"), env);
    expect(reply.headers.get("cache-control")).toBe("public,max-age=2");
  });
});
