import type { Env, LiveCue } from "./contracts";
import { CUE_ALERT, sendTopicPush } from "./apns";
import { zikrTitle } from "./live";
import { serveObject } from "./media";
import { cleanText, json } from "./util";

// The free relay of the Paltalk room and its cues (Docs/LIVE_ZIKR_PIPELINE.md).
// The listener cuts the room's sound into short HLS pieces and uploads them to
// R2 under live/official/; this module serves them to the apps (R2 charges
// nothing for what is read), and turns a host's chat message - "L-3",
// "M-Nabvee", exactly as posted - into an alert with sound and the banner on
// the live card.

/** The relay's playlist, as the apps play it. */
export const RELAY_PLAYLIST = "/v1/live/audio/index.m3u8";
const RELAY_FILE = /^(index\.m3u8|seg-\d{1,9}\.(aac|ts))$/;
/** A cue repeated within this long (the listener retrying) is not re-sent. */
const CUE_REPEAT_MS = 10 * 60_000;

export function equalSecret(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  return difference === 0;
}

function isListener(request: Request, env: Env): boolean {
  const token = env.LISTENER_TOKEN;
  const header = request.headers.get("authorization") ?? "";
  return !!token && header.startsWith("Bearer ") && equalSecret(header.slice(7), token);
}

/** GET /v1/live/audio/<file> - the relay's playlist and pieces. The playlist
 *  changes every few seconds, so it is never cached; a piece never changes. */
export async function liveAudioFile(request: Request, env: Env, name: string): Promise<Response> {
  if (!RELAY_FILE.test(name)) return json({ error: "Not found" }, { status: 404 });
  const playlist = name.endsWith(".m3u8");
  return serveObject(request, env, `live/official/${name}`, playlist ? "no-store" : "public, max-age=300");
}

/** Paltalk usernames whose chat messages are cues: the room's admins,
 *  moderators and speakers, as the owner lists them. */
export function cueHosts(env: Env): string[] {
  return (env.LIVE_CUE_HOSTS ?? "").split(",").map(value => value.trim().toLowerCase()).filter(Boolean);
}

/** GET /v1/live/listener/config - what the listener needs from the server:
 *  whose messages to send, so no one else's chat leaves the listener PC. */
export async function listenerConfig(request: Request, env: Env): Promise<Response> {
  if (!isListener(request, env)) return json({ error: "Not found" }, { status: 404 });
  return json({ cueHosts: cueHosts(env) });
}

/** POST /v1/live/cue - a host's message in the room: { sender, text }. */
export async function liveCue(request: Request, env: Env, now = new Date()): Promise<Response> {
  if (!isListener(request, env)) return json({ error: "Not found" }, { status: 404 });
  const input = await request.json<Record<string, unknown>>().catch(() => ({} as Record<string, unknown>));
  const sender = cleanText(input.sender, 60);
  const text = cleanText(input.text, 200);
  if (!sender || !text) return json({ error: "sender and text are required" }, { status: 400 });
  if (!cueHosts(env).includes(sender.toLowerCase())) return json({ ok: true, ignored: "not a host" });

  const prior = await currentCue(env);
  if (prior && prior.text === text && now.getTime() - Date.parse(prior.at) < CUE_REPEAT_MS) {
    return json({ ok: true, repeated: true });
  }
  const cue: LiveCue = { text, sender, at: now.toISOString() };
  await env.DB.prepare(`INSERT INTO app_config(key,value_json,updated_at) VALUES('liveCue',?,?)
    ON CONFLICT(key) DO UPDATE SET value_json=excluded.value_json,updated_at=excluded.updated_at`)
    .bind(JSON.stringify(cue), cue.at).run();
  // The message itself is the notification's title, exactly as the host
  // wrote it; the sound is the point - the mic may have dropped. Its body
  // names the session by Pakistan time, so a cue before dawn says Tahajjud.
  await sendTopicPush(env, `cue:${cue.at.slice(0, 19)}`, "liveZikr", text, zikrTitle(now),
    "darulirfan://live/official-live", CUE_ALERT).catch(() => 0);
  return json({ ok: true, sent: true });
}

/** The last cue, if any. */
export async function currentCue(env: Env): Promise<LiveCue | null> {
  const row = await env.DB.prepare("SELECT value_json FROM app_config WHERE key='liveCue'").first<{ value_json: string }>();
  if (!row) return null;
  try {
    const value = JSON.parse(row.value_json) as LiveCue;
    return typeof value.text === "string" && typeof value.at === "string" ? value : null;
  } catch {
    return null;
  }
}
