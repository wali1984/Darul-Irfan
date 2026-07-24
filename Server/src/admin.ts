import type { Env } from "./contracts";
import { actorEmail, cleanText, json, validHTTPURL, validISODate } from "./util";
import { sendTopicPush } from "./apns";

export async function adminRequest(request: Request, env: Env, path: string): Promise<Response> {
  const actor = actorEmail(request);
  if (!actor) return json({ error: "Cloudflare Access authentication required" }, { status: 401 });
  if (request.method === "GET" && path === "/admin") return adminHTML(actor);
  if (request.method === "GET" && path === "/admin/api/state") {
    const [live, schedules, drafts] = await Promise.all([
      env.DB.prepare("SELECT * FROM live_broadcasts WHERE id='official-live'").first(),
      env.DB.prepare("SELECT * FROM zikr_schedules ORDER BY start_hour,start_minute").all(),
      env.DB.prepare("SELECT * FROM feed_items WHERE source='announcement' ORDER BY updated_at DESC LIMIT 50").all()
    ]);
    return json({ live, schedules: schedules.results, announcements: drafts.results });
  }
  if (request.method === "GET" && path.startsWith("/admin/api/preview/announcements/")) {
    const id = entityID(path); if (!id) return json({ error: "Invalid announcement ID" }, { status: 400 });
    const item = await env.DB.prepare("SELECT id,source,kind,title,body,source_url,image_url,published_at,is_featured,publication_status,expires_at FROM feed_items WHERE id=? AND source='announcement'").bind(id).first();
    return item ? json({ preview: item }) : json({ error: "Announcement not found" }, { status: 404 });
  }
  if (request.method !== "GET" && path !== "/admin/api/push" && !hasRole(actor, env.ADMIN_EDITOR_EMAILS)) {
    return json({ error: "Editor role required" }, { status: 403 });
  }
  if (request.method === "PUT" && path === "/admin/api/live") {
    const input = await request.json<Record<string, unknown>>();
    const state = ["offline", "scheduled", "live", "ended"].includes(String(input.state)) ? String(input.state) : null;
    const title = cleanText(input.title, 300); if (!state || !title) return json({ error: "Invalid state or title" }, { status: 400 });
    const scheduledStart = validISODate(input.scheduledStart);
    if (cleanText(input.scheduledStart) && !scheduledStart) return json({ error: "Scheduled start must be ISO 8601" }, { status: 400 });
    const before = await env.DB.prepare("SELECT * FROM live_broadcasts WHERE id='official-live'").first();
    const now = new Date().toISOString();
    const sourceMode = input.sourceMode === "manual" ? "manual" : "auto";
    await env.DB.prepare(`UPDATE live_broadcasts SET source_mode=?,state=?,title=?,details=?,scheduled_start=?,youtube_video_id=?,paltalk_url=?,owned_stream_url=?,updated_at=? WHERE id='official-live'`)
      .bind(sourceMode, state, title, cleanText(input.details) ?? null, scheduledStart ?? null, cleanText(input.youtubeVideoID, 40) ?? null,
        validHTTPURL(input.paltalkURL) ?? null, validHTTPURL(input.ownedStreamURL) ?? null, now).run();
    const after = await env.DB.prepare("SELECT * FROM live_broadcasts WHERE id='official-live'").first();
    await audit(env, actor, "update", "liveBroadcast", "official-live", before, after, now);
    return json({ ok: true, live: after });
  }
  if (request.method === "PUT" && path.startsWith("/admin/api/schedules/")) {
    const id = entityID(path); if (!id) return json({ error: "Invalid schedule ID" }, { status: 400 });
    const input = await request.json<Record<string, unknown>>(); const title = cleanText(input.title, 300);
    const weekdays = Array.isArray(input.weekdays) ? input.weekdays.map(Number).filter(value => value >= 1 && value <= 7) : [];
    const hour = Number(input.startHour); const minute = Number(input.startMinute); const duration = Number(input.durationMinutes);
    if (!title || !weekdays.length || hour < 0 || hour > 23 || minute < 0 || minute > 59 || duration < 1 || duration > 480) return json({ error: "Invalid schedule" }, { status: 400 });
    const before = await env.DB.prepare("SELECT * FROM zikr_schedules WHERE id=?").bind(id).first(); const now = new Date().toISOString();
    await env.DB.prepare(`INSERT INTO zikr_schedules(id,title,weekdays_json,start_hour,start_minute,duration_minutes,timezone,join_url,instructions,availability_note,is_active,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,weekdays_json=excluded.weekdays_json,start_hour=excluded.start_hour,start_minute=excluded.start_minute,duration_minutes=excluded.duration_minutes,timezone=excluded.timezone,join_url=excluded.join_url,instructions=excluded.instructions,availability_note=excluded.availability_note,is_active=excluded.is_active,updated_at=excluded.updated_at`)
      .bind(id, title, JSON.stringify([...new Set(weekdays)]), hour, minute, duration, "Asia/Karachi", validHTTPURL(input.joinURL) ?? null,
        cleanText(input.instructions) ?? null, cleanText(input.availabilityNote, 500) ?? null, input.isActive === false ? 0 : 1, now).run();
    const after = await env.DB.prepare("SELECT * FROM zikr_schedules WHERE id=?").bind(id).first();
    await audit(env, actor, before ? "update" : "create", "zikrSchedule", id, before, after, now);
    return json({ ok: true, schedule: after });
  }
  if (request.method === "PUT" && path.startsWith("/admin/api/announcements/")) {
    const id = entityID(path); if (!id) return json({ error: "Invalid announcement ID" }, { status: 400 });
    const input = await request.json<Record<string, unknown>>(); const title = cleanText(input.title, 300); const sourceURL = validHTTPURL(input.sourceURL);
    const status = input.publicationStatus === "published" ? "published" : "draft";
    if (!title || !sourceURL) return json({ error: "Title and official HTTPS source URL are required" }, { status: 400 });
    const publishedAt = validISODate(input.publishedAt) ?? new Date().toISOString();
    const expiresAt = validISODate(input.expiresAt);
    if (cleanText(input.publishedAt) && !validISODate(input.publishedAt)) return json({ error: "Published date must be ISO 8601" }, { status: 400 });
    if (cleanText(input.expiresAt) && !expiresAt) return json({ error: "Expiry must be ISO 8601" }, { status: 400 });
    const before = await env.DB.prepare("SELECT * FROM feed_items WHERE id=?").bind(id).first(); const now = new Date().toISOString();
    await env.DB.prepare(`INSERT INTO feed_items(id,source,kind,title,body,source_url,image_url,published_at,is_featured,is_hidden,publication_status,expires_at,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,body=excluded.body,source_url=excluded.source_url,image_url=excluded.image_url,is_featured=excluded.is_featured,publication_status=excluded.publication_status,expires_at=excluded.expires_at,updated_at=excluded.updated_at`)
      .bind(id, "announcement", "announcement", title, cleanText(input.body) ?? null, sourceURL, validHTTPURL(input.imageURL) ?? null,
        publishedAt, input.isFeatured === true ? 1 : 0, 0, status, expiresAt ?? null, now).run();
    const after = await env.DB.prepare("SELECT * FROM feed_items WHERE id=?").bind(id).first();
    await audit(env, actor, before ? "update" : "create", "announcement", id, before, after, now);
    return json({ ok: true, announcement: after });
  }
  if (request.method === "PATCH" && path.startsWith("/admin/api/feed/")) {
    const id = entityID(path); if (!id) return json({ error: "Invalid feed ID" }, { status: 400 });
    const input = await request.json<Record<string, unknown>>(); const before = await env.DB.prepare("SELECT * FROM feed_items WHERE id=?").bind(id).first();
    if (!before) return json({ error: "Feed item not found" }, { status: 404 }); const now = new Date().toISOString();
    await env.DB.prepare("UPDATE feed_items SET is_featured=?,is_hidden=?,updated_at=? WHERE id=?")
      .bind(input.isFeatured === true ? 1 : 0, input.isHidden === true ? 1 : 0, now, id).run();
    const after = await env.DB.prepare("SELECT * FROM feed_items WHERE id=?").bind(id).first();
    await audit(env, actor, "moderate", "feedItem", id, before, after, now);
    return json({ ok: true, item: after });
  }
  if (request.method === "POST" && path === "/admin/api/push") {
    if (!hasRole(actor, env.ADMIN_BROADCASTER_EMAILS)) return json({ error: "Broadcaster role required" }, { status: 403 });
    const input = await request.json<Record<string, unknown>>();
    if (input.confirm !== true) return json({ error: "Explicit confirmation is required" }, { status: 400 });
    const topic = String(input.topic); if (!["liveZikr", "broadcasts", "announcements", "events"].includes(topic)) return json({ error: "Invalid topic" }, { status: 400 });
    const eventID = cleanText(input.eventID, 150); const title = cleanText(input.title, 120); const body = cleanText(input.body, 500); const deepLink = cleanText(input.path, 300);
    if (!eventID || !title || !body || !deepLink?.startsWith("darulirfan://")) return json({ error: "Invalid push payload" }, { status: 400 });
    const accepted = await sendTopicPush(env, eventID, topic as "liveZikr" | "broadcasts" | "announcements" | "events", title, body, deepLink);
    await audit(env, actor, "send", "push", eventID, null, { topic, title, body, deepLink, accepted }, new Date().toISOString());
    return json({ ok: true, accepted });
  }
  return json({ error: "Not found" }, { status: 404 });
}

function hasRole(actor: string, configured: string | undefined): boolean {
  const allowed = (configured ?? "").split(",").map(value => value.trim().toLowerCase()).filter(Boolean);
  return allowed.includes(actor.trim().toLowerCase());
}

function entityID(path: string): string | null {
  const id = decodeURIComponent(path.split("/").at(-1) ?? "");
  return /^[a-zA-Z0-9:_-]{1,150}$/.test(id) ? id : null;
}

async function audit(env: Env, actor: string, action: string, type: string, id: string, before: unknown, after: unknown, now: string): Promise<void> {
  await env.DB.prepare("INSERT INTO audit_log(actor_email,action,entity_type,entity_id,before_json,after_json,created_at) VALUES(?,?,?,?,?,?,?)")
    .bind(actor, action, type, id, before ? JSON.stringify(before) : null, after ? JSON.stringify(after) : null, now).run();
}

function adminHTML(actor: string): Response {
  const escaped = actor.replace(/[&<>"']/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char] ?? char));
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Darul Irfan Admin</title>
  <style>body{font:16px system-ui;background:#f6f4ef;color:#1d1c1c;margin:0}.wrap{max-width:760px;margin:auto;padding:32px}form{background:#fffaf3;padding:24px;border:1px solid #e4d9c6;border-radius:20px;display:grid;gap:16px}label{display:grid;gap:6px;font-weight:600}input,select,textarea,button{font:inherit;padding:12px;border:1px solid #c8bfae;border-radius:10px}button{background:#0b6e4f;color:white;border:0;font-weight:700}small{color:#6b6357}</style></head>
  <body><main class="wrap"><h1>Darul Irfan Admin</h1><p>Signed in as ${escaped}</p><form id="live"><h2>Official live broadcast</h2>
  <label>Control<select name="sourceMode"><option value="auto">Automatic from YouTube</option><option value="manual">Manual override</option></select></label><label>Status<select name="state"><option>offline</option><option>scheduled</option><option>live</option><option>ended</option></select></label>
  <label>Title<input name="title" value="Live Zikr" required maxlength="300"></label><label>Details<textarea name="details" maxlength="2000"></textarea></label>
  <label>Scheduled start (ISO 8601)<input name="scheduledStart" placeholder="2026-07-23T21:15:00+05:00"></label><label>YouTube video ID<input name="youtubeVideoID"></label>
  <label>Paltalk URL<input type="url" name="paltalkURL" value="https://www.paltalk.com"></label><label>Owned HTTPS stream URL<input type="url" name="ownedStreamURL"></label>
  <button>Save live state</button><output id="result"></output></form>
  <form id="schedule"><h2>Zikr schedule</h2><label>ID<input name="id" value="daily-evening" required pattern="[A-Za-z0-9:_-]+"></label><label>Title<input name="title" value="Daily Online Zikr" required></label><label>Weekdays (1–7)<input name="weekdays" value="1,2,3,4,5,6,7"></label><label>Start hour PKT<input name="startHour" type="number" min="0" max="23" value="21"></label><label>Minute<input name="startMinute" type="number" min="0" max="59" value="15"></label><label>Duration<input name="durationMinutes" type="number" min="1" value="30"></label><label>Join URL<input name="joinURL" type="url" value="https://www.paltalk.com"></label><button>Save schedule</button><output></output></form>
  <form id="announcement"><h2>Announcement</h2><label>ID<input name="id" required placeholder="announcement-2026-07"></label><label>Title<input name="title" required></label><label>Body<textarea name="body"></textarea></label><label>Official source URL<input type="url" name="sourceURL" value="https://www.naqshbandiaowaisiah.org/" required></label><label>Expires at (ISO 8601, optional)<input name="expiresAt" placeholder="2026-08-01T00:00:00Z"></label><label>Status<select name="publicationStatus"><option>draft</option><option>published</option></select></label><label><input type="checkbox" name="isFeatured"> Pin on Today</label><button>Save announcement</button><button type="button" id="preview">Preview saved draft</button><output></output><pre id="preview-output"></pre></form>
  <small>All changes are audited. Push sending uses the confirmed JSON API and remains separate from editing.</small></main>
  <script>const submit=(selector,url,transform=x=>x)=>document.querySelector(selector).addEventListener('submit',async e=>{e.preventDefault();let data=transform(Object.fromEntries(new FormData(e.target)));const r=await fetch(url.replace(':id',encodeURIComponent(data.id||'')),{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify(data)});e.target.querySelector('output').textContent=r.ok?'Saved':await r.text()});submit('#live','/admin/api/live');submit('#schedule','/admin/api/schedules/:id',d=>({...d,weekdays:d.weekdays.split(',').map(Number),startHour:Number(d.startHour),startMinute:Number(d.startMinute),durationMinutes:Number(d.durationMinutes)}));submit('#announcement','/admin/api/announcements/:id',d=>({...d,isFeatured:d.isFeatured==='on'}));document.querySelector('#preview').addEventListener('click',async()=>{const id=document.querySelector('#announcement [name=id]').value;const r=await fetch('/admin/api/preview/announcements/'+encodeURIComponent(id));document.querySelector('#preview-output').textContent=JSON.stringify(await r.json(),null,2)});</script></body></html>`;
  return new Response(html, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "content-security-policy": "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; frame-ancestors 'none'", "x-frame-options": "DENY" } });
}
