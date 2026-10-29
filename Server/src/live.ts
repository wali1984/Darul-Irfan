import type { Env } from "./contracts";
import { LIVE_ALERT, sendPushToInstallations, sendTopicPush } from "./apns";
import { cleanText, json } from "./util";
import { paltalkRoomStatus } from "./paltalkRoom";

// The live zikr pipeline (Docs/LIVE_ZIKR_PIPELINE.md). Daily Zikr follows the
// channel's live video only (sources.ts; the owner's decision, 2026-10-28).
// This module records the listeners' and Stream's reports and keeps the
// Paltalk room's state from Paltalk's own directory beside the broadcast: the
// Tahajjud zikr is joined in that room.

/** A listener's report is trusted for this long. */
const REPORT_FRESH_MS = 90_000;

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
  // "r2": the listener relays through R2 (liveRelay.ts) instead of a Stream input.
  const inputID = typeof input.input === "string" && /^([a-f0-9]{32}|r2)$/.test(input.input) ? input.input : null;
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

/** Puts the room's state beside the broadcast. Called on every heartbeat,
 *  every Stream event and every cron tick. A listener streaming, to Stream or
 *  to the relay, no longer makes the broadcast live: Daily Zikr follows the
 *  channel's live video alone. */
export async function reconcileLive(env: Env, now = new Date()): Promise<void> {
  const listeners = (await env.DB.prepare("SELECT * FROM live_listeners ORDER BY id").all<ListenerRow>()).results ?? [];
  // Paltalk's own directory says the room is open; a listener in it also counts.
  const roomOpen = (await paltalkRoomStatus(env))?.online === true
    || listeners.some(row => row.in_room === 1 && now.getTime() - Date.parse(row.last_seen_at) < REPORT_FRESH_MS);
  await settleBroadcast(env, roomOpen, now);
  // No alerts about listeners: the owner retired them (2026-10-28).
}

/** The room carries Daily Zikr in the evening and the Tahajjud zikr before
 *  dawn, Pakistan time. */
export function zikrTitle(now: Date): string {
  const hour = (now.getUTCHours() + 5) % 24;
  return hour < 7 ? "Tahajjud Zikr" : "Daily Zikr";
}

/** The day in Pakistan, "2026-10-29": one Tahajjud zikr each. */
export function pakistanDay(now: Date): string {
  return new Date(now.getTime() + 5 * 3_600_000).toISOString().slice(0, 10);
}

/** The official broadcast is the channel's live video. The Paltalk room
 *  opening never makes it live - the app would show "live" with nothing to
 *  play - and is recorded beside it: the Tahajjud zikr is joined in the room,
 *  and its opening is announced. */
async function settleBroadcast(env: Env, roomOpen: boolean, now: Date): Promise<void> {
  const row = await env.DB.prepare("SELECT source_mode,hub_stream_url,room_open FROM live_broadcasts WHERE id='official-live'")
    .first<{ source_mode: string; hub_stream_url: string | null; room_open: number }>();
  if (!row || row.source_mode === "manual") return;
  if (!row.hub_stream_url && (row.room_open === 1) === roomOpen) return;
  const at = now.toISOString();
  const opened = roomOpen && row.room_open !== 1;
  // A relay link left from before is dropped, never followed; whether the
  // broadcast is live stays the video's to say.
  await env.DB.prepare("UPDATE live_broadcasts SET hub_stream_url=NULL,room_open=?,updated_at=? WHERE id='official-live'")
    .bind(roomOpen ? 1 : 0, at).run();
  // Daily Zikr is announced when the channel goes live; the room opening
  // before dawn announces the Tahajjud zikr, which is joined on Paltalk. Once
  // a day: a room that drops out of the directory for a minute and reappears
  // is not announced again.
  if (opened && zikrTitle(now) === "Tahajjud Zikr") {
    await sendTopicPush(env, `room-open:${pakistanDay(now)}`, "liveZikr", "Tahajjud Zikr has started",
      "Join it on Paltalk from Darul Irfan.", "darulirfan://zikr/tahajjud", LIVE_ALERT).catch(() => 0);
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
