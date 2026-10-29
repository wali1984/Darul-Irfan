import type { Env } from "./contracts";
import { cleanText, json, validHTTPURL, validISODate } from "./util";
import { authenticatedActor } from "./access";
import { sendTopicPush } from "./apns";
import { createInvite, publishGroupPost, setGroupMembership } from "./members";
import { notifyGroup, shareFeedItemToGroup } from "./community";
import { listenerHealth } from "./live";
import { OFFICIAL_LIVE_TITLE } from "./sources";

/** The Silsila's Paltalk room (migration 0012), where the Tahajjud zikr is joined. */
const ZIKR_ROOM_URL = "https://paltalk.im/egnMPD3Y";

export async function adminRequest(request: Request, env: Env, path: string): Promise<Response> {
  const actor = await authenticatedActor(request, env);
  if (!actor) return json({ error: "Cloudflare Access authentication required" }, { status: 401 });
  if (!isEditor(actor, env) && !isBroadcaster(actor, env)) {
    return json({ error: "Staff role required" }, { status: 403 });
  }
  if (request.method === "GET" && path === "/admin") return adminHTML(actor);
  if (request.method === "GET" && path === "/admin/api/state") {
    const [live, schedules, drafts] = await Promise.all([
      env.DB.prepare("SELECT * FROM live_broadcasts WHERE id='official-live'").first(),
      env.DB.prepare("SELECT * FROM zikr_schedules ORDER BY start_hour,start_minute").all(),
      env.DB.prepare("SELECT * FROM feed_items WHERE source='announcement' ORDER BY updated_at DESC LIMIT 50").all()
    ]);
    return json({ live, schedules: schedules.results, announcements: drafts.results });
  }
  // The pipeline's state in full - each job's last error and the listeners -
  // which the public /health no longer shows.
  if (request.method === "GET" && path === "/admin/api/health") {
    const health = await env.DB.prepare("SELECT * FROM source_health ORDER BY source").all();
    const degraded = health.results.some(row => row.status === "degraded");
    return json({ ok: !degraded, environment: env.ENVIRONMENT, sources: health.results, listeners: await listenerHealth(env) });
  }
  if (request.method === "GET" && path.startsWith("/admin/api/preview/announcements/")) {
    const id = entityID(path); if (!id) return json({ error: "Invalid announcement ID" }, { status: 400 });
    const item = await env.DB.prepare("SELECT id,source,kind,title,body,source_url,image_url,published_at,is_featured,publication_status,expires_at FROM feed_items WHERE id=? AND source='announcement'").bind(id).first();
    return item ? json({ preview: item }) : json({ error: "Announcement not found" }, { status: 404 });
  }
  if (request.method === "GET" && path === "/admin/api/groups") {
    const [groups, members] = await Promise.all([
      env.DB.prepare("SELECT id,name,description,meeting_url,meeting_note,is_active FROM member_groups ORDER BY name").all(),
      env.DB.prepare(`SELECT g.group_id,g.member_id,g.added_at,m.display_name,m.email
        FROM member_group_members g JOIN members m ON m.id=g.member_id ORDER BY g.group_id,g.added_at`).all(),
    ]);
    return json({ groups: groups.results, memberships: members.results });
  }
  // Members who have signed in but belong to no group yet: the queue an admin
  // works through, since signing in grants nothing on its own.
  if (request.method === "GET" && path === "/admin/api/groups/pending") {
    const pending = await env.DB.prepare(`SELECT id,display_name,email,created_at FROM members
      WHERE id NOT IN (SELECT member_id FROM member_group_members) ORDER BY created_at DESC LIMIT 200`).all();
    return json({ pending: pending.results });
  }
  if (request.method !== "GET" && path !== "/admin/api/push" && !hasRole(actor, env.ADMIN_EDITOR_EMAILS)) {
    return json({ error: "Editor role required" }, { status: 403 });
  }
  if (request.method === "PUT" && path === "/admin/api/live") {
    const input = await request.json<Record<string, unknown>>();
    const before = await env.DB.prepare("SELECT * FROM live_broadcasts WHERE id='official-live'").first<Record<string, unknown>>();
    if (!before) return json({ error: "The live broadcast is missing" }, { status: 404 });
    // Only what is sent changes: a field left out keeps its value, so saving
    // the status can never reset the Paltalk room's link or the title.
    const given = (key: string) => Object.prototype.hasOwnProperty.call(input, key);
    const state = ["offline", "scheduled", "live", "ended"].includes(String(input.state)) ? String(input.state) : null;
    const title = given("title") ? cleanText(input.title, 300) : String(before.title);
    if (!state || !title) return json({ error: "Invalid state or title" }, { status: 400 });
    const scheduledStart = validISODate(input.scheduledStart);
    if (cleanText(input.scheduledStart) && !scheduledStart) return json({ error: "Scheduled start must be ISO 8601" }, { status: 400 });
    // A link that is not https is refused rather than quietly dropped.
    for (const key of ["paltalkURL", "ownedStreamURL"]) {
      if (cleanText(input[key]) && !validHTTPURL(input[key])) return json({ error: `${key} must be an https:// link` }, { status: 400 });
    }
    const now = new Date().toISOString();
    const sourceMode = given("sourceMode") ? (input.sourceMode === "manual" ? "manual" : "auto") : before.source_mode;
    await env.DB.prepare(`UPDATE live_broadcasts SET source_mode=?,state=?,title=?,details=?,scheduled_start=?,youtube_video_id=?,paltalk_url=?,owned_stream_url=?,updated_at=? WHERE id='official-live'`)
      .bind(sourceMode, state, title,
        given("details") ? cleanText(input.details) ?? null : before.details ?? null,
        given("scheduledStart") ? scheduledStart ?? null : before.scheduled_start ?? null,
        given("youtubeVideoID") ? cleanText(input.youtubeVideoID, 40) ?? null : before.youtube_video_id ?? null,
        given("paltalkURL") ? validHTTPURL(input.paltalkURL) ?? null : before.paltalk_url ?? null,
        given("ownedStreamURL") ? validHTTPURL(input.ownedStreamURL) ?? null : before.owned_stream_url ?? null,
        now).run();
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
  // /admin/api/groups/{group}                       -> meeting link and state
  // /admin/api/groups/{group}/posts/{post}           -> publish or edit a post
  // /admin/api/groups/{group}/members/{member}       -> grant or revoke access
  const groupRoute = /^\/admin\/api\/groups\/([a-z0-9-]{1,40})(?:\/(posts|members)\/([A-Za-z0-9:_-]{1,150}))?$/.exec(path);
  if (request.method === "PUT" && groupRoute) {
    const groupID = groupRoute[1] as string;
    const kind = groupRoute[2];
    const entity = groupRoute[3];
    const input = await request.json<Record<string, unknown>>();
    const now = new Date().toISOString();
    if (!kind) {
      const before = await env.DB.prepare("SELECT * FROM member_groups WHERE id=?").bind(groupID).first();
      if (!before) return json({ error: "Unknown group" }, { status: 404 });
      await env.DB.prepare("UPDATE member_groups SET meeting_url=?,meeting_note=?,is_active=?,updated_at=? WHERE id=?")
        .bind(validHTTPURL(input.meetingURL) ?? null, cleanText(input.meetingNote, 500) ?? null,
          input.isActive === false ? 0 : 1, now, groupID).run();
      const after = await env.DB.prepare("SELECT * FROM member_groups WHERE id=?").bind(groupID).first();
      await audit(env, actor, "update", "member_group", groupID, before, after, now);
      return json({ ok: true, group: after });
    }
    if (kind === "posts" && entity) {
      const response = await publishGroupPost(env, actor, groupID, entity, input);
      if (response.ok) await audit(env, actor, "publish", "member_group_post", `${groupID}:${entity}`, null, input, now);
      return response;
    }
    if (kind === "members" && entity) {
      const response = await setGroupMembership(env, actor, groupID, entity, input.member !== false);
      if (response.ok) await audit(env, actor, "membership", "member_group_member", `${groupID}:${entity}`, null, { member: input.member !== false }, now);
      return response;
    }
  }
  // WhatsApp numbers whose forwards go to a group by default.
  const senderRoute = /^\/admin\/api\/whatsapp\/senders\/([0-9]{6,20})$/.exec(path);
  if (senderRoute && request.method === "PUT") {
    const input = await request.json<Record<string, unknown>>();
    const groupID = typeof input.groupID === "string" ? input.groupID : "";
    const group = await env.DB.prepare("SELECT 1 AS ok FROM member_groups WHERE id=?").bind(groupID).first();
    if (!group) return json({ error: "Unknown group" }, { status: 404 });
    const now = new Date().toISOString();
    await env.DB.prepare(`INSERT INTO whatsapp_sender_groups(sender,group_id,label,updated_at,updated_by) VALUES(?,?,?,?,?)
      ON CONFLICT(sender) DO UPDATE SET group_id=excluded.group_id,label=excluded.label,updated_at=excluded.updated_at,updated_by=excluded.updated_by`)
      .bind(senderRoute[1], groupID, cleanText(input.label, 120) ?? null, now, actor).run();
    await audit(env, actor, "route", "whatsapp_sender", senderRoute[1] as string, null, { groupID }, now);
    return json({ ok: true, sender: senderRoute[1], groupID });
  }
  if (senderRoute && request.method === "DELETE") {
    await env.DB.prepare("DELETE FROM whatsapp_sender_groups WHERE sender=?").bind(senderRoute[1]).run();
    return new Response(null, { status: 204 });
  }
  if (request.method === "GET" && path === "/admin/api/whatsapp/senders") {
    const rows = await env.DB.prepare("SELECT sender,group_id,label,updated_at FROM whatsapp_sender_groups ORDER BY group_id,sender").all();
    return json({ senders: rows.results });
  }
  // A member's role in every Halqah they are in: member, Admin or
  // Administrator. One Halqah at a time is set from the app; Super admin is
  // the SUPER_ADMIN_EMAILS list alone.
  const roleRoute = /^\/admin\/api\/members\/([0-9a-f]{32})\/role$/.exec(path);
  if (roleRoute && request.method === "PUT") {
    const input = await request.json<Record<string, unknown>>();
    const role = input.role === "admin" || input.role === "administrator" ? input.role : "member";
    if (role === "administrator" && !hasRole(actor, env.SUPER_ADMIN_EMAILS)) {
      return json({ error: "Only a Super admin can make Administrators here" }, { status: 403 });
    }
    const result = await env.DB.prepare("UPDATE members SET role='member' WHERE id=?").bind(roleRoute[1]).run();
    if ((result.meta?.changes ?? 0) === 0) return json({ error: "Unknown member" }, { status: 404 });
    await env.DB.prepare("UPDATE member_group_members SET role=? WHERE member_id=?").bind(role, roleRoute[1]).run();
    await audit(env, actor, "role", "member", roleRoute[1] as string, null, { role }, new Date().toISOString());
    return json({ ok: true, memberID: roleRoute[1], role });
  }
  // A public feed item (post, video) sent into a group as a draft.
  const shareRoute = /^\/admin\/api\/groups\/([a-z0-9-]{1,40})\/share\/([A-Za-z0-9:_.-]{1,200})$/.exec(path);
  if (shareRoute && request.method === "POST") {
    const response = await shareFeedItemToGroup(env, shareRoute[1] as string, decodeURIComponent(shareRoute[2] as string));
    if (response.ok) await audit(env, actor, "share", "member_group_post", `${shareRoute[1]}:${shareRoute[2]}`, null, null, new Date().toISOString());
    return response;
  }
  // Drafts waiting in a group (forwarded from WhatsApp, or shared from the feed).
  const draftsRoute = /^\/admin\/api\/groups\/([a-z0-9-]{1,40})\/drafts$/.exec(path);
  if (draftsRoute && request.method === "GET") {
    const rows = await env.DB.prepare(`SELECT id,title,body,source,published_at FROM member_group_posts
      WHERE group_id=? AND status='draft' AND is_hidden=0 ORDER BY published_at DESC LIMIT 100`).bind(draftsRoute[1]).all();
    return json({ drafts: rows.results });
  }
  const approveRoute = /^\/admin\/api\/groups\/([a-z0-9-]{1,40})\/drafts\/([A-Za-z0-9:_-]{1,80})\/publish$/.exec(path);
  if (approveRoute && request.method === "POST") {
    const now = new Date().toISOString();
    const draft = await env.DB.prepare("SELECT title,body FROM member_group_posts WHERE group_id=? AND id=? AND status='draft'")
      .bind(approveRoute[1], approveRoute[2]).first<{ title: string; body: string | null }>();
    if (!draft) return json({ error: "Unknown draft" }, { status: 404 });
    await env.DB.prepare("UPDATE member_group_posts SET status='published',published_at=?,updated_at=? WHERE group_id=? AND id=?")
      .bind(now, now, approveRoute[1], approveRoute[2]).run();
    await audit(env, actor, "publish", "member_group_post", `${approveRoute[1]}:${approveRoute[2]}`, null, null, now);
    await notifyGroup(env, approveRoute[1] as string, `post:${approveRoute[2]}`, draft.title, (draft.body ?? "").slice(0, 140),
      `darulirfan://groups/${approveRoute[1]}`);
    return json({ ok: true });
  }
  // /admin/api/groups/{group}/invites -> mint a single-use code
  const inviteRoute = /^\/admin\/api\/groups\/([a-z0-9-]{1,40})\/invites$/.exec(path);
  if (request.method === "POST" && inviteRoute) {
    const groupID = inviteRoute[1] as string;
    const input = await request.json<Record<string, unknown>>();
    const response = await createInvite(env, actor, groupID, input);
    if (response.ok) {
      // The code never enters the audit log; only that one was issued.
      await audit(env, actor, "invite", "member_group_invite", groupID, null,
        { label: cleanText(input.label, 120) ?? null }, new Date().toISOString());
    }
    return response;
  }
  if (request.method === "POST" && path === "/admin/api/push") {
    if (!isBroadcaster(actor, env)) return json({ error: "Broadcaster role required" }, { status: 403 });
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

/** The super admin holds every staff role. */
function isEditor(actor: string, env: Env): boolean {
  return hasRole(actor, env.ADMIN_EDITOR_EMAILS) || hasRole(actor, env.SUPER_ADMIN_EMAILS);
}

function isBroadcaster(actor: string, env: Env): boolean {
  return hasRole(actor, env.ADMIN_BROADCASTER_EMAILS) || hasRole(actor, env.SUPER_ADMIN_EMAILS);
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
  // The live form is filled from the stored broadcast when the page opens,
  // so saving it sends back what is there now rather than the defaults.
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Darul Irfan Admin</title>
  <style>body{font:16px system-ui;background:#f6f4ef;color:#1d1c1c;margin:0}.wrap{max-width:760px;margin:auto;padding:32px}form{background:#fffaf3;padding:24px;border:1px solid #e4d9c6;border-radius:20px;display:grid;gap:16px}label{display:grid;gap:6px;font-weight:600}input,select,textarea,button{font:inherit;padding:12px;border:1px solid #c8bfae;border-radius:10px}button{background:#0b6e4f;color:white;border:0;font-weight:700}small{color:#6b6357}</style></head>
  <body><main class="wrap"><h1>Darul Irfan Admin</h1><p>Signed in as ${escaped}</p><form id="live"><h2>Official live broadcast</h2>
  <label>Control<select name="sourceMode"><option value="auto">Automatic from YouTube</option><option value="manual">Manual override</option></select></label><label>Status<select name="state"><option>offline</option><option>scheduled</option><option>live</option><option>ended</option></select></label>
  <label>Title<input name="title" value="${OFFICIAL_LIVE_TITLE}" required maxlength="300"></label><label>Details<textarea name="details" maxlength="2000"></textarea></label>
  <label>Scheduled start (ISO 8601)<input name="scheduledStart" placeholder="2026-07-23T21:15:00+05:00"></label><label>YouTube video ID<input name="youtubeVideoID"></label>
  <label>Paltalk URL<input type="url" name="paltalkURL" value="${ZIKR_ROOM_URL}"></label><label>Owned HTTPS stream URL<input type="url" name="ownedStreamURL"></label>
  <button>Save live state</button><output id="result"></output></form>
  <form id="schedule"><h2>Zikr schedule</h2><label>ID<input name="id" value="daily-evening" required pattern="[A-Za-z0-9:_-]+"></label><label>Title<input name="title" value="Daily Online Zikr" required></label><label>Weekdays (1–7)<input name="weekdays" value="1,2,3,4,5,6,7"></label><label>Start hour PKT<input name="startHour" type="number" min="0" max="23" value="21"></label><label>Minute<input name="startMinute" type="number" min="0" max="59" value="15"></label><label>Duration<input name="durationMinutes" type="number" min="1" value="30"></label><label>Join URL<input name="joinURL" type="url" value="https://www.paltalk.com"></label><button>Save schedule</button><output></output></form>
  <form id="announcement"><h2>Announcement</h2><label>ID<input name="id" required placeholder="announcement-2026-07"></label><label>Title<input name="title" required></label><label>Body<textarea name="body"></textarea></label><label>Official source URL<input type="url" name="sourceURL" value="https://www.naqshbandiaowaisiah.org/" required></label><label>Expires at (ISO 8601, optional)<input name="expiresAt" placeholder="2026-08-01T00:00:00Z"></label><label>Status<select name="publicationStatus"><option>draft</option><option>published</option></select></label><label><input type="checkbox" name="isFeatured"> Pin on Today</label><button>Save announcement</button><button type="button" id="preview">Preview saved draft</button><output></output><pre id="preview-output"></pre></form>
  <form id="invite"><h2>Private groups: invitation code</h2><small>A code admits one person to one group, once, and expires. It is shown here once and stored only as a hash, so copy it before leaving the page.</small><label>Group<select name="group"><option value="darul-irfan">Darul Irfan</option><option value="usa">United States</option><option value="canada">Canada</option></select></label><label>Note for your records (optional)<input name="label" maxlength="120" placeholder="Br. Imran, Houston"></label><label>Expires after (days)<input name="expiresInDays" type="number" min="1" max="90" value="30"></label><label>Role<select name="grantsRole"><option value="">Member</option><option value="admin">Group admin (posts, approves, runs zikr and meetings)</option><option value="administrator">Administrator (the Halqah's senior role)</option></select></label><button>Create code</button><output id="invite-code" style="font:700 28px ui-monospace,monospace;letter-spacing:2px"></output></form>
  <form id="sender"><h2>WhatsApp forwarding: sender to group</h2><small>Messages this number forwards to the WhatsApp Business number arrive as drafts in this group. A #usa, #canada or #darulirfan tag at the start of a message overrides it.</small><label>WhatsApp number (with country code)<input name="sender" required placeholder="923001234567"></label><label>Group<select name="group"><option value="darul-irfan">Darul Irfan</option><option value="usa">United States</option><option value="canada">Canada</option></select></label><label>Note<input name="label" maxlength="120"></label><button>Save routing</button><output></output></form>
  <form id="group"><h2>Private groups: meeting link</h2><label>Group<select name="group"><option value="darul-irfan">Darul Irfan</option><option value="usa">United States</option><option value="canada">Canada</option></select></label><label>Meeting URL<input name="meetingURL" type="url" placeholder="https://www.paltalk.com"></label><label>Meeting note<input name="meetingNote" maxlength="500" placeholder="Fridays after Isha, local time"></label><label><input type="checkbox" name="isActive" checked> Group active</label><button>Save group</button><output></output></form>
  <form id="grouppost"><h2>Private groups: post</h2><label>Group<select name="group"><option value="darul-irfan">Darul Irfan</option><option value="usa">United States</option><option value="canada">Canada</option></select></label><label>Post ID<input name="id" required pattern="[A-Za-z0-9:_-]+" placeholder="zikr-2026-10-31"></label><label>Kind<select name="kind"><option value="announcement">Announcement</option><option value="zikr">Recorded zikr (YouTube)</option></select></label><label>Title<input name="title" required maxlength="300"></label><label>Body<textarea name="body" maxlength="8000"></textarea></label><label>YouTube video ID (recorded zikr)<input name="youtubeVideoID" pattern="[A-Za-z0-9_-]{11}"></label><label>Link URL (optional)<input name="linkURL" type="url"></label><button>Publish post</button><output></output></form>
  <small>All changes are audited. Push sending uses the confirmed JSON API and remains separate from editing.</small></main>
  <script>const submit=(selector,url,transform=x=>x)=>document.querySelector(selector).addEventListener('submit',async e=>{e.preventDefault();let data=transform(Object.fromEntries(new FormData(e.target)));const r=await fetch(url.replace(':id',encodeURIComponent(data.id||'')),{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify(data)});e.target.querySelector('output').textContent=r.ok?'Saved':await r.text()});submit('#live','/admin/api/live');submit('#schedule','/admin/api/schedules/:id',d=>({...d,weekdays:d.weekdays.split(',').map(Number),startHour:Number(d.startHour),startMinute:Number(d.startMinute),durationMinutes:Number(d.durationMinutes)}));submit('#announcement','/admin/api/announcements/:id',d=>({...d,isFeatured:d.isFeatured==='on'}));const groupCall=(selector,method,url,transform)=>document.querySelector(selector).addEventListener('submit',async e=>{e.preventDefault();const data=Object.fromEntries(new FormData(e.target));const r=await fetch(url(data),{method,headers:{'content-type':'application/json'},body:JSON.stringify(transform(data))});const out=e.target.querySelector('output');if(!r.ok){out.textContent=await r.text();return}const body=await r.json();out.textContent=body.code??'Saved'});groupCall('#invite','POST',d=>'/admin/api/groups/'+encodeURIComponent(d.group)+'/invites',d=>({label:d.label||undefined,expiresInDays:Number(d.expiresInDays),grantsRole:d.grantsRole||undefined}));groupCall('#sender','PUT',d=>'/admin/api/whatsapp/senders/'+encodeURIComponent(d.sender.replace(/[^0-9]/g,'')),d=>({groupID:d.group,label:d.label||undefined}));groupCall('#group','PUT',d=>'/admin/api/groups/'+encodeURIComponent(d.group),d=>({meetingURL:d.meetingURL||null,meetingNote:d.meetingNote||null,isActive:d.isActive==='on'}));groupCall('#grouppost','PUT',d=>'/admin/api/groups/'+encodeURIComponent(d.group)+'/posts/'+encodeURIComponent(d.id),d=>({kind:d.kind,title:d.title,body:d.body||undefined,youtubeVideoID:d.youtubeVideoID||undefined,linkURL:d.linkURL||undefined}));document.querySelector('#preview').addEventListener('click',async()=>{const id=document.querySelector('#announcement [name=id]').value;const r=await fetch('/admin/api/preview/announcements/'+encodeURIComponent(id));document.querySelector('#preview-output').textContent=JSON.stringify(await r.json(),null,2)});fetch('/admin/api/state').then(r=>r.ok?r.json():null).then(s=>{const l=s&&s.live;if(!l)return;const f=document.querySelector('#live');const set=(n,v)=>{const e=f.querySelector('[name='+n+']');if(e&&v!=null)e.value=v};set('sourceMode',l.source_mode);set('state',l.state);set('title',l.title);set('details',l.details);set('scheduledStart',l.scheduled_start);set('youtubeVideoID',l.youtube_video_id);set('paltalkURL',l.paltalk_url);set('ownedStreamURL',l.owned_stream_url)}).catch(()=>{});</script></body></html>`;
  return new Response(html, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "content-security-policy": "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; frame-ancestors 'none'", "x-frame-options": "DENY" } });
}
