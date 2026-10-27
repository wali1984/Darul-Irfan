import type { Env } from "./contracts";
import { sendPushToInstallations, sendTopicPush } from "./apns";
import { cleanText, json } from "./util";

// The live zikr pipeline (Docs/LIVE_ZIKR_PIPELINE.md): cloud listeners join
// the Paltalk room and stream it to Cloudflare Stream, which simulcasts to
// YouTube and Facebook. This module keeps the app's broadcast in step with
// them and tells admins the moment any part stops.

/** A listener that has not reported for this long is down. */
const LISTENER_STALE_MS = 3 * 60_000;
/** A listener problem (in the room but not streaming, Paltalk closed) is
 *  reported once it has lasted this long, so a passing hiccup is not. */
const PROBLEM_GRACE_MS = 2 * 60_000;
/** A streaming report is trusted for this long. */
const STREAMING_FRESH_MS = 90_000;

interface ListenerRow {
  id: string; in_room: number; streaming: number; input_id: string | null;
  problem: string | null; problem_since: string | null; last_seen_at: string; alerted_at: string | null;
}

function equalSecret(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  return difference === 0;
}

function streamInputs(env: Env): string[] {
  return (env.STREAM_INPUTS ?? "").split(",").map(value => value.trim()).filter(value => /^[a-f0-9]{32}$/.test(value));
}

function playbackURL(env: Env, inputID: string): string | null {
  const host = (env.STREAM_CUSTOMER_HOST ?? "").trim();
  if (!/^customer-[a-z0-9]+\.cloudflarestream\.com$/.test(host)) return null;
  return `https://${host}/${inputID}/manifest/video.m3u8`;
}

/** POST /v1/live/listener - a listener's heartbeat, every few seconds. */
export async function listenerHeartbeat(request: Request, env: Env): Promise<Response> {
  const token = env.LISTENER_TOKEN;
  const header = request.headers.get("authorization") ?? "";
  if (!token || !header.startsWith("Bearer ") || !equalSecret(header.slice(7), token)) {
    return json({ error: "Not found" }, { status: 404 });
  }
  const input = await request.json<Record<string, unknown>>().catch(() => ({} as Record<string, unknown>));
  const id = cleanText(input.listener, 40);
  if (!id || !/^[a-z0-9-]+$/.test(id)) return json({ error: "listener is required" }, { status: 400 });
  const inputID = typeof input.input === "string" && /^[a-f0-9]{32}$/.test(input.input) ? input.input : null;
  const problem = cleanText(input.problem, 200) ?? null;
  const now = new Date().toISOString();
  const prior = await env.DB.prepare("SELECT * FROM live_listeners WHERE id=?").bind(id).first<ListenerRow>();
  // A problem keeps the time it began while it stays the same problem.
  const problemSince = problem ? (prior?.problem === problem && prior.problem_since ? prior.problem_since : now) : null;
  await env.DB.prepare(`INSERT INTO live_listeners(id,in_room,streaming,input_id,problem,problem_since,last_seen_at)
    VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET in_room=excluded.in_room,streaming=excluded.streaming,
    input_id=excluded.input_id,problem=excluded.problem,problem_since=excluded.problem_since,last_seen_at=excluded.last_seen_at`)
    .bind(id, input.inRoom === true ? 1 : 0, input.streaming === true ? 1 : 0, inputID, problem, problemSince, now).run();
  await reconcileLive(env);
  return json({ ok: true });
}

/** POST /v1/live/stream-events - Cloudflare's live input notifications
 *  (connected / disconnected), authenticated by the webhook secret header. */
export async function streamEvent(request: Request, env: Env): Promise<Response> {
  const secret = env.STREAM_WEBHOOK_SECRET;
  const header = request.headers.get("cf-webhook-auth") ?? "";
  if (!secret || !equalSecret(header, secret)) return json({ error: "Not found" }, { status: 404 });
  const payload = await request.json<{ data?: { input_id?: string; event_type?: string } }>().catch(() => null);
  const inputID = payload?.data?.input_id ?? "";
  const event = payload?.data?.event_type ?? "";
  if (!/^[a-f0-9]{32}$/.test(inputID) || !/^live_input\.(connected|disconnected|errored)$/.test(event)) {
    return json({ ok: true, ignored: true });
  }
  await env.DB.prepare(`INSERT INTO live_inputs(id,connected,updated_at) VALUES(?,?,?)
    ON CONFLICT(id) DO UPDATE SET connected=excluded.connected,updated_at=excluded.updated_at`)
    .bind(inputID, event === "live_input.connected" ? 1 : 0, new Date().toISOString()).run();
  await reconcileLive(env);
  return json({ ok: true });
}

/** Puts the broadcast in step with the listeners, and alerts on failures.
 *  Called on every heartbeat, every Stream event and every cron tick. */
export async function reconcileLive(env: Env, now = new Date()): Promise<void> {
  const listeners = (await env.DB.prepare("SELECT * FROM live_listeners ORDER BY id").all<ListenerRow>()).results ?? [];
  const inputs = (await env.DB.prepare("SELECT id,connected FROM live_inputs").all<{ id: string; connected: number }>()).results ?? [];
  const reported = new Map(inputs.map(row => [row.id, row.connected === 1]));

  // The hub is live on an input a fresh listener is streaming to and that
  // Stream itself has not reported disconnected. Inputs keep their configured
  // order, so the app stays on input A while it is up.
  const streamingInputs = new Set(listeners
    .filter(row => row.streaming === 1 && row.input_id && now.getTime() - Date.parse(row.last_seen_at) < STREAMING_FRESH_MS)
    .map(row => String(row.input_id)));
  const liveInput = streamInputs(env).find(id => streamingInputs.has(id) && reported.get(id) !== false);
  // A fresh listener in the room means the room is open, stream or not.
  const roomOpen = listeners.some(row => row.in_room === 1 && now.getTime() - Date.parse(row.last_seen_at) < STREAMING_FRESH_MS);
  await settleBroadcast(env, liveInput ? playbackURL(env, liveInput) : null, roomOpen, now);

  for (const listener of listeners) await checkListener(env, listener, now);
}

/** The room carries Daily Zikr in the evening and the Tahajjud zikr before
 *  dawn, Pakistan time. */
export function zikrTitle(now: Date): string {
  const hour = (now.getUTCHours() + 5) % 24;
  return hour < 7 ? "Tahajjud Zikr" : "Daily Zikr";
}

async function settleBroadcast(env: Env, hubURL: string | null, roomOpen: boolean, now: Date): Promise<void> {
  const row = await env.DB.prepare("SELECT state,source_mode,hub_stream_url,room_open FROM live_broadcasts WHERE id='official-live'")
    .first<{ state: string; source_mode: string; hub_stream_url: string | null; room_open: number }>();
  if (!row || row.source_mode === "manual") return;
  if (row.hub_stream_url === hubURL && (row.room_open === 1) === roomOpen) return;
  const at = now.toISOString();
  const title = zikrTitle(now);
  if (hubURL) {
    await env.DB.prepare(`UPDATE live_broadcasts SET hub_stream_url=?,room_open=?,state='live',title=?,
      started_at=CASE WHEN state='live' THEN started_at ELSE ? END,ended_at=NULL,updated_at=? WHERE id='official-live'`)
      .bind(hubURL, roomOpen ? 1 : 0, title, at, at).run();
    // Whichever source goes live first announces it; the other sees "live".
    if (row.state !== "live") {
      await sendTopicPush(env, `hub-live:${at.slice(0, 16)}`, "liveZikr", "Daily Zikr has started",
        "Join the official daily zikr in Darul Irfan.", "darulirfan://live/official-live").catch(() => 0);
    }
  } else if (roomOpen) {
    // No stream to play in the app yet: the room itself is offered to join.
    await env.DB.prepare(`UPDATE live_broadcasts SET hub_stream_url=NULL,room_open=1,state='live',
      title=CASE WHEN youtube_live=1 THEN title ELSE ? END,
      started_at=CASE WHEN state='live' THEN started_at ELSE ? END,ended_at=NULL,updated_at=? WHERE id='official-live'`)
      .bind(title, at, at).run();
    if (row.state !== "live") {
      await sendTopicPush(env, `room-open:${at.slice(0, 16)}`, "liveZikr", `${title} has started`,
        "Join the zikr from Darul Irfan.", "darulirfan://live/official-live").catch(() => 0);
    }
  } else {
    // The channel's live video, if it is on, keeps the broadcast live.
    await env.DB.prepare(`UPDATE live_broadcasts SET hub_stream_url=NULL,room_open=0,
      state=CASE WHEN youtube_live=1 THEN state ELSE 'ended' END,
      ended_at=CASE WHEN youtube_live=1 THEN ended_at ELSE ? END,updated_at=? WHERE id='official-live'`)
      .bind(at, at).run();
  }
}

async function checkListener(env: Env, listener: ListenerRow, now: Date): Promise<void> {
  const silentFor = now.getTime() - Date.parse(listener.last_seen_at);
  let trouble: string | null = null;
  if (silentFor > LISTENER_STALE_MS) {
    trouble = `Live listener ${listener.id} has stopped reporting (last heard ${Math.round(silentFor / 60_000)} min ago).`;
  } else if (listener.problem && listener.problem_since && now.getTime() - Date.parse(listener.problem_since) > PROBLEM_GRACE_MS) {
    trouble = `Live listener ${listener.id}: ${listener.problem}`;
  }
  if (trouble && !listener.alerted_at) {
    await env.DB.prepare("UPDATE live_listeners SET alerted_at=? WHERE id=?").bind(now.toISOString(), listener.id).run();
    await alertAdmins(env, `listener-down:${listener.id}:${now.toISOString().slice(0, 16)}`, trouble);
  } else if (!trouble && listener.alerted_at) {
    await env.DB.prepare("UPDATE live_listeners SET alerted_at=NULL WHERE id=?").bind(listener.id).run();
    await alertAdmins(env, `listener-up:${listener.id}:${now.toISOString().slice(0, 16)}`, `Live listener ${listener.id} is working again.`);
  }
}

/** Tells the super admins on their phones (push) and on WhatsApp. A failed
 *  alert channel never stops the other. */
export async function alertAdmins(env: Env, eventID: string, message: string): Promise<void> {
  const emails = (env.SUPER_ADMIN_EMAILS ?? "").split(",").map(value => value.trim().toLowerCase()).filter(Boolean);
  const listed = emails.length ? ` OR lower(m.email) IN (${emails.map(() => "?").join(",")})` : "";
  const devices = await env.DB.prepare(`SELECT DISTINCT md.installation_id FROM member_devices md JOIN members m ON m.id=md.member_id
    WHERE m.role='superadmin'${listed}`).bind(...emails).all<{ installation_id: string }>();
  const ids = (devices.results ?? []).map(row => row.installation_id);
  await sendPushToInstallations(env, eventID, "live-alerts", ids, "Daily Zikr live", message, "darulirfan://live/official-live")
    .catch(() => 0);
  await whatsappAlert(env, message).catch(() => undefined);
  console.warn(`live alert: ${message}`);
}

/** WhatsApp text to the alert numbers. Outside WhatsApp's 24-hour window a
 *  business may only send an approved template, so ALERT_WHATSAPP_TEMPLATE
 *  (one body parameter) is used when set. */
async function whatsappAlert(env: Env, message: string): Promise<void> {
  const numbers = (env.ALERT_WHATSAPP_NUMBERS ?? "").split(",").map(value => value.replace(/[^0-9]/g, "")).filter(Boolean);
  if (!numbers.length || !env.WHATSAPP_ACCESS_TOKEN || !env.WHATSAPP_PHONE_NUMBER_ID) return;
  const version = /^v\d+\.\d+$/.test(env.FACEBOOK_GRAPH_VERSION) ? env.FACEBOOK_GRAPH_VERSION : "v25.0";
  for (const to of numbers) {
    const body = env.ALERT_WHATSAPP_TEMPLATE
      ? { messaging_product: "whatsapp", to, type: "template", template: { name: env.ALERT_WHATSAPP_TEMPLATE, language: { code: "en" },
          components: [{ type: "body", parameters: [{ type: "text", text: message.slice(0, 1_000) }] }] } }
      : { messaging_product: "whatsapp", to, type: "text", text: { body: message } };
    await fetch(`https://graph.facebook.com/${version}/${env.WHATSAPP_PHONE_NUMBER_ID}/messages`, {
      method: "POST",
      headers: { authorization: `Bearer ${env.WHATSAPP_ACCESS_TOKEN}`, "content-type": "application/json" },
      body: JSON.stringify(body),
    });
  }
}

/** The listeners' state, for /health. No secrets, no input ids. */
export async function listenerHealth(env: Env): Promise<Array<Record<string, unknown>>> {
  const rows = (await env.DB.prepare("SELECT id,in_room,streaming,problem,last_seen_at FROM live_listeners ORDER BY id")
    .all<{ id: string; in_room: number; streaming: number; problem: string | null; last_seen_at: string }>()).results ?? [];
  return rows.map(row => ({ id: row.id, inRoom: row.in_room === 1, streaming: row.streaming === 1, problem: row.problem ?? undefined, lastSeenAt: row.last_seen_at }));
}
