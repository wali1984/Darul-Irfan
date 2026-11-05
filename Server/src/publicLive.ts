import type { Env } from "./contracts";
import { RECITATIONS } from "./groupZikrStages";
import { liveRow, sessionPayload } from "./session";
import { json, sha256 } from "./util";

// The websites (oursheikh., namerica., uk.naqshbandiaowaisiah.us) show every
// named Halqah's live Zikr and let anyone join it from the browser (owner
// 2026-11-04): they give a name and a place, then hear and watch it with no
// controls. A visitor is not made a member of the Halqah; they are counted in
// the session's attendance, which the Halqah's admins see.

interface PublicLive {
  kind: string; title?: string; isTest?: boolean; startedAt?: string;
  hasRoom: boolean; videoID?: string; recorded: boolean;
}

async function liveOf(env: Env, groupID: string): Promise<{ live: PublicLive; row: NonNullable<Awaited<ReturnType<typeof liveRow>>> } | null> {
  const row = await liveRow(env, groupID);
  // A test Zikr shows on the websites too, marked as a test (owner 2026-11-04).
  if (row?.state !== "live" || row.kind !== "zikr") return null;
  let queue: unknown[] = [];
  try { queue = JSON.parse(row.queue_json || "[]"); } catch { /* none */ }
  return { row, live: {
    kind: row.kind, title: row.title ?? undefined, isTest: row.is_test ? true : undefined, startedAt: row.started_at ?? undefined,
    hasRoom: !!row.room_id, videoID: row.video_id ?? undefined, recorded: Array.isArray(queue) && queue.length > 0,
  } };
}

/** The stage being followed in this session: the latest announcement since it began. */
async function currentStage(env: Env, groupID: string, startedAt: string | undefined) {
  const since = startedAt ?? new Date(Date.now() - 3 * 3_600_000).toISOString();
  const cue = await env.DB.prepare(`SELECT stage_id,title,title_ur,created_at FROM group_zikr_cues
      WHERE group_id=? AND hidden_at IS NULL AND created_at>=? ORDER BY sequence DESC LIMIT 1`)
    .bind(groupID, since).first<{ stage_id: string; title: string; title_ur: string | null; created_at: string }>();
  return cue ? { stageID: cue.stage_id, title: cue.title, titleUr: cue.title_ur ?? undefined, at: cue.created_at,
    arabic: RECITATIONS.find(recitation => recitation.id === cue.stage_id)?.arabic } : null;
}

/** GET /v1/public/live?ids=: each named active Halqah, what is live in it and its stage. */
export async function publicLive(env: Env, ids: string[]): Promise<Record<string, unknown>> {
  if (!ids.length) return { halqahs: [] };
  const rows = await env.DB.prepare(`SELECT id,name,description FROM member_groups WHERE is_active=1 AND id IN (${ids.map(() => "?").join(",")})`)
    .bind(...ids).all<{ id: string; name: string; description: string | null }>();
  const found = new Map((rows.results ?? []).map(row => [row.id, row]));
  const halqahs = [];
  for (const id of ids) {
    const group = found.get(id);
    if (!group) continue;
    const now = await liveOf(env, id);
    halqahs.push({ id, name: group.name, description: group.description ?? undefined, live: now?.live ?? null,
      stage: now ? await currentStage(env, id, now.live.startedAt) : null });
  }
  return { halqahs };
}

function field(value: unknown, maximum: number): string | null {
  if (typeof value !== "string") return null;
  const text = value.trim().replace(/\s+/g, " ");
  return text && text.length <= maximum && !/[\u0000-\u001f\u007f<>]/.test(text) ? text : null;
}

async function visitor(env: Env, input: Record<string, unknown>): Promise<string | Response> {
  if (typeof input.guestSecret !== "string" || !/^[0-9a-f]{64}$/.test(input.guestSecret)) {
    return json({ error: "A secure guest credential is required" }, { status: 400 });
  }
  return (await sha256(`web-guest:${input.guestSecret}`)).slice(0, 32);
}

/** What a joined visitor's browser plays: the live video or the recordings on the
 *  shared clock. A room's sound is never given to a website visitor through
 *  RealtimeKit, which bills per listener: the owner's budget (under $70 a month)
 *  sends listeners through the Realtime SFU feed instead (Tools/LiveRelay). */
async function presence(env: Env, groupID: string, memberID: string): Promise<Response> {
  const now = await liveOf(env, groupID);
  if (!now?.row.session_id) return json({ error: "This Halqah's Zikr is not live right now.", live: null }, { status: 409 });
  const stamp = new Date().toISOString();
  await env.DB.prepare(`INSERT INTO group_live_presence(session_id,group_id,member_id,first_seen_at,last_seen_at) VALUES(?,?,?,?,?)
    ON CONFLICT(session_id,member_id) DO UPDATE SET last_seen_at=excluded.last_seen_at`)
    .bind(now.row.session_id, groupID, memberID, stamp, stamp).run();
  const session = await sessionPayload(env, groupID, now.row, false);
  return json({ live: now.live, stage: await currentStage(env, groupID, now.live.startedAt),
    queue: session.queue, playback: session.playback, notice: session.notice });
}

/** POST /v1/public/halqahs/:id/join {name, city, countryCode, guestSecret}. */
export async function publicJoin(env: Env, groupID: string, input: Record<string, unknown>): Promise<Response> {
  const name = field(input.name, 80);
  const city = field(input.city, 100);
  const country = field(input.countryCode, 2)?.toUpperCase();
  if (!name || !city || !country || !/^[A-Z]{2}$/.test(country)) {
    return json({ error: "Enter your name, your city and your country." }, { status: 400 });
  }
  const memberID = await visitor(env, input);
  if (memberID instanceof Response) return memberID;
  const group = await env.DB.prepare("SELECT id FROM member_groups WHERE id=? AND is_active=1").bind(groupID).first();
  if (!group) return json({ error: "Not found" }, { status: 404 });
  // Nothing about the visitor is kept unless there is a live Zikr to join.
  if (!await liveOf(env, groupID)) return json({ error: "This Halqah's Zikr is not live right now.", live: null }, { status: 409 });
  const stamp = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare(`INSERT INTO members(id,apple_subject,display_name,email,created_at,last_seen_at) VALUES(?,?,?,NULL,?,?)
      ON CONFLICT(id) DO UPDATE SET display_name=excluded.display_name,last_seen_at=excluded.last_seen_at`)
      .bind(memberID, `web-guest:${memberID}`, name, stamp, stamp),
    env.DB.prepare(`INSERT INTO sheikh_public_profiles(member_id,display_name,city,country_code,contact_email,updated_at)
      VALUES(?,?,?,?,NULL,?) ON CONFLICT(member_id) DO UPDATE SET display_name=excluded.display_name,city=excluded.city,
      country_code=excluded.country_code,updated_at=excluded.updated_at`).bind(memberID, name, city, country, stamp),
  ]);
  return presence(env, groupID, memberID);
}

/** POST /v1/public/halqahs/:id/presence {guestSecret}: still here; the latest playback clock and stage. */
export async function publicPresence(env: Env, groupID: string, input: Record<string, unknown>): Promise<Response> {
  const memberID = await visitor(env, input);
  if (memberID instanceof Response) return memberID;
  const known = await env.DB.prepare("SELECT id FROM members WHERE id=? AND apple_subject=?").bind(memberID, `web-guest:${memberID}`).first();
  if (!known) return json({ error: "Join first" }, { status: 401 });
  return presence(env, groupID, memberID);
}
