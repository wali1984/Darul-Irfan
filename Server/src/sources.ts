import type { Env } from "./contracts";
import { cleanText, validHTTPURL, wholeSeconds } from "./util";
import { LIVE_ALERT, sendTopicPush } from "./apns";

interface YouTubeVideoItem { id?: string; snippet?: { title?: string; description?: string; publishedAt?: string; liveBroadcastContent?: string; thumbnails?: { high?: { url?: string } } }; liveStreamingDetails?: { scheduledStartTime?: string; actualStartTime?: string; actualEndTime?: string } }
interface YouTubeVideosResponse { items?: YouTubeVideoItem[] }
interface YouTubePlaylistResponse { items?: Array<{ contentDetails?: { videoId?: string } }> }
interface FacebookResponse { data?: Array<{ id?: string; message?: string; created_time?: string; permalink_url?: string; full_picture?: string }> }
interface CatalogContent { id?: string; title?: string; excerpt?: string; sourceUrl?: string; publishedAt?: string; updatedAt?: string; mediaUrls?: string[] }
interface CatalogEvent { id?: string; title?: string; details?: string; sourceUrl?: string; startDate?: string; updatedAt?: string }
interface CatalogManifest { version?: number; generatedAt?: string; files?: { articles?: string; events?: string } }

/**
 * Website pages without an editorial publication/update date are evergreen
 * library material, not news. Returning undefined keeps them out of the
 * chronological official-updates feed instead of stamping them with every
 * cron run and making them permanently look new.
 */
export function catalogTimestamp(item: Pick<CatalogContent, "publishedAt" | "updatedAt">): string | undefined {
  for (const candidate of [item.publishedAt, item.updatedAt]) {
    if (!candidate) continue;
    const parsed = new Date(candidate);
    if (!Number.isNaN(parsed.getTime())) return wholeSeconds(parsed);
  }
  return undefined;
}

/** The official broadcast's name in the apps, whatever the video is titled. */
export const OFFICIAL_LIVE_TITLE = "Online Zikr with Sheikh-ul-Mukarram Hazrat Ameer Abdul Qadeer Awan MZA";

/** An upcoming stream counts from a day before it starts until two hours
 *  after its time, if it has not started by then. */
const UPCOMING_AHEAD_MS = 24 * 3_600_000;
const UPCOMING_GRACE_MS = 2 * 3_600_000;

export async function refreshYouTube(env: Env): Promise<void> {
  if (!env.YOUTUBE_API_KEY) throw new Error("YOUTUBE_API_KEY is not configured");
  // Quota-safe detection: read the channel's uploads playlist (1 unit) then
  // hydrate those videos (1 unit) — ~2 units/run vs 100 for search.list, so a
  // 5-minute cron stays far under YouTube's 10k/day quota while still catching
  // a live broadcast within one tick. On videos.list, snippet.liveBroadcast
  // Content is live/upcoming/none and liveStreamingDetails carries the timings.
  const uploads = "UU" + env.YOUTUBE_CHANNEL_ID.slice(2);
  const plParams = new URLSearchParams({ part: "contentDetails", playlistId: uploads, maxResults: "20", key: env.YOUTUBE_API_KEY });
  const plResponse = await fetch(`https://www.googleapis.com/youtube/v3/playlistItems?${plParams}`);
  if (!plResponse.ok) throw new Error(`YouTube playlistItems ${plResponse.status}`);
  const plPayload = await plResponse.json<YouTubePlaylistResponse>();
  const ids = (plPayload.items ?? []).map(item => item.contentDetails?.videoId).filter((value): value is string => Boolean(value));
  if (!ids.length) return;

  const vParams = new URLSearchParams({ part: "snippet,liveStreamingDetails", id: ids.slice(0, 50).join(","), key: env.YOUTUBE_API_KEY });
  const vResponse = await fetch(`https://www.googleapis.com/youtube/v3/videos?${vParams}`);
  if (!vResponse.ok) throw new Error(`YouTube videos ${vResponse.status}`);
  const payload = await vResponse.json<YouTubeVideosResponse>();

  const prior = await env.DB.prepare("SELECT state,source_mode FROM live_broadcasts WHERE id='official-live'")
    .first<{ state: string; source_mode: string }>();
  const automatic = prior?.source_mode !== "manual";
  const now = new Date().toISOString();
  const clock = Date.parse(now);
  type Candidate = { id: string; details?: YouTubeVideoItem["liveStreamingDetails"] };
  let live: Candidate | undefined;
  let upcoming: (Candidate & { start: number }) | undefined;

  for (const item of payload.items ?? []) {
    const id = item.id; const snippet = item.snippet;
    if (!id || !snippet?.title || !snippet.publishedAt) continue;
    await env.DB.prepare(`INSERT INTO feed_items(id,source,kind,title,body,source_url,image_url,video_id,published_at,raw_json,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,body=excluded.body,image_url=excluded.image_url,raw_json=excluded.raw_json,updated_at=excluded.updated_at`)
      .bind(`youtube:${id}`, "youtube", "video", cleanText(snippet.title, 300), cleanText(snippet.description), `https://www.youtube.com/watch?v=${id}`,
        validHTTPURL(snippet.thumbnails?.high?.url) ?? null, id, snippet.publishedAt, JSON.stringify(item), now).run();
    if (!automatic) continue;
    if (snippet.liveBroadcastContent === "live") {
      // The video that is live wins, wherever the uploads list puts it: a
      // stream already scheduled for tomorrow is often listed first.
      live ??= { id, details: item.liveStreamingDetails };
    } else if (snippet.liveBroadcastContent === "upcoming") {
      // Only the next broadcast counts, and only when it is soon: a schedule
      // abandoned weeks ago, or one days away, is not the next Daily Zikr.
      const start = Date.parse(item.liveStreamingDetails?.scheduledStartTime ?? "");
      if (Number.isFinite(start) && start >= clock - UPCOMING_GRACE_MS && start <= clock + UPCOMING_AHEAD_MS
        && (!upcoming || start < upcoming.start)) {
        upcoming = { id, details: item.liveStreamingDetails, start };
      }
    }
  }
  const candidate = live ? { ...live, state: "live" as const } : upcoming ? { ...upcoming, state: "scheduled" as const } : undefined;

  if (automatic && candidate) {
    const details = candidate.details;
    // The live video alone makes the official broadcast live (the owner's
    // decision, 2026-10-28): nothing else holds it live or ends it.
    await env.DB.prepare(`UPDATE live_broadcasts SET state=?,
      title=?,youtube_video_id=?,youtube_live=?,scheduled_start=?,started_at=COALESCE(?,started_at),ended_at=?,updated_at=?,source_updated_at=? WHERE id='official-live'`)
      .bind(candidate.state, OFFICIAL_LIVE_TITLE, candidate.id, candidate.state === "live" ? 1 : 0, details?.scheduledStartTime ?? null,
        details?.actualStartTime ?? null, details?.actualEndTime ?? null, now, now).run();
    // Alert once when the channel actually goes live (not for upcoming). The
    // event is the video, so a stream that drops out for a minute and comes
    // back is not announced twice.
    if (candidate.state === "live" && prior?.state !== "live") {
      await sendTopicPush(
        env, `youtube-live:${candidate.id}`, "liveZikr",
        "Daily Zikr has started", "Join the official daily zikr in Darul Irfan.",
        "darulirfan://live/official-live", LIVE_ALERT
      );
    }
  } else if (automatic && prior?.state === "live") {
    await env.DB.prepare("UPDATE live_broadcasts SET state='ended',youtube_live=0,ended_at=?,updated_at=?,source_updated_at=? WHERE id='official-live'")
      .bind(now, now, now).run();
  } else if (automatic && prior?.state === "scheduled") {
    await env.DB.prepare("UPDATE live_broadcasts SET state='offline',youtube_video_id=NULL,youtube_live=0,updated_at=?,source_updated_at=? WHERE id='official-live'")
      .bind(now, now).run();
  }
}

export async function refreshFacebook(env: Env): Promise<void> {
  if (!env.FACEBOOK_PAGE_ACCESS_TOKEN) throw new Error("FACEBOOK_PAGE_ACCESS_TOKEN is not configured");
  const fields = "id,message,created_time,permalink_url,full_picture";
  const version = /^v\d+\.\d+$/.test(env.FACEBOOK_GRAPH_VERSION) ? env.FACEBOOK_GRAPH_VERSION : "v25.0";
  const url = `https://graph.facebook.com/${version}/${encodeURIComponent(env.FACEBOOK_PAGE_ID)}/posts?fields=${fields}&limit=20&access_token=${encodeURIComponent(env.FACEBOOK_PAGE_ACCESS_TOKEN)}`;
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Facebook API ${response.status}`);
  const payload = await response.json<FacebookResponse>(); const now = new Date().toISOString();
  for (const post of payload.data ?? []) {
    const message = cleanText(post.message); const sourceURL = validHTTPURL(post.permalink_url);
    if (!post.id || !post.created_time || !sourceURL || !message) continue;
    await env.DB.prepare(`INSERT INTO feed_items(id,source,kind,title,body,source_url,image_url,published_at,raw_json,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,body=excluded.body,image_url=excluded.image_url,updated_at=excluded.updated_at`)
      .bind(`facebook:${post.id}`, "facebook", "post", message.slice(0, 120), message, sourceURL, validHTTPURL(post.full_picture) ?? null,
        post.created_time, JSON.stringify(post), now).run();
  }
}

export async function refreshWebsiteCatalog(env: Env): Promise<void> {
  const base = "https://raw.githubusercontent.com/wali1984/Darul-Irfan/main/content/";
  const manifestResponse = await fetch(`${base}content_manifest.json`);
  if (!manifestResponse.ok) throw new Error(`Website manifest ${manifestResponse.status}`);
  const manifest = await manifestResponse.json<CatalogManifest>();
  const safeFilename = (value: string | undefined, fallback: string): string => value && /^[A-Za-z0-9_.-]+\.json$/.test(value) ? value : fallback;
  const [articlesResponse, eventsResponse] = await Promise.all([
    fetch(`${base}${safeFilename(manifest.files?.articles, "articles.json")}`),
    fetch(`${base}${safeFilename(manifest.files?.events, "events.json")}`)
  ]);
  if (!articlesResponse.ok || !eventsResponse.ok) throw new Error(`Website catalog ${articlesResponse.status}/${eventsResponse.status}`);
  const articles = await articlesResponse.json<CatalogContent[]>();
  const events = await eventsResponse.json<CatalogEvent[]>();
  const now = new Date().toISOString();

  // Every write below goes in one batch, which D1 runs as one transaction: a
  // feed read never finds the website items missing half-way through, and a
  // failure part-way leaves the last good set as it was.
  const writes: D1PreparedStatement[] = [];
  const kept: string[] = [];
  for (const item of articles.slice(0, 100)) {
    const sourceURL = validHTTPURL(item.sourceUrl); const title = cleanText(item.title, 300);
    const publishedAt = catalogTimestamp(item);
    if (!item.id || !sourceURL || !title || !publishedAt) continue;
    const image = (item.mediaUrls ?? []).map(validHTTPURL).find(Boolean);
    kept.push(`website:${item.id}`);
    writes.push(env.DB.prepare(`INSERT INTO feed_items(id,source,kind,title,body,source_url,image_url,published_at,is_hidden,updated_at)
      VALUES(?,?,?,?,?,?,?,?,0,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,body=excluded.body,image_url=excluded.image_url,published_at=excluded.published_at,is_hidden=0,updated_at=excluded.updated_at`)
      .bind(`website:${item.id}`, "website", "post", title, cleanText(item.excerpt) ?? null, sourceURL, image ?? null, publishedAt, now));
  }
  // Existing deployments may contain evergreen pages that older code marked
  // as freshly published on every run. Website rows that are not dated news
  // above are hidden - after the news is written, not before. The native
  // Library keeps carrying the complete evergreen catalog through the content
  // manifest.
  writes.push(env.DB.prepare(`UPDATE feed_items SET is_hidden=1,updated_at=? WHERE source='website' AND is_hidden=0
    AND id NOT IN (SELECT value FROM json_each(?))`).bind(now, JSON.stringify(kept)));
  for (const item of events.slice(0, 100)) {
    const sourceURL = validHTTPURL(item.sourceUrl); const title = cleanText(item.title, 300);
    // Dated by when it happens. One without a readable date is left out
    // rather than stamped with this run's time, which made it look new
    // every fifteen minutes (as undated pages did).
    const publishedAt = catalogTimestamp({ publishedAt: item.startDate, updatedAt: item.updatedAt });
    if (!item.id || !sourceURL || !title || !publishedAt) continue;
    writes.push(env.DB.prepare(`INSERT INTO feed_items(id,source,kind,title,body,source_url,published_at,updated_at)
      VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,body=excluded.body,published_at=excluded.published_at,updated_at=excluded.updated_at`)
      .bind(`event:${item.id}`, "event", "event", title, cleanText(item.details) ?? null, sourceURL, publishedAt, now));
  }
  const contentVersions = { website: Number.isInteger(manifest.version) ? Number(manifest.version) : 0, officialFeed: 1 };
  writes.push(env.DB.prepare(`INSERT INTO app_config(key,value_json,updated_at) VALUES('contentVersions',?,?)
    ON CONFLICT(key) DO UPDATE SET value_json=excluded.value_json,updated_at=excluded.updated_at`)
    .bind(JSON.stringify(contentVersions), now));
  await env.DB.batch(writes);
}
