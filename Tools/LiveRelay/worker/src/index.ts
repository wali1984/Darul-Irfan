// Staging Worker for the live relay test: proxies the Realtime SFU (the app
// token never reaches a client), routes state to the Control object, and
// serves the host and listener test pages.

import { Control, json, type Role } from "./control";
import hostPage from "./pages/host.html";
import listenPage from "./pages/listen.html";
import clientLib from "./pages/client.txt";

export { Control };

interface Env {
  CONTROL: DurableObjectNamespace;
  SFU_BASE: string;
  SFU_APP_ID: string;
  SFU_APP_TOKEN: string;
  HOST_KEY: string;
  RELAY_KEY: string;
  LISTEN_KEY: string;
  ALLOWED_ORIGINS?: string;
  PLATFORM_URL: string;
  HALQAH_ID: string;
  PLATFORM: Fetcher;
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

async function signAppKey(role: "host" | "listen", env: Env): Promise<string> {
  const body = `${role}.${Date.now() + APP_KEY_HOURS * 3_600_000}`;
  return `app.${body}.${await hmac(env.HOST_KEY, body)}`;
}

async function verifyAppKey(key: string, env: Env): Promise<Role | null> {
  const [, role, expires, signature] = key.split(".");
  if ((role !== "host" && role !== "listen") || !expires || !signature) return null;
  if (Number(expires) < Date.now()) return null;
  return (await hmac(env.HOST_KEY, `${role}.${expires}`)) === signature ? role : null;
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

async function sfu(request: Request, env: Env, role: Role, path: string): Promise<Response> {
  const method = request.method;
  let body: string | undefined;
  if (method === "POST" || method === "PUT") {
    body = await request.text();
    if (path.endsWith("/tracks/new")) {
      let parsed: any;
      try {
        parsed = JSON.parse(body || "{}");
      } catch {
        return json({ error: "bad json" }, 400);
      }
      if (!tracksAllowed(role, parsed.tracks)) return json({ error: "track not allowed for this key" }, 403);
    }
  }
  const upstream = await fetch(`${env.SFU_BASE}/${env.SFU_APP_ID}${path}`, {
    method,
    body,
    headers: { authorization: `Bearer ${env.SFU_APP_TOKEN}`, "content-type": "application/json" },
  });
  return new Response(upstream.body, {
    status: upstream.status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
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
          "access-control-allow-headers": "content-type, x-live-key",
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

    // /api/sfu/sessions/new, /api/sfu/sessions/:id/tracks/new,
    // /api/sfu/sessions/:id/renegotiate, /api/sfu/sessions/:id/tracks/close
    if (path.startsWith("/api/sfu/")) {
      const rest = path.slice("/api/sfu".length);
      if (!/^\/sessions\/(new|[A-Za-z0-9]+(\/tracks\/new|\/tracks\/close|\/renegotiate)?)$/.test(rest)) {
        return json({ error: "not found" }, 404);
      }
      return sfu(request, env, role, rest);
    }

    if (path === "/api/ws" && request.headers.get("upgrade") !== "websocket") return json({ error: "websocket expected" }, 426);
    const stub = env.CONTROL.get(env.CONTROL.idFromName("programme"));
    const forwarded = new Request(request, { headers: new Headers(request.headers) });
    forwarded.headers.set("x-live-role", role);
    return stub.fetch(forwarded);
}
