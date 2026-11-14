import test from "node:test";
import assert from "node:assert/strict";
import { createLiveReceiver } from "../src/live-audio.js";

const settle = () => new Promise(resolve => setTimeout(resolve, 0));
const source = (sessionId = "source-1") => ({ sessionId, trackName: "audio" });
function setup(options = {}) {
  const peers = [], requests = [], messages = [];
  class Peer {
    constructor() { this.connectionState = "new"; peers.push(this); }
    async setRemoteDescription() { if (!options.noTrack) this.ontrack?.({ streams: [{ id: `stream-${peers.indexOf(this)}` }] }); }
    async createAnswer() { return { type: "answer", sdp: "answer" }; }
    async setLocalDescription(description) { this.localDescription = description; }
    close() { this.closed = true; this.connectionState = "closed"; }
  }
  const audio = { srcObject: null, plays: 0, pause() {}, async play() { this.plays += 1; if (options.blockPlay) throw new Error("autoplay"); } };
  const fetcher = async (url, init) => {
    requests.push({ url, init });
    if (options.fetcher) return options.fetcher(url, init);
    return Response.json(url.endsWith("sessions/new") ? { sessionId: "listener", sessionToken: "scoped-token" } : { sessionDescription: { type: "offer", sdp: "offer" }, tracks: [{}] });
  };
  const receiver = createLiveReceiver({ feed: { base: "https://feed.invalid", key: "listener" }, audio, status: text => messages.push(text), Peer,
    fetcher, timeoutMs: options.timeoutMs ?? 1000, retryMs: options.retryMs ?? 10 });
  return { receiver, audio, peers, requests, messages };
}

test("a stopped negotiation cannot attach late audio or create further SFU tracks", async () => {
  let finish;
  const s = setup({ fetcher: () => new Promise(resolve => { finish = resolve; }) });
  s.receiver.update(source()); s.receiver.start();
  assert.equal(s.peers.length, 1);
  s.receiver.stop(); finish(Response.json({ sessionId: "old" })); await settle();
  assert.equal(s.audio.srcObject, null); assert.equal(s.audio.plays, 0);
  assert.equal(s.peers[0].closed, true); assert.equal(s.requests.length, 1);
  assert.equal(s.requests[0].init.signal.aborted, true);
});

test("source replacement closes old peer and carries the per-session credential", async () => {
  const s = setup(); s.receiver.update(source()); s.receiver.start(); await settle();
  assert.equal(s.audio.srcObject.id, "stream-0");
  assert.equal(s.requests[1].init.headers["x-live-session"], "scoped-token");
  assert.equal(s.requests[2].init.headers["x-live-session"], "scoped-token");
  s.receiver.update(source("source-2")); await settle();
  assert.equal(s.peers[0].closed, true); assert.equal(s.audio.srcObject.id, "stream-1");
  const tracks = s.requests.filter(r => r.url.endsWith("tracks/new"));
  assert.equal(JSON.parse(tracks[1].init.body).tracks[0].sessionId, "source-2");
  s.receiver.stop(); assert.equal(s.audio.srcObject, null);
});

test("missing track event times out, closes and retries instead of hanging", async () => {
  const s = setup({ noTrack: true, timeoutMs: 20, retryMs: 10 });
  s.receiver.update(source()); s.receiver.start();
  await new Promise(resolve => setTimeout(resolve, 75));
  s.receiver.stop();
  assert.ok(s.peers.length >= 2); assert.ok(s.peers.every(peer => peer.closed));
  assert.equal(s.audio.plays, 0); assert.ok(s.messages.some(message => message.includes("Retrying")));
});

test("explicit Play retries autoplay without creating a second SFU receiver", async () => {
  const s = setup({ blockPlay: true }); s.receiver.update(source()); s.receiver.start(); await settle();
  assert.ok(s.messages.at(-1).includes("Play sound"));
  s.audio.play = async () => { s.audio.plays += 1; };
  await s.receiver.play(); assert.equal(s.peers.length, 1); assert.equal(s.messages.at(-1), "Live sound of the Zikr");
  s.receiver.stop();
});

test("waiting for the source allocates no peer and clearing a source stops audio", async () => {
  const s = setup(); s.receiver.start(); assert.equal(s.peers.length, 0);
  s.receiver.update(source()); await settle(); s.receiver.update(null);
  assert.equal(s.peers[0].closed, true); assert.equal(s.audio.srcObject, null); s.receiver.stop();
});
