import type { Env, PushTopic } from "./contracts";
import { deliverFCM } from "./fcm";
import { base64url, inParallel } from "./util";

/** Extra APNs headers for an alert that means nothing once its moment has
 *  passed. Posts and group notices send none of these. */
export interface PushOptions {
  /** How long APNs keeps trying a phone that is offline before dropping it. */
  ttlSeconds?: number;
  /** A newer alert with the same id replaces the older one on the phone. */
  collapseID?: string;
}

/** "Daily Zikr has started" and "Tahajjud Zikr has started". */
export const LIVE_ALERT: PushOptions = { ttlSeconds: 1_800, collapseID: "live-zikr" };
/** The host's cues during a session ("L-3", "M-Nabvee"). */
export const CUE_ALERT: PushOptions = { ttlSeconds: 1_800, collapseID: "live-cue" };

/** Phones sent to at once, ids per lookup (D1 binds at most 100 values) and
 *  delivery records per batch. */
const SEND_CONCURRENCY = 20;
const IDS_PER_QUERY = 90;
const WRITES_PER_BATCH = 50;

/** Apple refuses a provider token renewed more often than every 20 minutes
 *  (429 TooManyProviderTokenUpdates) and one older than an hour, so one
 *  token is signed and kept for 50 minutes. */
const TOKEN_REUSE_MS = 50 * 60_000;
let providerToken: { key: string; jwt: string; issuedAt: number } | undefined;

/** Forgets the kept token, so the next send signs a new one. */
export function resetAPNSToken(): void {
  providerToken = undefined;
}

async function apnsJWT(env: Env): Promise<string> {
  if (!env.APNS_KEY_ID || !env.APNS_TEAM_ID || !env.APNS_PRIVATE_KEY) throw new Error("APNs credentials are incomplete");
  const keyID = `${env.APNS_TEAM_ID}:${env.APNS_KEY_ID}`;
  const now = Date.now();
  if (providerToken && providerToken.key === keyID && now - providerToken.issuedAt < TOKEN_REUSE_MS) return providerToken.jwt;
  const pem = env.APNS_PRIVATE_KEY.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  const der = Uint8Array.from(atob(pem), char => char.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = base64url(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID }));
  const claims = base64url(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: Math.floor(now / 1000) }));
  const unsigned = `${header}.${claims}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned));
  const jwt = `${unsigned}.${base64url(signature)}`;
  providerToken = { key: keyID, jwt, issuedAt: now };
  return jwt;
}

export async function sendTopicPush(
  env: Env, eventID: string, topic: PushTopic, title: string, body: string, path: string, options: PushOptions = {},
): Promise<number> {
  const devices = await env.DB.prepare("SELECT * FROM devices WHERE topics_json LIKE ?").bind(`%\"${topic}\"%`).all<Record<string, string>>();
  return deliver(env, eventID, topic, devices.results ?? [], title, body, path, options);
}

/** Pushes to named installations only - a group's members, never a topic. */
export async function sendPushToInstallations(
  env: Env, eventID: string, thread: string, installationIDs: string[], title: string, body: string, path: string,
  options: PushOptions = {},
): Promise<number> {
  const ids = [...new Set(installationIDs)];
  if (!ids.length) return 0;
  // A few lookups for a large Halqah instead of one per phone.
  const devices: Record<string, string>[] = [];
  for (let start = 0; start < ids.length; start += IDS_PER_QUERY) {
    const chunk = ids.slice(start, start + IDS_PER_QUERY);
    const rows = await env.DB.prepare(`SELECT * FROM devices WHERE installation_id IN (${chunk.map(() => "?").join(",")})`)
      .bind(...chunk).all<Record<string, string>>();
    devices.push(...(rows.results ?? []));
  }
  return deliver(env, eventID, thread, devices, title, body, path, options);
}

/** Each phone by its platform: APNs for an iPhone, FCM for an Android phone,
 *  with the same title, body and deep link. A list of iPhones alone is sent
 *  exactly as before. A failure of APNs credentials is still thrown, but only
 *  after the Android phones have been sent to; FCM never throws here (unset,
 *  its phones are skipped). */
async function deliver(
  env: Env, eventID: string, topic: string, devices: Record<string, string>[], title: string, body: string, path: string,
  options: PushOptions,
): Promise<number> {
  if (!devices.length) return 0;
  const android = devices.filter(device => device.platform === "android");
  const apple = android.length ? devices.filter(device => device.platform !== "android") : devices;
  let accepted = 0;
  let appleFailed = false; let appleError: unknown;
  if (apple.length) {
    try { accepted += await deliverAPNs(env, eventID, topic, apple, title, body, path, options); }
    catch (error) {
      if (!android.length) throw error;
      appleFailed = true; appleError = error;
    }
  }
  if (android.length) accepted += await deliverFCM(env, eventID, topic, android, title, body, path, options);
  if (appleFailed) throw appleError;
  return accepted;
}

async function deliverAPNs(
  env: Env, eventID: string, topic: string, devices: Record<string, string>[], title: string, body: string, path: string,
  options: PushOptions,
): Promise<number> {
  if (!devices.length) return 0;
  let jwt: string;
  try { jwt = await apnsJWT(env); }
  catch (error) {
    await recordAPNSHealth(env, false, error instanceof Error ? error.message : "APNs credential failure");
    throw error;
  }
  // Who already has this alert, read once: an event sent again (a retry, a
  // second start of the same stream) reaches only the phones it missed.
  const delivered = await env.DB.prepare("SELECT installation_id FROM notification_deliveries WHERE event_id=? AND status='accepted'")
    .bind(eventID).all<{ installation_id: string }>();
  const done = new Set((delivered.results ?? []).map(row => row.installation_id));
  const pending = devices.filter(device => !done.has(device.installation_id ?? ""));
  if (!pending.length) return 0;

  const headers: Record<string, string> = {
    authorization: `bearer ${jwt}`, "apns-topic": env.APNS_TOPIC, "apns-push-type": "alert", "apns-priority": "10",
  };
  if (options.ttlSeconds) headers["apns-expiration"] = String(Math.floor(Date.now() / 1000) + options.ttlSeconds);
  if (options.collapseID) headers["apns-collapse-id"] = options.collapseID;
  const payload = JSON.stringify({ aps: { alert: { title, body }, sound: "default", "thread-id": topic }, path });
  // Several phones at once, so a few hundred finish well inside one request.
  const sent = await inParallel(pending, SEND_CONCURRENCY, async device => {
    const host = device.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    try {
      const response = await fetch(`https://${host}/3/device/${device.apns_token}`, { method: "POST", headers, body: payload });
      return { device, status: response.status as number | null };
    } catch {
      return { device, status: null as number | null };
    }
  });

  let accepted = 0; let failed = 0;
  const createdAt = new Date().toISOString();
  const writes: D1PreparedStatement[] = [];
  for (const { device, status } of sent) {
    const ok = status !== null && status >= 200 && status < 300;
    if (ok) accepted += 1;
    else if (status !== 410) failed += 1;
    // A refused provider token is signed anew for the next alert.
    if (status === 403) resetAPNSToken();
    writes.push(env.DB.prepare(`INSERT INTO notification_deliveries(event_id,installation_id,topic,status,response_code,created_at) VALUES(?,?,?,?,?,?)
      ON CONFLICT(event_id,installation_id) DO UPDATE SET status=excluded.status,response_code=excluded.response_code,created_at=excluded.created_at`)
      .bind(eventID, device.installation_id, topic, ok ? "accepted" : "failed", status, createdAt));
    // 410: the app was removed from that phone; its token never works again.
    if (status === 410) writes.push(env.DB.prepare("DELETE FROM devices WHERE installation_id=?").bind(device.installation_id));
  }
  for (let start = 0; start < writes.length; start += WRITES_PER_BATCH) {
    await env.DB.batch(writes.slice(start, start + WRITES_PER_BATCH));
  }
  await recordAPNSHealth(env, failed === 0, failed ? `${failed} APNs deliveries failed` : undefined);
  return accepted;
}

async function recordAPNSHealth(env: Env, healthy: boolean, message?: string): Promise<void> {
  const now = new Date().toISOString();
  if (healthy) {
    await env.DB.prepare(`INSERT INTO source_health(source,status,last_success_at,last_attempt_at,consecutive_failures,last_error)
      VALUES('apns','healthy',?,?,0,NULL) ON CONFLICT(source) DO UPDATE SET status='healthy',last_success_at=excluded.last_success_at,last_attempt_at=excluded.last_attempt_at,consecutive_failures=0,last_error=NULL`).bind(now, now).run();
  } else {
    await env.DB.prepare(`INSERT INTO source_health(source,status,last_attempt_at,consecutive_failures,last_error)
      VALUES('apns','degraded',?,1,?) ON CONFLICT(source) DO UPDATE SET status='degraded',last_attempt_at=excluded.last_attempt_at,consecutive_failures=source_health.consecutive_failures+1,last_error=excluded.last_error`).bind(now, message?.slice(0, 500) ?? "APNs failure").run();
  }
}
