import type { AppBootstrap, Env, LiveBroadcast, OfficialFeedItem, RemoteZikrSchedule } from "./contracts";
import { parseJSON, validHTTPURL } from "./util";
import { schemaVersion } from "./contracts";

type Row = Record<string, string | number | null>;

export async function liveBroadcast(env: Env): Promise<LiveBroadcast> {
  const row = await env.DB.prepare("SELECT * FROM live_broadcasts WHERE id = ?").bind("official-live").first<Row>();
  if (!row) {
    return { id: "official-live", state: "offline", title: "Live Zikr", sources: [], updatedAt: new Date().toISOString() };
  }
  const sources: LiveBroadcast["sources"] = [];
  const owned = validHTTPURL(row.owned_stream_url);
  const videoID = typeof row.youtube_video_id === "string" ? row.youtube_video_id : undefined;
  const paltalk = validHTTPURL(row.paltalk_url);
  if (owned) sources.push({ kind: "ownedStream", url: owned, supportsBackgroundAudio: true });
  if (videoID) sources.push({ kind: "youtube", url: `https://www.youtube.com/watch?v=${encodeURIComponent(videoID)}`, videoID, supportsBackgroundAudio: false });
  if (paltalk) sources.push({ kind: "paltalk", url: paltalk, supportsBackgroundAudio: false });
  return {
    id: String(row.id), state: row.state as LiveBroadcast["state"], title: String(row.title),
    details: typeof row.details === "string" ? row.details : undefined,
    scheduledStart: typeof row.scheduled_start === "string" ? row.scheduled_start : undefined,
    startedAt: typeof row.started_at === "string" ? row.started_at : undefined,
    endedAt: typeof row.ended_at === "string" ? row.ended_at : undefined,
    sources, updatedAt: String(row.updated_at)
  };
}

export async function schedules(env: Env): Promise<RemoteZikrSchedule[]> {
  const result = await env.DB.prepare("SELECT * FROM zikr_schedules WHERE is_active = 1 ORDER BY start_hour, start_minute").all<Row>();
  return result.results.map(row => ({
    id: String(row.id), title: String(row.title), weekdays: parseJSON<number[]>(String(row.weekdays_json), []),
    startHour: Number(row.start_hour), startMinute: Number(row.start_minute), durationMinutes: Number(row.duration_minutes),
    timeZoneIdentifier: String(row.timezone), joinURL: validHTTPURL(row.join_url),
    instructions: typeof row.instructions === "string" ? row.instructions : undefined,
    availabilityNote: typeof row.availability_note === "string" ? row.availability_note : undefined
  }));
}

export async function bootstrap(env: Env): Promise<AppBootstrap> {
  const config = await env.DB.prepare("SELECT key, value_json FROM app_config").all<Row>();
  const values = Object.fromEntries(config.results.map(row => [String(row.key), parseJSON(String(row.value_json), null)]));
  return {
    schemaVersion, generatedAt: new Date().toISOString(),
    minimumSupportedVersion: typeof values.minimumSupportedVersion === "string" ? values.minimumSupportedVersion : "1.2.1",
    featureFlags: (values.featureFlags ?? {}) as Record<string, boolean>,
    officialLinks: (values.officialLinks ?? {}) as Record<string, string>,
    schedules: await schedules(env), live: await liveBroadcast(env),
    contentVersions: (values.contentVersions ?? { officialFeed: 1 }) as Record<string, number>
  };
}

export async function feed(env: Env, limit: number, cursor?: string): Promise<{ items: OfficialFeedItem[]; nextCursor?: string }> {
  const bounded = Math.max(1, Math.min(50, limit));
  const sql = cursor
    ? "SELECT * FROM feed_items WHERE publication_status='published' AND is_hidden=0 AND (expires_at IS NULL OR expires_at>datetime('now')) AND (published_at < ? OR (published_at = ? AND id < ?)) ORDER BY published_at DESC,id DESC LIMIT ?"
    : "SELECT * FROM feed_items WHERE publication_status='published' AND is_hidden=0 AND (expires_at IS NULL OR expires_at>datetime('now')) ORDER BY is_featured DESC,published_at DESC,id DESC LIMIT ?";
  const statement = cursor
    ? (() => { const [date, id] = cursor.split("|"); return env.DB.prepare(sql).bind(date, date, id, bounded + 1); })()
    : env.DB.prepare(sql).bind(bounded + 1);
  const rows = (await statement.all<Row>()).results;
  const visible = rows.slice(0, bounded);
  const items = visible.map(row => ({
    id: String(row.id), source: row.source as OfficialFeedItem["source"], kind: row.kind as OfficialFeedItem["kind"],
    title: String(row.title), body: typeof row.body === "string" ? row.body : undefined, sourceURL: String(row.source_url),
    imageURL: validHTTPURL(row.image_url), videoID: typeof row.video_id === "string" ? row.video_id : undefined,
    publishedAt: String(row.published_at), isFeatured: Number(row.is_featured) === 1
  }));
  const last = rows.length > bounded ? visible.at(-1) : undefined;
  return { items, nextCursor: last ? `${last.published_at}|${last.id}` : undefined };
}
