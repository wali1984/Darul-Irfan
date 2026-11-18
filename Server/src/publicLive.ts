import type { Env } from "./contracts";
import { RECITATIONS } from "./groupZikrStages";
import { liveRow } from "./session";
import { json, sha256 } from "./util";

// The websites (oursheikh., namerica., uk. on wajidali.us and naqshbandiaowaisiah.us) show every
// named Halqah's live Zikr and let anyone join it from the browser (owner
// 2026-11-04): they give a name and a place, then hear and watch it with no
// controls. A visitor is not made a member of the Halqah; they are counted in
// the session's attendance, which the Halqah's admins see.

interface PublicLive { kind: string; title?: string; isTest?: boolean; startedAt?: string; sessionID?: string }

async function liveOf(env: Env, groupID: string): Promise<{ live: PublicLive; row: NonNullable<Awaited<ReturnType<typeof liveRow>>> } | null> {
  const row = await liveRow(env, groupID);
  // A test Zikr shows on the websites too, marked as a test (owner 2026-11-04).
  if (row?.state !== "live" || row.kind !== "zikr") return null;
  // The session id lets the live Worker follow one session; a random id with no secret value.
  return { row, live: { kind: row.kind, title: row.title ?? undefined, isTest: row.is_test ? true : undefined, startedAt: row.started_at ?? undefined,
    sessionID: row.session_id ?? undefined } };
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

/** A Halqah's clock-time Zikr times, for a website's countdown (north-america.,
 *  owner 2026-11-17). A prayer-anchored time moves each day; it is named, not timed. */
async function zikrTimes(env: Env, groupID: string) {
  const rows = await env.DB.prepare(`SELECT title,weekdays_json,start_hour,start_minute,time_zone,anchor,duration_minutes
      FROM group_zikr_sessions WHERE group_id=? AND is_active=1 ORDER BY start_hour,start_minute`).bind(groupID)
    .all<{ title: string; weekdays_json: string; start_hour: number; start_minute: number; time_zone: string; anchor: string | null; duration_minutes: number }>();
  return (rows.results ?? []).map(row => {
    let weekdays: number[] = [];
    try { weekdays = (JSON.parse(row.weekdays_json) as unknown[]).filter((day): day is number => Number.isInteger(day) && (day as number) >= 1 && (day as number) <= 7); } catch { /* none */ }
    return { title: row.title, weekdays, hour: row.start_hour, minute: row.start_minute, timeZone: row.time_zone,
      anchor: row.anchor ?? undefined, durationMinutes: row.duration_minutes };
  });
}

/** GET /v1/public/live?ids=: each named active Halqah, what is live in it and its stage
 *  (and, with times=1, its Zikr times). */
export async function publicLive(env: Env, ids: string[], withTimes = false): Promise<Record<string, unknown>> {
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
      stage: now ? await currentStage(env, id, now.live.startedAt) : null, ...(withTimes ? { times: await zikrTimes(env, id) } : {}) });
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

// Seen within this many seconds: here now (the page checks in every 30, the app every 60).
const PRESENT_SECONDS = 150;

/** Who is in the Zikr now, for a website that shows it (north-america., owner
 *  2026-11-17: "Enter your name so others can see you joined"). Website visitors
 *  by the name they gave there; the admin who started the Zikr by name, marked
 *  Admin; members listening in the app only as a number, since they never agreed
 *  to be named on a public page. Never a city. */
async function participants(env: Env, row: { session_id: string | null; started_by: string | null }, memberID: string) {
  const since = new Date(Date.now() - PRESENT_SECONDS * 1000).toISOString();
  const rows = await env.DB.prepare(`SELECT p.member_id,COALESCE(pp.display_name,m.display_name) AS name,
      COALESCE(m.apple_subject LIKE 'web-guest:%',0) AS web
    FROM group_live_presence p LEFT JOIN members m ON m.id=p.member_id LEFT JOIN sheikh_public_profiles pp ON pp.member_id=p.member_id
    WHERE p.session_id=? AND p.last_seen_at>=? ORDER BY p.first_seen_at LIMIT 1000`).bind(row.session_id, since)
    .all<{ member_id: string; name: string | null; web: number }>();
  const people: { name: string; admin?: true; you?: true }[] = [];
  let inApp = 0;
  const host = row.started_by && /^[0-9a-f]{32}$/.test(row.started_by)
    ? await env.DB.prepare("SELECT display_name FROM members WHERE id=?").bind(row.started_by).first<{ display_name: string | null }>() : null;
  if (host?.display_name) people.push({ name: host.display_name, admin: true, ...(row.started_by === memberID ? { you: true as const } : {}) });
  for (const person of rows.results ?? []) {
    if (person.member_id === row.started_by && host?.display_name) continue;
    if (!person.web) { inApp += 1; continue; }
    if (people.length < 300) people.push({ name: person.name ?? "Guest", ...(person.member_id === memberID ? { you: true as const } : {}) });
  }
  // The visitor asking is always listed, even past the first 300.
  if (!people.some(person => person.you)) {
    const me = (rows.results ?? []).find(person => person.member_id === memberID && person.web);
    if (me) people.push({ name: me.name ?? "Guest", you: true });
  }
  const hostAway = !!host?.display_name && !(rows.results ?? []).some(person => person.member_id === row.started_by);
  return { people, inApp, total: (rows.results ?? []).length + (hostAway ? 1 : 0) };
}

/** A joined visitor is counted and sees the stage. Live only (owner 2026-11-04):
 *  no recording or past video is ever handed to a website, and a room's sound
 *  never goes through RealtimeKit, which bills per listener; the sound reaches
 *  listeners through the Silsila's Realtime SFU feed (Tools/LiveRelay). */
async function presence(env: Env, groupID: string, memberID: string, withPeople = false): Promise<Response> {
  const now = await liveOf(env, groupID);
  if (!now?.row.session_id) return json({ error: "This Halqah's Zikr is not live right now.", live: null }, { status: 409 });
  const stamp = new Date().toISOString();
  await env.DB.prepare(`INSERT INTO group_live_presence(session_id,group_id,member_id,first_seen_at,last_seen_at) VALUES(?,?,?,?,?)
    ON CONFLICT(session_id,member_id) DO UPDATE SET last_seen_at=excluded.last_seen_at`)
    .bind(now.row.session_id, groupID, memberID, stamp, stamp).run();
  return json({ live: now.live, stage: await currentStage(env, groupID, now.live.startedAt),
    notice: now.row.notice ? { text: now.row.notice } : undefined,
    ...(withPeople ? { participants: await participants(env, now.row, memberID) } : {}) });
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
  return presence(env, groupID, memberID, input.participants === true);
}

/** POST /v1/public/halqahs/:id/presence {guestSecret}: still here; the latest playback clock and stage. */
export async function publicPresence(env: Env, groupID: string, input: Record<string, unknown>): Promise<Response> {
  const memberID = await visitor(env, input);
  if (memberID instanceof Response) return memberID;
  const known = await env.DB.prepare("SELECT id FROM members WHERE id=? AND apple_subject=?").bind(memberID, `web-guest:${memberID}`).first();
  if (!known) return json({ error: "Join first" }, { status: 401 });
  return presence(env, groupID, memberID, input.participants === true);
}
