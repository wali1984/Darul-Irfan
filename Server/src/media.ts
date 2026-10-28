import type { Env } from "./contracts";
import { json } from "./util";

// Pictures forwarded to the WhatsApp Business number, and zikr recordings
// uploaded to a group (see recordings.ts).
//
// Meta hands a webhook only a media id. The picture itself is fetched with the
// Business account's access token - first the id resolves to a short-lived
// download address, then that address returns the bytes - and is kept in R2,
// because Meta's copy expires. Members reach it through a signed, expiring
// link: group pictures are as private as the group's posts.

const ALLOWED = new Map([
  ["image/jpeg", "jpg"], ["image/png", "png"], ["image/webp", "webp"],
]);
const MAX_BYTES = 12 * 1024 * 1024;

/** Downloads a WhatsApp picture into storage. Returns its storage key, or null
 *  when storage or the access token is not configured or the download fails -
 *  in which case the post still arrives, with its caption. */
export async function storeWhatsAppImage(env: Env, mediaID: string, messageID: string): Promise<string | null> {
  if (!env.MEDIA || !env.WHATSAPP_ACCESS_TOKEN || !/^[0-9]{5,40}$/.test(mediaID)) return null;
  const version = env.FACEBOOK_GRAPH_VERSION || "v25.0";
  const auth = { authorization: `Bearer ${env.WHATSAPP_ACCESS_TOKEN}` };
  try {
    const meta = await fetch(`https://graph.facebook.com/${version}/${mediaID}`, { headers: auth });
    if (!meta.ok) return null;
    const info = await meta.json<{ url?: string; mime_type?: string; file_size?: number }>();
    const extension = info.mime_type ? ALLOWED.get(info.mime_type) : undefined;
    if (!info.url || !extension || (info.file_size ?? 0) > MAX_BYTES) return null;
    const download = await fetch(info.url, { headers: auth });
    if (!download.ok) return null;
    const bytes = await download.arrayBuffer();
    if (bytes.byteLength === 0 || bytes.byteLength > MAX_BYTES) return null;
    const key = `whatsapp/${messageID.replace(/[^A-Za-z0-9._-]/g, "_")}.${extension}`;
    await env.MEDIA.put(key, bytes, { httpMetadata: { contentType: info.mime_type } });
    return key;
  } catch {
    return null;
  }
}

async function signature(env: Env, key: string, expires: number): Promise<string | null> {
  const secret = env.MEDIA_URL_SECRET;
  if (!secret) return null;
  const hmac = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signed = await crypto.subtle.sign("HMAC", hmac, new TextEncoder().encode(`${key}|${expires}`));
  return [...new Uint8Array(signed)].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

/** A link to a stored picture or recording, valid for `seconds`. */
export async function signedMediaURL(env: Env, key: string, seconds = 86_400): Promise<string | undefined> {
  const expires = Math.floor(Date.now() / 1000) + seconds;
  const sig = await signature(env, key, expires);
  if (!sig) return undefined;
  return `${env.PUBLIC_BASE_URL}/v1/media/${encodeURIComponent(key)}?exp=${expires}&sig=${sig}`;
}

const SERVABLE = /^(whatsapp\/[A-Za-z0-9._-]{1,120}|recordings\/[a-z0-9-]{1,40}\/[A-Za-z0-9._-]{1,120}|daily\/[A-Za-z0-9._-]{1,120}|posts\/[a-z0-9-]{1,40}\/[A-Za-z0-9._-]{1,120})$/;

/** Serves a stored picture or recording to a holder of a valid, unexpired
 *  link. Byte ranges are honoured: the player streams a recording in parts
 *  and seeks to where the group is listening. */
export async function serveMedia(request: Request, env: Env, rawKey: string, url: URL): Promise<Response> {
  const key = decodeURIComponent(rawKey);
  const expires = Number(url.searchParams.get("exp"));
  const given = url.searchParams.get("sig") ?? "";
  if (!env.MEDIA || !SERVABLE.test(key) || !Number.isInteger(expires) || expires * 1000 < Date.now()) {
    return json({ error: "Not found" }, { status: 404 });
  }
  const expected = await signature(env, key, expires);
  if (!expected || expected.length !== given.length) return json({ error: "Not found" }, { status: 404 });
  let difference = 0;
  for (let i = 0; i < expected.length; i += 1) difference |= expected.charCodeAt(i) ^ given.charCodeAt(i);
  if (difference !== 0) return json({ error: "Not found" }, { status: 404 });
  const ranged = request.headers.has("range");
  const object = request.method === "HEAD"
    ? await env.MEDIA.head(key)
    : await env.MEDIA.get(key, ranged ? { range: request.headers } : undefined).catch(() => null);
  if (!object) return json({ error: "Not found" }, { status: 404 });
  const headers = new Headers({
    "content-type": object.httpMetadata?.contentType ?? "application/octet-stream",
    "accept-ranges": "bytes",
    // Private to the device that asked; the link itself expires.
    "cache-control": "private, max-age=3600",
    "x-content-type-options": "nosniff",
  });
  const range = object.range as { offset?: number; length?: number; suffix?: number } | undefined;
  const body = request.method === "HEAD" ? null : (object as R2ObjectBody).body;
  if (ranged && range && body) {
    const offset = range.suffix !== undefined ? object.size - range.suffix : range.offset ?? 0;
    const length = range.suffix ?? range.length ?? object.size - offset;
    headers.set("content-range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
    headers.set("content-length", String(length));
    return new Response(body, { status: 206, headers });
  }
  if (Number.isFinite(object.size)) headers.set("content-length", String(object.size));
  return new Response(body, { headers });
}
