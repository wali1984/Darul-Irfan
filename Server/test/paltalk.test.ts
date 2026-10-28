import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { reconcileLive } from "../src/live";
import { refreshPaltalkRoom } from "../src/paltalkRoom";
import { sqliteD1 } from "./sqlite-d1";

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
    { state: string; room?: { platform: string; listeners: number } };
  return { env, raw, requests, live };
}

afterEach(() => vi.unstubAllGlobals());

describe("the Paltalk room, from Paltalk's public directory", () => {
  it("goes live when the room opens, with how many are in it, and ends when it closes", async () => {
    let open = true;
    const { env, live } = setup(() => (open ? [room()] : []));
    await refreshPaltalkRoom(env);
    await reconcileLive(env);
    expect(await live()).toMatchObject({ state: "live", room: { platform: "paltalk", listeners: 84 } });
    open = false;
    await refreshPaltalkRoom(env);
    await reconcileLive(env);
    const closed = await live();
    expect(closed.state).toBe("ended");
    expect(closed.room).toBeUndefined();
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
