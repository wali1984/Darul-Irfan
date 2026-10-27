import type { Env } from "./contracts";
import { json } from "./util";

// Pictures forwarded to the WhatsApp Business number.
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

/** A link to a stored picture, valid for `seconds`. */
export async function signedMediaURL(env: Env, key: string, seconds = 86_400): Promise<string | undefined> {
  const expires = Math.floor(Date.now() / 1000) + seconds;
  const sig = await signature(env, key, expires);
  if (!sig) return undefined;
  return `${env.PUBLIC_BASE_URL}/v1/media/${encodeURIComponent(key)}?exp=${expires}&sig=${sig}`;
}

/** Serves a stored picture to a holder of a valid, unexpired link. */
export async function serveMedia(env: Env, rawKey: string, url: URL): Promise<Response> {
  const key = decodeURIComponent(rawKey);
  const expires = Number(url.searchParams.get("exp"));
  const given = url.searchParams.get("sig") ?? "";
  if (!env.MEDIA || !/^whatsapp\/[A-Za-z0-9._-]{1,120}$/.test(key) || !Number.isInteger(expires) || expires * 1000 < Date.now()) {
    return json({ error: "Not found" }, { status: 404 });
  }
  const expected = await signature(env, key, expires);
  if (!expected || expected.length !== given.length) return json({ error: "Not found" }, { status: 404 });
  let difference = 0;
  for (let i = 0; i < expected.length; i += 1) difference |= expected.charCodeAt(i) ^ given.charCodeAt(i);
  if (difference !== 0) return json({ error: "Not found" }, { status: 404 });
  const object = await env.MEDIA.get(key);
  if (!object) return json({ error: "Not found" }, { status: 404 });
  return new Response(object.body, {
    headers: {
      "content-type": object.httpMetadata?.contentType ?? "application/octet-stream",
      // Private to the device that asked; the link itself expires.
      "cache-control": "private, max-age=3600",
      "x-content-type-options": "nosniff",
    },
  });
}
