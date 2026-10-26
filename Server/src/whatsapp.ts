import type { Env } from "./contracts";
import { cleanText, json, validHTTPURL } from "./util";

interface WhatsAppMessage {
  from?: string;
  id?: string;
  timestamp?: string;
  type?: string;
  text?: { body?: string };
}

interface WhatsAppWebhook {
  entry?: Array<{ changes?: Array<{ value?: { messages?: WhatsAppMessage[] } }> }>;
}

/** No API reads an existing WhatsApp group or channel, and driving a logged-in
 * personal session through an unofficial library would risk the number the
 * silsila depends on. What is supported is the other direction: messages sent
 * *to* the organisation's own WhatsApp Business number arrive here as webhooks.
 * Designated admins forward official material to that number and it is recorded
 * as a draft, so a person still approves everything before it reaches readers
 * in the sheikh's name. */

const digits = /^[0-9]{6,20}$/;

const allowedSenders = (env: Env): Set<string> =>
  new Set((env.WHATSAPP_ALLOWED_SENDERS ?? "")
    .split(",")
    .map(value => value.trim().replace(/^\+/, ""))
    .filter(value => digits.test(value)));

/** Compares in constant time: a leaky comparison would let a caller recover a
 * valid signature one byte at a time. */
function sameSignature(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  return difference === 0;
}

async function signatureOf(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signed = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body));
  return [...new Uint8Array(signed)].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

/** Meta's subscription handshake. It echoes the challenge only when the token
 * matches the one configured here, which is what proves the endpoint is ours. */
export function whatsappSubscription(env: Env, url: URL): Response {
  const token = env.WHATSAPP_VERIFY_TOKEN;
  const challenge = url.searchParams.get("hub.challenge") ?? "";
  if (!token || url.searchParams.get("hub.mode") !== "subscribe"
    || url.searchParams.get("hub.verify_token") !== token || !/^[0-9]{1,40}$/.test(challenge)) {
    return json({ error: "Subscription could not be verified" }, { status: 403 });
  }
  return new Response(challenge, { headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" } });
}

export async function whatsappWebhook(request: Request, env: Env, rawBody: string): Promise<Response> {
  const secret = env.WHATSAPP_APP_SECRET;
  const channelURL = validHTTPURL(env.WHATSAPP_CHANNEL_URL);
  if (!secret || !channelURL) return json({ error: "WhatsApp ingestion is not configured" }, { status: 503 });

  const header = request.headers.get("x-hub-signature-256") ?? "";
  if (!header.startsWith("sha256=") || !sameSignature(header.slice(7), await signatureOf(secret, rawBody))) {
    return json({ error: "Invalid signature" }, { status: 401 });
  }

  let payload: WhatsAppWebhook;
  try { payload = JSON.parse(rawBody) as WhatsAppWebhook; }
  catch { return json({ error: "Invalid JSON" }, { status: 400 }); }

  const senders = allowedSenders(env);
  const now = new Date().toISOString();
  let recorded = 0;

  for (const entry of payload.entry ?? []) {
    for (const change of entry.changes ?? []) {
      for (const message of change.value?.messages ?? []) {
        const from = (message.from ?? "").replace(/^\+/, "");
        const body = cleanText(message.text?.body, 4_000);
        // Only text, and only from an admin we already trust. Images and audio
        // need a second authenticated fetch from Meta's media endpoint, which
        // this does not yet do, so they are left for the admin page.
        if (!message.id || message.type !== "text" || !body || !senders.has(from)) continue;
        const seconds = Number(message.timestamp);
        const publishedAt = Number.isFinite(seconds) && seconds > 0
          ? new Date(seconds * 1000).toISOString()
          : now;
        // Drafts, never published: a person approves it in the admin page
        // before it carries the silsila's name. Meta retries webhooks, so the
        // message id keeps a redelivery from duplicating the post, and an
        // approval already given is not silently revoked by a retry.
        await env.DB.prepare(`INSERT INTO feed_items(id,source,kind,title,body,source_url,published_at,publication_status,raw_json,updated_at)
          VALUES(?,'whatsapp','post',?,?,?,?,'draft',?,?)
          ON CONFLICT(id) DO UPDATE SET title=excluded.title,body=excluded.body,updated_at=excluded.updated_at`)
          .bind(`whatsapp:${message.id}`, body.slice(0, 120), body, channelURL, publishedAt,
            JSON.stringify({ from, id: message.id, timestamp: message.timestamp }), now)
          .run();
        recorded += 1;
      }
    }
  }

  // Always 200 once the signature is good: anything else makes Meta retry a
  // payload we have deliberately ignored.
  return json({ ok: true, recorded });
}
