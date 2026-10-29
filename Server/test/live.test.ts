import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { reconcileLive, zikrTitle } from "../src/live";
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

/** A throwaway P-256 key, so APNs provider tokens can be signed. */
async function p256pem(): Promise<string> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey) as ArrayBuffer);
  let binary = ""; der.forEach(byte => binary += String.fromCharCode(byte));
  return `-----BEGIN PRIVATE KEY-----${btoa(binary)}-----END PRIVATE KEY-----`;
}

describe("live zikr pipeline", () => {
  it("refuses heartbeats and Stream events without their secrets", async () => {
    const { heartbeat, streamEvent } = setup();
    expect((await heartbeat({ listener: "listener-a" }, "wrong")).status).toBe(404);
    expect((await streamEvent(INPUT_A, "live_input.connected", "wrong")).status).toBe(404);
  });

  // Daily Zikr follows the channel's live video only (the owner, 2026-10-28).
  it("never makes Daily Zikr live from a streaming listener, offers no hub source and sends no alert", async () => {
    const { env, raw, heartbeat, live, sent } = setup();
    // Credentials and a subscribed phone, so an alert would really be sent.
    Object.assign(env, { APNS_KEY_ID: "KEY", APNS_TEAM_ID: "TEAM", APNS_PRIVATE_KEY: await p256pem() });
    raw.prepare(`INSERT INTO devices(installation_id,apns_token,locale,timezone,topics_json,environment,app_version,created_at,last_seen_at)
      VALUES('11111111-1111-4111-8111-111111111111',?,'en','UTC','["liveZikr"]','production','1',datetime('now'),datetime('now'))`).run("a".repeat(64));
    expect((await heartbeat({ listener: "listener-a", inRoom: true, streaming: true, input: INPUT_A })).status).toBe(200);
    expect((await heartbeat({ listener: "listener-b", inRoom: true, streaming: true, input: "r2" })).status).toBe(200);
    const on = await live();
    expect(on.state).not.toBe("live");
    expect(on.sources).toEqual([]);
    expect(sent.filter(s => s.url.includes("push.apple.com"))).toEqual([]);
    expect(sent.filter(s => s.url.includes("graph.facebook.com"))).toEqual([]);
  });

  it("does not call the YouTube zikr live because the room is open, and never lists the room as a source", async () => {
    const { raw, heartbeat, live } = setup();
    raw.prepare("UPDATE live_broadcasts SET paltalk_url='https://www.paltalk.com/room/zikr' WHERE id='official-live'").run();
    await heartbeat({ listener: "listener-a", inRoom: true, streaming: false });
    const on = await live();
    expect(on.state).not.toBe("live");
    expect(on.sources).toEqual([]);
  });

  it("names the session by Pakistan time: Tahajjud before dawn, Daily Zikr otherwise", () => {
    expect(zikrTitle(new Date("2026-10-27T23:30:00Z"))).toBe("Tahajjud Zikr"); // 04:30 in Pakistan
    expect(zikrTitle(new Date("2026-10-27T16:15:00Z"))).toBe("Daily Zikr"); // 21:15
  });

  it("records Stream's input reports, which no longer make the broadcast live", async () => {
    const { raw, heartbeat, streamEvent, live } = setup();
    await heartbeat({ listener: "listener-a", inRoom: true, streaming: true, input: INPUT_A });
    expect((await streamEvent(INPUT_B, "live_input.connected")).status).toBe(200);
    expect(raw.prepare("SELECT connected FROM live_inputs WHERE id=?").get(INPUT_B)).toEqual({ connected: 1 });
    const on = await live();
    expect(on.state).not.toBe("live");
    expect(on.sources).toEqual([]);
  });

  it("follows the channel's live video alone: a listener starting or stopping neither adds a source nor ends it", async () => {
    const { raw, heartbeat, live } = setup();
    raw.prepare("UPDATE live_broadcasts SET state='live',youtube_live=1,youtube_video_id='abcdefghijk' WHERE id='official-live'").run();
    await heartbeat({ listener: "listener-a", inRoom: true, streaming: true, input: INPUT_A });
    expect((await live()).sources.map(s => s.kind)).toEqual(["youtube"]);
    await heartbeat({ listener: "listener-a", inRoom: false, streaming: false });
    const after = await live();
    expect(after.state).toBe("live");
    expect(after.sources.map(s => s.kind)).toEqual(["youtube"]);
  });

  it("drops a relay link left from before without ending the video's broadcast", async () => {
    const { env, raw, live } = setup();
    raw.prepare(`UPDATE live_broadcasts SET state='live',youtube_live=1,youtube_video_id='abcdefghijk',
      hub_stream_url='https://api.example.com/v1/live/audio/index.m3u8' WHERE id='official-live'`).run();
    await reconcileLive(env);
    expect(raw.prepare("SELECT state,hub_stream_url FROM live_broadcasts WHERE id='official-live'").get())
      .toEqual({ state: "live", hub_stream_url: null });
    expect((await live()).sources.map(s => s.kind)).toEqual(["youtube"]);
  });

  it("sends no alerts about listeners, silent or troubled (retired 2026-10-28)", async () => {
    const { env, heartbeat, sent } = setup();
    await heartbeat({ listener: "listener-a", inRoom: true, streaming: false, problem: "In the room but not streaming" });
    await reconcileLive(env, new Date(Date.now() + 10 * 60_000));
    expect(sent.filter(s => s.url.includes("/messages"))).toEqual([]);
  });
});
