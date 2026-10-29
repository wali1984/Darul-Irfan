import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { sqliteD1 } from "./sqlite-d1";

function setup() {
  const { db, raw } = sqliteD1();
  vi.stubGlobal("fetch", async () => new Response("{}", { status: 200 }));
  const objects = new Map<string, { body: string; type: string }>();
  const env = {
    DB: db, APNS_TOPIC: "us.naqshbaniaowaisiah", PUBLIC_BASE_URL: "https://api.example.com/", FACEBOOK_GRAPH_VERSION: "v25.0",
    LISTENER_TOKEN: "listener-secret", LIVE_CUE_HOSTS: "ameer_imam, Some_Moderator",
    MEDIA: {
      get: async (key: string) => objects.has(key)
        ? { size: objects.get(key)!.body.length, httpMetadata: { contentType: objects.get(key)!.type }, body: objects.get(key)!.body }
        : null,
      head: async () => null,
    },
  } as unknown as Env;
  const call = (path: string, init: RequestInit = {}, token = "listener-secret") =>
    worker.fetch(new Request(`https://api.example.com${path}`, {
      ...init, headers: { authorization: `Bearer ${token}`, "content-type": "application/json", ...(init.headers ?? {}) },
    }), env);
  const post = (path: string, body: unknown, token?: string) => call(path, { method: "POST", body: JSON.stringify(body) }, token);
  const live = async () => (await (await worker.fetch(new Request("https://api.example.com/v1/live"), env)).json()) as
    { state: string; sources: { kind: string; url: string }[]; cue?: { text: string; sender: string } };
  return { env, raw, objects, call, post, live };
}

afterEach(() => vi.unstubAllGlobals());

describe("free relay of the room and its cues", () => {
  // Daily Zikr follows the channel's live video only (the owner, 2026-10-28).
  it("never offers the room's relay as the official broadcast, beside the channel's video or instead of it", async () => {
    const { raw, post, live } = setup();
    raw.prepare("UPDATE live_broadcasts SET youtube_live=1,youtube_video_id='TQJMn7Nw13s',state='live' WHERE id='official-live'").run();
    expect((await post("/v1/live/listener", { listener: "listener-a", inRoom: true, streaming: true, input: "r2" })).status).toBe(200);
    const on = await live();
    expect(on.state).toBe("live");
    expect(on.sources.map(s => s.kind)).toEqual(["youtube"]);
    raw.prepare("UPDATE live_broadcasts SET youtube_live=0,youtube_video_id=NULL,state='ended' WHERE id='official-live'").run();
    await post("/v1/live/listener", { listener: "listener-a", inRoom: true, streaming: true, input: "r2" });
    const off = await live();
    expect(off.state).toBe("ended");
    expect(off.sources).toEqual([]);
  });

  it("serves only the relay's playlist and pieces, the playlist uncached", async () => {
    const { objects, call } = setup();
    objects.set("live/official/index.m3u8", { body: "#EXTM3U", type: "application/vnd.apple.mpegurl" });
    const playlist = await call("/v1/live/audio/index.m3u8");
    expect(playlist.status).toBe(200);
    expect(playlist.headers.get("cache-control")).toBe("no-store");
    expect(playlist.headers.get("access-control-allow-origin")).toBe("*");
    expect((await call("/v1/live/audio/../../media/x")).status).toBe(404);
    expect((await call("/v1/live/audio/secret.json")).status).toBe(404);
  });

  it("tells the listener whose messages are cues, and nobody else", async () => {
    const { call } = setup();
    expect((await call("/v1/live/listener/config", {}, "wrong")).status).toBe(404);
    expect(await (await call("/v1/live/listener/config")).json()).toEqual({ cueHosts: ["ameer_imam", "some_moderator"] });
  });

  it("turns a host's message into the session's cue, exactly as written", async () => {
    const { raw, post, live } = setup();
    raw.prepare("UPDATE live_broadcasts SET state='live',started_at=? WHERE id='official-live'").run(new Date(Date.now() - 300_000).toISOString());
    expect(await (await post("/v1/live/cue", { sender: "someone_else", text: "L-3" })).json()).toEqual({ ok: true, ignored: "not a host" });
    expect((await live()).cue).toBeUndefined();
    expect(await (await post("/v1/live/cue", { sender: "Ameer_Imam", text: "M-Nabvee" })).json()).toEqual({ ok: true, sent: true });
    expect((await live()).cue).toEqual(expect.objectContaining({ text: "M-Nabvee", sender: "Ameer_Imam" }));
    // The listener resending the same message does not alert twice.
    expect(await (await post("/v1/live/cue", { sender: "ameer_imam", text: "M-Nabvee" })).json()).toEqual({ ok: true, repeated: true });
    expect((await post("/v1/live/cue", { sender: "ameer_imam", text: "L-4" }, "wrong")).status).toBe(404);
  });

  it("drops a cue from an earlier session", async () => {
    const { raw, post, live } = setup();
    raw.prepare("UPDATE live_broadcasts SET state='live',started_at=? WHERE id='official-live'").run(new Date(Date.now() - 300_000).toISOString());
    await post("/v1/live/cue", { sender: "ameer_imam", text: "L-7" });
    raw.prepare("UPDATE live_broadcasts SET started_at=? WHERE id='official-live'").run(new Date(Date.now() + 60_000).toISOString());
    expect((await live()).cue).toBeUndefined();
    raw.prepare("UPDATE live_broadcasts SET state='ended' WHERE id='official-live'").run();
    expect((await live()).cue).toBeUndefined();
  });
});
