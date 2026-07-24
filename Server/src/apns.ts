import type { Env, PushTopic } from "./contracts";

const base64url = (input: ArrayBuffer | string): string => {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let binary = ""; bytes.forEach(value => binary += String.fromCharCode(value));
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
};

async function apnsJWT(env: Env): Promise<string> {
  if (!env.APNS_KEY_ID || !env.APNS_TEAM_ID || !env.APNS_PRIVATE_KEY) throw new Error("APNs credentials are incomplete");
  const pem = env.APNS_PRIVATE_KEY.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  const der = Uint8Array.from(atob(pem), char => char.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = base64url(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID }));
  const claims = base64url(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) }));
  const unsigned = `${header}.${claims}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned));
  return `${unsigned}.${base64url(signature)}`;
}

export async function sendTopicPush(env: Env, eventID: string, topic: PushTopic, title: string, body: string, path: string): Promise<number> {
  const devices = await env.DB.prepare("SELECT * FROM devices WHERE topics_json LIKE ?").bind(`%\"${topic}\"%`).all<Record<string, string>>();
  if (!devices.results.length) return 0;
  let jwt: string;
  try { jwt = await apnsJWT(env); }
  catch (error) {
    await recordAPNSHealth(env, false, error instanceof Error ? error.message : "APNs credential failure");
    throw error;
  }
  let accepted = 0; let failed = 0;
  for (const device of devices.results) {
    const prior = await env.DB.prepare("SELECT status FROM notification_deliveries WHERE event_id=? AND installation_id=?").bind(eventID, device.installation_id).first<{ status: string }>();
    if (prior?.status === "accepted") continue;
    const host = device.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    let response: Response;
    try {
      response = await fetch(`https://${host}/3/device/${device.apns_token}`, {
        method: "POST",
        headers: { authorization: `bearer ${jwt}`, "apns-topic": env.APNS_TOPIC, "apns-push-type": "alert", "apns-priority": "10" },
        body: JSON.stringify({ aps: { alert: { title, body }, sound: "default", "thread-id": topic }, path })
      });
    } catch {
      failed += 1;
      await env.DB.prepare(`INSERT INTO notification_deliveries(event_id,installation_id,topic,status,response_code,created_at) VALUES(?,?,?,?,?,?)
        ON CONFLICT(event_id,installation_id) DO UPDATE SET status=excluded.status,response_code=excluded.response_code,created_at=excluded.created_at`)
        .bind(eventID, device.installation_id, topic, "failed", null, new Date().toISOString()).run();
      continue;
    }
    await env.DB.prepare(`INSERT INTO notification_deliveries(event_id,installation_id,topic,status,response_code,created_at) VALUES(?,?,?,?,?,?)
      ON CONFLICT(event_id,installation_id) DO UPDATE SET status=excluded.status,response_code=excluded.response_code,created_at=excluded.created_at`)
      .bind(eventID, device.installation_id, topic, response.ok ? "accepted" : "failed", response.status, new Date().toISOString()).run();
    if (response.ok) accepted += 1;
    else if (response.status !== 410) failed += 1;
    if (response.status === 410) await env.DB.prepare("DELETE FROM devices WHERE installation_id=?").bind(device.installation_id).run();
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
