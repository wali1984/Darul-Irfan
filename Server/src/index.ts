import type { DeviceRegistration, Env } from "./contracts";
import { adminRequest } from "./admin";
import { bootstrap, feed, liveBroadcast } from "./repository";
import { refreshWebsiteCatalog, refreshYouTube } from "./sources";
import { cleanText, isUUID, json, redactDiagnostics, sha256 } from "./util";

const allowedTopics = new Set(["liveZikr", "broadcasts", "announcements", "events"]);

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url); const path = url.pathname.replace(/\/$/, "") || "/";
  if (path === "/health") {
    const health = await env.DB.prepare("SELECT * FROM source_health ORDER BY source").all();
    const degraded = health.results.some(row => row.status === "degraded");
    return json({ ok: !degraded, environment: env.ENVIRONMENT, sources: health.results }, { status: degraded ? 503 : 200 });
  }
  if (path.startsWith("/admin")) return adminRequest(request, env, path);
  if (request.method === "GET" && path === "/v1/bootstrap") return cachedJSON(await bootstrap(env), request, 300);
  if (request.method === "GET" && path === "/v1/live") return cachedJSON(await liveBroadcast(env), request, 60);
  if (request.method === "GET" && path === "/v1/feed") {
    const limit = Number(url.searchParams.get("limit") ?? 20); const cursor = url.searchParams.get("cursor") ?? undefined;
    return cachedJSON(await feed(env, limit, cursor), request, 300);
  }
  if (request.method === "POST" && path === "/v1/devices") {
    if (!await withinWriteLimit(request, env, "devices", 30)) return json({ error: "Too many requests" }, { status: 429 });
    return registerDevice(request, env);
  }
  if (request.method === "DELETE" && path.startsWith("/v1/devices/")) return deleteDevice(request, env, path.split("/").at(-1) ?? "");
  if (request.method === "POST" && path === "/v1/diagnostics") {
    if (!await withinWriteLimit(request, env, "diagnostics", 10)) return json({ error: "Too many requests" }, { status: 429 });
    return diagnostics(request, env);
  }
  return json({ error: "Not found" }, { status: 404 });
}

async function withinWriteLimit(request: Request, env: Env, bucket: string, maximum: number): Promise<boolean> {
  const client = request.headers.get("cf-connecting-ip") ?? "unknown";
  const keyHash = await sha256(`${bucket}:${client}`);
  const now = new Date();
  const windowStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), now.getUTCHours())).toISOString();
  await env.DB.prepare(`INSERT INTO rate_limits(key_hash,window_start,request_count) VALUES(?,?,1)
    ON CONFLICT(key_hash,window_start) DO UPDATE SET request_count=request_count+1`).bind(keyHash, windowStart).run();
  const row = await env.DB.prepare("SELECT request_count FROM rate_limits WHERE key_hash=? AND window_start=?").bind(keyHash, windowStart).first<{ request_count: number }>();
  return Number(row?.request_count ?? maximum + 1) <= maximum;
}

async function cachedJSON(value: unknown, request: Request, maxAge: number): Promise<Response> {
  const body = JSON.stringify(value); const etag = `\"${await sha256(body)}\"`;
  if (request.headers.get("if-none-match") === etag) return new Response(null, { status: 304, headers: { etag, "cache-control": `public,max-age=${maxAge}` } });
  return new Response(body, { headers: { "content-type": "application/json; charset=utf-8", etag, "cache-control": `public,max-age=${maxAge}`, "x-content-type-options": "nosniff" } });
}

async function registerDevice(request: Request, env: Env): Promise<Response> {
  const input = await request.json<DeviceRegistration>();
  if (!isUUID(input.installationID) || !/^[0-9a-f]{64,200}$/i.test(input.apnsToken) || !["sandbox", "production"].includes(input.environment)) return json({ error: "Invalid registration" }, { status: 400 });
  const topics = [...new Set(input.topics.filter(topic => allowedTopics.has(topic)))];
  const now = new Date().toISOString();
  // APNs may return the same token after a reinstall. Move it to the current
  // anonymous installation instead of failing the UNIQUE constraint.
  await env.DB.prepare("DELETE FROM devices WHERE apns_token=? AND installation_id<>?")
    .bind(input.apnsToken.toLowerCase(), input.installationID).run();
  await env.DB.prepare(`INSERT INTO devices(installation_id,apns_token,locale,timezone,topics_json,environment,app_version,created_at,last_seen_at)
    VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(installation_id) DO UPDATE SET apns_token=excluded.apns_token,locale=excluded.locale,timezone=excluded.timezone,topics_json=excluded.topics_json,environment=excluded.environment,app_version=excluded.app_version,last_seen_at=excluded.last_seen_at`)
    .bind(input.installationID, input.apnsToken.toLowerCase(), cleanText(input.locale, 20) ?? "en", cleanText(input.timeZone, 80) ?? "UTC", JSON.stringify(topics), input.environment, cleanText(input.appVersion, 30) ?? "unknown", now, now).run();
  return json({ ok: true }, { status: 201 });
}

async function deleteDevice(request: Request, env: Env, installationID: string): Promise<Response> {
  if (!isUUID(installationID)) return json({ error: "Invalid installation ID" }, { status: 400 });
  const token = request.headers.get("x-apns-token"); if (!token) return json({ error: "Token confirmation required" }, { status: 401 });
  await env.DB.prepare("DELETE FROM devices WHERE installation_id=? AND apns_token=?").bind(installationID, token.toLowerCase()).run();
  return new Response(null, { status: 204 });
}

async function diagnostics(request: Request, env: Env): Promise<Response> {
  const input = await request.json<Record<string, unknown>>(); const installationID = cleanText(input.installationID, 50);
  if (!installationID || !isUUID(installationID)) return json({ error: "Invalid diagnostic payload" }, { status: 400 });
  const redacted = redactDiagnostics(input) as Record<string, unknown>;
  const encoded = JSON.stringify(redacted); if (encoded.length > 256_000) return json({ error: "Payload too large" }, { status: 413 });
  const now = new Date(); const expires = new Date(now.getTime() + 30 * 86_400_000);
  await env.DB.prepare("INSERT INTO diagnostics(installation_hash,app_version,os_version,payload_json,received_at,expires_at) VALUES(?,?,?,?,?,?)")
    .bind(await sha256(installationID), cleanText(redacted.appVersion, 30) ?? "unknown", cleanText(redacted.osVersion, 30) ?? "unknown", encoded, now.toISOString(), expires.toISOString()).run();
  return json({ ok: true }, { status: 202 });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try { return await route(request, env); }
    catch (error) {
      console.error("request failed", error instanceof Error ? error.message : "unknown error");
      return json({ error: "Request could not be completed" }, { status: 500 });
    }
  },
  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    const minute = new Date().getUTCMinutes();
    // Facebook is intentionally NOT ingested: with only public (non-admin)
    // access to the official Page, the Graph API cannot read its posts. The
    // app deep-links to Facebook instead. Re-add refreshFacebook here once a
    // Page access token is available.
    const jobs: Array<{ name: string; run: Promise<void> }> = [{ name: "youtube", run: refreshYouTube(env) }];
    if (minute % 15 === 0) jobs.push(
      { name: "website", run: refreshWebsiteCatalog(env) }
    );
    const results = await Promise.allSettled(jobs.map(job => job.run));
    const attemptedAt = new Date().toISOString();
    for (let index = 0; index < jobs.length; index += 1) {
      const job = jobs[index]; const result = results[index];
      if (!job || !result) continue;
      if (result.status === "fulfilled") {
        await env.DB.prepare(`INSERT INTO source_health(source,status,last_success_at,last_attempt_at,consecutive_failures,last_error)
          VALUES(?,'healthy',?,?,0,NULL) ON CONFLICT(source) DO UPDATE SET status='healthy',last_success_at=excluded.last_success_at,last_attempt_at=excluded.last_attempt_at,consecutive_failures=0,last_error=NULL`)
          .bind(job.name, attemptedAt, attemptedAt).run();
      } else {
        const message = result.reason instanceof Error ? result.reason.message : String(result.reason);
        await env.DB.prepare(`INSERT INTO source_health(source,status,last_attempt_at,consecutive_failures,last_error)
          VALUES(?,'degraded',?,1,?) ON CONFLICT(source) DO UPDATE SET status='degraded',last_attempt_at=excluded.last_attempt_at,consecutive_failures=source_health.consecutive_failures+1,last_error=excluded.last_error`)
          .bind(job.name, attemptedAt, message.slice(0, 500)).run();
        console.error(`${job.name} refresh failed: ${message}`);
      }
    }
    await env.DB.prepare("DELETE FROM diagnostics WHERE expires_at < ?").bind(new Date().toISOString()).run();
    await env.DB.prepare("DELETE FROM rate_limits WHERE window_start < ?").bind(new Date(Date.now() - 2 * 86_400_000).toISOString()).run();
  }
} satisfies ExportedHandler<Env>;

export { route };
