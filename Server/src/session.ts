import type { Env } from "./contracts";
import { canManage, canSee, memberRole, notifyGroup } from "./community";
import { signedMediaURL } from "./media";
import { groupRecording, youtubeVideos } from "./recordings";
import { startRoomRecording, stopRoomRecording } from "./roomRecordings";
import { cleanText, json } from "./util";

// A Halqah session that plays recordings and past zikr to the group.
//
// Everyone plays the same item at the same place. The server keeps one clock:
// where playback stood (position) at a moment (positionAt), and whether it is
// paused. Each phone works out the present place from that, so nothing has to
// be streamed and a member who opens the page late joins where the group is.
// The admin pauses, moves and adds to it; an item whose length is known moves
// on to the next by itself. The session stays open until an admin ends it.

export type QueueItem = { kind: "recording" | "video"; id: string; title: string; durationSeconds?: number };
export type Playback = { index: number; positionSeconds: number; paused: boolean; finished: boolean };

type LiveRow = {
  state: string; kind: string; title: string | null; video_id: string | null; room_id: string | null;
  started_at: string | null; started_by: string | null; session_id: string | null; queue_json: string;
  queue_index: number; position_seconds: number; position_at: string | null; paused: number;
  notice: string | null; notice_at: string | null; room_recording: number;
};

const notFound = () => json({ error: "Not found" }, { status: 404 });
const forbidden = () => json({ error: "Group admin role required" }, { status: 403 });
const nothingLive = () => json({ error: "Nothing is live in this group right now." }, { status: 409 });
/** A member counts as listening while their app has checked in this recently. */
const PRESENT_SECONDS = 150;

/** Where the group is in the queue at `now`. Items of unknown length play
 *  until the admin moves on. */
export function playbackAt(queue: QueueItem[], index: number, position: number, positionAt: string | null, paused: boolean, now: Date): Playback {
  if (!queue.length) return { index: 0, positionSeconds: 0, paused, finished: false };
  let at = paused || !positionAt ? position : position + Math.max(0, now.getTime() - Date.parse(positionAt)) / 1000;
  let i = Math.max(0, index);
  while (i < queue.length) {
    const length = queue[i]!.durationSeconds;
    if (!length || at < length) break;
    at -= length;
    i += 1;
  }
  if (i >= queue.length) {
    const last = queue.length - 1;
    return { index: last, positionSeconds: queue[last]!.durationSeconds ?? at, paused, finished: true };
  }
  return { index: i, positionSeconds: Math.max(0, at), paused, finished: false };
}

export async function liveRow(env: Env, groupID: string): Promise<LiveRow | null> {
  return env.DB.prepare(`SELECT state,kind,title,video_id,room_id,started_at,started_by,session_id,queue_json,queue_index,
    position_seconds,position_at,paused,notice,notice_at,room_recording FROM group_live WHERE group_id=?`).bind(groupID).first<LiveRow>();
}

export function queueOf(row: Pick<LiveRow, "queue_json"> | null): QueueItem[] {
  try {
    const value = JSON.parse(row?.queue_json ?? "[]");
    return Array.isArray(value) ? value as QueueItem[] : [];
  } catch {
    return [];
  }
}

async function saveClock(env: Env, groupID: string, queue: QueueItem[], index: number, position: number, paused: boolean, now: Date) {
  await env.DB.prepare(`UPDATE group_live SET queue_json=?,queue_index=?,position_seconds=?,position_at=?,paused=?,updated_at=?
    WHERE group_id=?`).bind(JSON.stringify(queue), index, position, now.toISOString(), paused ? 1 : 0, now.toISOString(), groupID).run();
}

/** Turns what the admin chose - recordings of the group and YouTube videos -
 *  into queue items with their titles and lengths. A video still live is
 *  refused here; it is shared as a live video instead. */
export async function resolveQueue(env: Env, groupID: string, raw: unknown): Promise<QueueItem[] | Response> {
  const entries = Array.isArray(raw) ? raw.slice(0, 20) : [];
  const videoIDs = entries.map(entry => (entry as { videoID?: unknown })?.videoID)
    .filter((id): id is string => typeof id === "string" && /^[\w-]{11}$/.test(id));
  const info = await youtubeVideos(env, videoIDs);
  const items: QueueItem[] = [];
  for (const entry of entries) {
    const { recordingID, videoID, title } = (entry ?? {}) as { recordingID?: unknown; videoID?: unknown; title?: unknown };
    if (typeof recordingID === "string") {
      const recording = await groupRecording(env, groupID, recordingID);
      if (!recording) return notFound();
      items.push({ kind: "recording", id: recording.id, title: recording.title, durationSeconds: recording.duration_seconds ?? undefined });
    } else if (typeof videoID === "string" && /^[\w-]{11}$/.test(videoID)) {
      const known = info?.get(videoID);
      if (known?.live) return json({ error: "That video is live now. Share it as a live video instead." }, { status: 400 });
      const stored = await env.DB.prepare("SELECT title FROM feed_items WHERE id=?").bind(`youtube:${videoID}`).first<{ title: string }>();
      items.push({
        kind: "video", id: videoID, title: cleanText(title, 200) ?? stored?.title ?? "Recorded zikr",
        durationSeconds: known?.durationSeconds ?? undefined,
      });
    } else {
      return json({ error: "Each item needs a recording or a video" }, { status: 400 });
    }
  }
  return items;
}

/** Starts a session, ending any session already live. */
export async function beginSession(
  env: Env, groupID: string, startedBy: string,
  session: {
    kind: "zikr" | "meeting"; title: string; videoID: string | null; roomID: string | null; queue: QueueItem[]; roomRecording?: boolean;
  },
): Promise<string> {
  const current = await liveRow(env, groupID);
  if (current?.state === "live") await endSession(env, groupID, startedBy);
  const now = new Date().toISOString();
  const sessionID = `session-${crypto.randomUUID().slice(0, 12)}`;
  await env.DB.prepare(`INSERT INTO group_live(group_id,state,kind,title,video_id,room_id,started_at,started_by,updated_at,
      session_id,queue_json,queue_index,position_seconds,position_at,paused,notice,notice_at,room_recording)
    VALUES(?,'live',?,?,?,?,?,?,?,?,?,0,0,?,0,NULL,NULL,?)
    ON CONFLICT(group_id) DO UPDATE SET state='live',kind=excluded.kind,title=excluded.title,video_id=excluded.video_id,
      room_id=excluded.room_id,started_at=excluded.started_at,started_by=excluded.started_by,updated_at=excluded.updated_at,
      session_id=excluded.session_id,queue_json=excluded.queue_json,queue_index=0,position_seconds=0,
      position_at=excluded.position_at,paused=0,notice=NULL,notice_at=NULL,room_recording=excluded.room_recording`)
    .bind(groupID, session.kind, session.title, session.videoID, session.roomID, now, startedBy, now, sessionID,
      JSON.stringify(session.queue), now, session.roomRecording ? 1 : 0).run();
  return sessionID;
}

/** Ends the live session and keeps a record of it. */
export async function endSession(env: Env, groupID: string, endedBy: string): Promise<void> {
  const live = await liveRow(env, groupID);
  const now = new Date().toISOString();
  // The recording closes with the session, and is then kept.
  if (live?.state === "live" && live.room_id && live.room_recording) await stopRoomRecording(env, groupID, live.room_id);
  if (live?.state === "live" && live.session_id) {
    const attended = await env.DB.prepare("SELECT COUNT(*) AS n FROM group_live_presence WHERE session_id=?")
      .bind(live.session_id).first<{ n: number }>();
    await env.DB.prepare(`INSERT OR REPLACE INTO group_live_history(session_id,group_id,kind,title,started_at,started_by,ended_at,ended_by,attendees)
      VALUES(?,?,?,?,?,?,?,?,?)`)
      .bind(live.session_id, groupID, live.kind, live.title, live.started_at ?? now, live.started_by, now, endedBy, attended?.n ?? 0).run();
  }
  await env.DB.prepare(`INSERT INTO group_live(group_id,state,updated_at) VALUES(?,'offline',?)
    ON CONFLICT(group_id) DO UPDATE SET state='offline',video_id=NULL,room_id=NULL,session_id=NULL,queue_json='[]',
      queue_index=0,position_seconds=0,position_at=NULL,paused=0,notice=NULL,notice_at=NULL,room_recording=0,updated_at=excluded.updated_at`)
    .bind(groupID, now).run();
}

/** The live session as the group page shows it. Admins also get who is
 *  listening and the dua requests. */
export async function sessionPayload(env: Env, groupID: string, live: LiveRow, managing: boolean, now = new Date()) {
  const queue = queueOf(live);
  const playback = playbackAt(queue, live.queue_index, live.position_seconds, live.position_at, !!live.paused, now);
  const items = [];
  for (const item of queue) {
    if (item.kind === "recording") {
      const recording = await groupRecording(env, groupID, item.id);
      items.push({
        kind: item.kind, id: item.id, title: item.title, durationSeconds: item.durationSeconds,
        contentType: recording?.content_type,
        // Long enough to outlast any session; the link is private to the group.
        url: recording ? await signedMediaURL(env, recording.media_key, 24 * 3_600) : undefined,
      });
    } else {
      items.push({ kind: item.kind, id: item.id, title: item.title, durationSeconds: item.durationSeconds, videoID: item.id });
    }
  }
  const since = new Date(now.getTime() - PRESENT_SECONDS * 1000).toISOString();
  const listening = live.session_id ? await env.DB.prepare(
    "SELECT COUNT(*) AS n FROM group_live_presence WHERE session_id=? AND last_seen_at>=?",
  ).bind(live.session_id, since).first<{ n: number }>() : null;
  const payload: Record<string, unknown> = {
    sessionID: live.session_id ?? undefined,
    recorded: queue.length > 0,
    queue: items,
    playback: queue.length ? { ...playback, at: now.toISOString() } : undefined,
    notice: live.notice ? { text: live.notice, postedAt: live.notice_at ?? undefined } : undefined,
    listeners: listening?.n ?? 0,
    // Everyone in the session is told when its room is being recorded.
    roomRecording: !!live.room_id && !!live.room_recording,
  };
  if (managing && live.session_id) {
    const attendance = await env.DB.prepare(`SELECT p.member_id,m.display_name,p.first_seen_at,p.last_seen_at
      FROM group_live_presence p LEFT JOIN members m ON m.id=p.member_id WHERE p.session_id=? ORDER BY p.first_seen_at`)
      .bind(live.session_id).all<{ member_id: string; display_name: string | null; first_seen_at: string; last_seen_at: string }>();
    payload.attendance = (attendance.results ?? []).map(row => ({
      name: row.display_name ?? "Member", firstSeenAt: row.first_seen_at, lastSeenAt: row.last_seen_at, isHere: row.last_seen_at >= since,
    }));
  }
  return payload;
}

// MARK: - Admin controls

/** One playback control from an admin, applied for everyone. */
export async function controlSession(env: Env, memberID: string, groupID: string, input: Record<string, unknown>): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  if (!await canManage(env, memberID, role, groupID)) return forbidden();
  const live = await liveRow(env, groupID);
  if (live?.state !== "live") return nothingLive();
  const now = new Date();
  let queue = queueOf(live);
  const current = playbackAt(queue, live.queue_index, live.position_seconds, live.position_at, !!live.paused, now);
  const length = queue[current.index]?.durationSeconds;
  const number = (value: unknown) => typeof value === "number" && Number.isFinite(value) ? value : NaN;
  switch (input.action) {
    case "pause":
      await saveClock(env, groupID, queue, current.index, current.positionSeconds, true, now);
      break;
    case "resume":
      await saveClock(env, groupID, queue, current.index, current.positionSeconds, false, now);
      break;
    case "skip": {
      const by = number(input.seconds);
      if (Number.isNaN(by)) return json({ error: "seconds is required" }, { status: 400 });
      const target = Math.max(0, current.positionSeconds + by);
      await saveClock(env, groupID, queue, current.index, length ? Math.min(target, length) : target, current.paused, now);
      break;
    }
    case "seek": {
      const to = number(input.seconds);
      if (Number.isNaN(to) || to < 0) return json({ error: "seconds is required" }, { status: 400 });
      await saveClock(env, groupID, queue, current.index, length ? Math.min(to, length) : to, current.paused, now);
      break;
    }
    case "next":
      if (current.index + 1 >= queue.length) {
        // Past the last item: the session stays open, with nothing playing.
        await saveClock(env, groupID, queue, queue.length, 0, current.paused, now);
      } else {
        await saveClock(env, groupID, queue, current.index + 1, 0, current.paused, now);
      }
      break;
    case "previous": {
      // Like any player: back to the start of this item, or to the one before
      // when already at its start.
      const index = current.positionSeconds > 5 && !current.finished ? current.index : Math.max(0, current.index - (current.finished ? 0 : 1));
      await saveClock(env, groupID, queue, index, 0, current.paused, now);
      break;
    }
    case "jump": {
      const index = number(input.index);
      if (!Number.isInteger(index) || index < 0 || index >= queue.length) return json({ error: "No such item" }, { status: 400 });
      await saveClock(env, groupID, queue, index, 0, false, now);
      break;
    }
    case "add": {
      const added = await resolveQueue(env, groupID, input.items);
      if (added instanceof Response) return added;
      const wasFinished = current.finished || !queue.length;
      const start = queue.length;
      queue = [...queue, ...added].slice(0, 30);
      // Added to a finished session, it plays straight away.
      if (wasFinished && added.length) await saveClock(env, groupID, queue, start, 0, false, now);
      else await saveClock(env, groupID, queue, current.index, current.positionSeconds, current.paused, now);
      break;
    }
    case "remove": {
      const index = number(input.index);
      if (!Number.isInteger(index) || index < 0 || index >= queue.length || index === current.index) {
        return json({ error: "Only an item not playing now can be removed" }, { status: 400 });
      }
      queue = queue.filter((_, i) => i !== index);
      await saveClock(env, groupID, queue, index < current.index ? current.index - 1 : current.index, current.positionSeconds, current.paused, now);
      break;
    }
    case "notice": {
      const text = cleanText(input.text, 280);
      await env.DB.prepare("UPDATE group_live SET notice=?,notice_at=?,updated_at=? WHERE group_id=?")
        .bind(text ?? null, text ? now.toISOString() : null, now.toISOString(), groupID).run();
      if (text && input.notify === true) {
        await notifyGroup(env, groupID, `notice:${groupID}:${now.toISOString()}`, live.title ?? "Halqah Zikr", text, `darulirfan://groups/${groupID}`);
      }
      break;
    }
    case "record": {
      if (!live.room_id) return json({ error: "This session has no room to record." }, { status: 400 });
      const refused = await startRoomRecording(env, groupID, live.room_id);
      if (refused) return refused;
      break;
    }
    case "stopRecording":
      if (live.room_id) await stopRoomRecording(env, groupID, live.room_id);
      break;
    default:
      return json({ error: "Unknown action" }, { status: 400 });
  }
  const updated = await liveRow(env, groupID);
  return json({ ok: true, live: updated ? await sessionPayload(env, groupID, updated, true, now) : undefined });
}

// MARK: - Members

/** The app checks in each minute while the session is open on screen or
 *  playing, so the admin sees who is there. */
export async function checkIn(env: Env, memberID: string, groupID: string): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  const live = await liveRow(env, groupID);
  if (live?.state !== "live" || !live.session_id) return nothingLive();
  const now = new Date().toISOString();
  await env.DB.prepare(`INSERT INTO group_live_presence(session_id,group_id,member_id,first_seen_at,last_seen_at) VALUES(?,?,?,?,?)
    ON CONFLICT(session_id,member_id) DO UPDATE SET last_seen_at=excluded.last_seen_at`)
    .bind(live.session_id, groupID, memberID, now, now).run();
  const since = new Date(Date.now() - PRESENT_SECONDS * 1000).toISOString();
  const listening = await env.DB.prepare("SELECT COUNT(*) AS n FROM group_live_presence WHERE session_id=? AND last_seen_at>=?")
    .bind(live.session_id, since).first<{ n: number }>();
  return json({ ok: true, listeners: listening?.n ?? 0 });
}

/** A dua request to the group's admins, read out at the end of the zikr. */
export async function requestDua(env: Env, memberID: string, groupID: string, input: Record<string, unknown>): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  const text = cleanText(input.text, 500);
  if (!text) return json({ error: "Write the dua request first." }, { status: 400 });
  const hourAgo = new Date(Date.now() - 3_600_000).toISOString();
  const recent = await env.DB.prepare("SELECT COUNT(*) AS n FROM group_dua_requests WHERE member_id=? AND created_at>=?")
    .bind(memberID, hourAgo).first<{ n: number }>();
  if ((recent?.n ?? 0) >= 5) return json({ error: "You have sent several requests this hour. Please wait a little." }, { status: 429 });
  const live = await liveRow(env, groupID);
  const id = `dua-${crypto.randomUUID().slice(0, 12)}`;
  await env.DB.prepare(`INSERT INTO group_dua_requests(id,group_id,session_id,member_id,show_name,text,created_at) VALUES(?,?,?,?,?,?,?)`)
    .bind(id, groupID, live?.state === "live" ? live.session_id : null, memberID, input.showName === false ? 0 : 1, text, new Date().toISOString()).run();
  return json({ ok: true, id }, { status: 201 });
}

/** The group's dua requests for its admins: unread first, then the last day's. */
export async function duaRequests(env: Env, memberID: string, groupID: string): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  if (!await canManage(env, memberID, role, groupID)) return forbidden();
  const since = new Date(Date.now() - 86_400_000).toISOString();
  const rows = await env.DB.prepare(`SELECT d.id,d.text,d.show_name,d.created_at,d.read_at,m.display_name FROM group_dua_requests d
    LEFT JOIN members m ON m.id=d.member_id WHERE d.group_id=? AND (d.read_at IS NULL OR d.created_at>=?)
    ORDER BY d.read_at IS NOT NULL, d.created_at DESC LIMIT 100`).bind(groupID, since)
    .all<{ id: string; text: string; show_name: number; created_at: string; read_at: string | null; display_name: string | null }>();
  return json({
    requests: (rows.results ?? []).map(row => ({
      id: row.id, text: row.text, createdAt: row.created_at, isRead: !!row.read_at,
      // Without a name it stays without one, for the admins too.
      name: row.show_name ? row.display_name ?? undefined : undefined,
    })),
  });
}

export async function markDuaRead(env: Env, memberID: string, groupID: string, duaID: string): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  if (!await canManage(env, memberID, role, groupID)) return forbidden();
  await env.DB.prepare("UPDATE group_dua_requests SET read_at=?,read_by=? WHERE group_id=? AND id=? AND read_at IS NULL")
    .bind(new Date().toISOString(), memberID, groupID, duaID).run();
  return new Response(null, { status: 204 });
}

export async function unreadDuaCount(env: Env, groupID: string): Promise<number> {
  const row = await env.DB.prepare("SELECT COUNT(*) AS n FROM group_dua_requests WHERE group_id=? AND read_at IS NULL")
    .bind(groupID).first<{ n: number }>();
  return row?.n ?? 0;
}

/** Past sessions, newest first; with an id, who attended that one. */
export async function sessionHistory(env: Env, memberID: string, groupID: string, sessionID?: string): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  if (!await canManage(env, memberID, role, groupID)) return forbidden();
  if (sessionID) {
    const rows = await env.DB.prepare(`SELECT m.display_name,p.first_seen_at,p.last_seen_at FROM group_live_presence p
      LEFT JOIN members m ON m.id=p.member_id WHERE p.group_id=? AND p.session_id=? ORDER BY p.first_seen_at`)
      .bind(groupID, sessionID).all<{ display_name: string | null; first_seen_at: string; last_seen_at: string }>();
    return json({
      attendees: (rows.results ?? []).map(row => ({ name: row.display_name ?? "Member", firstSeenAt: row.first_seen_at, lastSeenAt: row.last_seen_at })),
    });
  }
  const rows = await env.DB.prepare(`SELECT session_id,kind,title,started_at,ended_at,attendees FROM group_live_history
    WHERE group_id=? ORDER BY started_at DESC LIMIT 50`).bind(groupID)
    .all<{ session_id: string; kind: string; title: string | null; started_at: string; ended_at: string; attendees: number }>();
  return json({
    // Only the Super admin removes a past session from the record.
    canDelete: role === "superadmin",
    sessions: (rows.results ?? []).map(row => ({
      id: row.session_id, kind: row.kind, title: row.title ?? undefined, startedAt: row.started_at, endedAt: row.ended_at, attendees: row.attendees,
    })),
  });
}

/** Removes a past session from the record, with who attended it and the
 *  dua requests sent during it. Super admin only; a live session is ended,
 *  not deleted. */
export async function deleteSessionRecord(env: Env, memberID: string, groupID: string, sessionID: string): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  if (role !== "superadmin") return json({ error: "Super admin only" }, { status: 403 });
  const live = await liveRow(env, groupID);
  if (live?.state === "live" && live.session_id === sessionID) {
    return json({ error: "This session is live. End it first." }, { status: 409 });
  }
  const removed = await env.DB.prepare("DELETE FROM group_live_history WHERE group_id=? AND session_id=?").bind(groupID, sessionID).run();
  if ((removed.meta?.changes ?? 0) === 0) return notFound();
  await env.DB.prepare("DELETE FROM group_live_presence WHERE group_id=? AND session_id=?").bind(groupID, sessionID).run();
  await env.DB.prepare("DELETE FROM group_dua_requests WHERE group_id=? AND session_id=?").bind(groupID, sessionID).run();
  return new Response(null, { status: 204 });
}

// MARK: - Playing by itself at the zikr time

/** Weekday (1 = Sunday) and minutes past midnight at `now` in `zone`. */
export function localClock(now: Date, zone: string): { weekday: number; minutes: number } {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: zone, weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
    .formatToParts(now);
  const value = (type: string) => parts.find(part => part.type === type)?.value ?? "";
  const weekday = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].indexOf(value("weekday")) + 1;
  return { weekday, minutes: Number(value("hour")) * 60 + Number(value("minute")) };
}

/** Starts each clock-time zikr that has something to play, when its time
 *  comes and no admin has started a session. Runs every five minutes. */
export async function autoplayDue(env: Env, now = new Date()): Promise<void> {
  const rows = await env.DB.prepare(`SELECT s.id,s.group_id,s.title,s.weekdays_json,s.start_hour,s.start_minute,s.time_zone,s.autoplay_json,
      s.last_autoplay_at,l.state FROM group_zikr_sessions s LEFT JOIN group_live l ON l.group_id=s.group_id
    WHERE s.is_active=1 AND s.anchor IS NULL AND s.autoplay_json IS NOT NULL`).all<{
      id: string; group_id: string; title: string; weekdays_json: string; start_hour: number; start_minute: number;
      time_zone: string; autoplay_json: string; last_autoplay_at: string | null; state: string | null;
    }>();
  for (const row of rows.results ?? []) {
    if (row.state === "live") continue;
    const clock = localClock(now, row.time_zone);
    const start = row.start_hour * 60 + row.start_minute;
    // Minutes since the start, across midnight: a 23:58 zikr is two minutes
    // late on the 00:00 tick, and it is the day before's zikr (1 = Sunday,
    // so the day before Sunday is 7).
    const late = (clock.minutes - start + 1_440) % 1_440;
    const day = clock.minutes < start ? (clock.weekday + 5) % 7 + 1 : clock.weekday;
    const weekdays = JSON.parse(row.weekdays_json) as number[];
    if (!weekdays.includes(day) || late >= 5) continue;
    if (row.last_autoplay_at && now.getTime() - Date.parse(row.last_autoplay_at) < 3_600_000) continue;
    const queue = queueOf({ queue_json: row.autoplay_json });
    if (!queue.length) continue;
    await env.DB.prepare("UPDATE group_zikr_sessions SET last_autoplay_at=? WHERE group_id=? AND id=?")
      .bind(now.toISOString(), row.group_id, row.id).run();
    await beginSession(env, row.group_id, "schedule", { kind: "zikr", title: row.title, videoID: null, roomID: null, queue });
    await notifyGroup(env, row.group_id, `autoplay:${row.group_id}:${row.id}:${now.toISOString().slice(0, 13)}`, row.title,
      "The Halqah zikr has started. Listen together in Darul Irfan.", `darulirfan://groups/${row.group_id}`);
  }
}
