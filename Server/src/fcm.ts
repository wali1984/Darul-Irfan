import type { Env } from "./contracts";
import type { PushOptions } from "./apns";
import { base64url, inParallel } from "./util";

// Android alerts through Firebase Cloud Messaging's HTTP v1 API, authorised by
// a Google service account (FCM_PROJECT_ID, FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY).
// No Firebase SDK: a JWT signed with the service account's key is exchanged
// for an OAuth access token, and each phone is sent its own message, as each
// iPhone is sent its own APNs request.

export const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
export const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
export const fcmSendURL = (projectID: string): string =>
  `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectID)}/messages:send`;

/** The Android app's notification channels. A fixed contract with the app,
 *  which creates them; a notice names the one it is shown in. */
export const FCM_CHANNELS = {
  halqah: "halqah_notifications",
  dailyZikr: "daily_zikr_live",
  official: "official_alerts",
} as const;
export type FCMChannel = typeof FCM_CHANNELS[keyof typeof FCM_CHANNELS];

/** Phones sent to at once, and delivery records per batch, as for APNs. */
const SEND_CONCURRENCY = 20;
const WRITES_PER_BATCH = 50;
/** An access token lives an hour; it is renewed five minutes before that. */
const RENEW_BEFORE_MS = 5 * 60_000;
/** Google accepts a service account assertion of an hour at most. */
const ASSERTION_SECONDS = 3_600;

export interface FCMConfig { projectID: string; clientEmail: string; privateKey: string }

/** The three FCM values, or null while any of them is unset. */
export function fcmConfig(env: Env): FCMConfig | null {
  const projectID = env.FCM_PROJECT_ID?.trim();
  const clientEmail = env.FCM_CLIENT_EMAIL?.trim();
  const privateKey = env.FCM_PRIVATE_KEY?.trim();
  return projectID && clientEmail && privateKey ? { projectID, clientEmail, privateKey } : null;
}

/** The channel a notice is shown in on Android, by what it is about. */
export function fcmChannel(topic: string): FCMChannel {
  // A Halqah's own notices: its posts, its live zikr, its meetings.
  if (topic.startsWith("group:")) return FCM_CHANNELS.halqah;
  // The official live zikr: Daily Zikr (and the Tahajjud zikr) starting, the
  // host's cues during it, and the live pipeline's alerts.
  if (topic === "liveZikr" || topic === "live-alerts") return FCM_CHANNELS.dailyZikr;
  // Every other official alert: broadcasts, announcements, events.
  return FCM_CHANNELS.official;
}

/** One FCM v1 message, as POSTed in `{ "message": ... }`. */
export interface FCMMessage {
  token: string;
  notification: { title: string; body: string };
  android: {
    priority: "high";
    /** How long FCM keeps trying a phone that is offline ("1800s"). */
    ttl?: string;
    /** Only the newest of these is delivered to a phone that was offline. */
    collapse_key?: string;
    notification: {
      channel_id: FCMChannel;
      sound: "default";
      /** A newer notice with the same tag replaces the older one in the tray. */
      tag?: string;
    };
  };
  /** The deep link and what it is about, for the app to open when tapped. */
  data: { path: string; eventID: string; topic: string };
}

/** The message for one phone: the title, body and deep link the iPhone gets,
 *  in the channel its topic belongs to. A live alert's expiry and collapse id
 *  become FCM's ttl, collapse key and tag. */
export function fcmMessage(
  token: string, eventID: string, topic: string, title: string, body: string, path: string, options: PushOptions = {},
): FCMMessage {
  const android: FCMMessage["android"] = {
    priority: "high",
    notification: { channel_id: fcmChannel(topic), sound: "default" },
  };
  if (options.ttlSeconds) android.ttl = `${Math.floor(options.ttlSeconds)}s`;
  if (options.collapseID) {
    android.collapse_key = options.collapseID;
    android.notification.tag = options.collapseID;
  }
  return { token, notification: { title, body }, android, data: { path, eventID, topic } };
}

// MARK: - The service account's access token

/** The DER bytes of a PKCS#8 PEM key, however it was pasted: real line
 *  breaks, the JSON key file's literal "\n", or the value still in quotes. */
export function pkcs8FromPEM(pem: string): Uint8Array<ArrayBuffer> {
  const text = pem.trim().replace(/^"+|"+$/g, "").replace(/\\r/g, "").replace(/\\n/g, "\n");
  if (/-----BEGIN (RSA |ENCRYPTED )PRIVATE KEY-----/.test(text)) {
    throw new Error("FCM_PRIVATE_KEY must be the service account's unencrypted PKCS#8 key (BEGIN PRIVATE KEY)");
  }
  const body = text.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  if (!body || !/^[A-Za-z0-9+/]+={0,2}$/.test(body)) throw new Error("FCM_PRIVATE_KEY is not a PEM private key");
  return Uint8Array.from(atob(body), char => char.charCodeAt(0));
}

/** The JWT Google exchanges for an access token: RS256, signed with the
 *  service account's key, asking for the Firebase Messaging scope. */
export async function serviceAccountAssertion(config: FCMConfig, nowSeconds: number): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8", pkcs8FromPEM(config.privateKey), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: config.clientEmail, scope: FCM_SCOPE, aud: GOOGLE_TOKEN_URL, iat: nowSeconds, exp: nowSeconds + ASSERTION_SECONDS,
  }));
  const unsigned = `${header}.${claims}`;
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  return `${unsigned}.${base64url(signature)}`;
}

let accessToken: { key: string; token: string; renewAt: number } | undefined;
let pendingToken: { key: string; promise: Promise<string> } | undefined;

/** Forgets the kept access token, so the next send asks Google for a new one. */
export function resetFCMToken(): void {
  accessToken = undefined;
  pendingToken = undefined;
}

/** The access token FCM is called with: kept until five minutes before it
 *  expires, and asked for once however many sends want it at the same time. */
export async function fcmAccessToken(config: FCMConfig): Promise<string> {
  const key = `${config.projectID}|${config.clientEmail}`;
  if (accessToken && accessToken.key === key && Date.now() < accessToken.renewAt) return accessToken.token;
  if (pendingToken && pendingToken.key === key) return pendingToken.promise;
  const promise = exchangeAssertion(config, key).finally(() => {
    if (pendingToken?.promise === promise) pendingToken = undefined;
  });
  pendingToken = { key, promise };
  return promise;
}

async function exchangeAssertion(config: FCMConfig, key: string): Promise<string> {
  const issuedAt = Date.now();
  const assertion = await serviceAccountAssertion(config, Math.floor(issuedAt / 1000));
  const response = await fetch(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }).toString(),
  });
  const answer = await response.json<{ access_token?: unknown; expires_in?: unknown; error?: unknown; error_description?: unknown }>()
    .catch(() => ({} as Record<string, unknown>));
  if (!response.ok || typeof answer.access_token !== "string" || !answer.access_token) {
    const reason = [answer.error, answer.error_description].filter(part => typeof part === "string" && part).join(": ");
    throw new Error(`Google refused the FCM service account (${response.status}${reason ? `, ${reason.slice(0, 200)}` : ""})`);
  }
  const lifetime = Number(answer.expires_in) > 0 ? Number(answer.expires_in) * 1000 : ASSERTION_SECONDS * 1000;
  const renewAt = issuedAt + (lifetime > 2 * RENEW_BEFORE_MS ? lifetime - RENEW_BEFORE_MS : lifetime / 2);
  accessToken = { key, token: answer.access_token, renewAt };
  return answer.access_token;
}

// MARK: - Sending

/** FCM's error body: google.rpc.Status, with FCM's own code in `details`. */
export interface FCMErrorBody {
  error?: {
    code?: number;
    message?: string;
    status?: string;
    details?: Array<{ "@type"?: string; errorCode?: string; fieldViolations?: Array<{ field?: string; description?: string }> }>;
  };
}

/** What one send came to. `dead`: the token will never work again (the app
 *  was removed, or the token is not one), so the phone is forgotten, as on
 *  APNs 410. `unauthorized`: the access token was refused, and is renewed. */
export type FCMOutcome = "accepted" | "dead" | "unauthorized" | "failed";

const TOKEN_FIELD = /registration token|message\.token/i;

export function fcmOutcome(status: number | null, answer?: FCMErrorBody | null): FCMOutcome {
  if (status !== null && status >= 200 && status < 300) return "accepted";
  if (status === null) return "failed";
  const error = answer?.error;
  const details = Array.isArray(error?.details) ? error.details : [];
  const codes = new Set([error?.status, ...details.map(detail => detail?.errorCode)].filter(code => typeof code === "string"));
  if (codes.has("UNREGISTERED")) return "dead";
  // INVALID_ARGUMENT also answers a malformed message, which says nothing
  // about the phone: only one that names the registration token means the
  // token is bad. Otherwise one bad payload would forget every Android phone.
  if (codes.has("INVALID_ARGUMENT")) {
    const aboutToken = TOKEN_FIELD.test(error?.message ?? "") || details.some(detail =>
      (Array.isArray(detail?.fieldViolations) ? detail.fieldViolations : [])
        .some(violation => violation?.field === "message.token" || TOKEN_FIELD.test(violation?.description ?? "")));
    if (aboutToken) return "dead";
  }
  if (status === 401 || codes.has("UNAUTHENTICATED")) return "unauthorized";
  return "failed";
}

/** Sends to Android phones: devices rows with platform 'android', whose
 *  apns_token column holds the FCM token. Never throws for missing or refused
 *  credentials - those are logged and kept as FCM's health - so the iPhones
 *  in the same alert are never held up by FCM. */
export async function deliverFCM(
  env: Env, eventID: string, topic: string, devices: Record<string, string>[], title: string, body: string, path: string,
  options: PushOptions = {},
): Promise<number> {
  if (!devices.length) return 0;
  const config = fcmConfig(env);
  if (!config) {
    console.log(`FCM is not configured: ${devices.length} Android phone(s) skipped for ${eventID}`);
    return 0;
  }
  let bearer: string;
  try { bearer = await fcmAccessToken(config); }
  catch (error) {
    const message = error instanceof Error ? error.message : "FCM credential failure";
    console.error(`FCM: ${message}`);
    await recordFCMHealth(env, false, message);
    return 0;
  }
  // As for APNs: an event sent again reaches only the phones it missed.
  const delivered = await env.DB.prepare("SELECT installation_id FROM notification_deliveries WHERE event_id=? AND status='accepted'")
    .bind(eventID).all<{ installation_id: string }>();
  const done = new Set((delivered.results ?? []).map(row => row.installation_id));
  const pending = devices.filter(device => !done.has(device.installation_id ?? ""));
  if (!pending.length) return 0;

  const url = fcmSendURL(config.projectID);
  const headers = { authorization: `Bearer ${bearer}`, "content-type": "application/json; charset=utf-8" };
  const sent = await inParallel(pending, SEND_CONCURRENCY, async device => {
    const message = fcmMessage(device.apns_token ?? "", eventID, topic, title, body, path, options);
    try {
      const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ message }) });
      let answer: FCMErrorBody | null = null;
      if (response.ok) await response.body?.cancel();
      else answer = await response.json<FCMErrorBody>().catch(() => null);
      return { device, status: response.status as number | null, outcome: fcmOutcome(response.status, answer), reason: answer?.error?.message };
    } catch {
      return { device, status: null as number | null, outcome: "failed" as FCMOutcome, reason: undefined as string | undefined };
    }
  });

  let accepted = 0; let failed = 0; let firstReason: string | undefined;
  const createdAt = new Date().toISOString();
  const writes: D1PreparedStatement[] = [];
  for (const { device, status, outcome, reason } of sent) {
    if (outcome === "accepted") accepted += 1;
    else if (outcome !== "dead") { failed += 1; firstReason ??= reason; }
    // A refused access token is asked for anew for the next alert.
    if (outcome === "unauthorized") resetFCMToken();
    writes.push(env.DB.prepare(`INSERT INTO notification_deliveries(event_id,installation_id,topic,status,response_code,created_at) VALUES(?,?,?,?,?,?)
      ON CONFLICT(event_id,installation_id) DO UPDATE SET status=excluded.status,response_code=excluded.response_code,created_at=excluded.created_at`)
      .bind(eventID, device.installation_id, topic, outcome === "accepted" ? "accepted" : "failed", status, createdAt));
    // The app was removed, or the token never was one: forget the phone -
    // unless it has registered a new token since this one was read.
    if (outcome === "dead") {
      writes.push(env.DB.prepare("DELETE FROM devices WHERE installation_id=? AND apns_token=? AND platform='android'")
        .bind(device.installation_id, device.apns_token));
    }
  }
  for (let start = 0; start < writes.length; start += WRITES_PER_BATCH) {
    await env.DB.batch(writes.slice(start, start + WRITES_PER_BATCH));
  }
  await recordFCMHealth(env, failed === 0,
    failed ? `${failed} FCM deliveries failed${firstReason ? `: ${firstReason.slice(0, 200)}` : ""}` : undefined);
  return accepted;
}

async function recordFCMHealth(env: Env, healthy: boolean, message?: string): Promise<void> {
  const now = new Date().toISOString();
  if (healthy) {
    await env.DB.prepare(`INSERT INTO source_health(source,status,last_success_at,last_attempt_at,consecutive_failures,last_error)
      VALUES('fcm','healthy',?,?,0,NULL) ON CONFLICT(source) DO UPDATE SET status='healthy',last_success_at=excluded.last_success_at,last_attempt_at=excluded.last_attempt_at,consecutive_failures=0,last_error=NULL`).bind(now, now).run();
  } else {
    await env.DB.prepare(`INSERT INTO source_health(source,status,last_attempt_at,consecutive_failures,last_error)
      VALUES('fcm','degraded',?,1,?) ON CONFLICT(source) DO UPDATE SET status='degraded',last_attempt_at=excluded.last_attempt_at,consecutive_failures=source_health.consecutive_failures+1,last_error=excluded.last_error`).bind(now, message?.slice(0, 500) ?? "FCM failure").run();
  }
}
