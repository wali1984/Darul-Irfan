import * as apns from "../src/apns";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../src/contracts";
import { broadcastZikrCue, dispatchZikrCues, hideStageMessage, postStageMessage, zikrStage, zikrStages } from "../src/groupZikrStages";
import { sqliteD1 } from "./sqlite-d1";

function setup() {
  const { db, raw } = sqliteD1();
  raw.prepare("INSERT INTO member_groups(id,name,updated_at) VALUES('our-sheikh','Our Sheikh','now')").run();
  for (const [id, role] of [["member", "member"], ["admin", "admin"], ["outsider", "member"]] as const) {
    raw.prepare("INSERT INTO members(id,apple_subject,email,created_at,last_seen_at,display_name) VALUES(?,?,?,?,?,?)")
      .run(id, id, id + "@example.com", "now", "now", id === "admin" ? "Admin" : null);
    if (id !== "outsider") raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('our-sheikh',?,'now','test',?)").run(id, role);
  }
  raw.prepare("INSERT INTO sheikh_public_profiles(member_id,display_name,city,country_code,updated_at) VALUES('member','Ahmed','Lahore','PK','now')").run();
  raw.prepare("INSERT INTO group_live(group_id,state,kind,started_at,updated_at) VALUES('our-sheikh','live','zikr','2026-11-03T00:00:00.000Z','now')").run();
  raw.prepare(`INSERT INTO feed_items(id,source,kind,title,source_url,image_url,video_id,published_at,updated_at)
    VALUES('youtube:abcdefghijk','youtube','video','Online Zikr with Sheikh-ul-Mukarram','https://y','https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg','abcdefghijk','2026-11-02T00:00:00Z','now')`).run();
  return { raw, env: { DB: db } as Env };
}
const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const stage = (env: Env, member: string, query = "") =>
  zikrStage(env, member, "our-sheikh", new URL(`https://x/v1/groups/our-sheikh/stage${query}`));
afterEach(() => vi.restoreAllMocks());

describe("live Zikr stage", () => {
  it("shows the picture, the session and lets only admins lead", async () => {
    const { env } = setup();
    const member = await (await stage(env, "member")).json() as any;
    expect(member).toMatchObject({ live: { startedAt: "2026-11-03T00:00:00.000Z" }, canLead: false,
      pictureURL: "https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg",
      pictureHDURL: "https://i.ytimg.com/vi/abcdefghijk/maxresdefault.jpg", cues: [], messages: [] });
    expect((await (await stage(env, "admin")).json() as any).canLead).toBe(true);
    expect((await stage(env, "outsider")).status).toBe(404);
    expect((await stage(env, "member", "?chat=x")).status).toBe(400);
  });

  it("members send only ready-made messages; admins may type; names come from the public profile", async () => {
    const { env } = setup();
    const sent = await postStageMessage(env, "member", "our-sheikh", { id: uuid(1), presetID: "salam" });
    expect(sent.status).toBe(201);
    expect((await sent.json() as any).message).toMatchObject({ authorName: "Ahmed", city: "Lahore", presetID: "salam",
      text: "Assalamu alaikum wa rahmatullah", textUr: "السلام علیکم ورحمۃ اللہ" });
    expect((await postStageMessage(env, "member", "our-sheikh", { id: uuid(2), text: "hello" })).status).toBe(403);
    expect((await postStageMessage(env, "member", "our-sheikh", { id: uuid(3), presetID: "unknown" })).status).toBe(400);
    expect((await postStageMessage(env, "admin", "our-sheikh", { id: uuid(4), text: "  Zikr begins   now " })).status).toBe(201);
    expect((await postStageMessage(env, "admin", "our-sheikh", { id: uuid(5), text: "x".repeat(201) })).status).toBe(400);
    // A retry of the same message is the same message, not a second one.
    expect((await postStageMessage(env, "member", "our-sheikh", { id: uuid(1), presetID: "salam" })).status).toBe(200);
    const page = await (await stage(env, "member")).json() as any;
    expect(page.messages.map((m: any) => m.text)).toEqual(["Assalamu alaikum wa rahmatullah", "Zikr begins now"]);
    expect(page.nextChat).toBe(page.messages.at(-1).sequence);
  });

  it("slows a member to one message every 3 seconds and closes the chat when not live", async () => {
    const { env, raw } = setup();
    expect((await postStageMessage(env, "member", "our-sheikh", { id: uuid(1), presetID: "ameen" })).status).toBe(201);
    expect((await postStageMessage(env, "member", "our-sheikh", { id: uuid(2), presetID: "ameen" })).status).toBe(429);
    raw.prepare("UPDATE group_live SET state='offline'").run();
    expect((await postStageMessage(env, "admin", "our-sheikh", { id: uuid(3), presetID: "ameen" })).status).toBe(409);
  });

  it("an admin's removal reaches phones that already showed the message", async () => {
    const { env } = setup();
    await postStageMessage(env, "member", "our-sheikh", { id: uuid(1), presetID: "dua-request" });
    const first = await (await stage(env, "member")).json() as any;
    expect((await hideStageMessage(env, "member", "our-sheikh", uuid(1))).status).toBe(403);
    expect((await hideStageMessage(env, "admin", "our-sheikh", uuid(1))).status).toBe(204);
    const next = await (await stage(env, "member", `?chat=${first.nextChat}`)).json() as any;
    expect(next.hidden).toEqual([uuid(1)]);
    expect((await (await stage(env, "member")).json() as any).messages).toEqual([]);
  });

  it("recitations carry their Arabic, are offered to admins, and send no notification", async () => {
    const { env } = setup();
    const push = vi.spyOn(apns, "sendPushToInstallations").mockResolvedValue(undefined as any);
    const catalogue = await (await zikrStages(env, "admin", "our-sheikh")).json() as any;
    expect(catalogue.recitations.map((r: any) => r.id)).toContain("basmalah");
    expect(catalogue.presets.map((p: any) => p.id)).toContain("dua-request");
    const cue = await broadcastZikrCue(env, "admin", "our-sheikh", { id: uuid(9), stageID: "istighfar" });
    expect(cue.status).toBe(201);
    expect((await cue.json() as any).cue).toMatchObject({ title: "Istighfar", arabic: "أَسْتَغْفِرُ اللّٰهَ رَبِّي مِنْ كُلِّ ذَنْبٍ وَأَتُوبُ إِلَيْهِ", notificationState: "complete" });
    await dispatchZikrCues(env);
    expect(push).not.toHaveBeenCalled();
  });

  it("a recitation after a Latifa does not cancel the Latifa's pending notification", async () => {
    const { env, raw } = setup();
    vi.spyOn(apns, "sendPushToInstallations").mockRejectedValue(new Error("provider down"));
    await broadcastZikrCue(env, "admin", "our-sheikh", { id: uuid(10), stageID: "latifa-1" });
    await broadcastZikrCue(env, "admin", "our-sheikh", { id: uuid(11), stageID: "basmalah" });
    await dispatchZikrCues(env).catch(() => undefined);
    // No phone here to deliver to, so it completes; it must not be expired.
    expect((raw.prepare("SELECT notification_state FROM group_zikr_cues WHERE stage_id='latifa-1'").get() as any)
      .notification_state).not.toBe("expired");
  });
});
