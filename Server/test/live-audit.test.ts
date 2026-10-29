// Fixes from the October 2026 audit (SCRATCH ios-live.md): the dates the
// public API sends, how the official broadcast follows YouTube, and how
// alerts are sent.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { reconcileLive } from "../src/live";
import { refreshPaltalkRoom } from "../src/paltalkRoom";
import { refreshWebsiteCatalog, refreshYouTube } from "../src/sources";
import { autoplayDue } from "../src/session";
import { notifyGroup } from "../src/community";
import { resetAPNSToken, sendPushToInstallations, sendTopicPush } from "../src/apns";
import { sqliteD1 } from "./sqlite-d1";

const WHOLE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;

type Sent = { url: string; headers: Record<string, string>; body: string };

/** A throwaway P-256 key, so APNs provider tokens can be signed. */
async function p256pem(): Promise<string> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey) as ArrayBuffer);
  let binary = ""; der.forEach(byte => binary += String.fromCharCode(byte));
  return `-----BEGIN PRIVATE KEY-----${btoa(binary)}-----END PRIVATE KEY-----`;
}

/** A database, APNs credentials and a network stand-in that records every
 *  request; `answer` decides what each one gets back. */
async function setup(answer: (url: string) => Response | Promise<Response> = () => new Response("{}", { status: 200 })) {
  const { db, raw } = sqliteD1();
  const sent: Sent[] = [];
  vi.stubGlobal("fetch", async (input: string, init?: RequestInit) => {
    const url = String(input);
    sent.push({ url, headers: Object.fromEntries(new Headers(init?.headers).entries()), body: String(init?.body ?? "") });
    return answer(url);
  });
  const env = {
    DB: db, APNS_TOPIC: "us.naqshbaniaowaisiah", PUBLIC_BASE_URL: "https://api.example.com", FACEBOOK_GRAPH_VERSION: "v25.0",
    YOUTUBE_API_KEY: "k", YOUTUBE_CHANNEL_ID: "UCefP_tP1ROXmqu2miDVCtCg", PALTALK_ROOM: "oursheikh", PALTALK_GROUP_ID: "463712",
    APNS_KEY_ID: "KEY", APNS_TEAM_ID: "TEAM", APNS_PRIVATE_KEY: await p256pem(),
    LISTENER_TOKEN: "listener-secret", LIVE_CUE_HOSTS: "ameer_imam",
  } as unknown as Env;
  const device = (id: string, topics: string[] = ["liveZikr"], environment = "production") =>
    raw.prepare(`INSERT INTO devices(installation_id,apns_token,locale,timezone,topics_json,environment,app_version,created_at,last_seen_at)
      VALUES(?,?,'en','UTC',?,?,'1',datetime('now'),datetime('now'))`)
      .run(id, id.replace(/-/g, "").padEnd(64, "0"), JSON.stringify(topics), environment);
  const apns = () => sent.filter(request => request.url.includes("push.apple.com"));
  return { env, raw, sent, device, apns };
}

/** Installation ids that differ only in their last digits. */
const installation = (n: number) => `11111111-1111-4111-8111-${String(n).padStart(12, "0")}`;

beforeEach(() => resetAPNSToken());
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });

describe("LIVE-001: the public API sends whole-second dates", () => {
  async function seeded() {
    const context = await setup();
    const { raw } = context;
    const started = new Date(Date.now() - 10 * 60_000).toISOString(); // with milliseconds, as stored
    raw.prepare(`UPDATE live_broadcasts SET state='live',started_at=?,updated_at='2026-10-29T00:24:00.011Z',
      scheduled_start='2026-10-28T16:00:00.500Z',youtube_video_id='abcdefghijk',paltalk_url='https://paltalk.im/egnMPD3Y' WHERE id='official-live'`)
      .run(started);
    raw.prepare("INSERT INTO app_config(key,value_json,updated_at) VALUES('liveCue',?,datetime('now'))")
      .run(JSON.stringify({ text: "L-3", sender: "ameer_imam", at: new Date(Date.now() - 60_000).toISOString() }));
    raw.prepare("INSERT INTO app_config(key,value_json,updated_at) VALUES('paltalkRoom',?,datetime('now'))")
      .run(JSON.stringify({ online: true, listeners: 12, since: "2026-10-28T23:01:05.120Z", checkedAt: "2026-10-28T23:05:00.999Z" }));
    const feed = raw.prepare(`INSERT INTO feed_items(id,source,kind,title,source_url,published_at,updated_at)
      VALUES(?,?,?,?,'https://www.naqshbandiaowaisiah.org/x',?,datetime('now'))`);
    feed.run("youtube:abcdefghijk", "youtube", "video", "Online Zikr", "2026-10-28T16:06:07Z");
    feed.run("website:announcement-4276", "website", "post", "Announcement", "2026-09-05T00:00:00.000Z");
    feed.run("website:article-2", "website", "post", "Article", "2026-09-04T10:30:00.250Z");
    feed.run("event:seminar-1", "event", "event", "Seminar", "2026-09-06T00:00:00Z");
    feed.run("website:broken", "website", "post", "Undated", "sometime");
    return context;
  }
  const get = async (env: Env, path: string) => {
    const response = await worker.fetch(new Request(`https://api.example.com${path}`), env);
    expect(response.status).toBe(200);
    return response.text();
  };

  it("sends /v1/live with no milliseconds anywhere, the cue and the room included", async () => {
    const { env } = await seeded();
    const text = await get(env, "/v1/live");
    expect(text).not.toMatch(/\.\d{3}Z/);
    const live = JSON.parse(text) as Record<string, unknown> & { cue: { at: string }; room: { since: string } };
    for (const field of ["updatedAt", "startedAt", "scheduledStart"]) expect(live[field]).toMatch(WHOLE);
    expect(live.updatedAt).toBe("2026-10-29T00:24:00Z");
    expect(live.cue.at).toMatch(WHOLE);
    expect(live.room.since).toBe("2026-10-28T23:01:05Z");
  });

  it("sends /v1/bootstrap with whole-second dates, its live broadcast included", async () => {
    const { env } = await seeded();
    const text = await get(env, "/v1/bootstrap");
    expect(text).not.toMatch(/\.\d{3}Z/);
    const value = JSON.parse(text) as { generatedAt: string; live: { updatedAt: string } };
    expect(value.generatedAt).toMatch(WHOLE);
    expect(value.live.updatedAt).toMatch(WHOLE);
  });

  it("sends /v1/feed with whole-second dates, leaves out an undatable item, and still pages by the stored values", async () => {
    const { env } = await seeded();
    const first = JSON.parse(await get(env, "/v1/feed?limit=2")) as { items: { id: string; publishedAt: string }[]; nextCursor?: string };
    // "sometime" sorts first and takes a place on the first page, but is not sent.
    expect(first.items.map(item => item.id)).toEqual(["youtube:abcdefghijk"]);
    expect(first.nextCursor).toBeDefined();
    const ids = [...first.items.map(item => item.id)];
    let cursor = first.nextCursor;
    const dates = [...first.items.map(item => item.publishedAt)];
    while (cursor) {
      const page = JSON.parse(await get(env, `/v1/feed?limit=2&cursor=${encodeURIComponent(cursor)}`)) as typeof first;
      ids.push(...page.items.map(item => item.id));
      dates.push(...page.items.map(item => item.publishedAt));
      cursor = page.nextCursor;
    }
    expect(ids).toEqual(["youtube:abcdefghijk", "event:seminar-1", "website:announcement-4276", "website:article-2"]);
    for (const date of dates) expect(date).toMatch(WHOLE);
    expect(dates).toContain("2026-09-05T00:00:00Z");
  });
});

type Video = { id: string; content: "live" | "upcoming" | "none"; scheduled?: string; started?: string };

/** YouTube's uploads list and videos, in the order given. */
function youtube(videos: () => Video[]) {
  return (url: string): Response => {
    if (url.includes("/playlistItems")) {
      return new Response(JSON.stringify({ items: videos().map(video => ({ contentDetails: { videoId: video.id } })) }));
    }
    if (url.includes("/videos")) {
      return new Response(JSON.stringify({ items: videos().map(video => ({
        id: video.id,
        snippet: { title: `Online Zikr ${video.id}`, publishedAt: "2026-10-28T16:00:00Z", liveBroadcastContent: video.content },
        liveStreamingDetails: { scheduledStartTime: video.scheduled, actualStartTime: video.started },
      })) }));
    }
    return new Response("{}", { status: 200 });
  };
}

const broadcast = (raw: Awaited<ReturnType<typeof setup>>["raw"]) =>
  raw.prepare("SELECT state,youtube_video_id,youtube_live FROM live_broadcasts WHERE id='official-live'").get() as
    { state: string; youtube_video_id: string | null; youtube_live: number };

describe("LIVE-009: the official broadcast follows the live video, or the next one if it is soon", () => {
  const at = (time: string) => { vi.useFakeTimers({ toFake: ["Date"] }); vi.setSystemTime(new Date(time)); };

  it("takes the live video even when tomorrow's scheduled stream is listed first", async () => {
    at("2026-10-28T16:30:00Z");
    const { env, raw } = await setup(youtube(() => [
      { id: "tomorrow001", content: "upcoming", scheduled: "2026-10-29T16:00:00Z" },
      { id: "todaylive01", content: "live", started: "2026-10-28T16:02:00Z" },
    ]));
    await refreshYouTube(env);
    expect(broadcast(raw)).toEqual({ state: "live", youtube_video_id: "todaylive01", youtube_live: 1 });
  });

  it("ignores a scheduled stream that never started weeks ago, and one days away", async () => {
    at("2026-10-28T12:00:00Z");
    let videos: Video[] = [{ id: "soon0000001", content: "upcoming", scheduled: "2026-10-28T16:00:00Z" }];
    const { env, raw } = await setup(youtube(() => videos));
    await refreshYouTube(env);
    expect(broadcast(raw)).toMatchObject({ state: "scheduled", youtube_video_id: "soon0000001" });
    // The same stream abandoned: weeks later it no longer counts, and the card goes off air.
    at("2026-11-20T12:00:00Z");
    await refreshYouTube(env);
    expect(broadcast(raw).state).toBe("offline");
    videos = [{ id: "later000001", content: "upcoming", scheduled: "2026-11-23T16:00:00Z" }];
    await refreshYouTube(env);
    expect(broadcast(raw).state).toBe("offline");
  });

  it("counts a stream scheduled within the next day, and the sooner of two", async () => {
    at("2026-10-28T13:00:00Z");
    const { env, raw } = await setup(youtube(() => [
      { id: "evening0002", content: "upcoming", scheduled: "2026-10-29T12:00:00Z" },
      { id: "evening0001", content: "upcoming", scheduled: "2026-10-28T16:00:00Z" },
    ]));
    await refreshYouTube(env);
    expect(broadcast(raw)).toMatchObject({ state: "scheduled", youtube_video_id: "evening0001", youtube_live: 0 });
  });
});

describe("LIVE-010 / LIVE-027: one alert per broadcast, which expires and replaces the last", () => {
  it("announces a live stream that drops out for a minute and comes back once", async () => {
    let content: Video["content"] = "live";
    const { env, device, apns } = await setup(youtube(() => [{ id: "todaylive01", content, started: "2026-10-28T16:02:00Z" }]));
    device(installation(1));
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-10-28T16:03:00Z")); await refreshYouTube(env);
    content = "none"; vi.setSystemTime(new Date("2026-10-28T16:04:00Z")); await refreshYouTube(env);
    content = "live"; vi.setSystemTime(new Date("2026-10-28T16:05:00Z")); await refreshYouTube(env);
    expect(apns()).toHaveLength(1);
    const headers = apns()[0]!.headers;
    expect(headers["apns-collapse-id"]).toBe("live-zikr");
    expect(Number(headers["apns-expiration"])).toBe(Math.floor(Date.parse("2026-10-28T16:03:00Z") / 1000) + 1_800);
  });

  it("announces the Tahajjud room once a night, even when it flickers in Paltalk's directory", async () => {
    let open = true;
    const { env, device, apns } = await setup(url => url.startsWith("https://www.paltalk.com/")
      ? new Response(JSON.stringify({ data: { topRoomDetails: open ? [{ id: 463712, groupName: "OURSHEIKH", online: true, liveMemberCount: 40 }] : [] } }))
      : new Response("{}", { status: 200 }));
    device(installation(2));
    for (const [time, isOpen] of [["2026-10-28T23:00:00Z", true], ["2026-10-28T23:01:00Z", false], ["2026-10-28T23:02:00Z", true]] as const) {
      open = isOpen;
      await refreshPaltalkRoom(env, new Date(time));
      await reconcileLive(env, new Date(time));
    }
    expect(apns().map(request => JSON.parse(request.body).aps.alert.title)).toEqual(["Tahajjud Zikr has started"]);
    expect(apns()[0]!.headers["apns-collapse-id"]).toBe("live-zikr");
  });
});

describe("LIVE-017 / LIVE-018: sending to many phones", () => {
  it("sends to every subscribed phone once, records each, and never twice for one event", async () => {
    const { env, raw, device, apns } = await setup();
    for (let n = 1; n <= 45; n += 1) device(installation(n));
    expect(await sendTopicPush(env, "event-1", "liveZikr", "Daily Zikr has started", "Join", "darulirfan://live/official-live")).toBe(45);
    expect(apns()).toHaveLength(45);
    expect(raw.prepare("SELECT COUNT(*) AS n FROM notification_deliveries WHERE event_id='event-1' AND status='accepted'").get()).toEqual({ n: 45 });
    expect(await sendTopicPush(env, "event-1", "liveZikr", "Daily Zikr has started", "Join", "darulirfan://live/official-live")).toBe(0);
    expect(apns()).toHaveLength(45);
  });

  it("finds a large Halqah's phones in a few lookups, and forgets a phone APNs says is gone", async () => {
    const gone = installation(7);
    const { env, raw, device, apns } = await setup(url => new Response("", { status: url.includes(gone.replace(/-/g, "")) ? 410 : 200 }));
    const ids = Array.from({ length: 95 }, (_, index) => installation(index + 1));
    for (const id of ids) device(id, []);
    expect(await sendPushToInstallations(env, "post:1", "group:usa", [...ids, ids[0]!], "New post", "", "darulirfan://groups/usa")).toBe(94);
    expect(apns()).toHaveLength(95);
    expect(raw.prepare("SELECT COUNT(*) AS n FROM devices WHERE installation_id=?").get(gone)).toEqual({ n: 0 });
    // A group post is not a live alert: it keeps no expiry and replaces nothing.
    expect(apns()[0]!.headers["apns-collapse-id"]).toBeUndefined();
    expect(apns()[0]!.headers["apns-expiration"]).toBeUndefined();
  });

  it("signs one provider token and reuses it, renewing it after 50 minutes or when APNs refuses it", async () => {
    let status = 200;
    const { env, device, apns } = await setup(() => new Response("", { status }));
    device(installation(1));
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-10-28T16:00:00Z"));
    await sendTopicPush(env, "a", "liveZikr", "t", "b", "darulirfan://zikr");
    vi.setSystemTime(new Date("2026-10-28T16:01:00Z"));
    await sendTopicPush(env, "b", "liveZikr", "t", "b", "darulirfan://zikr");
    const tokens = () => apns().map(request => request.headers.authorization);
    expect(tokens()[1]).toBe(tokens()[0]);
    vi.setSystemTime(new Date("2026-10-28T16:52:00Z"));
    await sendTopicPush(env, "c", "liveZikr", "t", "b", "darulirfan://zikr");
    expect(tokens()[2]).not.toBe(tokens()[1]);
    status = 403;
    await sendTopicPush(env, "d", "liveZikr", "t", "b", "darulirfan://zikr");
    status = 200;
    vi.setSystemTime(new Date("2026-10-28T16:53:00Z"));
    await sendTopicPush(env, "e", "liveZikr", "t", "b", "darulirfan://zikr");
    expect(tokens()[4]).not.toBe(tokens()[3]);
  });
});

describe("LIVE-023 / LIVE-027: a host's cue", () => {
  it("names the session by Pakistan time and replaces the last cue on the phone", async () => {
    const { env, raw, device, apns } = await setup();
    device(installation(1));
    raw.prepare("UPDATE live_broadcasts SET title='Online Zikr with Sheikh-ul-Mukarram Hazrat Ameer Abdul Qadeer Awan MZA' WHERE id='official-live'").run();
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-10-28T23:30:00Z")); // 04:30 in Pakistan
    const response = await worker.fetch(new Request("https://api.example.com/v1/live/cue", {
      method: "POST", headers: { authorization: "Bearer listener-secret", "content-type": "application/json" },
      body: JSON.stringify({ sender: "ameer_imam", text: "L-3" }),
    }), env);
    expect(await response.json()).toEqual({ ok: true, sent: true });
    const alert = JSON.parse(apns()[0]!.body).aps.alert;
    expect(alert).toEqual({ title: "L-3", body: "Tahajjud Zikr" });
    expect(apns()[0]!.headers["apns-collapse-id"]).toBe("live-cue");
    expect(apns()[0]!.headers["apns-expiration"]).toBeDefined();
  });

  it("keeps group notices without an expiry", async () => {
    const { env, raw, device, apns } = await setup();
    device(installation(3), []);
    const now = new Date().toISOString();
    raw.prepare("INSERT INTO members(id,apple_subject,created_at,last_seen_at) VALUES(?,?,?,?)").run("m".repeat(32), "s", now, now);
    raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by) VALUES('usa',?,?,'t')").run("m".repeat(32), now);
    raw.prepare("INSERT INTO member_devices(member_id,installation_id,updated_at) VALUES(?,?,?)").run("m".repeat(32), installation(3).toUpperCase(), now);
    expect(await notifyGroup(env, "usa", "post:x", "Friday", "After Isha", "darulirfan://groups/usa")).toBe(1);
    expect(apns()[0]!.headers["apns-expiration"]).toBeUndefined();
  });
});

describe("LIVE-020: a zikr set just before midnight starts by itself", () => {
  const zikr = (raw: Awaited<ReturnType<typeof setup>>["raw"], weekdays: number[]) => {
    raw.prepare(`INSERT INTO group_zikr_sessions(id,group_id,title,weekdays_json,start_hour,start_minute,time_zone,anchor,duration_minutes,is_active,updated_at,autoplay_json)
      VALUES('late','usa','Late zikr',?,23,58,'UTC',NULL,30,1,datetime('now'),?)`)
      .run(JSON.stringify(weekdays), JSON.stringify([{ kind: "video", id: "abcdefghijk", title: "Recorded zikr", durationSeconds: 600 }]));
  };
  const live = (raw: Awaited<ReturnType<typeof setup>>["raw"]) =>
    (raw.prepare("SELECT state FROM group_live WHERE group_id='usa'").get() as { state: string } | undefined)?.state;

  it("starts a 23:58 zikr on the 00:00 tick, as that evening's zikr", async () => {
    const { env, raw } = await setup();
    zikr(raw, [4]); // Wednesday 2026-10-28
    await autoplayDue(env, new Date("2026-10-28T23:55:00Z"));
    expect(live(raw)).toBeUndefined();
    await autoplayDue(env, new Date("2026-10-29T00:00:00Z")); // Thursday 00:00, two minutes late
    expect(live(raw)).toBe("live");
  });

  it("checks the day the zikr was set for, not the day after midnight", async () => {
    const { env, raw } = await setup();
    zikr(raw, [5]); // Thursday only: Wednesday night's 23:58 is not it
    await autoplayDue(env, new Date("2026-10-29T00:00:00Z"));
    expect(live(raw)).toBeUndefined();
    await autoplayDue(env, new Date("2026-10-30T00:00:00Z")); // Thursday's 23:58, on Friday's first tick
    expect(live(raw)).toBe("live");
  });
});

describe("LIVE-031: the website's items never vanish from the feed while it refreshes", () => {
  const catalog = (articles: unknown[], events: unknown[], fail = false) => (url: string) => {
    if (url.endsWith("content_manifest.json")) return new Response(JSON.stringify({ version: 4 }));
    if (url.endsWith("articles.json")) return fail ? new Response("", { status: 500 }) : new Response(JSON.stringify(articles));
    if (url.endsWith("events.json")) return new Response(JSON.stringify(events));
    return new Response("{}", { status: 200 });
  };
  const visible = (raw: Awaited<ReturnType<typeof setup>>["raw"]) =>
    (raw.prepare("SELECT id,published_at FROM feed_items WHERE is_hidden=0 ORDER BY id").all() as { id: string; published_at: string }[]);
  const article = (id: string, publishedAt?: string) => ({ id, title: id, sourceUrl: `https://www.naqshbandiaowaisiah.org/${id}`, publishedAt });

  it("hides only what left the catalogue, dates everything in whole seconds, and skips the undated", async () => {
    let articles = [article("a", "2026-09-05T00:00:00.000Z"), article("b", "2026-09-04T10:00:00Z"), article("evergreen")];
    const events = [
      { id: "seminar-1", title: "Seminar", sourceUrl: "https://www.naqshbandiaowaisiah.org/s1", startDate: "2026-09-06T00:00:00Z" },
      { id: "undated", title: "Monthly Ijtema", sourceUrl: "https://www.naqshbandiaowaisiah.org/ijtema" },
    ];
    const { env, raw } = await setup(url => catalog(articles, events)(url));
    await refreshWebsiteCatalog(env);
    expect(visible(raw)).toEqual([
      { id: "event:seminar-1", published_at: "2026-09-06T00:00:00Z" },
      { id: "website:a", published_at: "2026-09-05T00:00:00Z" },
      { id: "website:b", published_at: "2026-09-04T10:00:00Z" },
    ]);
    articles = [article("a", "2026-09-05T00:00:00.000Z")];
    await refreshWebsiteCatalog(env);
    expect(visible(raw).map(row => row.id)).toEqual(["event:seminar-1", "website:a"]);
    expect(raw.prepare("SELECT is_hidden FROM feed_items WHERE id='website:b'").get()).toEqual({ is_hidden: 1 });
  });

  it("leaves the feed as it was when the catalogue cannot be read", async () => {
    let fail = false;
    const { env, raw } = await setup(url => catalog([article("a", "2026-09-05T00:00:00Z")], [], fail)(url));
    await refreshWebsiteCatalog(env);
    fail = true;
    await expect(refreshWebsiteCatalog(env)).rejects.toThrow();
    expect(visible(raw).map(row => row.id)).toEqual(["website:a"]);
  });
});

describe("LIVE-025: the public health check", () => {
  it("says only whether all is well", async () => {
    const { env, raw } = await setup();
    raw.prepare(`INSERT INTO source_health(source,status,last_attempt_at,consecutive_failures,last_error)
      VALUES('website','healthy','2026-10-28T00:00:00Z',0,NULL)`).run();
    const healthy = await worker.fetch(new Request("https://api.example.com/health"), env);
    expect(healthy.status).toBe(200);
    expect(await healthy.json()).toEqual({ ok: true });
    raw.prepare("UPDATE source_health SET status='degraded',last_error='YouTube videos 403: quota' WHERE source='website'").run();
    const degraded = await worker.fetch(new Request("https://api.example.com/health"), env);
    expect(degraded.status).toBe(503);
    const text = await degraded.text();
    expect(JSON.parse(text)).toEqual({ ok: false });
    expect(text).not.toContain("quota");
  });
});
