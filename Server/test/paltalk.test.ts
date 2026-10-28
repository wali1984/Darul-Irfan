import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { reconcileLive } from "../src/live";
import { refreshPaltalkRoom } from "../src/paltalkRoom";
import { sqliteD1 } from "./sqlite-d1";

const pushes: { title: string; path: string }[] = [];
vi.mock("../src/apns", async original => ({
  ...(await original<typeof import("../src/apns")>()),
  sendTopicPush: async (_env: unknown, _id: string, _topic: string, title: string, _body: string, path: string) => {
    pushes.push({ title, path });
    return 1;
  },
}));

const room = (overrides: Record<string, unknown> = {}) => ({ id: 1, groupId: 2, groupName: "OURSHEIKH", online: true, liveMemberCount: 84, ...overrides });

function setup(listed: () => Record<string, unknown>[]) {
  const { db, raw } = sqliteD1();
  const requests: string[] = [];
  vi.stubGlobal("fetch", async (url: string) => {
    requests.push(String(url));
    if (String(url).startsWith("https://www.paltalk.com/")) {
      return new Response(JSON.stringify({ statusCode: 200, data: { topRoomDetails: listed() } }), { status: 200 });
    }
    return new Response("{}", { status: 200 });
  });
  const env = { DB: db, APNS_TOPIC: "x", PUBLIC_BASE_URL: "https://api.example.com", FACEBOOK_GRAPH_VERSION: "v25.0",
    PALTALK_ROOM: "oursheikh", PALTALK_GROUP_ID: "463712" } as unknown as Env;
  const live = async () => (await (await worker.fetch(new Request("https://api.example.com/v1/live"), env)).json()) as
    { state: string; room?: { platform: string; listeners: number; url?: string } };
  return { env, raw, requests, live };
}

afterEach(() => vi.unstubAllGlobals());

describe("the Paltalk room, from Paltalk's public directory", () => {
  it("shows the open room with how many are in it and its link, without making the YouTube zikr live", async () => {
    let open = true;
    const { env, raw, live } = setup(() => (open ? [room()] : []));
    raw.prepare("UPDATE live_broadcasts SET paltalk_url='https://paltalk.im/egnMPD3Y' WHERE id='official-live'").run();
    await refreshPaltalkRoom(env);
    await reconcileLive(env);
    const on = await live();
    expect(on.room).toEqual(expect.objectContaining({ platform: "paltalk", listeners: 84, url: "https://paltalk.im/egnMPD3Y" }));
    expect(on.state).not.toBe("live");
    open = false;
    await refreshPaltalkRoom(env);
    await reconcileLive(env);
    expect((await live()).room).toBeUndefined();
  });

  it("announces the Tahajjud zikr when the room opens before dawn, and not the evening room", async () => {
    pushes.length = 0;
    const dawn = new Date("2026-10-28T23:00:00Z"); // 04:00 in Pakistan
    const early = setup(() => [room()]);
    await refreshPaltalkRoom(early.env, dawn);
    await reconcileLive(early.env, dawn);
    await reconcileLive(early.env, new Date(dawn.getTime() + 60_000)); // still open: not again
    expect(pushes).toEqual([{ title: "Tahajjud Zikr has started", path: "darulirfan://zikr" }]);
    pushes.length = 0;
    const evening = new Date("2026-10-29T16:15:00Z"); // 21:15 in Pakistan
    const late = setup(() => [room()]);
    await refreshPaltalkRoom(late.env, evening);
    await reconcileLive(late.env, evening);
    expect(pushes).toEqual([]);
  });

  it("counts only the room itself, not one whose name merely contains it", async () => {
    const { env } = setup(() => [room({ groupName: "OURSHEIKH fans", id: 9, groupId: 9 })]);
    expect((await refreshPaltalkRoom(env)).online).toBe(false);
  });

  it("finds the room by its group number when Paltalk lists another name", async () => {
    const { env, requests } = setup(() => [room({ groupName: "Our Sheikh", groupId: 463712 })]);
    expect((await refreshPaltalkRoom(env)).online).toBe(true);
    expect(requests[0]).toContain("keyword=oursheikh");
  });

  it("keeps the time the room opened while it stays open", async () => {
    const { env } = setup(() => [room()]);
    const first = await refreshPaltalkRoom(env, new Date("2026-10-28T16:00:00Z"));
    const later = await refreshPaltalkRoom(env, new Date("2026-10-28T16:05:00Z"));
    expect(later.since).toBe(first.since);
  });
});
