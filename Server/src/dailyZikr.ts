import type { Env } from "./contracts";
import type { QueueItem } from "./session";
import { cleanText, json } from "./util";

// The newest Daily Zikr, played from where the Zikr begins (owner 2026-11-19:
// "auto pick most recent zikr and its start time ... play 5 seconds before
// Ameer, Ghazi or Haleem starts the Zikr").
//
// The channel publishes each day's Zikr as "Online Zikr with Sheikhul
// Mukarram ..."; the platform's feed already lists it. Where the Zikr begins
// and ends in it is found by the detector on amd (or set by hand) and posted
// to /v1/service/video-marks. A zikr time with autoplay_latest plays the
// newest marked video; an admin's own choice wins for that day only.

/** The channel's title for each day's recorded Zikr. */
const DAILY_ZIKR_TITLE = "Online Zikr with Sheikh%";
/** How far back the newest Daily Zikr may be. */
const NEWEST_WITHIN_DAYS = 3;
/** An admin's own choice for a zikr time wins over the newest Daily Zikr this long. */
export const OVERRIDE_HOURS = 20;

/** The newest Daily Zikr that has its marks, as a clip, or null. */
export async function newestDailyZikr(env: Env, now = new Date()): Promise<QueueItem | null> {
  const since = new Date(now.getTime() - NEWEST_WITHIN_DAYS * 86_400_000).toISOString();
  const row = await env.DB.prepare(`SELECT f.video_id,f.title,m.start_seconds,m.end_seconds FROM feed_items f
      JOIN video_clip_marks m ON m.video_id=f.video_id
    WHERE f.source='youtube' AND f.title LIKE ? AND f.published_at>=? AND f.published_at<=?
    ORDER BY f.published_at DESC LIMIT 1`)
    .bind(DAILY_ZIKR_TITLE, since, now.toISOString())
    .first<{ video_id: string; title: string; start_seconds: number; end_seconds: number | null }>();
  if (!row) return null;
  const start = Math.max(0, row.start_seconds);
  const end = row.end_seconds != null && row.end_seconds > start ? row.end_seconds : null;
  return {
    kind: "video", id: row.video_id, title: row.title,
    startSeconds: start || undefined, endSeconds: end ?? undefined,
    durationSeconds: end != null ? end - start : undefined,
  };
}

/** An admin chose this time's video themselves recently enough that it still wins. */
export function overrideActive(overrideAt: string | null | undefined, now = new Date()): boolean {
  return !!overrideAt && now.getTime() - Date.parse(overrideAt) < OVERRIDE_HOURS * 3_600_000;
}

/** The detector's (or a person's) marks for one video: where the Zikr begins and ends. */
export async function saveVideoMarks(env: Env, input: Record<string, unknown>): Promise<Response> {
  const videoID = typeof input.videoID === "string" && /^[\w-]{11}$/.test(input.videoID) ? input.videoID : null;
  const whole = (value: unknown) => typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 86_400 ? Math.floor(value) : NaN;
  const start = whole(input.startSeconds);
  const end = input.endSeconds == null ? null : whole(input.endSeconds);
  if (!videoID || Number.isNaN(start) || (end !== null && (Number.isNaN(end) || end <= start))) {
    return json({ error: "videoID, startSeconds and an endSeconds after it are required" }, { status: 400 });
  }
  await env.DB.prepare(`INSERT INTO video_clip_marks(video_id,start_seconds,end_seconds,method,detected_at) VALUES(?,?,?,?,?)
    ON CONFLICT(video_id) DO UPDATE SET start_seconds=excluded.start_seconds,end_seconds=excluded.end_seconds,
      method=excluded.method,detected_at=excluded.detected_at`)
    .bind(videoID, start, end, cleanText(input.method, 60) ?? null, new Date().toISOString()).run();
  return json({ ok: true, videoID, startSeconds: start, endSeconds: end });
}
