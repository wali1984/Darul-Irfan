import type { Env } from "./contracts";
import { realtimeBase } from "./community";
import { json } from "./util";

// Recording the rooms a Halqah meets in, and keeping the recordings.
//
// The meeting service (Cloudflare RealtimeKit) records a room into its own
// bucket and hands back a download link that expires. Its API takes no R2
// destination of ours, so each finished recording is copied from that link
// into the app's R2 bucket and added to the group's recordings - where an
// admin can play it to the group again like any uploaded recording.

const MAX_SECONDS = 6 * 3_600;
const TYPES: Record<string, string> = { "audio/mp4": "m4a", "audio/aac": "aac", "audio/mpeg": "mp3", "video/mp4": "mp4", "video/webm": "webm" };

type ServiceRecording = {
  id?: string; status?: string; started_time?: string; invoked_time?: string; recording_duration?: number;
  file_size?: number; download_url?: string; audio_download_url?: string;
};

function headers(env: Env) {
  return { authorization: `Bearer ${env.REALTIME_API_TOKEN}`, "content-type": "application/json" };
}

/** What the service records: the room, and its sound as a file of its own
 *  (a zikr is kept as sound). The prefix names the files by group. */
export function recordingConfig(groupID: string) {
  return {
    file_name_prefix: groupID.replace(/[^A-Za-z0-9]/g, "_"),
    max_seconds: MAX_SECONDS,
    audio_config: { codec: "AAC", channel: "stereo", export_file: true },
  };
}

/** Remembers a room the server opened, so its recordings are collected. */
export async function trackRoom(
  env: Env, room: { roomID: string; groupID: string; sessionID: string | null; kind: string; title: string; record: boolean },
): Promise<void> {
  await env.DB.prepare(`INSERT INTO group_rooms(room_id,group_id,session_id,kind,title,record,created_at) VALUES(?,?,?,?,?,?,?)
    ON CONFLICT(room_id) DO UPDATE SET record=MAX(group_rooms.record,excluded.record)`)
    .bind(room.roomID, room.groupID, room.sessionID, room.kind, room.title, room.record ? 1 : 0, new Date().toISOString()).run();
}

/** Starts recording the live room. The service records only a room someone
 *  is in, and says so. */
export async function startRoomRecording(env: Env, groupID: string, roomID: string): Promise<Response | null> {
  const base = realtimeBase(env);
  if (!base) return json({ error: "Recording: integration in progress." }, { status: 503 });
  const response = await fetch(`${base}/recordings`, {
    method: "POST", headers: headers(env),
    body: JSON.stringify({ meeting_id: roomID, ...recordingConfig(groupID) }),
  });
  const body = await response.json<{ data?: ServiceRecording }>().catch(() => ({} as { data?: ServiceRecording }));
  if (!response.ok || !body.data?.id) {
    return json({ error: "Recording starts once someone is in the room. Join it, then try again." }, { status: 409 });
  }
  await env.DB.prepare("UPDATE group_rooms SET record=1 WHERE room_id=?").bind(roomID).run();
  await env.DB.prepare("UPDATE group_live SET room_recording=1 WHERE group_id=? AND room_id=?").bind(groupID, roomID).run();
  return null;
}

/** Stops whatever recording is running in the room. Best effort: a room no
 *  one is in has already stopped. */
export async function stopRoomRecording(env: Env, groupID: string, roomID: string): Promise<void> {
  const base = realtimeBase(env);
  await env.DB.prepare("UPDATE group_live SET room_recording=0 WHERE group_id=? AND room_id=?").bind(groupID, roomID).run();
  if (!base) return;
  try {
    const active = await fetch(`${base}/recordings/active-recording/${encodeURIComponent(roomID)}`, { headers: headers(env) });
    const body = await active.json<{ data?: ServiceRecording }>().catch(() => ({} as { data?: ServiceRecording }));
    if (active.ok && body.data?.id) {
      await fetch(`${base}/recordings/${encodeURIComponent(body.data.id)}`, {
        method: "PUT", headers: headers(env), body: JSON.stringify({ action: "stop" }),
      });
    }
  } catch {
    // The service closes a recording itself when the room empties.
  }
}

/** Finds the recordings of recent recorded rooms and copies each finished one
 *  into our storage, as a recording of its group. Runs every five minutes;
 *  copies at most a few files a run. */
export async function collectRoomRecordings(env: Env, now = new Date()): Promise<void> {
  const base = realtimeBase(env);
  if (!base || !env.MEDIA) return;
  const since = new Date(now.getTime() - 3 * 86_400_000).toISOString();
  const rooms = await env.DB.prepare(`SELECT room_id,group_id,session_id,kind,title FROM group_rooms
    WHERE record=1 AND created_at>=? ORDER BY created_at DESC LIMIT 10`).bind(since)
    .all<{ room_id: string; group_id: string; session_id: string | null; kind: string; title: string }>();
  for (const room of rooms.results ?? []) {
    const listed = await fetch(`${base}/recordings?meeting_id=${encodeURIComponent(room.room_id)}&per_page=20`, { headers: headers(env) });
    if (!listed.ok) continue;
    const body = await listed.json<{ data?: ServiceRecording[] }>().catch(() => ({} as { data?: ServiceRecording[] }));
    for (const recording of body.data ?? []) {
      if (!recording.id || !recording.status) continue;
      await env.DB.prepare(`INSERT INTO group_room_recordings(id,group_id,room_id,session_id,kind,title,status,started_at,updated_at)
        VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET status=excluded.status,updated_at=excluded.updated_at`)
        .bind(recording.id, room.group_id, room.room_id, room.session_id, room.kind, room.title, recording.status,
          recording.started_time ?? recording.invoked_time ?? null, now.toISOString()).run();
    }
  }
  const ready = await env.DB.prepare(`SELECT id,group_id,kind,title,started_at FROM group_room_recordings
    WHERE status='UPLOADED' AND recording_id IS NULL AND error IS NULL ORDER BY updated_at LIMIT 2`)
    .all<{ id: string; group_id: string; kind: string; title: string; started_at: string | null }>();
  for (const row of ready.results ?? []) {
    await copyRecording(env, base, row, now).catch(async (error: unknown) => {
      await env.DB.prepare("UPDATE group_room_recordings SET error=?,updated_at=? WHERE id=?")
        .bind(String(error instanceof Error ? error.message : error).slice(0, 300), now.toISOString(), row.id).run();
    });
  }
}

async function copyRecording(
  env: Env, base: string, row: { id: string; group_id: string; kind: string; title: string; started_at: string | null }, now: Date,
): Promise<void> {
  // A fresh link: the one the list gave may have expired.
  const detail = await fetch(`${base}/recordings/${encodeURIComponent(row.id)}`, { headers: headers(env) });
  const recording = (await detail.json<{ data?: ServiceRecording }>().catch(() => ({} as { data?: ServiceRecording }))).data;
  // A zikr is kept as its sound; a meeting with its picture.
  const link = row.kind === "zikr"
    ? recording?.audio_download_url ?? recording?.download_url
    : recording?.download_url ?? recording?.audio_download_url;
  if (!detail.ok || !recording || !link) throw new Error("No download link yet");
  const file = await fetch(link);
  if (!file.ok || !file.body) throw new Error(`Download failed: ${file.status}`);
  const contentType = (file.headers.get("content-type") ?? "").split(";")[0]!.trim().toLowerCase();
  const type = TYPES[contentType] ? contentType : link === recording.audio_download_url ? "audio/mp4" : "video/mp4";
  const key = `recordings/${row.group_id}/${row.id.replace(/[^A-Za-z0-9-]/g, "")}.${TYPES[type]}`;
  const length = Number(file.headers.get("content-length")) || recording.file_size || 0;
  // R2 needs to know a stream's length; without it the file is read whole.
  let stored: ReadableStream | ArrayBuffer = file.body;
  if (!file.headers.get("content-length")) {
    if (length > 0) {
      const fixed = new FixedLengthStream(length);
      file.body.pipeTo(fixed.writable);
      stored = fixed.readable;
    } else {
      stored = await file.arrayBuffer();
    }
  }
  await env.MEDIA!.put(key, stored, { httpMetadata: { contentType: type } });
  const day = (row.started_at ?? now.toISOString()).slice(0, 10);
  const id = `rec-${crypto.randomUUID().slice(0, 12)}`;
  await env.DB.prepare(`INSERT INTO group_recordings(id,group_id,title,media_key,content_type,byte_size,duration_seconds,created_by,created_at)
    VALUES(?,?,?,?,?,?,?,'room',?)`)
    .bind(id, row.group_id, `${row.title} · ${day}`, key, type, length || (stored instanceof ArrayBuffer ? stored.byteLength : 0),
      recording.recording_duration ? Math.round(recording.recording_duration) : null, now.toISOString()).run();
  await env.DB.prepare("UPDATE group_room_recordings SET recording_id=?,updated_at=? WHERE id=?").bind(id, now.toISOString(), row.id).run();
}
