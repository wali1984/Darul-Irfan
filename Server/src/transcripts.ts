import type { Env } from "./contracts";
import { json } from "./util";

// Bayan transcripts: one timed transcript per bayan, made on amd and uploaded
// to R2 under transcripts/<mediaId>.json.gz by Tools/Release/upload_transcripts.py.
// Public and read-only like the bayans themselves. The stored file is gzip; it
// is served as plain JSON (Cloudflare compresses it again for the client), and
// held at the edge for a long time because a transcript changes rarely.

/** A catalogue media id: lower-case letters, digits, "-" and "_", no dots or slashes. */
const ID = /^[a-z0-9][a-z0-9_-]{0,159}$/;
const FOUND_CACHE = "public, max-age=86400, s-maxage=2592000";
const MISSING_CACHE = "public, max-age=300";

export const isTranscriptID = (id: string): boolean => ID.test(id);

/** GET|HEAD /v1/transcripts/<mediaId> */
export async function transcript(request: Request, env: Env, id: string): Promise<Response> {
  if (!isTranscriptID(id)) return json({ error: "Not found" }, { status: 404, headers: { "cache-control": MISSING_CACHE } });
  const key = `transcripts/${id}.json.gz`;
  const isHead = request.method === "HEAD";
  const cache = !isHead && typeof caches !== "undefined" ? (caches as unknown as { default?: Cache }).default : undefined;
  const cacheKey = new Request(new URL(`/v1/transcripts/${id}`, request.url).toString());
  const cached = await cache?.match(cacheKey).catch(() => undefined);
  if (cached) return cached;
  if (!env.MEDIA) return json({ error: "Not found" }, { status: 404, headers: { "cache-control": MISSING_CACHE } });
  const object = isHead
    ? await env.MEDIA.head(key).catch(() => null)
    : await env.MEDIA.get(key).catch(() => null);
  if (!object) return json({ error: "Not found" }, { status: 404, headers: { "cache-control": MISSING_CACHE } });
  const headers = new Headers({
    "content-type": "application/json; charset=utf-8",
    "cache-control": FOUND_CACHE,
    "x-content-type-options": "nosniff",
  });
  if (object.httpEtag) headers.set("etag", object.httpEtag);
  if (isHead) return new Response(null, { headers });
  const body = new Response((object as R2ObjectBody).body).body;
  if (!body) return json({ error: "Not found" }, { status: 404, headers: { "cache-control": MISSING_CACHE } });
  const response = new Response(body.pipeThrough(new DecompressionStream("gzip")), { headers });
  await cache?.put(cacheKey, response.clone()).catch(() => undefined);
  return response;
}
