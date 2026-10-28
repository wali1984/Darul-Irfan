import type { Env } from "./contracts";
import { serveObject } from "./media";
import { json } from "./util";

// Narration of the Silsila's Qur'an translations and tafsir. Public like the
// text it reads: one MP3 per ayah (translations) or per tafsir passage, so the
// player starts and stops on ayah ends. Generated on amd with OmniVoice and
// uploaded to R2 under audio/quran/; the manifest lists what exists, so new
// files reach the apps without an app update.

const FILE = /^(akram-ut-tarajum-ur|akram-ut-tarajum-en|asrar-at-tanzil-en|akram-ut-tafaseer-ur)\/(translation|tafsir)\/\d{6}(-\d{3})?\.mp3$/;

/** GET /v1/audio/quran/manifest - which narrations exist, and their voice credits. */
export async function quranAudioManifest(env: Env): Promise<Response> {
  const object = await env.MEDIA?.get("audio/quran/manifest.json").catch(() => null);
  const headers = { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=300" };
  if (!object) return new Response(JSON.stringify({ version: 0, voices: {}, editions: {} }), { headers });
  return new Response((object as R2ObjectBody).body, { headers });
}

/** GET /v1/audio/quran/<edition>/<kind>/<SSSAAA[-EEE]>.mp3 */
export async function quranAudioFile(request: Request, env: Env, rest: string): Promise<Response> {
  if (!FILE.test(rest)) return json({ error: "Not found" }, { status: 404 });
  return serveObject(request, env, `audio/quran/${rest}`, "public, max-age=604800");
}
