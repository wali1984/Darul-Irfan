// Staging Worker for the live relay test: proxies the Realtime SFU (the app
// token never reaches a client), routes state to the Control object, and
// serves the host and listener test pages.

import { Control, json, type ControlEnv, type Role } from "./control";
import hostPage from "./pages/host.html";
import listenPage from "./pages/listen.html";
import clientLib from "./pages/client.txt";

export { Control };

interface Env extends ControlEnv {
  CONTROL: DurableObjectNamespace;
  SFU_BASE: string;
  SFU_APP_ID: string;
  SFU_APP_TOKEN: string;
  HOST_KEY: string;
  RELAY_KEY: string;
  LISTEN_KEY: string;
  ALLOWED_ORIGINS?: string;
}

async function roleFor(request: Request, env: Env): Promise<Role | null> {
  const url = new URL(request.url);
  const key = request.headers.get("x-live-key") ?? url.searchParams.get("key") ?? "";
  if (!key) return null;
  if (env.HOST_KEY && key === env.HOST_KEY) return "host";
  if (env.RELAY_KEY && key === env.RELAY_KEY) return "relay";
  if (env.LISTEN_KEY && key === env.LISTEN_KEY) return "listen";
  if (key.startsWith("app.")) return verifyAppKey(key, env);
  return null;
}

// MARK: - App keys
// The app never holds a live key. It trades the user's Darul Irfan sign-in
// for a signed key good for 12 hours: "host" for the Halqah's moderators
// (Hazrat ji and admins, per the platform's own stage poll), "listen" for
// everyone else.

const APP_KEY_HOURS = 12;

async function hmac(secret: string, text: string): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = new Uint8Array(await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(text)));
  return btoa(String.fromCharCode(...signature)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// Compares a presented signature with the right one in time that does not
// depend on where they differ, so a guess learns nothing from the clock.
function sameSignature(presented: string, expected: string): boolean {
  const a = new TextEncoder().encode(presented);
  const b = new TextEncoder().encode(expected);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

async function signAppKey(role: "host" | "listen", env: Env): Promise<string> {
  const body = `${role}.${Date.now() + APP_KEY_HOURS * 3_600_000}`;
  return `app.${body}.${await hmac(env.HOST_KEY, body)}`;
}

async function verifyAppKey(key: string, env: Env): Promise<Role | null> {
  const [, role, expires, signature] = key.split(".");
  if ((role !== "host" && role !== "listen") || !expires || !signature) return null;
  if (Number(expires) < Date.now()) return null;
  return sameSignature(signature, await hmac(env.HOST_KEY, `${role}.${expires}`)) ? role : null;
}

async function appSession(request: Request, env: Env): Promise<Response> {
  const bearer = request.headers.get("authorization") ?? "";
  if (!/^Bearer \S+$/.test(bearer)) return json({ error: "sign-in required" }, 401);
  const answer = await env.PLATFORM.fetch(`${env.PLATFORM_URL}/v1/groups/${env.HALQAH_ID}/stage`, {
    headers: { authorization: bearer, "user-agent": "DarulIrfanLive/1.0" },
  });
  // Our Sheikh is public: anyone may listen. Only the platform's yes makes a
  // host; any other answer (signed out, not a member, platform down) is a
  // listener.
  const stage = answer.ok ? ((await answer.json()) as { canModerate?: boolean }) : {};
  const role = stage.canModerate === true ? "host" : "listen";
  return json({ role, key: await signAppKey(role, env), expiresInHours: APP_KEY_HOURS });
}

// MARK: - SFU session ownership
// Whoever opens an SFU session gets a signed token for it; the follow-up
// calls (tracks/new, renegotiate, tracks/close) must carry it, so a listener
// key can only ever touch the listener's own receiving session, never the
// publisher's. The token is bound to the session and to the caller's role.
// Format: sess.<sessionId>.<role>.<expiresMs>.<hmac>

const SESSION_TOKEN_HOURS = 14;
const SESSION_HEADER = "x-live-session";

async function signSessionToken(sessionId: string, role: Role, env: Env): Promise<string> {
  const body = `${sessionId}.${role}.${Date.now() + SESSION_TOKEN_HOURS * 3_600_000}`;
  return `sess.${body}.${await hmac(env.HOST_KEY, body)}`;
}

async function verifySessionToken(token: string, sessionId: string, role: Role, env: Env): Promise<boolean> {
  const parts = token.split(".");
  if (parts.length !== 5 || parts[0] !== "sess") return false;
  const [, id, tokenRole, expires, signature] = parts;
  if (id !== sessionId || tokenRole !== role || !signature) return false;
  if (!/^\d+$/.test(expires) || Number(expires) < Date.now()) return false;
  return sameSignature(signature, await hmac(env.HOST_KEY, `${id}.${tokenRole}.${expires}`));
}

// The SFU operations a client may ask for, each with its one method.
const SFU_OPERATIONS: Record<string, string> = { new: "POST", "tracks/new": "POST", "tracks/close": "PUT", renegotiate: "PUT" };

// What each role may publish: the host page only "app…" tracks, the relay
// only "paltalk…" tracks, listeners nothing.
function tracksAllowed(role: Role, tracks: unknown): boolean {
  if (!Array.isArray(tracks)) return false;
  return tracks.every((track: any) => {
    if (track?.location === "remote") return true;
    if (track?.location !== "local") return false;
    const name = String(track.trackName ?? "");
    return (role === "host" && name.startsWith("app")) || (role === "relay" && name.startsWith("paltalk"));
  });
}

async function sfuFetch(env: Env, path: string, method: string, body?: string): Promise<Response> {
  return fetch(`${env.SFU_BASE}/${env.SFU_APP_ID}${path}`, {
    method,
    body,
    headers: { authorization: `Bearer ${env.SFU_APP_TOKEN}`, "content-type": "application/json" },
  });
}

// Opens a session and hands the caller its token.
async function sfuNewSession(env: Env, role: Role): Promise<Response> {
  const upstream = await sfuFetch(env, "/sessions/new", "POST");
  const text = await upstream.text();
  let data: any = null;
  try {
    data = JSON.parse(text || "{}");
  } catch {
    data = null;
  }
  if (!upstream.ok || typeof data?.sessionId !== "string") {
    return new Response(text, { status: upstream.status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
  }
  return json({ ...data, sessionToken: await signSessionToken(data.sessionId, role, env) });
}

async function sfu(request: Request, env: Env, role: Role, path: string): Promise<Response> {
  const method = request.method;
  const body = await request.text();
  if (path.endsWith("/tracks/new")) {
    let parsed: any;
    try {
      parsed = JSON.parse(body || "{}");
    } catch {
      return json({ error: "bad json" }, 400);
    }
    if (!tracksAllowed(role, parsed.tracks)) return json({ error: "track not allowed for this key" }, 403);
  }
  const upstream = await sfuFetch(env, path, method, body);
  return new Response(upstream.body, {
    status: upstream.status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

// /api/sfu/sessions/new, /api/sfu/sessions/:id/tracks/new,
// /api/sfu/sessions/:id/renegotiate, /api/sfu/sessions/:id/tracks/close
async function sfuRoute(request: Request, env: Env, role: Role, rest: string): Promise<Response> {
  const match = /^\/sessions\/(?:(new)|([A-Za-z0-9]+)\/(tracks\/new|tracks\/close|renegotiate))$/.exec(rest);
  if (!match) return json({ error: "not found" }, 404);
  const operation = match[1] ?? match[3];
  const sessionId = match[2] ?? "";
  const allowed = SFU_OPERATIONS[operation];
  if (request.method !== allowed) {
    const response = json({ error: "method not allowed" }, 405);
    response.headers.set("allow", allowed);
    return response;
  }
  if (operation === "new") return sfuNewSession(env, role);
  // Ownership is settled here, before anything reaches the SFU.
  const token = request.headers.get(SESSION_HEADER) ?? "";
  if (!(await verifySessionToken(token, sessionId, role, env))) return json({ error: "not your session" }, 403);
  return sfu(request, env, role, rest);
}

function page(html: string): Response {
  return new Response(html, {
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-robots-tag": "noindex" },
  });
}

// The public websites listen from their own origins: the listener calls
// (state, SFU pull) answer them with CORS; nothing else does.
function corsOrigin(request: Request, env: Env): string | null {
  const origin = request.headers.get("origin");
  if (!origin) return null;
  const allowed = (env.ALLOWED_ORIGINS ?? "").split(",").map((value) => value.trim()).filter(Boolean);
  return allowed.includes(origin) ? origin : null;
}

function withCors(response: Response, origin: string): Response {
  const headers = new Headers(response.headers);
  headers.set("access-control-allow-origin", origin);
  headers.set("vary", "origin");
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

const LISTENER_PATHS = /^\/api\/(state|whoami|sfu\/.*)$/;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const path = new URL(request.url).pathname;
    const origin = LISTENER_PATHS.test(path) ? corsOrigin(request, env) : null;
    if (request.method === "OPTIONS") {
      if (!origin) return new Response(null, { status: 403 });
      return new Response(null, {
        status: 204,
        headers: {
          "access-control-allow-origin": origin,
          "access-control-allow-methods": "GET, POST, PUT",
          "access-control-allow-headers": `content-type, x-live-key, ${SESSION_HEADER}`,
          "access-control-max-age": "86400",
          vary: "origin",
        },
      });
    }
    const response = await handle(request, env);
    return origin && response.status !== 101 ? withCors(response, origin) : response;
  },
} satisfies ExportedHandler<Env>;

async function handle(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/" || path === "/listen") return page(listenPage);
    if (path === "/host") return page(hostPage);
    if (path === "/client.js") {
      return new Response(clientLib, { headers: { "content-type": "text/javascript; charset=utf-8", "cache-control": "no-store" } });
    }
    if (path === "/health") return json({ ok: true, environment: "staging" });

    if (!path.startsWith("/api/")) return json({ error: "not found" }, 404);
    if (path === "/api/app-session" && request.method === "POST") return appSession(request, env);
    const role = await roleFor(request, env);
    if (!role) return json({ error: "key required" }, 401);
    if (path === "/api/whoami") return json({ role });

    if (path.startsWith("/api/sfu/")) return sfuRoute(request, env, role, path.slice("/api/sfu".length));

    if (path === "/api/ws" && request.headers.get("upgrade") !== "websocket") return json({ error: "websocket expected" }, 426);
    const stub = env.CONTROL.get(env.CONTROL.idFromName("programme"));
    const forwarded = new Request(request, { headers: new Headers(request.headers) });
    forwarded.headers.set("x-live-role", role);
    return stub.fetch(forwarded);
}
