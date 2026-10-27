import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { reconcileLive } from "../src/live";
import { sqliteD1 } from "./sqlite-d1";

const INPUT_A = "a".repeat(32);
const INPUT_B = "b".repeat(32);
const HOST = "customer-abc123.cloudflarestream.com";

function setup() {
  const { db, raw } = sqliteD1();
  const sent: Array<{ url: string; body: string }> = [];
  vi.stubGlobal("fetch", async (url: string, init?: RequestInit) => {
    sent.push({ url: String(url), body: String(init?.body ?? "") });
    return new Response("{}", { status: 200 });
  });
  const env = {
    DB: db, APNS_TOPIC: "us.naqshbaniaowaisiah", PUBLIC_BASE_URL: "https://api.example.com", FACEBOOK_GRAPH_VERSION: "v25.0",
    LISTENER_TOKEN: "listener-secret", STREAM_INPUTS: `${INPUT_A},${INPUT_B}`, STREAM_CUSTOMER_HOST: HOST,
    STREAM_WEBHOOK_SECRET: "stream-secret", ALERT_WHATSAPP_NUMBERS: "+1 929 240 5561",
    WHATSAPP_ACCESS_TOKEN: "wa-token", WHATSAPP_PHONE_NUMBER_ID: "123456",
  } as unknown as Env;
  const heartbeat = (body: Record<string, unknown>, token = "listener-secret") =>
    worker.fetch(new Request("https://api.example.com/v1/live/listener", {
      method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify(body),
    }), env);
  const streamEvent = (input: string, event: string, secret = "stream-secret") =>
    worker.fetch(new Request("https://api.example.com/v1/live/stream-events", {
      method: "POST", headers: { "cf-webhook-auth": secret, "content-type": "application/json" },
      body: JSON.stringify({ data: { input_id: input, event_type: event } }),
    }), env);
  const live = async () => (await (await worker.fetch(new Request("https://api.example.com/v1/live"), env)).json()) as
    { state: string; sources: { kind: string; url: string }[] };
  return { env, raw, sent, heartbeat, streamEvent, live };
}

afterEach(() => vi.unstubAllGlobals());

describe("live zikr pipeline", () => {
  it("refuses heartbeats and Stream events without their secrets", async () => {
    const { heartbeat, streamEvent } = setup();
    expect((await heartbeat({ listener: "listener-a" }, "wrong")).status).toBe(404);
    expect((await streamEvent(INPUT_A, "live_input.connected", "wrong")).status).toBe(404);
  });

  it("goes live in the app when a listener streams, and ends when it stops", async () => {
    const { heartbeat, live, sent } = setup();
    expect((await heartbeat({ listener: "listener-a", inRoom: true, streaming: true, input: INPUT_A })).status).toBe(200);
    const on = await live();
    expect(on.state).toBe("live");
    expect(on.sources[0]).toEqual(expect.objectContaining({ kind: "ownedStream", url: `https://${HOST}/${INPUT_A}/manifest/video.m3u8` }));
    await heartbeat({ listener: "listener-a", inRoom: false, streaming: false });
    const off = await live();
    expect(off.state).toBe("ended");
    expect(off.sources.filter(s => s.kind === "ownedStream")).toEqual([]);
    expect(sent.filter(s => s.url.includes("graph.facebook.com"))).toEqual([]);
  });

  it("fails over to input B when Stream reports input A disconnected", async () => {
    const { heartbeat, streamEvent, live } = setup();
    await heartbeat({ listener: "listener-a", inRoom: true, streaming: true, input: INPUT_A });
    await heartbeat({ listener: "listener-b", inRoom: true, streaming: true, input: INPUT_B });
    expect((await live()).sources[0]?.url).toContain(INPUT_A);
    await streamEvent(INPUT_A, "live_input.disconnected");
    expect((await live()).sources[0]?.url).toContain(INPUT_B);
    await streamEvent(INPUT_A, "live_input.connected");
    expect((await live()).sources[0]?.url).toContain(INPUT_A);
  });

  it("offers the hub only while the channel's own live video is off", async () => {
    const { raw, heartbeat, live } = setup();
    await heartbeat({ listener: "listener-a", inRoom: true, streaming: true, input: INPUT_A });
    raw.prepare("UPDATE live_broadcasts SET youtube_live=1,youtube_video_id='abcdefghijk' WHERE id='official-live'").run();
    const kinds = (await live()).sources.map(s => s.kind);
    expect(kinds).toContain("youtube");
    expect(kinds).not.toContain("ownedStream");
    // When the hub stops, the video keeps the broadcast live.
    await heartbeat({ listener: "listener-a", inRoom: false, streaming: false });
    expect((await live()).state).toBe("live");
  });

  it("alerts admins once when a listener goes silent, and again when it is back", async () => {
    const { env, heartbeat, sent } = setup();
    await heartbeat({ listener: "listener-a", inRoom: false, streaming: false });
    const later = new Date(Date.now() + 4 * 60_000);
    await reconcileLive(env, later);
    await reconcileLive(env, new Date(later.getTime() + 60_000));
    const alerts = () => sent.filter(s => s.url === "https://graph.facebook.com/v25.0/123456/messages");
    expect(alerts()).toHaveLength(1);
    expect(JSON.parse(alerts()[0]!.body)).toMatchObject({ to: "19292405561", type: "text" });
    expect(alerts()[0]!.body).toContain("listener-a has stopped reporting");
    await heartbeat({ listener: "listener-a", inRoom: false, streaming: false });
    expect(alerts()).toHaveLength(2);
    expect(alerts()[1]!.body).toContain("working again");
  });

  it("reports a lasting listener problem, not a passing one", async () => {
    const { env, heartbeat, sent } = setup();
    await heartbeat({ listener: "listener-a", inRoom: true, streaming: false, problem: "In the room but not streaming" });
    const alerts = () => sent.filter(s => s.url.includes("/messages"));
    expect(alerts()).toHaveLength(0);
    await reconcileLive(env, new Date(Date.now() + 2.5 * 60_000));
    expect(alerts()).toHaveLength(1);
    expect(alerts()[0]!.body).toContain("In the room but not streaming");
  });
});
