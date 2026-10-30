// Android phones next to iPhones: registering, being sent the same alerts
// through FCM, being forgotten when FCM says the token is dead - and iPhones
// sent exactly what they were sent before.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { LIVE_ALERT, resetAPNSToken, sendPushToInstallations, sendTopicPush } from "../src/apns";
import { GOOGLE_TOKEN_URL, resetFCMToken } from "../src/fcm";
import { notifyGroup } from "../src/community";
import { sqliteD1 } from "./sqlite-d1";

type Sent = { url: string; headers: Record<string, string>; body: string };

async function p256pem(): Promise<string> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey) as ArrayBuffer);
  let binary = ""; der.forEach(byte => binary += String.fromCharCode(byte));
  return `-----BEGIN PRIVATE KEY-----${btoa(binary)}-----END PRIVATE KEY-----`;
}

/** A service account key as `wrangler secret put` gets it pasted from the
 *  JSON key file: one line, with literal \n. */
async function serviceAccountPEM(): Promise<string> {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true, ["sign", "verify"],
  ) as CryptoKeyPair;
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey) as ArrayBuffer);
  let binary = ""; der.forEach(byte => binary += String.fromCharCode(byte));
  return `-----BEGIN PRIVATE KEY-----\\n${(btoa(binary).match(/.{1,64}/g) ?? []).join("\\n")}\\n-----END PRIVATE KEY-----\\n`;
}

const installation = (n: number) => `22222222-2222-4222-8222-${String(n).padStart(12, "0")}`;
/** FCM tokens: mixed case, with the ':' FCM puts in them. */
const fcmToken = (n: number) => `dQw4w9WgXcQ:APA91bH${String(n).padStart(4, "0")}_Kx-ZyAbCdEfGhIjKlMnOpQrStUvWxYz0123456789aBcDeFgHiJkLmNoPqRsTuVwXyZ`;
const FCM_SEND = "https://fcm.googleapis.com/v1/projects/darul-irfan-test/messages:send";

interface Options {
  /** FCM's answer to one message, by the token it was for. */
  fcmAnswer?: (token: string) => Response;
  /** Leave FCM unconfigured. */
  noFCM?: boolean;
  /** Leave APNs unconfigured. */
  noAPNs?: boolean;
  apnsStatus?: (url: string) => number;
}

async function setup(options: Options = {}) {
  const { db, raw } = sqliteD1();
  const sent: Sent[] = [];
  let exchanges = 0;
  vi.stubGlobal("fetch", async (input: string, init?: RequestInit) => {
    const url = String(input);
    const body = String(init?.body ?? "");
    sent.push({ url, headers: Object.fromEntries(new Headers(init?.headers).entries()), body });
    if (url === GOOGLE_TOKEN_URL) {
      exchanges += 1;
      return Response.json({ access_token: `ya29.access-${exchanges}`, expires_in: 3599, token_type: "Bearer" });
    }
    if (url.startsWith("https://fcm.googleapis.com/")) {
      const token = (JSON.parse(body) as { message: { token: string } }).message.token;
      return options.fcmAnswer?.(token) ?? Response.json({ name: "projects/darul-irfan-test/messages/0:1" });
    }
    if (url.includes("push.apple.com")) return new Response("", { status: options.apnsStatus?.(url) ?? 200 });
    return new Response("{}", { status: 200 });
  });
  const env = {
    DB: db, APNS_TOPIC: "us.naqshbaniaowaisiah", PUBLIC_BASE_URL: "https://api.example.com",
    ...(options.noAPNs ? {} : { APNS_KEY_ID: "KEY", APNS_TEAM_ID: "TEAM", APNS_PRIVATE_KEY: await p256pem() }),
    ...(options.noFCM ? {} : {
      FCM_PROJECT_ID: "darul-irfan-test",
      FCM_CLIENT_EMAIL: "push@darul-irfan-test.iam.gserviceaccount.com",
      FCM_PRIVATE_KEY: await serviceAccountPEM(),
    }),
  } as unknown as Env;
  /** An iPhone as the iOS app has always registered it: no platform given. */
  const iphone = (n: number, topics: string[] = ["liveZikr"]) =>
    raw.prepare(`INSERT INTO devices(installation_id,apns_token,locale,timezone,topics_json,environment,app_version,created_at,last_seen_at)
      VALUES(?,?,'en','UTC',?,'production','1.12',datetime('now'),datetime('now'))`)
      .run(installation(n), installation(n).replace(/-/g, "").padEnd(64, "0"), JSON.stringify(topics));
  const android = (n: number, topics: string[] = ["liveZikr"]) =>
    raw.prepare(`INSERT INTO devices(installation_id,apns_token,locale,timezone,topics_json,environment,app_version,created_at,last_seen_at,platform)
      VALUES(?,?,'en','UTC',?,'production','1.0.0',datetime('now'),datetime('now'),'android')`)
      .run(installation(n), fcmToken(n), JSON.stringify(topics));
  const apns = () => sent.filter(request => request.url.includes("push.apple.com"));
  const fcm = () => sent.filter(request => request.url.startsWith("https://fcm.googleapis.com/"));
  const oauth = () => sent.filter(request => request.url === GOOGLE_TOKEN_URL);
  const google = () => sent.filter(request => request.url.includes("googleapis.com"));
  const messages = () => fcm().map(request => (JSON.parse(request.body) as { message: Record<string, unknown> & { token: string } }).message);
  const health = (source: string) => raw.prepare("SELECT status,last_error FROM source_health WHERE source=?").get(source) as
    { status: string; last_error: string | null } | undefined;
  const deviceCount = (n: number) => (raw.prepare("SELECT COUNT(*) AS n FROM devices WHERE installation_id=?").get(installation(n)) as { n: number }).n;
  return { env, raw, sent, iphone, android, apns, fcm, oauth, google, messages, health, deviceCount };
}

beforeEach(() => { resetAPNSToken(); resetFCMToken(); });
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });

const register = (env: Env, body: Record<string, unknown>, ip = "7.7.7.7") =>
  worker.fetch(new Request("https://api.example.com/v1/devices", {
    method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": ip }, body: JSON.stringify(body),
  }), env);

describe("POST /v1/devices from an Android phone", () => {
  const androidBody = (n: number, extra: Record<string, unknown> = {}) => ({
    platform: "android", installationID: installation(n), token: fcmToken(n), locale: "ur", timeZone: "Asia/Karachi",
    topics: ["liveZikr", "announcements", "unknown-topic"], appVersion: "1.0.0", ...extra,
  });
  interface DeviceRow {
    apns_token: string; platform: string; environment: string; topics_json: string; locale: string; timezone: string; app_version: string;
  }
  const row = (raw: Awaited<ReturnType<typeof setup>>["raw"], n: number) =>
    raw.prepare("SELECT apns_token,platform,environment,topics_json,locale,timezone,app_version FROM devices WHERE installation_id=?")
      .get(installation(n)) as DeviceRow | undefined;

  it("registers the FCM token exactly as sent, as an Android phone", async () => {
    const { env, raw } = await setup();
    const response = await register(env, androidBody(1));
    expect(response.status).toBe(201);
    expect(await response.json()).toEqual({ ok: true });
    expect(row(raw, 1)).toEqual({
      apns_token: fcmToken(1), platform: "android", environment: "production",
      topics_json: JSON.stringify(["liveZikr", "announcements"]), locale: "ur", timezone: "Asia/Karachi", app_version: "1.0.0",
    });
  });

  it("keeps an iPhone's body exactly as it was: no platform, an APNs token, lower-cased", async () => {
    const { env, raw } = await setup();
    const token = "AB".repeat(32);
    const response = await register(env, { installationID: installation(2), apnsToken: token, locale: "en", timeZone: "UTC",
      topics: ["liveZikr"], environment: "sandbox", appVersion: "1.12" });
    expect(response.status).toBe(201);
    expect(await response.json()).toEqual({ ok: true });
    expect(row(raw, 2)).toMatchObject({ apns_token: token.toLowerCase(), platform: "ios", environment: "sandbox" });
    expect((await register(env, { installationID: installation(3), apnsToken: "cd".repeat(32), locale: "en", timeZone: "UTC",
      topics: [], environment: "production", appVersion: "1.12", platform: "ios" })).status).toBe(201);
    expect(row(raw, 3)).toMatchObject({ platform: "ios" });
  });

  it("refuses an Android body without a usable token, and a platform it does not know", async () => {
    const { env } = await setup();
    for (const body of [
      androidBody(4, { token: undefined }),
      androidBody(4, { token: "short" }),
      androidBody(4, { token: `${fcmToken(4)} with spaces` }),
      androidBody(4, { installationID: "not-a-uuid" }),
      androidBody(4, { topics: "liveZikr" }),
      androidBody(4, { environment: "staging" }),
      { ...androidBody(4), platform: "web" },
      // An Android token is not an APNs token, so the iPhone body refuses it.
      { installationID: installation(4), apnsToken: fcmToken(4), locale: "en", timeZone: "UTC", topics: [], environment: "production", appVersion: "1" },
    ]) {
      expect((await register(env, body)).status).toBe(400);
    }
  });

  it("keeps the official topics a Halqah-only registration does not mention, as on iOS", async () => {
    const { env, raw } = await setup();
    await register(env, androidBody(5));
    expect((await register(env, androidBody(5, { topics: [], keepTopics: true }))).status).toBe(201);
    expect(JSON.parse(row(raw, 5)!.topics_json)).toEqual(["liveZikr", "announcements"]);
    await register(env, androidBody(5, { topics: ["events"] }));
    expect(JSON.parse(row(raw, 5)!.topics_json)).toEqual(["events"]);
  });

  it("moves a token to the installation that now holds it", async () => {
    const { env, raw } = await setup();
    await register(env, androidBody(6));
    await register(env, { ...androidBody(7), token: fcmToken(6) });
    expect(row(raw, 6)).toBeUndefined();
    expect(row(raw, 7)).toMatchObject({ apns_token: fcmToken(6), platform: "android" });
  });

  it("forgets the phone when the app turns its alerts off, given the exact token", async () => {
    const { env, raw } = await setup();
    await register(env, androidBody(8));
    const remove = (headers: Record<string, string>) => worker.fetch(new Request(`https://api.example.com/v1/devices/${installation(8)}`, {
      method: "DELETE", headers,
    }), env);
    expect((await remove({})).status).toBe(401);
    // An FCM token's case matters: the same letters in lower case are another token.
    expect((await remove({ "x-push-token": fcmToken(8).toLowerCase() })).status).toBe(204);
    expect(row(raw, 8)).toBeDefined();
    expect((await remove({ "x-push-token": fcmToken(8) })).status).toBe(204);
    expect(row(raw, 8)).toBeUndefined();
    // x-apns-token carries it as well.
    await register(env, androidBody(8));
    expect((await remove({ "x-apns-token": fcmToken(8) })).status).toBe(204);
    expect(row(raw, 8)).toBeUndefined();
  });

  it("still forgets an iPhone by its APNs token in any case", async () => {
    const { env, raw } = await setup();
    const token = "ef".repeat(32);
    await register(env, { installationID: installation(9), apnsToken: token, locale: "en", timeZone: "UTC", topics: [], environment: "production", appVersion: "1" });
    const response = await worker.fetch(new Request(`https://api.example.com/v1/devices/${installation(9)}`, {
      method: "DELETE", headers: { "x-apns-token": token.toUpperCase() },
    }), env);
    expect(response.status).toBe(204);
    expect(row(raw, 9)).toBeUndefined();
  });
});

describe("one alert, sent to each phone by its platform", () => {
  /** What every iPhone has always been sent for this alert. */
  const expectedAPNs = (n: number, title: string, body: string, thread: string, path: string, live: boolean) => ({
    url: `https://api.push.apple.com/3/device/${installation(n).replace(/-/g, "").padEnd(64, "0")}`,
    headerNames: ["apns-priority", "apns-push-type", "apns-topic", "authorization", ...(live ? ["apns-collapse-id", "apns-expiration"] : [])].sort(),
    body: JSON.stringify({ aps: { alert: { title, body }, sound: "default", "thread-id": thread }, path }),
  });

  it("sends iPhones alone exactly the APNs requests they had, and never calls Google", async () => {
    const { env, iphone, apns, google, sent } = await setup();
    for (const n of [1, 2, 3]) iphone(n);
    expect(await sendTopicPush(env, "youtube-live:abc", "liveZikr", "Daily Zikr has started",
      "Join the official daily zikr in Darul Irfan.", "darulirfan://live/official-live", LIVE_ALERT)).toBe(3);
    expect(google()).toHaveLength(0);
    expect(sent).toHaveLength(3);
    for (const [index, n] of [1, 2, 3].entries()) {
      const request = apns()[index]!;
      const expected = expectedAPNs(n, "Daily Zikr has started", "Join the official daily zikr in Darul Irfan.", "liveZikr",
        "darulirfan://live/official-live", true);
      expect(request.url).toBe(expected.url);
      expect(Object.keys(request.headers).sort()).toEqual(expected.headerNames);
      expect(request.headers).toMatchObject({
        "apns-topic": "us.naqshbaniaowaisiah", "apns-push-type": "alert", "apns-priority": "10", "apns-collapse-id": "live-zikr",
      });
      expect(request.headers.authorization).toMatch(/^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
      expect(request.body).toBe(expected.body);
    }
  });

  it("sends Android phones the same title, body and deep link through FCM, and iPhones as before", async () => {
    const { env, iphone, android, apns, fcm, oauth, messages, raw, health } = await setup();
    iphone(1); android(2); iphone(3); android(4);
    // A phone subscribed to something else is not sent this one.
    android(5, ["events"]);
    expect(await sendTopicPush(env, "youtube-live:abc", "liveZikr", "Daily Zikr has started",
      "Join the official daily zikr in Darul Irfan.", "darulirfan://live/official-live", LIVE_ALERT)).toBe(4);

    expect(apns().map(request => request.url)).toEqual([expectedAPNs(1, "", "", "", "", true).url, expectedAPNs(3, "", "", "", "", true).url]);
    expect(apns()[0]!.body).toBe(expectedAPNs(1, "Daily Zikr has started", "Join the official daily zikr in Darul Irfan.", "liveZikr",
      "darulirfan://live/official-live", true).body);

    expect(oauth()).toHaveLength(1);
    expect(fcm().map(request => request.url)).toEqual([FCM_SEND, FCM_SEND]);
    expect(fcm()[0]!.headers.authorization).toBe("Bearer ya29.access-1");
    expect(fcm()[0]!.headers["content-type"]).toContain("application/json");
    expect(messages()).toEqual([2, 4].map(n => ({
      token: fcmToken(n),
      notification: { title: "Daily Zikr has started", body: "Join the official daily zikr in Darul Irfan." },
      android: {
        priority: "high", ttl: "1800s", collapse_key: "live-zikr",
        notification: { channel_id: "daily_zikr_live", sound: "default", tag: "live-zikr" },
      },
      data: { path: "darulirfan://live/official-live", eventID: "youtube-live:abc", topic: "liveZikr" },
    })));
    expect(raw.prepare("SELECT COUNT(*) AS n FROM notification_deliveries WHERE event_id='youtube-live:abc' AND status='accepted'").get())
      .toEqual({ n: 4 });
    expect(health("fcm")).toEqual({ status: "healthy", last_error: null });
    expect(health("apns")).toEqual({ status: "healthy", last_error: null });

    // The same event again reaches nobody twice.
    expect(await sendTopicPush(env, "youtube-live:abc", "liveZikr", "Daily Zikr has started",
      "Join the official daily zikr in Darul Irfan.", "darulirfan://live/official-live", LIVE_ALERT)).toBe(0);
    expect(fcm()).toHaveLength(2);
    expect(apns()).toHaveLength(2);
  });

  it("reuses one access token across alerts", async () => {
    const { env, android, oauth, fcm } = await setup();
    android(1, ["announcements"]);
    await sendTopicPush(env, "a", "announcements", "One", "Body", "darulirfan://feed");
    await sendTopicPush(env, "b", "announcements", "Two", "Body", "darulirfan://feed");
    expect(fcm()).toHaveLength(2);
    expect(oauth()).toHaveLength(1);
  });

  it("sends a Halqah's notice to its Android members in the Halqah channel", async () => {
    const { env, raw, iphone, android, apns, messages } = await setup();
    iphone(1, []); android(2, []);
    const now = new Date().toISOString();
    for (const [member, n] of [["a".repeat(32), 1], ["b".repeat(32), 2]] as const) {
      raw.prepare("INSERT INTO members(id,apple_subject,created_at,last_seen_at) VALUES(?,?,?,?)").run(member, `s-${member}`, now, now);
      raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by) VALUES('usa',?,?,'t')").run(member, now);
      // The app links its installation id; the server keeps it upper-cased.
      raw.prepare("INSERT INTO member_devices(member_id,installation_id,updated_at) VALUES(?,?,?)").run(member, installation(n).toUpperCase(), now);
    }
    expect(await notifyGroup(env, "usa", "post:p1", "Friday", "After Isha", "darulirfan://groups/usa")).toBe(2);
    expect(apns()).toHaveLength(1);
    expect(apns()[0]!.headers["apns-collapse-id"]).toBeUndefined();
    expect(messages()).toEqual([{
      token: fcmToken(2),
      notification: { title: "Friday", body: "After Isha" },
      android: { priority: "high", notification: { channel_id: "halqah_notifications", sound: "default" } },
      data: { path: "darulirfan://groups/usa", eventID: "post:p1", topic: "group:usa" },
    }]);
  });

  it("sends official broadcasts in the official channel", async () => {
    const { env, android, messages } = await setup();
    android(1, ["announcements"]);
    expect(await sendTopicPush(env, "notice-1", "announcements", "Monthly Ijtema", "This Sunday", "darulirfan://events")).toBe(1);
    expect(messages()[0]!.android).toEqual({ priority: "high", notification: { channel_id: "official_alerts", sound: "default" } });
  });

  it("skips Android phones quietly while FCM is not configured, and sends the iPhones", async () => {
    const { env, iphone, android, apns, google, health } = await setup({ noFCM: true });
    iphone(1); android(2);
    const log = vi.spyOn(console, "log").mockImplementation(() => undefined);
    expect(await sendTopicPush(env, "e1", "liveZikr", "Daily Zikr has started", "Join", "darulirfan://live/official-live")).toBe(1);
    expect(apns()).toHaveLength(1);
    expect(google()).toHaveLength(0);
    expect(log.mock.calls.some(call => String(call[0]).includes("FCM is not configured"))).toBe(true);
    // Nothing is degraded: an unconfigured FCM is not a failure.
    expect(health("fcm")).toBeUndefined();
    expect(health("apns")).toEqual({ status: "healthy", last_error: null });
    log.mockRestore();
  });

  it("still sends the Android phones when APNs credentials are missing, then reports APNs as before", async () => {
    const { env, iphone, android, fcm, health } = await setup({ noAPNs: true });
    iphone(1); android(2);
    await expect(sendTopicPush(env, "e2", "liveZikr", "Daily Zikr has started", "Join", "darulirfan://live/official-live"))
      .rejects.toThrow("APNs credentials are incomplete");
    expect(fcm()).toHaveLength(1);
    expect(health("apns")?.status).toBe("degraded");
    expect(health("fcm")?.status).toBe("healthy");
  });

  it("throws for missing APNs credentials exactly as before when there are only iPhones", async () => {
    const { env, iphone, google } = await setup({ noAPNs: true });
    iphone(1);
    await expect(sendPushToInstallations(env, "post:x", "group:usa", [installation(1)], "t", "b", "darulirfan://groups/usa"))
      .rejects.toThrow("APNs credentials are incomplete");
    expect(google()).toHaveLength(0);
  });

  it("keeps the iPhones going when Google refuses the service account, and records FCM as degraded", async () => {
    const { env, iphone, android, apns, fcm, health, sent } = await setup();
    iphone(1); android(2);
    vi.stubGlobal("fetch", async (input: string, init?: RequestInit) => {
      const url = String(input);
      sent.push({ url, headers: {}, body: String(init?.body ?? "") });
      if (url === GOOGLE_TOKEN_URL) return Response.json({ error: "invalid_grant", error_description: "Invalid JWT Signature." }, { status: 400 });
      return new Response("", { status: 200 });
    });
    const error = vi.spyOn(console, "error").mockImplementation(() => undefined);
    expect(await sendTopicPush(env, "e3", "liveZikr", "Daily Zikr has started", "Join", "darulirfan://live/official-live")).toBe(1);
    expect(apns()).toHaveLength(1);
    expect(fcm()).toHaveLength(0);
    expect(health("fcm")?.status).toBe("degraded");
    expect(health("fcm")?.last_error).toContain("invalid_grant");
    error.mockRestore();
  });
});

describe("dead Android tokens", () => {
  const status = (code: number, statusText: string, message: string, details: unknown[]) =>
    Response.json({ error: { code, message, status: statusText, details } }, { status: code });
  const fcmCode = (errorCode: string) => ({ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode });

  it("forgets a phone FCM calls UNREGISTERED or not a token, and keeps the rest", async () => {
    const answers: Record<number, () => Response> = {
      2: () => status(404, "NOT_FOUND", "Requested entity was not found.", [fcmCode("UNREGISTERED")]),
      3: () => status(400, "INVALID_ARGUMENT", "The registration token is not a valid FCM registration token", [fcmCode("INVALID_ARGUMENT")]),
      4: () => status(400, "INVALID_ARGUMENT", "Invalid value at 'message.android.ttl'",
        [{ "@type": "type.googleapis.com/google.rpc.BadRequest", fieldViolations: [{ field: "message.android.ttl", description: "Invalid value" }] }]),
      5: () => status(503, "UNAVAILABLE", "The service is currently unavailable.", [fcmCode("UNAVAILABLE")]),
    };
    const byToken = new Map(Object.entries(answers).map(([n, answer]) => [fcmToken(Number(n)), answer]));
    const { env, raw, iphone, android, deviceCount, health, fcm } = await setup({
      fcmAnswer: token => byToken.get(token)?.() ?? Response.json({ name: "projects/darul-irfan-test/messages/0:2" }),
    });
    iphone(1); for (const n of [2, 3, 4, 5, 6]) android(n);
    expect(await sendTopicPush(env, "e4", "liveZikr", "Daily Zikr has started", "Join", "darulirfan://live/official-live")).toBe(2);
    expect([1, 2, 3, 4, 5, 6].map(deviceCount)).toEqual([1, 0, 0, 1, 1, 1]);
    // Two real failures; the two dead phones are not failures.
    expect(health("fcm")?.status).toBe("degraded");
    expect(health("fcm")?.last_error).toMatch(/^2 FCM deliveries failed/);
    expect(raw.prepare("SELECT installation_id,status,response_code FROM notification_deliveries WHERE event_id='e4' ORDER BY installation_id").all())
      .toEqual([
        { installation_id: installation(1), status: "accepted", response_code: 200 },
        { installation_id: installation(4), status: "failed", response_code: 400 },
        { installation_id: installation(5), status: "failed", response_code: 503 },
        { installation_id: installation(6), status: "accepted", response_code: 200 },
      ]);
    // Sent again, the event reaches only the two that failed.
    byToken.clear();
    expect(await sendTopicPush(env, "e4", "liveZikr", "Daily Zikr has started", "Join", "darulirfan://live/official-live")).toBe(2);
    expect(fcm().slice(5).map(request => (JSON.parse(request.body) as { message: { token: string } }).message.token))
      .toEqual([fcmToken(4), fcmToken(5)]);
    expect(health("fcm")).toEqual({ status: "healthy", last_error: null });
  });

  it("does not forget a phone that registered a new token while the alert was going out", async () => {
    let raw!: Awaited<ReturnType<typeof setup>>["raw"];
    const context = await setup({
      fcmAnswer: token => {
        // The app reinstalled and registered again before FCM answered.
        raw.prepare("UPDATE devices SET apns_token=? WHERE apns_token=?").run(fcmToken(99), token);
        return status(404, "NOT_FOUND", "Requested entity was not found.", [fcmCode("UNREGISTERED")]);
      },
    });
    raw = context.raw;
    context.android(2);
    expect(await sendTopicPush(context.env, "e5", "liveZikr", "t", "b", "darulirfan://zikr")).toBe(0);
    expect(context.deviceCount(2)).toBe(1);
  });

  it("asks for a new access token after FCM refuses the one it has", async () => {
    let refuse = true;
    const { env, android, oauth, fcm } = await setup({
      fcmAnswer: () => refuse
        ? status(401, "UNAUTHENTICATED", "Request had invalid authentication credentials.", [])
        : Response.json({ name: "projects/darul-irfan-test/messages/0:3" }),
    });
    android(2);
    expect(await sendTopicPush(env, "e6", "liveZikr", "t", "b", "darulirfan://zikr")).toBe(0);
    refuse = false;
    expect(await sendTopicPush(env, "e7", "liveZikr", "t", "b", "darulirfan://zikr")).toBe(1);
    expect(oauth()).toHaveLength(2);
    expect(fcm().map(request => request.headers.authorization)).toEqual(["Bearer ya29.access-1", "Bearer ya29.access-2"]);
  });
});
