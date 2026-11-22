import type { Env } from "./contracts";
import { serveObject } from "./media";
import { json } from "./util";

// Narration of the Silsila's Qur'an translations and tafsir. Public like the
// text it reads: one MP3 per ayah (translations) or per tafsir passage, so the
// player starts and stops on ayah ends. The files are kept in storage under
// audio/quran/; the manifest lists what exists, so new files reach the apps
// without an app update.

const FILE = /^(akram-ut-tarajum-ur|akram-ut-tarajum-en|asrar-at-tanzil-en|akram-ut-tafaseer-ur)\/(translation|tafsir)\/\d{6}(-\d{3})?\.mp3$/;
const LANGUAGE = /^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$/;

/** What the apps are sent. `revision` changes whenever narrations are re-made;
 *  each language's `name` is a mark of the same kind and nothing else. */
export interface NarrationManifest {
  version: number;
  revision: string;
  voices: Record<string, { name: string }>;
  editions: Record<string, Record<string, string[]>>;
}

/** 64-bit FNV-1a in base 36: the hash the released apps make of the `voices`
 *  they are sent, to name the folder their kept narrations live in. */
function mark(text: string): string {
  let hash = 0xcbf29ce484222325n;
  for (const byte of new TextEncoder().encode(text)) {
    hash = BigInt.asUintN(64, (hash ^ BigInt(byte)) * 0x100000001b3n);
  }
  return hash.toString(36);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** The stored lists of files, edition -> kind -> names, keeping only names the
 *  file route below serves. Anything else stored among them is left behind. */
function listedFiles(stored: unknown): Record<string, Record<string, string[]>> {
  const editions: Record<string, Record<string, string[]>> = {};
  if (!isRecord(stored)) return editions;
  for (const [edition, kinds] of Object.entries(stored)) {
    if (!isRecord(kinds)) continue;
    const kept: Record<string, string[]> = {};
    for (const [kind, names] of Object.entries(kinds)) {
      if (!Array.isArray(names)) continue;
      const files = names.filter((name): name is string => typeof name === "string" && FILE.test(`${edition}/${kind}/${name}.mp3`));
      if (files.length > 0) kept[kind] = files;
    }
    if (Object.keys(kept).length > 0) editions[edition] = kept;
  }
  return editions;
}

/** The stored manifest as the apps receive it. Only the count, the lists of
 *  files and revision marks go out: whatever storage holds for a language, or
 *  as its own `revision`, is folded into a mark and never sent as written, and
 *  any other field is left behind.
 *
 *  A language's mark changes whenever anything in its stored entry (or the
 *  stored `revision`) changes, so the released apps - which hash the names - still
 *  drop the copies they kept of a narration that has since been re-made.
 *  `revision` is that same hash, worked out here: an app that reads it lands
 *  on the folder it already uses. */
export function publicNarrationManifest(stored: unknown): NarrationManifest {
  const source = isRecord(stored) ? stored : {};
  const stamp = typeof source.revision === "string" || typeof source.revision === "number" ? String(source.revision) : "";
  const voices: Record<string, { name: string }> = {};
  const signature: string[] = [];
  const given = isRecord(source.voices) ? source.voices : {};
  for (const language of Object.keys(given).filter(key => LANGUAGE.test(key)).sort()) {
    const entry = given[language];
    const text = typeof entry === "string" ? entry : JSON.stringify(entry) ?? "";
    const name = `r${mark(`${stamp}\n${text}`)}`;
    voices[language] = { name };
    signature.push(`${language}=${name}`);
  }
  return {
    version: typeof source.version === "number" && Number.isFinite(source.version) ? Math.trunc(source.version) : 0,
    revision: mark(signature.length > 0 ? signature.join(";") : stamp),
    voices,
    editions: listedFiles(source.editions),
  };
}

/** GET /v1/audio/quran/manifest - which narrations exist, and their revision. */
export async function quranAudioManifest(env: Env): Promise<Response> {
  const object = await env.MEDIA?.get("audio/quran/manifest.json").catch(() => null);
  const headers = { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=300" };
  if (!object) return new Response(JSON.stringify(publicNarrationManifest(null)), { headers });
  let stored: unknown;
  try {
    stored = JSON.parse(await new Response((object as R2ObjectBody).body).text());
  } catch {
    // An app that gets no list keeps the one it has, and the copies with it.
    return json({ error: "Narration list unavailable" }, { status: 503 });
  }
  return new Response(JSON.stringify(publicNarrationManifest(stored)), { headers });
}

/** GET /v1/audio/quran/<edition>/<kind>/<SSSAAA[-EEE]>.mp3 */
export async function quranAudioFile(request: Request, env: Env, rest: string): Promise<Response> {
  if (!FILE.test(rest)) return json({ error: "Not found" }, { status: 404 });
  return serveObject(request, env, `audio/quran/${rest}`, "public, max-age=604800");
}
