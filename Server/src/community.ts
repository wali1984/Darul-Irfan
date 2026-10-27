import type { Env } from "./contracts";
import { cleanText, json, validHTTPURL, validISODate } from "./util";
import { sendPushToInstallations } from "./apns";
import { signedMediaURL } from "./media";
import { youtubeVideos } from "./recordings";
import { beginSession, endSession, liveRow, queueOf, resolveQueue, sessionPayload, unreadDuaCount } from "./session";
import { recordingConfig, trackRoom } from "./roomRecordings";

// Community groups: what members see and do inside their group, and what the
// group's admins can run from the app itself.
//
// Roles
//   member      reads its own groups, watches and joins their sessions
//   admin       also publishes, approves drafts, runs zikr and meetings, and
//               adds and removes people, in the groups it is admin of (the
//               role belongs to the place in a group, not to the person)
//   superadmin  does all of that in every group
//
// The isolation rule from the first version still holds for members and
// admins: a group they are not in answers 404, exactly like a group that does
// not exist. Only the super admin sees across groups.

export type Role = "member" | "admin" | "superadmin";

const notFound = () => json({ error: "Not found" }, { status: 404 });
const forbidden = () => json({ error: "Group admin role required" }, { status: 403 });

/** The member's highest role: super admin, admin of at least one group, or
 *  member. What they may do in a particular group is `canManage`. */
export async function memberRole(env: Env, memberID: string): Promise<Role> {
  const row = await env.DB.prepare("SELECT role,email FROM members WHERE id=?").bind(memberID)
    .first<{ role: string; email: string | null }>();
  if (isSuperAdmin(env, row)) return "superadmin";
  const admin = await env.DB.prepare("SELECT 1 AS ok FROM member_group_members WHERE member_id=? AND role='admin' LIMIT 1")
    .bind(memberID).first();
  return admin ? "admin" : "member";
}

/** The email comes only from a verified Apple identity token, never from input. */
export function isSuperAdmin(env: Env, row: { role?: unknown; email?: unknown } | null | undefined): boolean {
  if (row?.role === "superadmin") return true;
  return typeof row?.email === "string" && superAdminEmails(env).includes(row.email.trim().toLowerCase());
}

function superAdminEmails(env: Env): string[] {
  return (env.SUPER_ADMIN_EMAILS ?? "").split(",").map(value => value.trim().toLowerCase()).filter(Boolean);
}

export async function groupExists(env: Env, groupID: string): Promise<boolean> {
  return !!await env.DB.prepare("SELECT 1 AS ok FROM member_groups WHERE id=? AND is_active=1").bind(groupID).first();
}

async function isMember(env: Env, memberID: string, groupID: string): Promise<boolean> {
  return !!await env.DB.prepare("SELECT 1 AS ok FROM member_group_members WHERE group_id=? AND member_id=?")
    .bind(groupID, memberID).first();
}

/** Whether the caller may see this group at all. */
export async function canSee(env: Env, memberID: string, role: Role, groupID: string): Promise<boolean> {
  if (role === "superadmin") return groupExists(env, groupID);
  return isMember(env, memberID, groupID);
}

/** Whether the caller may publish, run sessions and manage people in this group. */
export async function canManage(env: Env, memberID: string, role: Role, groupID: string): Promise<boolean> {
  if (role === "superadmin") return groupExists(env, groupID);
  return !!await env.DB.prepare("SELECT 1 AS ok FROM member_group_members WHERE group_id=? AND member_id=? AND role='admin'")
    .bind(groupID, memberID).first();
}

const newID = (prefix: string) => `${prefix}-${crypto.randomUUID().slice(0, 12)}`;

// MARK: - Reading

export async function me(env: Env, memberID: string): Promise<Response> {
  const row = await env.DB.prepare("SELECT id,role,display_name FROM members WHERE id=?").bind(memberID)
    .first<{ id: string; role: string; display_name: string | null }>();
  if (!row) return notFound();
  return json({ memberID: row.id, role: await memberRole(env, memberID), displayName: row.display_name ?? undefined });
}

/** The caller's groups - every group for the super admin - each with whether
 *  they manage it and whether something is live in it now. */
export async function communityGroups(env: Env, memberID: string): Promise<Response> {
  const role = await memberRole(env, memberID);
  const sql = role === "superadmin"
    ? `SELECT g.id,g.name,g.description,g.meeting_url,g.meeting_note,l.state AS live_state,l.kind AS live_kind
       FROM member_groups g LEFT JOIN group_live l ON l.group_id=g.id WHERE g.is_active=1 ORDER BY g.name`
    : `SELECT g.id,g.name,g.description,g.meeting_url,g.meeting_note,l.state AS live_state,l.kind AS live_kind
       FROM member_groups g JOIN member_group_members m ON m.group_id=g.id
       LEFT JOIN group_live l ON l.group_id=g.id
       WHERE m.member_id=? AND g.is_active=1 ORDER BY g.name`;
  const statement = env.DB.prepare(sql);
  const result = await (role === "superadmin" ? statement : statement.bind(memberID)).all();
  const groups = [];
  for (const row of result.results ?? []) {
    groups.push({
      id: row.id, name: row.name, description: row.description ?? undefined,
      meetingURL: row.meeting_url ?? undefined, meetingNote: row.meeting_note ?? undefined,
      isLive: row.live_state === "live", liveKind: row.live_state === "live" ? row.live_kind : undefined,
      canManage: await canManage(env, memberID, role, String(row.id)),
    });
  }
  return json({ role, groups });
}

/** Everything about one group a member needs: its live session, its zikr
 *  times and its upcoming meetings. */
export async function groupDetail(env: Env, memberID: string, groupID: string): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  const [group, live, zikr, meetings] = await Promise.all([
    env.DB.prepare("SELECT id,name,description FROM member_groups WHERE id=?").bind(groupID).first(),
    liveRow(env, groupID),
    env.DB.prepare(`SELECT id,title,weekdays_json,start_hour,start_minute,time_zone,anchor,duration_minutes,autoplay_json
      FROM group_zikr_sessions WHERE group_id=? AND is_active=1 ORDER BY start_hour,start_minute`).bind(groupID).all(),
    env.DB.prepare(`SELECT id,title,starts_at,duration_minutes FROM group_meetings
      WHERE group_id=? AND is_cancelled=0 AND starts_at >= ? ORDER BY starts_at LIMIT 20`)
      .bind(groupID, new Date(Date.now() - 6 * 3_600_000).toISOString()).all(),
  ]);
  const isLive = live?.state === "live";
  const managing = await canManage(env, memberID, role, groupID);
  return json({
    group: { id: group?.id, name: group?.name, description: group?.description ?? undefined },
    canManage: managing,
    live: isLive && live ? {
      kind: live?.kind, title: live?.title ?? undefined,
      // The video plays in the app; the room is joined through /join.
      videoID: live?.video_id ?? undefined, hasRoom: !!live?.room_id, startedAt: live?.started_at ?? undefined,
      // Recordings and past videos played to the group, the shared playback
      // clock, the admin's notice and who is listening.
      ...await sessionPayload(env, groupID, live, managing),
    } : undefined,
    unreadDuaRequests: managing ? await unreadDuaCount(env, groupID) : undefined,
    zikrSessions: (zikr.results ?? []).map(row => ({
      id: row.id, title: row.title, weekdays: JSON.parse(String(row.weekdays_json)),
      startHour: row.start_hour, startMinute: row.start_minute, timeZoneIdentifier: row.time_zone,
      anchor: row.anchor ?? undefined, durationMinutes: row.duration_minutes,
      // What this time plays by itself when no admin starts a session.
      autoplayTitle: queueOf({ queue_json: String(row.autoplay_json ?? "[]") }).map(item => item.title).join(" · ") || undefined,
    })),
    meetings: (meetings.results ?? []).map(row => ({
      id: row.id, title: row.title, startsAt: row.starts_at, durationMinutes: row.duration_minutes,
    })),
    integrations: integrationStatus(env),
  });
}

/** Posts in a group. Managers may also ask for drafts, which members never see. */
export async function communityPosts(env: Env, memberID: string, groupID: string, limit: number, drafts: boolean): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  const managing = drafts && await canManage(env, memberID, role, groupID);
  const status = managing ? "draft" : "published";
  const result = await env.DB.prepare(`SELECT id,kind,title,body,youtube_video_id,link_url,published_at,status,source,image_key
    FROM member_group_posts WHERE group_id=? AND is_hidden=0 AND status=?
    ORDER BY published_at DESC, id DESC LIMIT ?`).bind(groupID, status, limit).all();
  const posts = [];
  for (const row of result.results ?? []) {
    posts.push({
      id: row.id, kind: row.kind, title: row.title, body: row.body ?? undefined,
      youtubeVideoID: row.youtube_video_id ?? undefined, linkURL: row.link_url ?? undefined,
      // A day-long link: long enough to read, short enough that a copied
      // link does not leave the group for good.
      imageURL: row.image_key ? await signedMediaURL(env, String(row.image_key)) : undefined,
      publishedAt: row.published_at, isDraft: row.status === "draft", source: row.source,
    });
  }
  return json({ groupID, posts });
}

// MARK: - Publishing (group admins)

/** A new post from the app. Published straight away unless saved as a draft. */
export async function createPost(env: Env, memberID: string, groupID: string, input: Record<string, unknown>): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  if (!await canManage(env, memberID, role, groupID)) return forbidden();
  const kind = input.kind === "zikr" ? "zikr" : "announcement";
  const title = cleanText(input.title, 300);
  if (!title) return json({ error: "A title is required" }, { status: 400 });
  const video = typeof input.youtubeVideoID === "string" && /^[\w-]{11}$/.test(input.youtubeVideoID) ? input.youtubeVideoID : null;
  if (kind === "zikr" && !video) return json({ error: "A recorded zikr needs a video" }, { status: 400 });
  const publish = input.publish !== false;
  const id = newID("post");
  const now = new Date().toISOString();
  await env.DB.prepare(`INSERT INTO member_group_posts(id,group_id,kind,title,body,youtube_video_id,link_url,published_at,author_email,is_hidden,updated_at,status,source)
    VALUES(?,?,?,?,?,?,?,?,?,0,?,?,'admin')`)
    .bind(id, groupID, kind, title, cleanText(input.body, 8_000) ?? null, video, validHTTPURL(input.linkURL) ?? null,
      now, `member:${memberID}`, now, publish ? "published" : "draft").run();
  if (publish) await notifyGroup(env, groupID, `post:${id}`, title, cleanText(input.body, 140) ?? "", `darulirfan://groups/${groupID}`);
  return json({ ok: true, id, published: publish }, { status: 201 });
}

/** Approves a draft (forwarded from WhatsApp, or saved for later). */
export async function publishDraft(env: Env, memberID: string, groupID: string, postID: string, input: Record<string, unknown>): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  if (!await canManage(env, memberID, role, groupID)) return forbidden();
  const draft = await env.DB.prepare("SELECT title,body FROM member_group_posts WHERE id=? AND group_id=? AND status='draft' AND is_hidden=0")
    .bind(postID, groupID).first<{ title: string; body: string | null }>();
  if (!draft) return notFound();
  // An admin may tidy the forwarded text before it goes out.
  const title = cleanText(input.title, 300) ?? draft.title;
  const body = input.body === undefined ? draft.body : cleanText(input.body, 8_000) ?? null;
  const now = new Date().toISOString();
  await env.DB.prepare(`UPDATE member_group_posts SET status='published',title=?,body=?,published_at=?,updated_at=?
    WHERE id=? AND group_id=?`).bind(title, body, now, now, postID, groupID).run();
  await notifyGroup(env, groupID, `post:${postID}`, title, (body ?? "").slice(0, 140), `darulirfan://groups/${groupID}`);
  return json({ ok: true, id: postID, published: true });
}

export async function hidePost(env: Env, memberID: string, groupID: string, postID: string): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  if (!await canManage(env, memberID, role, groupID)) return forbidden();
  await env.DB.prepare("UPDATE member_group_posts SET is_hidden=1,updated_at=? WHERE id=? AND group_id=?")
    .bind(new Date().toISOString(), postID, groupID).run();
  return new Response(null, { status: 204 });
}

// MARK: - Group zikr

export async function saveZikrSession(env: Env, memberID: string, groupID: string, sessionID: string, input: Record<string, unknown>): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  if (!await canManage(env, memberID, role, groupID)) return forbidden();
  const title = cleanText(input.title, 120);
  const hour = Number(input.startHour), minute = Number(input.startMinute);
  const zone = typeof input.timeZoneIdentifier === "string" ? input.timeZoneIdentifier : "";
  const weekdays = Array.isArray(input.weekdays) ? input.weekdays.map(Number).filter(d => Number.isInteger(d) && d >= 1 && d <= 7) : [1, 2, 3, 4, 5, 6, 7];
  // "beforeFajr" is the Tahajjud zikr; it is stored under the column's
  // original name, which the app reads the same way.
  const anchor = input.anchor === "afterIsha" ? "afterIsha"
    : input.anchor === "beforeFajr" || input.anchor === "tahajjud" ? "tahajjud" : null;
  const duration = Number(input.durationMinutes ?? 30);
  // Played by itself at a clock time; a prayer-anchored time moves each day.
  let autoplay: string | null = null;
  if (Array.isArray(input.autoplay) && input.autoplay.length && !anchor) {
    const queue = await resolveQueue(env, groupID, input.autoplay);
    if (queue instanceof Response) return queue;
    autoplay = JSON.stringify(queue);
  }
  if (!title || !Number.isInteger(hour) || hour < 0 || hour > 23 || !Number.isInteger(minute) || minute < 0 || minute > 59
    || !validTimeZone(zone) || !Number.isInteger(duration) || duration < 5 || duration > 240) {
    return json({ error: "Title, a valid time, a time zone and a duration of 5-240 minutes are required" }, { status: 400 });
  }
  await env.DB.prepare(`INSERT INTO group_zikr_sessions(id,group_id,title,weekdays_json,start_hour,start_minute,time_zone,anchor,duration_minutes,is_active,updated_at,autoplay_json)
    VALUES(?,?,?,?,?,?,?,?,?,1,?,?)
    ON CONFLICT(group_id,id) DO UPDATE SET title=excluded.title,weekdays_json=excluded.weekdays_json,start_hour=excluded.start_hour,
      start_minute=excluded.start_minute,time_zone=excluded.time_zone,anchor=excluded.anchor,
      duration_minutes=excluded.duration_minutes,is_active=1,updated_at=excluded.updated_at,autoplay_json=excluded.autoplay_json`)
    .bind(sessionID, groupID, title, JSON.stringify(weekdays.length ? weekdays : [1, 2, 3, 4, 5, 6, 7]), hour, minute, zone, anchor, duration,
      new Date().toISOString(), autoplay).run();
  return json({ ok: true, id: sessionID });
}

export async function removeZikrSession(env: Env, memberID: string, groupID: string, sessionID: string): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  if (!await canManage(env, memberID, role, groupID)) return forbidden();
  await env.DB.prepare("UPDATE group_zikr_sessions SET is_active=0,updated_at=? WHERE group_id=? AND id=?")
    .bind(new Date().toISOString(), groupID, sessionID).run();
  return new Response(null, { status: 204 });
}

function validTimeZone(zone: string): boolean {
  if (!/^[A-Za-z_]+(?:\/[A-Za-z0-9_+-]+){0,2}$/.test(zone)) return false;
  try { new Intl.DateTimeFormat("en", { timeZone: zone }); return true; } catch { return false; }
}

// MARK: - Live sessions and meetings

/** Starts or ends what is live in a group: a zikr (watched as a stream, joined
 *  together in a room, or both; or a recording played to the group) or a
 *  meeting. Members are told when it starts. */
export async function setLive(env: Env, memberID: string, groupID: string, input: Record<string, unknown>): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  if (!await canManage(env, memberID, role, groupID)) return forbidden();
  if (input.state !== "live") {
    // Only an admin ends a session; a finished recording leaves it open.
    await endSession(env, groupID, memberID);
    return json({ ok: true, state: "offline" });
  }
  const kind = input.kind === "meeting" ? "meeting" : "zikr";
  const title = cleanText(input.title, 200) ?? (kind === "zikr" ? "Halqah Zikr" : "Group meeting");
  let video = typeof input.videoID === "string" && /^[\w-]{11}$/.test(input.videoID) ? input.videoID : null;
  const wantsRoom = input.room === true || kind === "meeting";
  // What plays to the group: recordings and past videos, one after another.
  // The older single forms (recordingID, a recorded videoID) still work.
  let entries: unknown[] = kind === "zikr" && Array.isArray(input.queue) ? input.queue : [];
  if (kind === "zikr" && typeof input.recordingID === "string") entries = [{ recordingID: input.recordingID }, ...entries];
  if (kind === "zikr" && video && !wantsRoom) {
    // A past video plays as a recording, together; a live one is watched live.
    // YouTube says which it is; without it, the app does.
    const info = (await youtubeVideos(env, [video]))?.get(video);
    if (info ? !info.live : input.recorded === true) {
      entries = [{ videoID: video }, ...entries];
      video = null;
    }
  }
  const queue = await resolveQueue(env, groupID, entries);
  if (queue instanceof Response) return queue;
  if (!video && !wantsRoom && !queue.length) return json({ error: "A live session needs a video, a room, or something to play" }, { status: 400 });
  // A room can be recorded from the moment the first person joins; the
  // recording is kept in the group's recordings afterwards.
  const record = wantsRoom && input.record === true;
  let roomID: string | null = null;
  if (wantsRoom) {
    const room = await createRoom(env, `${groupID}: ${title}`, record ? groupID : null);
    if (room instanceof Response) return room;
    roomID = room;
  }
  const sessionID = await beginSession(env, groupID, memberID, { kind, title, videoID: video, roomID, queue, roomRecording: record });
  if (roomID) await trackRoom(env, { roomID, groupID, sessionID, kind, title, record });
  const recorded = queue.length > 0;
  await notifyGroup(env, groupID, `live:${groupID}:${sessionID}`, title,
    kind === "meeting" ? "The group meeting has started. Join now in Darul Irfan."
      : recorded && !roomID ? "The Halqah zikr has started. Listen together in Darul Irfan."
      : "Halqah zikr has started. Join now in Darul Irfan.",
    `darulirfan://groups/${groupID}`);
  return json({ ok: true, state: "live", kind, hasRoom: !!roomID, recorded, sessionID });
}

export async function scheduleMeeting(env: Env, memberID: string, groupID: string, input: Record<string, unknown>): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  if (!await canManage(env, memberID, role, groupID)) return forbidden();
  const title = cleanText(input.title, 200);
  const startsAt = validISODate(input.startsAt);
  const duration = Number(input.durationMinutes ?? 60);
  if (!title || !startsAt || !Number.isInteger(duration) || duration < 10 || duration > 480) {
    return json({ error: "A title, a start time and a duration of 10-480 minutes are required" }, { status: 400 });
  }
  const id = newID("meeting");
  await env.DB.prepare(`INSERT INTO group_meetings(id,group_id,title,starts_at,duration_minutes,created_by,updated_at)
    VALUES(?,?,?,?,?,?,?)`).bind(id, groupID, title, startsAt, duration, memberID, new Date().toISOString()).run();
  await notifyGroup(env, groupID, `meeting:${id}`, title, "A group meeting has been scheduled. See the time in Darul Irfan.",
    `darulirfan://groups/${groupID}`);
  return json({ ok: true, id }, { status: 201 });
}

export async function cancelMeeting(env: Env, memberID: string, groupID: string, meetingID: string): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  if (!await canManage(env, memberID, role, groupID)) return forbidden();
  await env.DB.prepare("UPDATE group_meetings SET is_cancelled=1,updated_at=? WHERE group_id=? AND id=?")
    .bind(new Date().toISOString(), groupID, meetingID).run();
  return new Response(null, { status: 204 });
}

/** A place in the room: the live session's, or a scheduled meeting's (whose
 *  room is opened by the first person to join from ten minutes before). */
export async function joinRoom(env: Env, memberID: string, groupID: string, input: Record<string, unknown>): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  const managing = await canManage(env, memberID, role, groupID);
  let roomID: string | null = null;
  if (typeof input.meetingID === "string") {
    const meeting = await env.DB.prepare(`SELECT title,starts_at,duration_minutes,room_id FROM group_meetings
      WHERE group_id=? AND id=? AND is_cancelled=0`).bind(groupID, input.meetingID)
      .first<{ title: string; starts_at: string; duration_minutes: number; room_id: string | null }>();
    if (!meeting) return notFound();
    const opens = Date.parse(meeting.starts_at) - 10 * 60_000;
    const closes = Date.parse(meeting.starts_at) + meeting.duration_minutes * 60_000 + 30 * 60_000;
    if (!managing && (Date.now() < opens || Date.now() > closes)) {
      return json({ error: "The meeting room opens ten minutes before it starts." }, { status: 409 });
    }
    roomID = meeting.room_id;
    if (!roomID) {
      const room = await createRoom(env, `${groupID}: ${meeting.title}`, null);
      if (room instanceof Response) return room;
      roomID = room;
      await trackRoom(env, { roomID, groupID, sessionID: null, kind: "meeting", title: meeting.title, record: false });
      await env.DB.prepare("UPDATE group_meetings SET room_id=?,updated_at=? WHERE group_id=? AND id=? AND room_id IS NULL")
        .bind(roomID, new Date().toISOString(), groupID, input.meetingID).run();
      const stored = await env.DB.prepare("SELECT room_id FROM group_meetings WHERE group_id=? AND id=?")
        .bind(groupID, input.meetingID).first<{ room_id: string }>();
      roomID = stored?.room_id ?? roomID;
    }
  } else {
    const live = await env.DB.prepare("SELECT state,room_id FROM group_live WHERE group_id=?").bind(groupID)
      .first<{ state: string; room_id: string | null }>();
    if (live?.state !== "live" || !live.room_id) return json({ error: "Nothing is live in this group right now." }, { status: 409 });
    roomID = live.room_id;
  }
  const name = (await env.DB.prepare("SELECT display_name FROM members WHERE id=?").bind(memberID)
    .first<{ display_name: string | null }>())?.display_name ?? "Member";
  const token = await addParticipant(env, roomID, memberID, name, managing);
  if (token instanceof Response) return token;
  return json({ authToken: token, pageURL: `${env.PUBLIC_BASE_URL}/v1/meet` });
}

/** Which outside services are connected yet. The app marks the rest
 *  "integration in progress" instead of offering something that cannot work,
 *  and the label goes away by itself once the service's keys are set. */
export function integrationStatus(env: Env): { meetings: boolean; whatsappForwarding: boolean; liveBroadcast: boolean } {
  return {
    meetings: realtimeBase(env) !== null,
    whatsappForwarding: !!(env.WHATSAPP_APP_SECRET && env.WHATSAPP_CHANNEL_URL && env.WHATSAPP_ACCESS_TOKEN && env.WHATSAPP_ALLOWED_SENDERS),
    liveBroadcast: !!(env.STREAM_INPUTS && env.STREAM_CUSTOMER_HOST && env.LISTENER_TOKEN),
  };
}

// MARK: - The meeting service (Cloudflare RealtimeKit)

export function realtimeBase(env: Env): string | null {
  if (!env.REALTIME_ACCOUNT_ID || !env.REALTIME_APP_ID || !env.REALTIME_API_TOKEN) return null;
  return `https://api.cloudflare.com/client/v4/accounts/${env.REALTIME_ACCOUNT_ID}/realtime/kit/${env.REALTIME_APP_ID}`;
}

const notConfigured = () => json({ error: "Video meetings: integration in progress. They open here once it is complete." }, { status: 503 });

/** Opens a room. With `recordFor` (the group), the room records itself from
 *  when the first person joins. */
async function createRoom(env: Env, title: string, recordFor: string | null): Promise<string | Response> {
  const base = realtimeBase(env);
  if (!base) return notConfigured();
  const response = await fetch(`${base}/meetings`, {
    method: "POST",
    headers: { authorization: `Bearer ${env.REALTIME_API_TOKEN}`, "content-type": "application/json" },
    body: JSON.stringify({
      title: title.slice(0, 120),
      ...(recordFor ? { record_on_start: true, recording_config: recordingConfig(recordFor) } : {}),
    }),
  });
  const body = await response.json<{ data?: { id?: string }; result?: { id?: string } }>().catch(() => ({}) as Record<string, never>);
  const id = (body as { data?: { id?: string } }).data?.id ?? (body as { result?: { id?: string } }).result?.id;
  if (!response.ok || !id) return json({ error: "The meeting room could not be opened. Try again." }, { status: 502 });
  return id;
}

async function addParticipant(env: Env, roomID: string, memberID: string, name: string, host: boolean): Promise<string | Response> {
  const base = realtimeBase(env);
  if (!base) return notConfigured();
  const response = await fetch(`${base}/meetings/${encodeURIComponent(roomID)}/participants`, {
    method: "POST",
    headers: { authorization: `Bearer ${env.REALTIME_API_TOKEN}`, "content-type": "application/json" },
    body: JSON.stringify({
      name: name.slice(0, 80),
      // Hosts can moderate (mute, remove); members join as participants.
      preset_name: host ? (env.REALTIME_PRESET_HOST ?? "group_call_host") : (env.REALTIME_PRESET_MEMBER ?? "group_call_participant"),
      custom_participant_id: memberID,
    }),
  });
  const body = await response.json<Record<string, unknown>>().catch(() => ({}));
  const data = (body as { data?: { token?: string; authToken?: string } }).data
    ?? (body as { result?: { token?: string; authToken?: string } }).result;
  const token = data?.authToken ?? data?.token;
  if (!response.ok || !token) return json({ error: "Could not join the room. Try again." }, { status: 502 });
  return token;
}

/** The in-app meeting screen. The app loads it in its own web view with the
 *  participant token in the URL fragment, which is never sent to a server, so
 *  the token stays out of every log. Library versions are pinned. */
export function meetingPage(): Response {
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Darul Irfan</title>
<style>html,body{margin:0;height:100%;background:#0b2b20;color:#f6f4ef;font:16px -apple-system,system-ui}
rtk-meeting{display:block;height:100%}#note{padding:24px;text-align:center}</style>
<script type="module">
import { defineCustomElements } from "https://cdn.jsdelivr.net/npm/@cloudflare/realtimekit-ui@2.0.2/loader/index.es2017.js";
defineCustomElements();
</script>
<script src="https://cdn.jsdelivr.net/npm/@cloudflare/realtimekit@2.0.2/dist/browser.js"></script>
</head><body><rtk-meeting id="meeting" show-setup-screen="true"></rtk-meeting><div id="note" hidden></div>
<script>
const token = new URLSearchParams(location.hash.slice(1)).get("token");
const note = document.getElementById("note");
if (!token) { note.hidden = false; note.textContent = "This room link is not valid."; }
else RealtimeKitClient.init({ authToken: token }).then(m => {
  document.getElementById("meeting").meeting = m;
  m.self.on("roomLeft", () => { try { window.webkit.messageHandlers.darulirfan.postMessage("left"); } catch (e) {} });
}).catch(() => { note.hidden = false; note.textContent = "Could not join the room. Close and try again."; });
</script></body></html>`;
  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "content-security-policy": "default-src 'self'; script-src 'unsafe-inline' https://cdn.jsdelivr.net; style-src 'unsafe-inline' https://cdn.jsdelivr.net; connect-src https: wss:; img-src https: data: blob:; media-src https: blob:; font-src https: data:; frame-ancestors 'none'",
      "referrer-policy": "no-referrer",
      "permissions-policy": "camera=(self), microphone=(self), display-capture=(self)",
    },
  });
}

// MARK: - Notifications

/** Links this member's push installation, so group notices reach them. */
export async function registerMemberDevice(env: Env, memberID: string, input: Record<string, unknown>): Promise<Response> {
  const installation = typeof input.installationID === "string" && /^[0-9A-Fa-f-]{36}$/.test(input.installationID)
    ? input.installationID.toUpperCase() : null;
  if (!installation) return json({ error: "A valid installation id is required" }, { status: 400 });
  await env.DB.prepare(`INSERT INTO member_devices(member_id,installation_id,updated_at) VALUES(?,?,?)
    ON CONFLICT(member_id,installation_id) DO UPDATE SET updated_at=excluded.updated_at`)
    .bind(memberID, installation, new Date().toISOString()).run();
  return new Response(null, { status: 204 });
}

/** Pushes to this group's members only - never a topic everyone shares. A
 *  missing push credential never blocks the post or session itself. */
export async function notifyGroup(env: Env, groupID: string, eventID: string, title: string, body: string, path: string): Promise<number> {
  const devices = await env.DB.prepare(`SELECT DISTINCT d.installation_id FROM devices d
    JOIN member_devices md ON upper(md.installation_id)=upper(d.installation_id)
    JOIN member_group_members gm ON gm.member_id=md.member_id
    WHERE gm.group_id=?`).bind(groupID).all<{ installation_id: string }>();
  const ids = (devices.results ?? []).map(row => row.installation_id);
  if (!ids.length) return 0;
  try {
    return await sendPushToInstallations(env, eventID, `group:${groupID}`, ids, title, body, path);
  } catch {
    return 0;
  }
}

// MARK: - Routing posts into groups

const TAG = /^\s*#([a-z][a-z0-9-]{1,39})\b\s*/i;

/** Which group a forwarded message belongs to: a #tag at its start wins (and
 *  is removed from the text), otherwise the sender's own group. Null when it
 *  belongs to no group, so it goes to the public feed's drafts as before. */
export async function routeToGroup(env: Env, sender: string, text: string): Promise<{ groupID: string; text: string } | null> {
  const tag = TAG.exec(text);
  if (tag) {
    const raw = (tag[1] ?? "").toLowerCase();
    const candidates = [raw, raw === "darulirfan" ? "darul-irfan" : raw];
    for (const candidate of candidates) {
      if (await groupExists(env, candidate)) return { groupID: candidate, text: text.slice(tag[0].length).trim() };
    }
  }
  const mapped = await env.DB.prepare("SELECT group_id FROM whatsapp_sender_groups WHERE sender=?").bind(sender)
    .first<{ group_id: string }>();
  return mapped ? { groupID: mapped.group_id, text } : null;
}

/** Records a routed message as a draft in its group. Idempotent on the
 *  message id: a redelivered webhook does not duplicate the post. */
export async function recordGroupDraft(
  env: Env, groupID: string, sourceRef: string, text: string, publishedAt: string, imageKey: string | null = null,
): Promise<void> {
  const now = new Date().toISOString();
  const firstLine = text.split("\n")[0] ?? text;
  await env.DB.prepare(`INSERT OR IGNORE INTO member_group_posts(id,group_id,kind,title,body,published_at,author_email,is_hidden,updated_at,status,source,source_ref,image_key)
    VALUES(?,?,'announcement',?,?,?,'whatsapp',0,?,'draft','whatsapp',?,?)`)
    .bind(newID("wa"), groupID, firstLine.slice(0, 120), text, publishedAt, now, sourceRef, imageKey).run();
}

/** Admin page: copies a public feed item into a group as a draft. */
export async function shareFeedItemToGroup(env: Env, groupID: string, feedItemID: string): Promise<Response> {
  if (!await groupExists(env, groupID)) return json({ error: "Unknown group" }, { status: 404 });
  const item = await env.DB.prepare("SELECT title,body,video_id,published_at FROM feed_items WHERE id=?").bind(feedItemID)
    .first<{ title: string; body: string | null; video_id: string | null; published_at: string }>();
  if (!item) return json({ error: "Unknown feed item" }, { status: 404 });
  const now = new Date().toISOString();
  const id = newID("feed");
  await env.DB.prepare(`INSERT OR IGNORE INTO member_group_posts(id,group_id,kind,title,body,youtube_video_id,published_at,author_email,is_hidden,updated_at,status,source,source_ref)
    VALUES(?,?,?,?,?,?,?,'feed',0,?,'draft','feed',?)`)
    .bind(id, groupID, "announcement", item.title, item.body, item.video_id, now, now, feedItemID).run();
  return json({ ok: true, id }, { status: 201 });
}
