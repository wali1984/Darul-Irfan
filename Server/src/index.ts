import type { DeviceRegistration, Env } from "./contracts";
import { adminRequest } from "./admin";
import { bootstrap, feed, liveBroadcast } from "./repository";
import { refreshWebsiteCatalog, refreshYouTube } from "./sources";
import { cleanText, isUUID, json, redactDiagnostics, sha256 } from "./util";
import { whatsappSubscription, whatsappWebhook } from "./whatsapp";
import { authenticatedMember, createSession, deleteMember, redeemInvite } from "./members";
import {
  cancelMeeting, communityGroups, communityPosts, createPost, groupDetail, hidePost, joinRoom, me, meetingPage,
  publishDraft, registerMemberDevice, removeZikrSession, saveZikrSession, scheduleMeeting, setLive,
} from "./community";
import { serveMedia } from "./media";
import { addPerson, groupPeople, removePerson, revokeInvitation, setPersonRole } from "./groupAdmin";
import { listenerHealth, listenerHeartbeat, reconcileLive, streamEvent } from "./live";
import { deleteRecording, listRecordings, uploadRecording } from "./recordings";
import { autoplayDue, checkIn, controlSession, duaRequests, markDuaRead, requestDua, sessionHistory } from "./session";
import { collectRoomRecordings } from "./roomRecordings";
import { createHalqah, memberDirectory, retireHalqah, updateHalqah } from "./halqahs";
import { dailyMediaFor, deleteDailyMedia, manageDailyMedia, updateDailyMedia, uploadDailyMedia } from "./dailyMedia";

const allowedTopics = new Set(["liveZikr", "broadcasts", "announcements", "events"]);

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url); const path = url.pathname.replace(/\/$/, "") || "/";
  if (path === "/health") {
    const health = await env.DB.prepare("SELECT * FROM source_health ORDER BY source").all();
    const degraded = health.results.some(row => row.status === "degraded");
    return json({ ok: !degraded, environment: env.ENVIRONMENT, sources: health.results, listeners: await listenerHealth(env) },
      { status: degraded ? 503 : 200 });
  }
  if (path.startsWith("/admin")) return adminRequest(request, env, path);
  if (request.method === "GET" && path === "/v1/bootstrap") return cachedJSON(await bootstrap(env), request, 300);
  if (request.method === "GET" && path === "/v1/live") return cachedJSON(await liveBroadcast(env), request, 60);
  if (request.method === "GET" && path === "/v1/feed") {
    const limit = Number(url.searchParams.get("limit") ?? 20); const cursor = url.searchParams.get("cursor") ?? undefined;
    if (!Number.isInteger(limit) || limit < 1 || limit > 50) return json({ error: "Limit must be an integer from 1 to 50" }, { status: 400 });
    return cachedJSON(await feed(env, limit, cursor), request, 300);
  }
  // Authenticated by Meta's HMAC over the raw body, so it needs the body text
  // rather than a parsed object, and it is deliberately not rate limited: a
  // throttled 429 would make Meta retry the same payload.
  if (path === "/v1/whatsapp") {
    if (request.method === "GET") return whatsappSubscription(env, url);
    if (request.method === "POST") return whatsappWebhook(request, env, await request.text());
    return json({ error: "Not found" }, { status: 404 });
  }
  // Private regional groups. Everything past the session exchange requires a
  // member bearer token, and none of it is reachable from the public feed.
  if (request.method === "POST" && path === "/v1/members/session") {
    if (!await withinWriteLimit(request, env, "member-session", 20)) return json({ error: "Too many requests" }, { status: 429 });
    return createSession(request, env);
  }
  if (request.method === "POST" && path === "/v1/members/invite") {
    // Rate limited harder than the session exchange: this one takes a secret
    // that could otherwise be guessed at.
    if (!await withinWriteLimit(request, env, "member-invite", 10)) return json({ error: "Too many requests" }, { status: 429 });
    return redeemInvite(request, env);
  }
  // The live zikr pipeline: listener heartbeats and Stream's input events,
  // each authenticated by its own secret and not rate limited, since both
  // arrive every few seconds while a session runs.
  if (request.method === "POST" && path === "/v1/live/listener") return listenerHeartbeat(request, env);
  if (request.method === "POST" && path === "/v1/live/stream-events") return streamEvent(request, env);
  // The in-app meeting screen. It holds no secret: the participant token
  // travels in the URL fragment, which browsers never send.
  if (request.method === "GET" && path === "/v1/meet") return meetingPage();
  // Pictures and recordings, by signed and expiring link only.
  if ((request.method === "GET" || request.method === "HEAD") && path.startsWith("/v1/media/")) {
    return serveMedia(request, env, path.slice("/v1/media/".length), url);
  }
  // The Today page's pictures for a day, as published.
  if (request.method === "GET" && path === "/v1/daily-media") return dailyMediaFor(env, url);
  if (path.startsWith("/v1/daily-media/manage")) {
    const member = await authenticatedMember(request, env);
    if (!member) return json({ error: "Member sign-in required" }, { status: 401 });
    const item = /^\/v1\/daily-media\/manage\/(daily-[a-f0-9-]{12})$/.exec(path)?.[1];
    if (path === "/v1/daily-media/manage" && request.method === "GET") return manageDailyMedia(env, member);
    if (path === "/v1/daily-media/manage" && request.method === "POST") {
      if (!await withinWriteLimit(request, env, "daily-media-upload", 60)) return json({ error: "Too many requests" }, { status: 429 });
      return uploadDailyMedia(request, env, member, url);
    }
    const input = (request.headers.get("content-type") ?? "").includes("json")
      ? await request.json<Record<string, unknown>>().catch(() => ({} as Record<string, unknown>)) : {};
    if (item && request.method === "PUT") return updateDailyMedia(env, member, item, input);
    if (item && request.method === "DELETE") return deleteDailyMedia(env, member, item);
    return json({ error: "Not found" }, { status: 404 });
  }
  if (path.startsWith("/v1/members") || path.startsWith("/v1/groups")) {
    const member = await authenticatedMember(request, env);
    if (!member) return json({ error: "Member sign-in required" }, { status: 401 });
    const body = async () => (request.headers.get("content-type") ?? "").includes("json")
      ? await request.json<Record<string, unknown>>().catch(() => ({} as Record<string, unknown>)) : {};
    if (request.method === "GET" && path === "/v1/groups") return communityGroups(env, member);
    // The Super admin's: make a Halqah, and everyone who has signed in.
    if (request.method === "POST" && path === "/v1/groups") return createHalqah(env, member, await body());
    if (request.method === "GET" && path === "/v1/members") return memberDirectory(env, member);
    if (request.method === "GET" && path === "/v1/members/me") return me(env, member);
    if (request.method === "POST" && path === "/v1/members/devices") return registerMemberDevice(env, member, await body());
    // Apple requires an account made in the app to be deletable from inside it.
    if (request.method === "DELETE" && path === "/v1/members/me") return deleteMember(env, member);

    const route = /^\/v1\/groups\/([a-z0-9-]{1,40})(?:\/(posts|zikr|live|meetings|join|people|invitations|recordings|control|presence|duas|history)(?:\/([A-Za-z0-9:_-]{1,80})(?:\/(publish|read))?)?)?$/.exec(path);
    if (!route) return json({ error: "Not found" }, { status: 404 });
    const [, groupID = "", section, entity, action] = route;
    if (!section && request.method === "GET") return groupDetail(env, member, groupID);
    if (!section && request.method === "PUT") return updateHalqah(env, member, groupID, await body());
    if (!section && request.method === "DELETE") return retireHalqah(env, member, groupID);
    if (section === "posts" && !entity && request.method === "GET") {
      const limit = Number(url.searchParams.get("limit") ?? 30);
      if (!Number.isInteger(limit) || limit < 1 || limit > 100) return json({ error: "Limit must be an integer from 1 to 100" }, { status: 400 });
      return communityPosts(env, member, groupID, limit, url.searchParams.get("drafts") === "1");
    }
    if (section === "posts" && !entity && request.method === "POST") return createPost(env, member, groupID, await body());
    if (section === "posts" && entity && action === "publish" && request.method === "POST") return publishDraft(env, member, groupID, entity, await body());
    if (section === "posts" && entity && !action && request.method === "DELETE") return hidePost(env, member, groupID, entity);
    if (section === "zikr" && entity && request.method === "PUT") return saveZikrSession(env, member, groupID, entity, await body());
    if (section === "zikr" && entity && request.method === "DELETE") return removeZikrSession(env, member, groupID, entity);
    if (section === "live" && !entity && request.method === "POST") return setLive(env, member, groupID, await body());
    if (section === "meetings" && !entity && request.method === "POST") return scheduleMeeting(env, member, groupID, await body());
    if (section === "meetings" && entity && request.method === "DELETE") return cancelMeeting(env, member, groupID, entity);
    if (section === "join" && !entity && request.method === "POST") return joinRoom(env, member, groupID, await body());
    if (section === "people" && !entity && request.method === "GET") return groupPeople(env, member, groupID);
    if (section === "people" && !entity && request.method === "POST") return addPerson(env, member, groupID, await body());
    if (section === "people" && entity && request.method === "PUT") return setPersonRole(env, member, groupID, entity, await body());
    if (section === "people" && entity && request.method === "DELETE") return removePerson(env, member, groupID, entity);
    if (section === "invitations" && entity && request.method === "DELETE") return revokeInvitation(env, member, groupID, entity);
    if (section === "recordings" && !entity && request.method === "GET") return listRecordings(env, member, groupID);
    if (section === "recordings" && !entity && request.method === "POST") {
      if (!await withinWriteLimit(request, env, "recording-upload", 20)) return json({ error: "Too many requests" }, { status: 429 });
      return uploadRecording(request, env, member, groupID, url);
    }
    if (section === "recordings" && entity && request.method === "DELETE") return deleteRecording(env, member, groupID, entity);
    if (section === "control" && !entity && request.method === "POST") return controlSession(env, member, groupID, await body());
    if (section === "presence" && !entity && request.method === "POST") return checkIn(env, member, groupID);
    if (section === "duas" && !entity && request.method === "GET") return duaRequests(env, member, groupID);
    if (section === "duas" && !entity && request.method === "POST") return requestDua(env, member, groupID, await body());
    if (section === "duas" && entity && action === "read" && request.method === "POST") return markDuaRead(env, member, groupID, entity);
    if (section === "history" && request.method === "GET") return sessionHistory(env, member, groupID, entity);
    return json({ error: "Not found" }, { status: 404 });
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
  if (!input || !isUUID(input.installationID) || !/^[0-9a-f]{64,200}$/i.test(input.apnsToken) || !["sandbox", "production"].includes(input.environment) || !Array.isArray(input.topics) || input.topics.some(topic => typeof topic !== "string")) return json({ error: "Invalid registration" }, { status: 400 });
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
  const input = await request.json<Record<string, unknown>>(); const installationID = cleanText(input?.installationID, 50);
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
    try {
      if (request.method === "POST" && Number(request.headers.get("content-length") ?? 0) > 256_000) return json({ error: "Payload too large" }, { status: 413 });
      const response = await route(request, env);
      // Public, read-only feeds are intentionally available to web companions.
      // Administrative and device routes never receive browser CORS permission.
      if (request.method === "GET" && ["/v1/live", "/v1/bootstrap", "/v1/feed"].includes(new URL(request.url).pathname)) response.headers.set("access-control-allow-origin", "*");
      return response;
    }
    catch (error) {
      if (error instanceof SyntaxError) return json({ error: "Invalid JSON" }, { status: 400 });
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
    const jobs: Array<{ name: string; run: Promise<void> }> = [
      { name: "youtube", run: refreshYouTube(env) },
      // Catches a listener that has gone silent, which no heartbeat reports.
      { name: "live-listeners", run: reconcileLive(env) },
      // Starts a group's zikr that plays a recording by itself at its time.
      { name: "group-autoplay", run: autoplayDue(env) },
      // Copies finished room recordings into our storage and the group's recordings.
      { name: "room-recordings", run: collectRoomRecordings(env) },
    ];
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
