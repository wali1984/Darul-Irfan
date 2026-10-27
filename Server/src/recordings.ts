import type { Env } from "./contracts";
import { canManage, canSee, memberRole } from "./community";
import { cleanText, json } from "./util";

// Recorded zikr. An admin who cannot lead the zikr live plays recordings to
// the group instead: files uploaded to the group, or past zikr from the
// official YouTube channel. How they play together is session.ts.

const TYPES = new Map([
  ["audio/mpeg", "mp3"], ["audio/mp4", "m4a"], ["audio/x-m4a", "m4a"], ["audio/aac", "aac"],
  ["audio/wav", "wav"], ["audio/x-wav", "wav"], ["video/mp4", "mp4"], ["video/quicktime", "mov"],
]);
// A Worker accepts request bodies up to 100 MB: about three hours of speech
// at 64 kbit/s, or one at 192.
export const MAX_RECORDING_BYTES = 95 * 1024 * 1024;
const ZIKR_TITLE = /zikr|dhikr|ذکر/i;

const notFound = () => json({ error: "Not found" }, { status: 404 });
const forbidden = () => json({ error: "Group admin role required" }, { status: 403 });

async function managerCheck(env: Env, memberID: string, groupID: string): Promise<Response | null> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return notFound();
  if (!await canManage(env, memberID, role, groupID)) return forbidden();
  return null;
}

/** What an admin can play: the group's uploaded recordings, and the
 *  channel's past zikr videos, newest first. */
export async function listRecordings(env: Env, memberID: string, groupID: string): Promise<Response> {
  const refused = await managerCheck(env, memberID, groupID);
  if (refused) return refused;
  const uploaded = await env.DB.prepare(`SELECT id,title,content_type,byte_size,duration_seconds,created_at
    FROM group_recordings WHERE group_id=? ORDER BY created_at DESC`).bind(groupID).all();
  const stored = await env.DB.prepare(`SELECT video_id,title,published_at FROM feed_items
    WHERE source='youtube' AND video_id IS NOT NULL AND is_hidden=0 ORDER BY published_at DESC LIMIT 200`).all<
    { video_id: string; title: string; published_at: string }>();
  const candidates = (stored.results ?? []).filter(row => ZIKR_TITLE.test(row.title)).slice(0, 50);
  const info = await youtubeVideos(env, candidates.map(row => row.video_id));
  const pastVideos = candidates
    // A session still live or only scheduled is not a recording yet.
    .filter(row => !info?.get(row.video_id)?.live)
    .map(row => ({
      videoID: row.video_id, title: row.title, publishedAt: row.published_at,
      durationSeconds: info?.get(row.video_id)?.durationSeconds ?? undefined,
    }));
  return json({
    recordings: (uploaded.results ?? []).map(row => ({
      id: row.id, title: row.title, contentType: row.content_type, byteSize: row.byte_size,
      durationSeconds: row.duration_seconds ?? undefined, createdAt: row.created_at,
    })),
    pastVideos,
    maxUploadBytes: MAX_RECORDING_BYTES,
  });
}

/** Stores a recording the admin picked on the phone. The file is the request
 *  body; its title and length come in the query. */
export async function uploadRecording(request: Request, env: Env, memberID: string, groupID: string, url: URL): Promise<Response> {
  const refused = await managerCheck(env, memberID, groupID);
  if (refused) return refused;
  if (!env.MEDIA) return json({ error: "Recordings are not available yet." }, { status: 503 });
  const contentType = (request.headers.get("content-type") ?? "").split(";")[0]!.trim().toLowerCase();
  const extension = TYPES.get(contentType);
  if (!extension) return json({ error: "Choose an audio or video file (MP3, M4A, AAC, WAV, MP4 or MOV)." }, { status: 415 });
  const size = Number(request.headers.get("content-length"));
  if (!Number.isInteger(size) || size <= 0) return json({ error: "The file is empty." }, { status: 411 });
  if (size > MAX_RECORDING_BYTES) return json({ error: "The file is larger than 95 MB." }, { status: 413 });
  const title = cleanText(url.searchParams.get("title"), 200) ?? "Recorded zikr";
  const duration = Number(url.searchParams.get("durationSeconds"));
  const id = `rec-${crypto.randomUUID().slice(0, 12)}`;
  const key = `recordings/${groupID}/${id}.${extension}`;
  await env.MEDIA.put(key, request.body, { httpMetadata: { contentType } });
  await env.DB.prepare(`INSERT INTO group_recordings(id,group_id,title,media_key,content_type,byte_size,duration_seconds,created_by,created_at)
    VALUES(?,?,?,?,?,?,?,?,?)`)
    .bind(id, groupID, title, key, contentType, size,
      Number.isInteger(duration) && duration > 0 && duration < 86_400 ? duration : null, memberID, new Date().toISOString()).run();
  return json({ ok: true, id }, { status: 201 });
}

export async function deleteRecording(env: Env, memberID: string, groupID: string, recordingID: string): Promise<Response> {
  const refused = await managerCheck(env, memberID, groupID);
  if (refused) return refused;
  // The id is "rec-" and twelve hex digits, so a text match is exact.
  const needle = `%"id":"${recordingID}"%`;
  const playing = await env.DB.prepare("SELECT 1 AS ok FROM group_live WHERE group_id=? AND state='live' AND queue_json LIKE ?")
    .bind(groupID, needle).first();
  if (playing) return json({ error: "This recording is in the session now. End the session first." }, { status: 409 });
  const scheduled = await env.DB.prepare("SELECT title FROM group_zikr_sessions WHERE group_id=? AND is_active=1 AND autoplay_json LIKE ?")
    .bind(groupID, needle).first<{ title: string }>();
  if (scheduled) return json({ error: `"${scheduled.title}" plays this recording. Change that zikr time first.` }, { status: 409 });
  const row = await env.DB.prepare("SELECT media_key FROM group_recordings WHERE group_id=? AND id=?")
    .bind(groupID, recordingID).first<{ media_key: string }>();
  if (!row) return notFound();
  await env.MEDIA?.delete(row.media_key);
  await env.DB.prepare("DELETE FROM group_recordings WHERE group_id=? AND id=?").bind(groupID, recordingID).run();
  return new Response(null, { status: 204 });
}

// MARK: - Used by sessions

export async function groupRecording(env: Env, groupID: string, recordingID: string) {
  return env.DB.prepare("SELECT id,title,media_key,content_type,duration_seconds FROM group_recordings WHERE group_id=? AND id=?")
    .bind(groupID, recordingID)
    .first<{ id: string; title: string; media_key: string; content_type: string; duration_seconds: number | null }>();
}

type VideoInfo = { live: boolean; durationSeconds: number | null };

/** Whether each video is still live or scheduled, and how long it runs.
 *  One quota unit for up to 50 videos. Null when YouTube cannot be asked. */
export async function youtubeVideos(env: Env, ids: string[]): Promise<Map<string, VideoInfo> | null> {
  if (!env.YOUTUBE_API_KEY || !ids.length) return null;
  const params = new URLSearchParams({ part: "snippet,contentDetails", id: ids.slice(0, 50).join(","), key: env.YOUTUBE_API_KEY });
  try {
    const response = await fetch(`https://www.googleapis.com/youtube/v3/videos?${params}`);
    if (!response.ok) return null;
    const payload = await response.json<{ items?: Array<{
      id?: string; snippet?: { liveBroadcastContent?: string }; contentDetails?: { duration?: string };
    }> }>();
    const info = new Map<string, VideoInfo>();
    for (const item of payload.items ?? []) {
      if (!item.id) continue;
      const state = item.snippet?.liveBroadcastContent;
      info.set(item.id, { live: state === "live" || state === "upcoming", durationSeconds: isoDuration(item.contentDetails?.duration) });
    }
    return info;
  } catch {
    return null;
  }
}

/** "PT1H2M3S" -> 3723. A live video reports "P0D", which is no length. */
export function isoDuration(value: string | undefined): number | null {
  const match = /^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/.exec(value ?? "");
  if (!match) return null;
  const [, d = "0", h = "0", m = "0", s = "0"] = match;
  const seconds = Number(d) * 86_400 + Number(h) * 3_600 + Number(m) * 60 + Number(s);
  return seconds > 0 ? seconds : null;
}
