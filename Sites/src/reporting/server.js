// reporting.naqshbandiaowaisiah.us: the Silsila Markaz's reports and analytics
// for super admins and the Markaz's officers (owner 2026-11-05). Nothing here
// is public: the page signs in with a code that an officer approves in the
// app (Halqah > Reports & analytics > Sign in on a computer). The session then
// lives in an HttpOnly cookie, and every read goes to the platform's
// /v1/markaz routes with it; the platform checks the role on every request.
import APP from "./app.client.txt";
import STYLE from "./app.css.txt";

export const REPORTING_HOST = "reporting.naqshbandiaowaisiah.us";
const COOKIE = "__Host-di_report";

const HEADERS = {
  "x-content-type-options": "nosniff",
  "x-frame-options": "DENY",
  "referrer-policy": "no-referrer",
  "strict-transport-security": "max-age=31536000; includeSubDomains",
  "permissions-policy": "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
  "cross-origin-opener-policy": "same-origin",
  "x-robots-tag": "noindex, nofollow",
  "content-security-policy": [
    "default-src 'none'", "script-src 'self'", "style-src 'self' https://fonts.googleapis.com", "font-src https://fonts.gstatic.com",
    "img-src 'self' data:", "connect-src 'self'", "base-uri 'none'", "form-action 'self'", "frame-ancestors 'none'",
  ].join("; "),
};

const respond = (body, type, status = 200, extra = {}) =>
  new Response(body, { status, headers: { "content-type": type, "cache-control": "no-store", ...HEADERS, ...extra } });
const jsonOut = (status, body, extra = {}) => respond(JSON.stringify(body), "application/json; charset=utf-8", status, extra);

function tokenOf(request) {
  const cookie = request.headers.get("cookie") ?? "";
  const match = new RegExp(`(?:^|;\\s*)${COOKIE}=([0-9a-f]{64})`).exec(cookie);
  return match ? match[1] : null;
}

async function platform(env, request, path, init = {}) {
  const headers = new Headers({ accept: "application/json", ...(init.headers ?? {}) });
  // The platform's rate limits count each person, not this Worker.
  const ip = request.headers.get("cf-connecting-ip");
  if (ip) headers.set("cf-connecting-ip", ip);
  return env.API.fetch(new Request(`https://platform${path}`, { ...init, headers }));
}

const page = (logo) => `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Silsila Markaz · Reports</title><meta name="robots" content="noindex,nofollow">
<link rel="icon" href="/logo.webp"><link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Cormorant+Garamond:wght@600;700&display=swap">
<link rel="stylesheet" href="/app.css"></head>
<body><div id="app" data-logo="${logo}"><div class="boot"><img src="/logo.webp" alt="" width="72" height="72"><p>Loading the Silsila Markaz…</p></div></div>
<script src="/app.js" defer></script></body></html>`;

/** Every request to the reporting host. */
export async function reportingRequest(request, env, logo) {
  const url = new URL(request.url);
  const path = url.pathname;
  if (path === "/logo.webp") return new Response(logo, { headers: { "content-type": "image/webp", "cache-control": "public, max-age=604800" } });
  if (path === "/app.js") return respond(APP, "text/javascript; charset=utf-8", 200, { "cache-control": "no-cache" });
  if (path === "/app.css") return respond(STYLE, "text/css; charset=utf-8", 200, { "cache-control": "no-cache" });
  if (path === "/robots.txt") return respond("User-agent: *\nDisallow: /\n", "text/plain; charset=utf-8");

  // Sign-in: a code to show, then waiting for the officer to approve it.
  if (path === "/auth/start" && request.method === "POST") {
    const answer = await platform(env, request, "/v1/reporting/link", { method: "POST" });
    return jsonOut(answer.status, await answer.json().catch(() => ({ error: "Try again" })));
  }
  if (path === "/auth/poll" && request.method === "POST") {
    const input = await request.json().catch(() => ({}));
    const answer = await platform(env, request, "/v1/reporting/link/poll",
      { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ pollToken: String(input.pollToken ?? "") }) });
    const body = await answer.json().catch(() => ({ status: "expired" }));
    if (body.status === "approved" && /^[0-9a-f]{64}$/.test(body.token ?? "")) {
      const maxAge = Math.max(60, Math.floor((Date.parse(body.expiresAt) - Date.now()) / 1000));
      // The token never reaches the page's script.
      return jsonOut(200, { status: "approved" }, { "set-cookie": `${COOKIE}=${body.token}; Path=/; Max-Age=${maxAge}; HttpOnly; Secure; SameSite=Strict` });
    }
    return jsonOut(answer.status === 429 ? 429 : 200, { status: body.status ?? "expired" });
  }
  if (path === "/auth/signout" && request.method === "POST") {
    const token = tokenOf(request);
    if (token) {
      const auth = { authorization: `Bearer ${token}` };
      const list = await platform(env, request, "/v1/markaz/reporting-sessions", { headers: auth }).then(r => r.json()).catch(() => null);
      const mine = list?.sessions?.find(item => item.current);
      if (mine) await platform(env, request, `/v1/markaz/reporting-sessions/${mine.id}`, { method: "DELETE", headers: auth });
    }
    return jsonOut(200, { ok: true }, { "set-cookie": `${COOKIE}=; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Strict` });
  }

  // The reports: /api/<route> is the platform's /v1/markaz/<route>, with the cookie's session.
  if (path.startsWith("/api/")) {
    const token = tokenOf(request);
    if (!token) return jsonOut(401, { error: "Sign in" });
    const method = request.method;
    if (!["GET", "PUT", "POST", "DELETE"].includes(method)) return jsonOut(405, { error: "Not allowed" });
    // Changes come only from this page's own script (with SameSite=Strict, a second guard against forged requests).
    if (method !== "GET" && request.headers.get("x-markaz") !== "1") return jsonOut(403, { error: "Not allowed" });
    const rest = path.slice(5);
    if (!/^[a-z-]+(\/[A-Za-z0-9:_-]{1,80}){0,2}$/.test(rest)) return jsonOut(404, { error: "Not found" });
    const init = { method, headers: { authorization: `Bearer ${token}` } };
    if (method === "PUT" || method === "POST") {
      const text = await request.text();
      if (text.length > 20_000) return jsonOut(413, { error: "Too large" });
      init.headers["content-type"] = "application/json";
      init.body = text || "{}";
    }
    const answer = await platform(env, request, `/v1/markaz/${rest}${url.search}`, init);
    const type = answer.headers.get("content-type") ?? "application/json; charset=utf-8";
    const extra = {};
    const disposition = answer.headers.get("content-disposition");
    if (disposition) extra["content-disposition"] = disposition;
    // A session that ended or lost its access signs the page out.
    if (answer.status === 401) extra["set-cookie"] = `${COOKIE}=; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Strict`;
    return respond(answer.body, type, answer.status, extra);
  }

  if (path === "/" || path === "/index.html") return respond(page("/logo.webp"), "text/html; charset=utf-8");
  return respond("Not found", "text/plain; charset=utf-8", 404);
}
