// Contract tests for the live Worker (audit 2026-11-06, section 8): SFU
// session ownership (F01) and the Durable Object as a projection of the
// platform's session (F02). Runs under node:test with no network: the SFU
// and the platform are stubbed, keys are dummy strings.
//
//   node --test worker/test/contract.test.mjs

import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createHmac } from "node:crypto";
import { stripTypeScriptTypes } from "node:module";
import { pathToFileURL, fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const src = path.join(here, "..", "src");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "di-live-contract-"));

let handler;
let Control;

// Node refuses status 101; the Durable Object answers a socket upgrade with
// it, so for the tests a 101 becomes a 200 that remembers the socket.
const RealResponse = globalThis.Response;
class TestResponse extends RealResponse {
  constructor(body, init) {
    if (init && init.status === 101) {
      super(body, { ...init, status: 200 });
      this.upgraded = true;
      this.webSocket = init.webSocket;
    } else {
      super(body, init);
    }
  }
}

before(async () => {
  for (const name of ["control", "index"]) {
    let text = fs.readFileSync(path.join(src, name + ".ts"), "utf8");
    if (name === "index") {
      text = text.replace('from "./control"', 'from "./control.mjs"').replace(/^import (\w+) from "\.\/pages\/.*?";/gm, "const $1 = \"\";");
    }
    fs.writeFileSync(path.join(tmp, name + ".mjs"), stripTypeScriptTypes(text, { mode: "transform" }));
  }
  ({ default: handler } = await import(pathToFileURL(path.join(tmp, "index.mjs"))));
  ({ Control } = await import(pathToFileURL(path.join(tmp, "control.mjs"))));
  globalThis.Response = TestResponse;
});

after(() => {
  globalThis.Response = RealResponse;
  fs.rmSync(tmp, { recursive: true, force: true });
});

// MARK: - Fakes

const KEYS = { HOST_KEY: "test-host-key", RELAY_KEY: "test-relay-key", LISTEN_KEY: "test-listen-key" };
const ROLE_KEY = { host: KEYS.HOST_KEY, relay: KEYS.RELAY_KEY, listen: KEYS.LISTEN_KEY };

// The SFU behind the Worker: records every call, opens session "abc123".
function fakeSfu() {
  const calls = [];
  globalThis.fetch = async (url, options) => {
    calls.push({ url: String(url), method: options?.method ?? "GET", body: options?.body });
    if (String(url).endsWith("/sessions/new")) return new RealResponse(JSON.stringify({ sessionId: "abc123" }), { status: 200 });
    return new RealResponse(JSON.stringify({ ok: true }), { status: 200 });
  };
  return calls;
}

// The platform's public live answer: `live` is replaced by each test. A
// `gate` promise holds the answer until the test releases it.
function fakePlatform() {
  const platform = {
    calls: [],
    live: null,
    fail: false,
    delay: 0,
    gate: null,
    fetch: async (url) => {
      platform.calls.push(String(url));
      if (platform.delay) await new Promise((resolve) => setTimeout(resolve, platform.delay));
      if (platform.gate) await platform.gate;
      if (platform.fail) return new RealResponse("down", { status: 503 });
      return new RealResponse(JSON.stringify({ halqahs: [{ id: "our-sheikh", name: "Our Sheikh", live: platform.live, stage: null }] }), { status: 200 });
    },
  };
  return platform;
}

function workerEnv(platform) {
  return { ...KEYS, SFU_BASE: "https://sfu.invalid", SFU_APP_ID: "app", SFU_APP_TOKEN: "sfu-token-test-only", PLATFORM_URL: "https://platform.invalid", HALQAH_ID: "our-sheikh", PLATFORM: platform ?? fakePlatform(), ALLOWED_ORIGINS: "https://site.invalid" };
}

function sfuRequest(role, method, rest, { token, body } = {}) {
  const headers = { "x-live-key": ROLE_KEY[role], "content-type": "application/json" };
  if (token !== undefined) headers["x-live-session"] = token;
  return new Request("https://worker.invalid/api/sfu" + rest, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
}

async function openSession(env, role) {
  const response = await handler.fetch(sfuRequest(role, "POST", "/sessions/new"), env);
  assert.equal(response.status, 200);
  return response.json();
}

// Mirrors the Worker's signing so the tests can mint expired or foreign tokens.
function mintToken(sessionId, role, expires, secret = KEYS.HOST_KEY) {
  const body = `${sessionId}.${role}.${expires}`;
  const signature = createHmac("sha256", secret).update(body).digest("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return `sess.${body}.${signature}`;
}

// A Durable Object with in-memory storage, a fake alarm and fake sockets.
function fakeControl(platform) {
  const values = new Map();
  const sockets = [];
  const ctx = {
    alarm: null,
    storage: {
      get: async (key) => values.get(key),
      put: async (key, value) => values.set(key, structuredClone(value)),
      getAlarm: async () => ctx.alarm,
      setAlarm: async (at) => { ctx.alarm = at; },
    },
    getWebSockets: () => sockets,
    acceptWebSocket: (ws) => sockets.push(ws),
  };
  const control = new Control(ctx, { PLATFORM: platform, PLATFORM_URL: "https://platform.invalid", HALQAH_ID: "our-sheikh" });
  const call = async (pathname, body, role = "relay") => {
    const response = await control.fetch(new Request("https://worker.invalid" + pathname, {
      method: body ? "POST" : "GET",
      headers: { "x-live-role": role, "content-type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
    }));
    return { status: response.status, data: await response.json() };
  };
  const state = async () => (await call("/api/state")).data;
  return { control, ctx, call, state, sockets };
}

// A clock the tests move by hand.
const realNow = Date.now;
let now = 1_700_000_000_000;
beforeEach(() => {
  now = 1_700_000_000_000;
  Date.now = () => now;
});
after(() => { Date.now = realNow; });

// MARK: - Contract A: SFU session ownership (audit F01, contract test 1)

test("sessions/new answers the session id and a signed session token", async () => {
  const upstream = fakeSfu();
  const env = workerEnv();
  const session = await openSession(env, "listen");
  assert.equal(session.sessionId, "abc123");
  const parts = session.sessionToken.split(".");
  assert.equal(parts.length, 5);
  assert.deepEqual(parts.slice(0, 3), ["sess", "abc123", "listen"]);
  assert.equal(Number(parts[3]), now + 14 * 3_600_000, "lives 14 hours");
  assert.equal(session.sessionToken, mintToken("abc123", "listen", parts[3]));
  assert.deepEqual(upstream.map((c) => [c.method, c.url]), [["POST", "https://sfu.invalid/app/sessions/new"]]);
});

for (const operation of ["tracks/close", "renegotiate"]) {
  test(`a listener cannot ${operation} another session: 403 before any upstream call`, async () => {
    const upstream = fakeSfu();
    const env = workerEnv();
    const session = await openSession(env, "listen");
    upstream.length = 0;
    const response = await handler.fetch(sfuRequest("listen", "PUT", `/sessions/publisherXYZ/${operation}`, { token: session.sessionToken, body: { tracks: [], force: true } }), env);
    assert.equal(response.status, 403);
    assert.deepEqual(await response.json(), { error: "not your session" });
    assert.deepEqual(upstream, [], "nothing reached the SFU");
  });
}

test("a listener's own renegotiate with its token is forwarded", async () => {
  const upstream = fakeSfu();
  const env = workerEnv();
  const session = await openSession(env, "listen");
  upstream.length = 0;
  const response = await handler.fetch(sfuRequest("listen", "PUT", "/sessions/abc123/renegotiate", { token: session.sessionToken, body: { sessionDescription: { type: "answer", sdp: "v=0" } } }), env);
  assert.equal(response.status, 200);
  assert.equal(upstream.length, 1);
  assert.equal(upstream[0].method, "PUT");
  assert.equal(upstream[0].url, "https://sfu.invalid/app/sessions/abc123/renegotiate");
  assert.equal(JSON.parse(upstream[0].body).sessionDescription.type, "answer");
});

test("a listener's own tracks/close with its token is forwarded", async () => {
  const upstream = fakeSfu();
  const env = workerEnv();
  const session = await openSession(env, "listen");
  upstream.length = 0;
  const response = await handler.fetch(sfuRequest("listen", "PUT", "/sessions/abc123/tracks/close", { token: session.sessionToken, body: { tracks: [{ mid: "0" }], force: true } }), env);
  assert.equal(response.status, 200);
  assert.equal(upstream.length, 1);
  assert.equal(upstream[0].url, "https://sfu.invalid/app/sessions/abc123/tracks/close");
});

test("a token minted for one role is refused under another role's key", async () => {
  const upstream = fakeSfu();
  const env = workerEnv();
  const session = await openSession(env, "listen");
  upstream.length = 0;
  for (const role of ["host", "relay"]) {
    const response = await handler.fetch(sfuRequest(role, "PUT", "/sessions/abc123/renegotiate", { token: session.sessionToken, body: {} }), env);
    assert.equal(response.status, 403, role);
  }
  assert.deepEqual(upstream, []);
});

test("an expired token is refused", async () => {
  const upstream = fakeSfu();
  const env = workerEnv();
  const expired = mintToken("abc123", "listen", now - 1);
  const response = await handler.fetch(sfuRequest("listen", "PUT", "/sessions/abc123/renegotiate", { token: expired, body: {} }), env);
  assert.equal(response.status, 403);
  assert.deepEqual(upstream, []);
  // The same token one millisecond earlier would have been good.
  now -= 2;
  const fine = await handler.fetch(sfuRequest("listen", "PUT", "/sessions/abc123/renegotiate", { token: expired, body: {} }), env);
  assert.equal(fine.status, 200);
});

test("a missing, malformed or forged token is refused", async () => {
  const upstream = fakeSfu();
  const env = workerEnv();
  const cases = [
    undefined,
    "",
    "garbage",
    "sess.abc123.listen",
    mintToken("abc123", "listen", now + 1000, "wrong-secret"),
    mintToken("abc123", "listen", "soon"),
    "app.listen." + (now + 1000) + ".sig",
  ];
  for (const token of cases) {
    const response = await handler.fetch(sfuRequest("listen", "POST", "/sessions/abc123/tracks/new", { token, body: { tracks: [{ location: "remote", sessionId: "pub", trackName: "paltalk-1" }] } }), env);
    assert.equal(response.status, 403, String(token));
  }
  assert.deepEqual(upstream, []);
});

test("only the allowed method reaches each SFU operation", async () => {
  const upstream = fakeSfu();
  const env = workerEnv();
  const session = await openSession(env, "listen");
  upstream.length = 0;
  const cases = [
    ["GET", "/sessions/new", 405],
    ["PUT", "/sessions/new", 405],
    ["GET", "/sessions/abc123/tracks/new", 405],
    ["PUT", "/sessions/abc123/tracks/new", 405],
    ["POST", "/sessions/abc123/renegotiate", 405],
    ["POST", "/sessions/abc123/tracks/close", 405],
    ["DELETE", "/sessions/abc123/tracks/close", 405],
    ["GET", "/sessions/abc123", 404],
    ["PUT", "/sessions/abc123/tracks/update", 404],
    ["PUT", "/sessions/../tracks/close", 404],
  ];
  for (const [method, rest, status] of cases) {
    const response = await handler.fetch(sfuRequest("listen", method, rest, { token: session.sessionToken, body: method === "GET" ? undefined : {} }), env);
    assert.equal(response.status, status, `${method} ${rest}`);
  }
  assert.deepEqual(upstream, [], "none of them reached the SFU");
});

test("track rules still apply on the caller's own session", async () => {
  const upstream = fakeSfu();
  const env = workerEnv();
  const listener = await openSession(env, "listen");
  upstream.length = 0;
  const local = await handler.fetch(sfuRequest("listen", "POST", "/sessions/abc123/tracks/new", { token: listener.sessionToken, body: { tracks: [{ location: "local", mid: "0", trackName: "app-x" }] } }), env);
  assert.equal(local.status, 403);
  assert.deepEqual(await local.json(), { error: "track not allowed for this key" });
  assert.deepEqual(upstream, []);
  const remote = await handler.fetch(sfuRequest("listen", "POST", "/sessions/abc123/tracks/new", { token: listener.sessionToken, body: { tracks: [{ location: "remote", sessionId: "pub", trackName: "paltalk-1" }] } }), env);
  assert.equal(remote.status, 200);
  assert.equal(upstream.length, 1);
  // The relay publishes paltalk tracks on its own session only.
  const relay = await openSession(env, "relay");
  upstream.length = 0;
  const publish = await handler.fetch(sfuRequest("relay", "POST", "/sessions/abc123/tracks/new", { token: relay.sessionToken, body: { tracks: [{ location: "local", mid: "0", trackName: "paltalk-relay" }] } }), env);
  assert.equal(publish.status, 200);
  const foreign = await handler.fetch(sfuRequest("relay", "POST", "/sessions/otherSession/tracks/new", { token: relay.sessionToken, body: { tracks: [{ location: "local", mid: "0", trackName: "paltalk-relay" }] } }), env);
  assert.equal(foreign.status, 403);
  assert.equal(upstream.length, 1);
});

test("the CORS preflight for the websites allows the session header", async () => {
  fakeSfu();
  const env = workerEnv();
  const response = await handler.fetch(new Request("https://worker.invalid/api/sfu/sessions/abc123/renegotiate", { method: "OPTIONS", headers: { origin: "https://site.invalid" } }), env);
  assert.equal(response.status, 204);
  assert.match(response.headers.get("access-control-allow-headers"), /x-live-session/);
});

// MARK: - Contract B: the session is the platform's (audit F02, contract tests 2, 3, 12)

test("/api/session start or end is refused: the platform owns the session", async () => {
  const platform = fakePlatform();
  const { call, state } = fakeControl(platform);
  for (const role of ["host", "relay"]) {
    for (const action of ["start", "end"]) {
      const { status, data } = await call("/api/session", { action }, role);
      assert.equal(status, 409, `${role} ${action}`);
      assert.deepEqual(data, { error: "the platform owns the session" });
    }
  }
  assert.equal((await state()).session.state, "idle");
});

test("a publisher heartbeat registers transport only; the platform's no keeps the session idle", async () => {
  const platform = fakePlatform();
  const { call, state } = fakeControl(platform);
  await call("/api/lease", { relayId: "relay-a" });
  const beat = await call("/api/source", { source: "paltalk", relayId: "relay-a", sessionId: "pub1", trackName: "paltalk-1" });
  assert.equal(beat.status, 200);
  let s = await state();
  assert.equal(s.session.state, "idle");
  assert.equal(s.active.source, null, "nothing is on air without a live session");
  assert.ok(s.sources.paltalk?.fresh, "the transport is registered");
  // The platform goes live: the same heartbeat now carries the air.
  platform.live = { kind: "zikr", sessionID: "zikr-1", title: "Zikr", startedAt: "2026-11-06T20:00:00Z" };
  now += 11_000;
  s = await state();
  assert.equal(s.session.state, "live");
  assert.equal(s.session.id, "zikr-1");
  assert.equal(s.session.startedBy, "platform");
  await call("/api/source", { source: "paltalk", relayId: "relay-a", sessionId: "pub1", trackName: "paltalk-1" });
  assert.equal((await state()).active.source, "paltalk");
});

test("platform live then not live ends the session; the same id never revives it (contract tests 2 and 12)", async () => {
  const platform = fakePlatform();
  const { call, state, control } = fakeControl(platform);
  platform.live = { kind: "zikr", sessionID: "zikr-1" };
  let s = await state();
  assert.equal(s.session.state, "live");
  await call("/api/stage", { stage: "1st Latifa", origin: "paltalk" });
  // The platform ends it.
  platform.live = null;
  now += 11_000;
  s = await state();
  assert.equal(s.session.state, "ended");
  assert.equal(s.session.id, "zikr-1", "the id is kept");
  assert.equal(s.session.endedAt, now);
  assert.equal(s.platform.live, false);
  // A stale snapshot of the old session comes back: ended stays ended.
  platform.live = { kind: "zikr", sessionID: "zikr-1" };
  now += 11_000;
  s = await state();
  assert.equal(s.session.state, "ended");
  // The relay's heartbeat after the end does not start anything either.
  await call("/api/lease", { relayId: "relay-a" });
  await call("/api/source", { source: "paltalk", relayId: "relay-a", sessionId: "pub1", trackName: "paltalk-1" });
  await control.alarm();
  s = await state();
  assert.equal(s.session.state, "ended");
  assert.equal(s.active.source, null);
  // A genuinely new platform session starts afresh with an empty stage log.
  platform.live = { kind: "zikr", sessionID: "zikr-2" };
  now += 11_000;
  s = await state();
  assert.equal(s.session.state, "live");
  assert.equal(s.session.id, "zikr-2");
  assert.deepEqual(s.stages, []);
  assert.equal(s.active.source, null, "the transport went quiet 11 s ago");
  await call("/api/lease", { relayId: "relay-a" });
  await call("/api/source", { source: "paltalk", relayId: "relay-a", sessionId: "pub1", trackName: "paltalk-1" });
  assert.equal((await state()).active.source, "paltalk", "a fresh heartbeat puts the transport on air");
});

test("a platform session without sessionID is named by its startedAt", async () => {
  const platform = fakePlatform();
  const { state } = fakeControl(platform);
  platform.live = { kind: "zikr", startedAt: "2026-11-06T20:00:00Z", isTest: true, title: "Rehearsal" };
  const s = await state();
  assert.equal(s.session.id, "platform-2026-11-06T20:00:00Z");
  assert.deepEqual(s.platform, { live: true, sessionID: "platform-2026-11-06T20:00:00Z", title: "Rehearsal", isTest: true, checkedAt: now, ok: true });
});

test("expired source and lease with the platform not live: nothing on air, not live, no new session (contract test 3)", async () => {
  const platform = fakePlatform();
  const { call, state, control, ctx } = fakeControl(platform);
  platform.live = { kind: "zikr", sessionID: "zikr-1" };
  await call("/api/lease", { relayId: "relay-a" });
  await call("/api/source", { source: "paltalk", relayId: "relay-a", sessionId: "pub1", trackName: "paltalk-1" });
  assert.equal((await state()).active.source, "paltalk");
  // The relay dies and the platform ends the Zikr.
  platform.live = null;
  now += 400_000;
  await control.alarm();
  const s = await state();
  assert.equal(s.session.state, "ended");
  assert.equal(s.active.source, null);
  assert.equal(s.lease, null);
  assert.equal(s.sources.paltalk, undefined);
  assert.equal(ctx.alarm === null || ctx.alarm <= now, true, "no further tick is owed once nothing is live");
});

test("a platform failure keeps the last state and marks it, never flipping the session", async () => {
  const platform = fakePlatform();
  const { state } = fakeControl(platform);
  platform.live = { kind: "zikr", sessionID: "zikr-1" };
  assert.equal((await state()).session.state, "live");
  platform.fail = true;
  now += 11_000;
  let s = await state();
  assert.equal(s.session.state, "live");
  assert.equal(s.platform.ok, false);
  assert.equal(s.platform.live, true, "the last good answer is kept");
  assert.equal(s.platform.checkedAt, now);
  platform.fail = false;
  platform.live = null;
  now += 11_000;
  s = await state();
  assert.equal(s.session.state, "ended");
  assert.equal(s.platform.ok, true);
});

test("/api/state asks the platform only when the last answer is older than 10 s", async () => {
  const platform = fakePlatform();
  const { state } = fakeControl(platform);
  await state();
  assert.equal(platform.calls.length, 1);
  assert.match(platform.calls[0], /^https:\/\/platform\.invalid\/v1\/public\/live\?ids=our-sheikh$/);
  now += 5_000;
  await state();
  assert.equal(platform.calls.length, 1, "fresh enough");
  now += 6_000;
  await state();
  assert.equal(platform.calls.length, 2);
});

test("concurrent reads share one platform request", async () => {
  const platform = fakePlatform();
  platform.delay = 20;
  const { state } = fakeControl(platform);
  await Promise.all([state(), state(), state()]);
  assert.equal(platform.calls.length, 1);
});

test("accepting a socket refreshes a stale platform view and sends the fresh state", async () => {
  const platform = fakePlatform();
  platform.live = { kind: "zikr", sessionID: "zikr-1" };
  const { control, sockets } = fakeControl(platform);
  const sent = [];
  globalThis.WebSocketPair = class { constructor() { this[0] = { sent }; this[1] = { send: (m) => sent.push(JSON.parse(m)) }; } };
  try {
    const response = await control.fetch(new Request("https://worker.invalid/api/ws", { headers: { "x-live-role": "listen" } }));
    assert.equal(response.upgraded, true);
    assert.equal(platform.calls.length, 1);
    assert.equal(sockets.length, 1);
    assert.equal(sent[0].state.session.state, "live");
    assert.equal(sent[0].state.session.id, "zikr-1");
    // The platform ends it: every open socket hears the end on the next tick.
    platform.live = null;
    now += 2_000;
    await control.alarm();
    assert.equal(sent.at(-1).state.session.state, "ended");
  } finally {
    delete globalThis.WebSocketPair;
  }
});

test("while live the alarm asks the platform every tick and stops once nothing is live", async () => {
  const platform = fakePlatform();
  platform.live = { kind: "zikr", sessionID: "zikr-1" };
  const { state, control, ctx } = fakeControl(platform);
  await state();
  assert.equal(ctx.alarm, now + 2_000, "a live session keeps the tick going");
  for (let tick = 0; tick < 3; tick++) {
    now += 2_000;
    await control.alarm();
  }
  assert.equal(platform.calls.length, 4, "one at the read, one per tick");
  platform.live = null;
  now += 2_000;
  await control.alarm();
  assert.equal((await state()).session.state, "ended");
  assert.equal(ctx.alarm <= now, true, "no new tick after the end");
});

test("reset clears the transport side but not the session or the platform view", async () => {
  const platform = fakePlatform();
  platform.live = { kind: "zikr", sessionID: "zikr-1" };
  const { call, state } = fakeControl(platform);
  await call("/api/lease", { relayId: "relay-a" });
  await call("/api/source", { source: "paltalk", relayId: "relay-a", sessionId: "pub1", trackName: "paltalk-1" });
  await call("/api/override", { source: "paltalk" }, "host");
  await call("/api/stage", { stage: "1st Latifa" }, "host");
  const reset = await call("/api/reset", {}, "host");
  assert.equal(reset.status, 200);
  const s = await state();
  assert.equal(s.session.state, "live");
  assert.equal(s.session.id, "zikr-1");
  assert.equal(s.platform.live, true);
  assert.deepEqual(s.sources, {});
  assert.equal(s.lease, null);
  assert.equal(s.override, "auto");
  assert.deepEqual(s.stages, []);
  assert.equal(s.active.source, null);
  // Reset cannot invent a session either.
  platform.live = null;
  now += 11_000;
  await state();
  const again = await call("/api/reset", {}, "host");
  assert.equal(again.data.session.state, "ended");
});

test("publisher priority uses the time we first heard from each device, not what the client claims", async () => {
  const platform = fakePlatform();
  platform.live = { kind: "zikr", sessionID: "zikr-1" };
  const { call, state } = fakeControl(platform);
  await state();
  // Phone A claims to have started far in the future; it still registered first.
  const a = { source: "app", sessionId: "phoneA", trackName: "app-a", by: "phone A", startedAt: now + 10 * 3_600_000 };
  const b = { source: "app", sessionId: "phoneB", trackName: "app-b", by: "phone B", startedAt: 1 };
  assert.equal((await call("/api/source", a, "host")).status, 200);
  now += 1_000;
  assert.equal((await call("/api/source", b, "host")).status, 200, "the newest registration wins");
  let s = await state();
  assert.equal(s.sources.app.sessionId, "phoneB");
  assert.equal(s.sources.app.startedAt, now, "server receipt time");
  // Phone A's next heartbeat is told it was superseded.
  now += 1_000;
  const late = await call("/api/source", a, "host");
  assert.equal(late.status, 409);
  assert.deepEqual(late.data, { superseded: true, by: "phone B" });
  assert.equal((await state()).sources.app.sessionId, "phoneB");
  // Once phone B has gone quiet, phone A may come back.
  now += 11_000;
  assert.equal((await call("/api/source", a, "host")).status, 200);
  s = await state();
  assert.equal(s.sources.app.sessionId, "phoneA");
});

test("state saved before the platform projection existed loads with the new fields", async () => {
  const platform = fakePlatform();
  const { control, ctx, state } = fakeControl(platform);
  await ctx.storage.put("state", {
    session: { state: "live", id: "old-uuid", startedAt: 1, endedAt: null, startedBy: "paltalk" },
    sources: {}, override: "auto", active: { source: null, sessionId: null, trackName: null, since: 0 }, lease: null, relay: null, stages: [], seq: 0,
    // One number per publisher: the first-seen stamp of the earlier shape.
    publishers: { phoneOld: now - 1_000 },
  });
  const s = await state();
  assert.equal(s.platform.ok, true, "the platform was asked on load");
  assert.equal(s.session.state, "ended", "the platform says not live, so the stale live ends");
  assert.equal(s.session.id, "old-uuid");
  assert.deepEqual((await ctx.storage.get("state")).publishers, { phoneOld: { first: now - 1_000, last: now - 1_000 } });
  await control.alarm();
  assert.equal((await state()).session.state, "ended");
});

// MARK: - Fix round (review of 2026-11-06)

test("a session replaced straight by another is over: A, then B, then a stale A does not revive A", async () => {
  const platform = fakePlatform();
  const { call, state } = fakeControl(platform);
  platform.live = { kind: "zikr", sessionID: "A" };
  await state();
  await call("/api/stage", { stage: "1st Latifa" }, "host");
  platform.live = { kind: "zikr", sessionID: "B" };
  now += 11_000;
  let s = await state();
  assert.equal(s.session.id, "B");
  assert.deepEqual(s.stages, [], "B starts with its own log");
  await call("/api/stage", { stage: "2nd" }, "host");
  // A stale read of the platform answers A again.
  platform.live = { kind: "zikr", sessionID: "A" };
  now += 11_000;
  s = await state();
  assert.equal(s.session.state, "live");
  assert.equal(s.session.id, "B", "A was retired when B took over");
  assert.deepEqual(s.stages.map((e) => e.stage), ["2nd"], "B's log is untouched");
});

test("a publisher that keeps heartbeating keeps its first-seen stamp past five minutes, so a newer device still wins", async () => {
  const platform = fakePlatform();
  platform.live = { kind: "zikr", sessionID: "zikr-1" };
  const { call, state, control } = fakeControl(platform);
  await state();
  const a = { source: "app", sessionId: "phoneA", trackName: "app-a", by: "phone A" };
  const b = { source: "app", sessionId: "phoneB", trackName: "app-b", by: "phone B" };
  // Phone A heartbeats every 3 s for six minutes while the alarm ticks.
  const first = now + 3_000;
  for (let i = 0; i < 120; i++) {
    now += 3_000;
    assert.equal((await call("/api/source", a, "host")).status, 200);
    await control.alarm();
  }
  assert.equal((await state()).sources.app.startedAt, first, "the stamp never moved");
  // Phone B goes live: it is the newest and takes the air.
  now += 1_000;
  assert.equal((await call("/api/source", b, "host")).status, 200);
  assert.equal((await state()).sources.app.sessionId, "phoneB");
  // Phone A's next heartbeat is told to stop; it does not take the air back.
  now += 1_000;
  const late = await call("/api/source", a, "host");
  assert.equal(late.status, 409);
  assert.deepEqual(late.data, { superseded: true, by: "phone B" });
  assert.equal((await state()).sources.app.sessionId, "phoneB");
});

test("a host reset that lands while the platform is being asked is not undone", async () => {
  const platform = fakePlatform();
  platform.live = { kind: "zikr", sessionID: "zikr-1" };
  const { call, state, ctx } = fakeControl(platform);
  await call("/api/lease", { relayId: "relay-a" });
  await call("/api/source", { source: "paltalk", relayId: "relay-a", sessionId: "pub1", trackName: "paltalk-1" });
  await call("/api/override", { source: "paltalk" }, "host");
  await call("/api/stage", { stage: "1st Latifa" }, "host");
  assert.equal((await state()).active.source, "paltalk");
  // The view goes stale; the next read asks the platform and waits on it.
  now += 11_000;
  let release;
  platform.gate = new Promise((resolve) => { release = resolve; });
  const pending = state();
  await new Promise((resolve) => setTimeout(resolve, 5));
  assert.equal(platform.calls.length, 2, "the read is waiting on the platform");
  // The host resets in that window, then the platform answers.
  const reset = await call("/api/reset", {}, "host");
  assert.deepEqual(reset.data.sources, {});
  release();
  await pending;
  const s = await state();
  assert.deepEqual(s.sources, {});
  assert.equal(s.override, "auto");
  assert.deepEqual(s.stages, []);
  assert.equal(s.lease, null);
  assert.equal(s.active.source, null);
  assert.equal(s.session.state, "live", "the session is the platform's and stays");
  const stored = await ctx.storage.get("state");
  assert.equal(stored.override, "auto");
  assert.deepEqual(stored.sources, {});
});

test("a stage cue is fenced to the live session; the platform is asked again before a refusal", async () => {
  const platform = fakePlatform();
  const { call, state } = fakeControl(platform);
  await state();
  const asked = platform.calls.length;
  // Nothing is live: refused, after one more look at the platform.
  const idle = await call("/api/stage", { stage: "1st Latifa" }, "host");
  assert.equal(idle.status, 409);
  assert.deepEqual(idle.data, { error: "no live session" });
  assert.equal(platform.calls.length, asked + 1);
  // The platform starts a session; our 3 s old view still says idle, but
  // the cue is not lost: a fresh look finds the session.
  platform.live = { kind: "zikr", sessionID: "S1" };
  now += 3_000;
  const early = await call("/api/stage", { stage: "1st Latifa", sessionId: "S1" }, "host");
  assert.equal(early.status, 200);
  assert.equal((await state()).session.id, "S1");
  // Naming the current session is fine; naming another is stale.
  assert.equal((await call("/api/stage", { stage: "2nd", sessionId: "S1" }, "host")).status, 200);
  const stale = await call("/api/stage", { stage: "3rd", sessionId: "S0" }, "host");
  assert.equal(stale.status, 409);
  assert.deepEqual(stale.data, { error: "stale session" });
  // After the end a late cue is refused, and it cannot reach the next session either.
  platform.live = null;
  now += 11_000;
  await state();
  const after = await call("/api/stage", { stage: "Dua", origin: "paltalk" });
  assert.equal(after.status, 409);
  assert.deepEqual(after.data, { error: "no live session" });
  platform.live = { kind: "zikr", sessionID: "S2" };
  now += 11_000;
  await state();
  const old = await call("/api/stage", { stage: "Dua", sessionId: "S1" }, "host");
  assert.equal(old.status, 409);
  assert.deepEqual(old.data, { error: "stale session" });
  assert.deepEqual((await state()).stages, [], "S2's log is clean");
  const unnamed = await call("/api/stage", { stage: "1st Latifa", origin: "paltalk" });
  assert.equal(unnamed.status, 200, "a cue that names no session goes to the live one");
  assert.deepEqual((await state()).stages.map((e) => e.stage), ["1st Latifa"]);
});

test("a session the platform cannot name is never remembered as ended", async () => {
  const platform = fakePlatform();
  const { state, ctx } = fakeControl(platform);
  platform.live = { kind: "zikr" };
  let s = await state();
  assert.equal(s.session.id, "platform-unknown");
  platform.live = null;
  now += 11_000;
  s = await state();
  assert.equal(s.session.state, "ended");
  assert.deepEqual((await ctx.storage.get("state")).ended, []);
  platform.live = { kind: "zikr" };
  now += 11_000;
  s = await state();
  assert.equal(s.session.state, "live", "the next unnamed session still goes live");
});

test("a host key cannot grow the publisher stamps without bound", async () => {
  const platform = fakePlatform();
  platform.live = { kind: "zikr", sessionID: "zikr-1" };
  const { call, ctx, state } = fakeControl(platform);
  await state();
  for (let i = 0; i < 40; i++) {
    now += 10;
    await call("/api/source", { source: "app", sessionId: "phone" + i, trackName: "app-" + i }, "host");
  }
  const stored = await ctx.storage.get("state");
  assert.ok(Object.keys(stored.publishers).length <= 21, `kept ${Object.keys(stored.publishers).length}`);
  assert.ok(stored.publishers.phone39, "the device on air is kept");
  assert.equal(stored.publishers.phone0, undefined, "the oldest spare stamps go first");
});

test("a signature of the right length but wrong bytes is refused", async () => {
  const upstream = fakeSfu();
  const env = workerEnv();
  const good = mintToken("abc123", "listen", now + 1000);
  const parts = good.split(".");
  const flipped = parts[4].slice(0, -1) + (parts[4].endsWith("A") ? "B" : "A");
  const response = await handler.fetch(sfuRequest("listen", "PUT", "/sessions/abc123/renegotiate", { token: parts.slice(0, 4).concat(flipped).join("."), body: {} }), env);
  assert.equal(response.status, 403);
  assert.deepEqual(upstream, []);
  const fine = await handler.fetch(sfuRequest("listen", "PUT", "/sessions/abc123/renegotiate", { token: good, body: {} }), env);
  assert.equal(fine.status, 200);
});
