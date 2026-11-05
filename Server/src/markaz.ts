import type { Env } from "./contracts";
import { halqahRole, isSuperAdmin, memberRole, notifyGroup, roleIn } from "./community";
import { upsertMembership } from "./members";
import { sendPushToInstallations } from "./apns";
import { cleanText, json, sha256 } from "./util";

// The Silsila Markaz (owner 2026-11-05): every Halqah's Zikr and meetings in
// one place - daily and monthly reports, who attends, trends, the
// organisation by region, notices to many Halqahs at once, and the sign-in of
// the reporting website. Super admins and the Markaz's Administrators and
// Admins see it ("officers"); nobody else. Test sessions are never counted.
// The contract is Docs/MARKAZ_ANALYTICS_API.md.

export const MARKAZ_ID = "silsila-markaz";
const AUTOMATED = new Set(["schedule", "service-paltalk-relay"]);
const PRESENT_SECONDS = 150;
const MAX_DAYS = 400;
const DAY = 86_400_000;

const forbidden = () => json({ error: "Markaz access required" }, { status: 403 });
const superOnly = () => json({ error: "Super admin only" }, { status: 403 });
const notFound = () => json({ error: "Not found" }, { status: 404 });
const badRequest = (error: string) => json({ error }, { status: 400 });

// MARK: - Access

export async function markazAccess(env: Env, memberID: string): Promise<{ canReport: boolean; isSuperAdmin: boolean; markazRole: string | null }> {
  const role = await memberRole(env, memberID);
  const inMarkaz = await roleIn(env, memberID, MARKAZ_ID);
  const superAdmin = role === "superadmin";
  return { canReport: superAdmin || inMarkaz === "admin" || inMarkaz === "administrator", isSuperAdmin: superAdmin, markazRole: inMarkaz };
}

/** GET /v1/markaz/access */
export async function access(env: Env, memberID: string): Promise<Response> {
  const result = await markazAccess(env, memberID);
  return json({ ...result, markazGroupID: MARKAZ_ID });
}

// MARK: - Dates in the reader's time zone

const formatters = new Map<string, Intl.DateTimeFormat>();

function zoneOf(value: string | null): string {
  const zone = (value ?? "").trim() || "UTC";
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: zone });
    return zone;
  } catch {
    return "UTC";
  }
}

/** The local date (YYYY-MM-DD), weekday (1 = Monday) and hour of an instant. */
function local(iso: string, zone: string): { date: string; weekday: number; hour: number } {
  let format = formatters.get(zone);
  if (!format) {
    format = new Intl.DateTimeFormat("en-US", { timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit",
      weekday: "short", hour: "2-digit", hourCycle: "h23" });
    formatters.set(zone, format);
  }
  const parts = format.formatToParts(new Date(iso));
  const value = (type: string) => parts.find(part => part.type === type)?.value ?? "";
  const weekday = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].indexOf(value("weekday")) + 1;
  return { date: `${value("year")}-${value("month")}-${value("day")}`, weekday, hour: Number(value("hour")) % 24 };
}

const validDate = (value: string | null): string | null =>
  value && /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(`${value}T00:00:00Z`)) ? value : null;
const addDays = (date: string, days: number): string => new Date(Date.parse(`${date}T00:00:00Z`) + days * DAY).toISOString().slice(0, 10);
const daysBetween = (from: string, to: string): number => Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / DAY) + 1;
const today = (zone: string): string => local(new Date().toISOString(), zone).date;
const round1 = (value: number): number => Math.round(value * 10) / 10;
const change = (now: number, before: number): number | null => before > 0 ? Math.round(((now - before) / before) * 1000) / 1000 : null;

// MARK: - Loading

interface Group { id: string; name: string; region: string | null; kind: string; country_code: string | null; city: string | null }
interface SessionRow {
  session_id: string; group_id: string; kind: string; title: string | null; started_at: string; ended_at: string;
  started_by: string | null; starter: string | null;
}
interface Presence {
  session_id: string; group_id: string; member_id: string; first_seen_at: string; last_seen_at: string;
  name: string | null; city: string | null; country: string | null; web: number;
}
interface Scope { kind: "all" | "region" | "halqah"; id: string | null; name: string; groups: Group[] }
interface Window { from: string; to: string; zone: string }

async function activeGroups(env: Env): Promise<Group[]> {
  const rows = await env.DB.prepare("SELECT id,name,region,kind,country_code,city FROM member_groups WHERE is_active=1 ORDER BY name COLLATE NOCASE")
    .all<Group>();
  return rows.results ?? [];
}

function scopeOf(groups: Group[], value: string | null): Scope | null {
  const raw = (value ?? "all").trim();
  if (!raw || raw === "all") return { kind: "all", id: null, name: "All Halqahs", groups };
  if (raw.startsWith("region:")) {
    const region = raw.slice(7).trim();
    const chosen = groups.filter(group => (group.region ?? "") === region);
    return chosen.length ? { kind: "region", id: region, name: region, groups: chosen } : null;
  }
  if (raw.startsWith("halqah:")) {
    const group = groups.find(item => item.id === raw.slice(7));
    return group ? { kind: "halqah", id: group.id, name: group.name, groups: [group] } : null;
  }
  return null;
}

/** Sessions (not tests) that started on a local date in the window, and who was present. */
async function load(env: Env, window: Window, groupIDs: Set<string>, kind: string): Promise<{ sessions: SessionRow[]; presence: Presence[] }> {
  // A day either side in UTC, then the exact local dates.
  const lower = `${addDays(window.from, -1)}T00:00:00.000Z`, upper = `${addDays(window.to, 2)}T00:00:00.000Z`;
  const rows = await env.DB.prepare(`SELECT h.session_id,h.group_id,h.kind,h.title,h.started_at,h.ended_at,h.started_by,m.display_name AS starter
      FROM group_live_history h LEFT JOIN members m ON m.id=h.started_by
      WHERE h.is_test=0 AND h.started_at>=? AND h.started_at<? ORDER BY h.started_at DESC`)
    .bind(lower, upper).all<SessionRow>();
  const sessions = (rows.results ?? []).filter(row => {
    if (!groupIDs.has(row.group_id)) return false;
    if (kind !== "all" && row.kind !== kind) return false;
    const date = local(row.started_at, window.zone).date;
    return date >= window.from && date <= window.to;
  });
  if (!sessions.length) return { sessions, presence: [] };
  const ids = new Set(sessions.map(row => row.session_id));
  const seen = await env.DB.prepare(`SELECT p.session_id,p.group_id,p.member_id,p.first_seen_at,p.last_seen_at,
        COALESCE(pp.display_name,m.display_name) AS name,pp.city,pp.country_code AS country,
        CASE WHEN m.apple_subject LIKE 'web-guest:%' THEN 1 ELSE 0 END AS web
      FROM group_live_presence p LEFT JOIN members m ON m.id=p.member_id LEFT JOIN sheikh_public_profiles pp ON pp.member_id=p.member_id
      WHERE p.first_seen_at>=? AND p.first_seen_at<?`)
    .bind(lower, `${addDays(window.to, 3)}T00:00:00.000Z`).all<Presence>();
  return { sessions, presence: (seen.results ?? []).filter(row => ids.has(row.session_id)) };
}

const minutesOf = (start: string, end: string): number => Math.max(0, Math.round((Date.parse(end) - Date.parse(start)) / 60_000));
const sessionPresence = (presence: Presence[]): Map<string, Presence[]> => {
  const map = new Map<string, Presence[]>();
  for (const row of presence) {
    const list = map.get(row.session_id) ?? [];
    list.push(row);
    map.set(row.session_id, list);
  }
  return map;
};

/** Counts within the sessions' own time: stages called, chat, and duas. */
async function sessionActivity(env: Env, sessions: SessionRow[], window: Window): Promise<{ cues: Map<string, number>; chat: number; duas: number }> {
  const cues = new Map<string, number>();
  if (!sessions.length) return { cues, chat: 0, duas: 0 };
  const lower = `${addDays(window.from, -1)}T00:00:00.000Z`, upper = `${addDays(window.to, 3)}T00:00:00.000Z`;
  const [cueRows, chatRows, duaRows] = await Promise.all([
    env.DB.prepare("SELECT group_id,created_at FROM group_zikr_cues WHERE hidden_at IS NULL AND created_at>=? AND created_at<?")
      .bind(lower, upper).all<{ group_id: string; created_at: string }>(),
    env.DB.prepare("SELECT group_id,created_at FROM group_stage_messages WHERE hidden_at IS NULL AND created_at>=? AND created_at<?")
      .bind(lower, upper).all<{ group_id: string; created_at: string }>(),
    env.DB.prepare("SELECT group_id,created_at FROM group_dua_requests WHERE removed_at IS NULL AND created_at>=? AND created_at<?")
      .bind(lower, upper).all<{ group_id: string; created_at: string }>(),
  ]);
  const within = (row: { group_id: string; created_at: string }) =>
    sessions.find(session => session.group_id === row.group_id && row.created_at >= session.started_at && row.created_at <= session.ended_at);
  for (const row of cueRows.results ?? []) {
    const session = within(row);
    if (session) cues.set(session.session_id, (cues.get(session.session_id) ?? 0) + 1);
  }
  const chat = (chatRows.results ?? []).filter(within).length;
  const duas = (duaRows.results ?? []).filter(within).length;
  return { cues, chat, duas };
}

async function memberCounts(env: Env): Promise<Map<string, number>> {
  const rows = await env.DB.prepare("SELECT group_id,COUNT(*) AS n FROM member_group_members GROUP BY group_id").all<{ group_id: string; n: number }>();
  return new Map((rows.results ?? []).map(row => [row.group_id, Number(row.n)]));
}

async function lastSessions(env: Env): Promise<Map<string, string>> {
  const rows = await env.DB.prepare("SELECT group_id,MAX(started_at) AS at FROM group_live_history WHERE is_test=0 GROUP BY group_id")
    .all<{ group_id: string; at: string }>();
  return new Map((rows.results ?? []).map(row => [row.group_id, row.at]));
}

function statusOf(last: string | undefined, now = Date.now()): "active" | "quiet" | "inactive" {
  if (!last) return "inactive";
  const days = (now - Date.parse(last)) / DAY;
  return days <= 7 ? "active" : days <= 21 ? "quiet" : "inactive";
}

// MARK: - Summaries

interface Summary {
  sessions: number; zikrSessions: number; meetings: number; attendance: number; uniqueAttendees: number;
  appAttendance: number; webAttendance: number; averageAttendance: number; averageMinutes: number; totalMinutes: number;
  activeHalqahs: number; totalHalqahs: number; members: number; newMembers: number; duaRequests: number;
  stagesAnnounced: number; chatMessages: number; automatedStarts: number;
}

async function summarise(env: Env, window: Window, scope: Scope, kind: string, sessions: SessionRow[], presence: Presence[]): Promise<Summary> {
  const ids = scope.groups.map(group => group.id);
  const marks = ids.map(() => "?").join(",");
  const [members, joined, activity] = await Promise.all([
    ids.length ? env.DB.prepare(`SELECT COUNT(DISTINCT member_id) AS n FROM member_group_members WHERE group_id IN (${marks})`).bind(...ids).first<{ n: number }>() : null,
    ids.length ? env.DB.prepare(`SELECT added_at FROM member_group_members WHERE group_id IN (${marks}) AND added_at>=? AND added_at<?`)
      .bind(...ids, `${addDays(window.from, -1)}T00:00:00.000Z`, `${addDays(window.to, 2)}T00:00:00.000Z`).all<{ added_at: string }>() : null,
    sessionActivity(env, sessions, window),
  ]);
  const totalMinutes = sessions.reduce((sum, row) => sum + minutesOf(row.started_at, row.ended_at), 0);
  const web = presence.filter(row => row.web).length;
  const newMembers = (joined?.results ?? []).filter(row => {
    const date = local(row.added_at, window.zone).date;
    return date >= window.from && date <= window.to;
  }).length;
  return {
    sessions: sessions.length,
    zikrSessions: sessions.filter(row => row.kind === "zikr").length,
    meetings: sessions.filter(row => row.kind === "meeting").length,
    attendance: presence.length,
    uniqueAttendees: new Set(presence.map(row => row.member_id)).size,
    appAttendance: presence.length - web,
    webAttendance: web,
    averageAttendance: sessions.length ? round1(presence.length / sessions.length) : 0,
    averageMinutes: sessions.length ? Math.round(totalMinutes / sessions.length) : 0,
    totalMinutes,
    activeHalqahs: new Set(sessions.map(row => row.group_id)).size,
    totalHalqahs: scope.groups.filter(group => group.kind === "halqah").length,
    members: Number(members?.n ?? 0),
    newMembers,
    duaRequests: activity.duas,
    stagesAnnounced: [...activity.cues.values()].reduce((sum, n) => sum + n, 0),
    chatMessages: activity.chat,
    automatedStarts: sessions.filter(row => AUTOMATED.has(row.started_by ?? "")).length,
  };
}

function sessionItem(row: SessionRow, groups: Map<string, Group>, presence: Presence[]) {
  const web = presence.filter(item => item.web).length;
  return {
    id: row.session_id, groupID: row.group_id, groupName: groups.get(row.group_id)?.name ?? row.group_id, kind: row.kind,
    title: row.title ?? (row.kind === "meeting" ? "Meeting" : "Halqah Zikr"), startedAt: row.started_at, endedAt: row.ended_at,
    minutes: minutesOf(row.started_at, row.ended_at), attendance: presence.length, app: presence.length - web, web,
    startedBy: AUTOMATED.has(row.started_by ?? "") ? null : row.starter ?? null,
    automated: AUTOMATED.has(row.started_by ?? ""),
  };
}

function attendee(row: Presence) {
  return {
    memberID: row.member_id, name: row.name ?? "Member", city: row.city ?? undefined, country: row.country ?? undefined,
    via: row.web ? "web" : "app", joinedAt: row.first_seen_at, minutes: minutesOf(row.first_seen_at, row.last_seen_at),
  };
}

function daily(window: Window, sessions: SessionRow[], bySession: Map<string, Presence[]>) {
  const days: { date: string; sessions: number; attendance: number; unique: number }[] = [];
  const index = new Map<string, { sessions: number; attendance: number; people: Set<string> }>();
  for (let date = window.from; date <= window.to; date = addDays(date, 1)) index.set(date, { sessions: 0, attendance: 0, people: new Set() });
  for (const row of sessions) {
    const bucket = index.get(local(row.started_at, window.zone).date);
    if (!bucket) continue;
    const present = bySession.get(row.session_id) ?? [];
    bucket.sessions += 1;
    bucket.attendance += present.length;
    for (const person of present) bucket.people.add(person.member_id);
  }
  for (const [date, bucket] of index) days.push({ date, sessions: bucket.sessions, attendance: bucket.attendance, unique: bucket.people.size });
  return days;
}

function weekdayHour(window: Window, sessions: SessionRow[], bySession: Map<string, Presence[]>) {
  const cells = new Map<string, { weekday: number; hour: number; sessions: number; attendance: number }>();
  for (const row of sessions) {
    const when = local(row.started_at, window.zone);
    const key = `${when.weekday}:${when.hour}`;
    const cell = cells.get(key) ?? { weekday: when.weekday, hour: when.hour, sessions: 0, attendance: 0 };
    cell.sessions += 1;
    cell.attendance += (bySession.get(row.session_id) ?? []).length;
    cells.set(key, cell);
  }
  return [...cells.values()].sort((a, b) => a.weekday - b.weekday || a.hour - b.hour);
}

/** Per Halqah in the scope, with the change from the period before. */
async function halqahRows(env: Env, scope: Scope, sessions: SessionRow[], bySession: Map<string, Presence[]>, previous: SessionRow[], previousBy: Map<string, Presence[]>) {
  const [counts, last] = await Promise.all([memberCounts(env), lastSessions(env)]);
  return scope.groups.map(group => {
    const mine = sessions.filter(row => row.group_id === group.id);
    const present = mine.flatMap(row => bySession.get(row.session_id) ?? []);
    const before = previous.filter(row => row.group_id === group.id).flatMap(row => previousBy.get(row.session_id) ?? []).length;
    const unique = new Set(present.map(row => row.member_id)).size;
    const members = counts.get(group.id) ?? 0;
    return {
      id: group.id, name: group.name, region: group.region ?? undefined, kind: group.kind,
      sessions: mine.length, attendance: present.length, averageAttendance: mine.length ? round1(present.length / mine.length) : 0,
      uniqueAttendees: unique, members, attendanceRate: members ? Math.round(Math.min(1, unique / members) * 100) / 100 : null,
      lastSessionAt: last.get(group.id) ?? null, change: change(present.length, before), status: statusOf(last.get(group.id)),
    };
  }).sort((a, b) => b.attendance - a.attendance || a.name.localeCompare(b.name));
}

function regionRows(halqahs: { region?: string; sessions: number; attendance: number; members: number }[]) {
  const map = new Map<string, { name: string; halqahs: number; sessions: number; attendance: number; members: number }>();
  for (const row of halqahs) {
    const name = row.region ?? "Not placed";
    const region = map.get(name) ?? { name, halqahs: 0, sessions: 0, attendance: 0, members: 0 };
    region.halqahs += 1; region.sessions += row.sessions; region.attendance += row.attendance; region.members += row.members;
    map.set(name, region);
  }
  return [...map.values()].sort((a, b) => b.attendance - a.attendance);
}

function countries(presence: Presence[]) {
  const people = new Map<string, string>();
  for (const row of presence) if (row.country) people.set(row.member_id, row.country.toUpperCase());
  const counts = new Map<string, number>();
  for (const code of people.values()) counts.set(code, (counts.get(code) ?? 0) + 1);
  return [...counts.entries()].map(([code, attendees]) => ({ code, attendees })).sort((a, b) => b.attendees - a.attendees);
}

function people(presence: Presence[], groups: Map<string, Group>, zone: string) {
  const map = new Map<string, { memberID: string; name: string; via: string; sessions: Set<string>; days: Set<string>; halqahs: Set<string>; lastSeenAt: string }>();
  for (const row of presence) {
    const person = map.get(row.member_id) ?? { memberID: row.member_id, name: row.name ?? "Member", via: row.web ? "web" : "app",
      sessions: new Set<string>(), days: new Set<string>(), halqahs: new Set<string>(), lastSeenAt: row.last_seen_at };
    person.sessions.add(row.session_id);
    person.days.add(local(row.first_seen_at, zone).date);
    person.halqahs.add(groups.get(row.group_id)?.name ?? row.group_id);
    if (row.last_seen_at > person.lastSeenAt) person.lastSeenAt = row.last_seen_at;
    map.set(row.member_id, person);
  }
  return [...map.values()]
    .map(person => ({ memberID: person.memberID, name: person.name, via: person.via, sessions: person.sessions.size, days: person.days.size,
      halqahs: [...person.halqahs], lastSeenAt: person.lastSeenAt }))
    .sort((a, b) => b.sessions - a.sessions || a.name.localeCompare(b.name));
}

/** People who came 3+ times in the six months before the last three weeks, and not since. */
async function needsCare(env: Env, scope: Scope, end: string, zone: string) {
  const ids = new Set(scope.groups.map(group => group.id));
  const endAt = Date.parse(`${addDays(end, 1)}T00:00:00Z`);
  const recent = new Date(endAt - 21 * DAY).toISOString(), since = new Date(endAt - 180 * DAY).toISOString();
  const rows = await env.DB.prepare(`SELECT p.member_id,p.group_id,p.last_seen_at,COALESCE(pp.display_name,m.display_name) AS name
      FROM group_live_presence p JOIN group_live_history h ON h.session_id=p.session_id AND h.is_test=0
      JOIN members m ON m.id=p.member_id LEFT JOIN sheikh_public_profiles pp ON pp.member_id=p.member_id
      WHERE p.first_seen_at>=? AND p.first_seen_at<? AND m.apple_subject NOT LIKE 'web-guest:%'`)
    .bind(since, new Date(endAt).toISOString()).all<{ member_id: string; group_id: string; last_seen_at: string; name: string | null }>();
  const map = new Map<string, { name: string; count: number; last: string; groups: Map<string, number> }>();
  for (const row of rows.results ?? []) {
    if (!ids.has(row.group_id)) continue;
    const person = map.get(row.member_id) ?? { name: row.name ?? "Member", count: 0, last: row.last_seen_at, groups: new Map() };
    person.count += 1;
    if (row.last_seen_at > person.last) person.last = row.last_seen_at;
    person.groups.set(row.group_id, (person.groups.get(row.group_id) ?? 0) + 1);
    map.set(row.member_id, person);
  }
  const names = new Map(scope.groups.map(group => [group.id, group.name]));
  void zone;
  return [...map.entries()]
    .filter(([, person]) => person.count >= 3 && person.last < recent)
    .map(([memberID, person]) => {
      const top = [...person.groups.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? "";
      return { memberID, name: person.name, lastSeenAt: person.last, sessionsBefore: person.count, halqah: names.get(top) ?? top };
    })
    .sort((a, b) => b.sessionsBefore - a.sessionsBefore)
    .slice(0, 50);
}

type Insight = { level: "good" | "watch" | "alert"; title: string; detail: string; halqahID: string | null };

function insights(summary: Summary, before: { attendance: number; sessions: number }, halqahs: Awaited<ReturnType<typeof halqahRows>>,
  cells: ReturnType<typeof weekdayHour>, care: number): Insight[] {
  const out: Insight[] = [];
  const moved = change(summary.attendance, before.attendance);
  if (moved !== null && moved >= 0.1) out.push({ level: "good", title: `Attendance up ${Math.round(moved * 100)}%`,
    detail: `${summary.attendance} present, against ${before.attendance} in the period before.`, halqahID: null });
  if (moved !== null && moved <= -0.15) out.push({ level: moved <= -0.3 ? "alert" : "watch", title: `Attendance down ${Math.round(-moved * 100)}%`,
    detail: `${summary.attendance} present, against ${before.attendance} in the period before.`, halqahID: null });
  for (const row of halqahs.filter(item => item.kind === "halqah" && item.status === "inactive" && item.members > 0)) {
    out.push({ level: "alert", title: `${row.name}: no Zikr in three weeks`, detail: row.lastSessionAt ? "The last session was over 21 days ago." : "No session has been held yet.", halqahID: row.id });
  }
  for (const row of halqahs.filter(item => item.kind === "halqah" && item.status === "quiet")) {
    out.push({ level: "watch", title: `${row.name} has been quiet`, detail: "No session in the last week.", halqahID: row.id });
  }
  for (const row of halqahs.filter(item => item.change !== null && item.change <= -0.3 && item.attendance > 0)) {
    out.push({ level: "watch", title: `${row.name}: attendance down ${Math.round(-(row.change ?? 0) * 100)}%`, detail: `${row.attendance} present this period.`, halqahID: row.id });
  }
  const best = halqahs.filter(item => item.attendanceRate !== null && item.members >= 3).sort((a, b) => (b.attendanceRate ?? 0) - (a.attendanceRate ?? 0))[0];
  if (best && (best.attendanceRate ?? 0) > 0) out.push({ level: "good", title: `${best.name} leads in attendance`,
    detail: `${Math.round((best.attendanceRate ?? 0) * 100)}% of its members came at least once.`, halqahID: best.id });
  if (summary.automatedStarts) out.push({ level: "good", title: `${summary.automatedStarts} sessions ran by themselves`,
    detail: "Started from Paltalk or at a Zikr time, with no one tapping Start.", halqahID: null });
  if (summary.webAttendance) out.push({ level: "good", title: `${summary.webAttendance} joined from the websites`,
    detail: "Visitors who are not yet in the app, following the live stage.", halqahID: null });
  const peak = [...cells].sort((a, b) => b.attendance - a.attendance)[0];
  if (peak && peak.attendance) {
    const day = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][peak.weekday - 1];
    out.push({ level: "good", title: `Busiest: ${day} at ${String(peak.hour).padStart(2, "0")}:00`, detail: `${peak.attendance} present across ${peak.sessions} sessions at that hour.`, halqahID: null });
  }
  if (care) out.push({ level: "watch", title: `${care} regulars not seen in three weeks`, detail: "They came often before; a call from their Halqah may help.", halqahID: null });
  if (!summary.sessions) out.push({ level: "alert", title: "No sessions in this period", detail: "Nothing was held in the chosen Halqahs.", halqahID: null });
  return out;
}

// MARK: - Analytics

function windowFrom(url: URL, zone: string): Window | string {
  const to = validDate(url.searchParams.get("to")) ?? today(zone);
  const from = validDate(url.searchParams.get("from")) ?? addDays(to, -29);
  if (from > to) return "The start date is after the end date.";
  if (daysBetween(from, to) > MAX_DAYS) return `Choose at most ${MAX_DAYS} days.`;
  return { from, to, zone };
}

/** GET /v1/markaz/analytics */
export async function analytics(env: Env, memberID: string, url: URL): Promise<Response> {
  if (!(await markazAccess(env, memberID)).canReport) return forbidden();
  const zone = zoneOf(url.searchParams.get("tz"));
  const window = windowFrom(url, zone);
  if (typeof window === "string") return badRequest(window);
  const kind = ["zikr", "meeting"].includes(url.searchParams.get("kind") ?? "") ? String(url.searchParams.get("kind")) : "all";
  const groups = await activeGroups(env);
  const scope = scopeOf(groups, url.searchParams.get("scope"));
  if (!scope) return notFound();
  return json(await report(env, window, scope, kind, groups));
}

async function report(env: Env, window: Window, scope: Scope, kind: string, groups: Group[]) {
  const ids = new Set(scope.groups.map(group => group.id));
  const days = daysBetween(window.from, window.to);
  const previousWindow = { from: addDays(window.from, -days), to: addDays(window.from, -1), zone: window.zone };
  const [current, previous] = await Promise.all([load(env, window, ids, kind), load(env, previousWindow, ids, kind)]);
  const bySession = sessionPresence(current.presence), previousBy = sessionPresence(previous.presence);
  const byID = new Map(groups.map(group => [group.id, group]));
  const summary = await summarise(env, window, scope, kind, current.sessions, current.presence);
  const halqahs = await halqahRows(env, scope, current.sessions, bySession, previous.sessions, previousBy);
  const cells = weekdayHour(window, current.sessions, bySession);
  const care = await needsCare(env, scope, window.to, window.zone);
  const everyone = people(current.presence, byID, window.zone);
  const before = { from: previousWindow.from, to: previousWindow.to, sessions: previous.sessions.length, attendance: previous.presence.length,
    uniqueAttendees: new Set(previous.presence.map(row => row.member_id)).size,
    averageAttendance: previous.sessions.length ? round1(previous.presence.length / previous.sessions.length) : 0 };
  return {
    range: { from: window.from, to: window.to, days, tz: window.zone },
    scope: { kind: scope.kind, id: scope.id, name: scope.name },
    generatedAt: new Date().toISOString(),
    summary,
    previous: before,
    daily: daily(window, current.sessions, bySession),
    weekdayHour: cells,
    halqahs,
    regions: regionRows(halqahs),
    countries: countries(current.presence),
    regulars: everyone.filter(person => person.via === "app").slice(0, 25)
      .map(person => ({ memberID: person.memberID, name: person.name, sessions: person.sessions, lastSeenAt: person.lastSeenAt, halqahs: person.halqahs })),
    needsCare: care,
    sessions: current.sessions.slice(0, 200).map(row => sessionItem(row, byID, bySession.get(row.session_id) ?? [])),
    insights: insights(summary, before, halqahs, cells, care.length),
    people: everyone,
  };
}

// MARK: - Reports

/** GET /v1/markaz/reports/daily */
export async function dailyReport(env: Env, memberID: string, url: URL): Promise<Response> {
  if (!(await markazAccess(env, memberID)).canReport) return forbidden();
  const zone = zoneOf(url.searchParams.get("tz"));
  const date = validDate(url.searchParams.get("date")) ?? addDays(today(zone), -1);
  return json(await dayReport(env, date, zone));
}

async function dayReport(env: Env, date: string, zone: string) {
  const groups = await activeGroups(env);
  const scope: Scope = { kind: "all", id: null, name: "All Halqahs", groups };
  const window = { from: date, to: date, zone };
  const ids = new Set(groups.map(group => group.id));
  const [current, before] = await Promise.all([load(env, window, ids, "all"), load(env, { from: addDays(date, -1), to: addDays(date, -1), zone }, ids, "all")]);
  const bySession = sessionPresence(current.presence);
  const byID = new Map(groups.map(group => [group.id, group]));
  const summary = await summarise(env, window, scope, "all", current.sessions, current.presence);
  const halqahs = groups.filter(group => current.sessions.some(row => row.group_id === group.id)).map(group => ({
    id: group.id, name: group.name, region: group.region ?? undefined,
    sessions: current.sessions.filter(row => row.group_id === group.id).reverse().map(row => ({
      ...sessionItem(row, byID, bySession.get(row.session_id) ?? []),
      attendees: (bySession.get(row.session_id) ?? []).sort((a, b) => a.first_seen_at.localeCompare(b.first_seen_at)).map(attendee),
    })),
  }));
  // Halqahs that keep a Zikr time on that weekday but held nothing.
  const weekday = new Date(`${date}T12:00:00Z`).getUTCDay() + 1;
  const times = await env.DB.prepare("SELECT DISTINCT group_id,weekdays_json FROM group_zikr_sessions WHERE is_active=1")
    .all<{ group_id: string; weekdays_json: string }>();
  const expected = new Set((times.results ?? []).filter(row => {
    try { return (JSON.parse(row.weekdays_json) as number[]).includes(weekday); } catch { return false; }
  }).map(row => row.group_id));
  const noSession = groups.filter(group => expected.has(group.id) && !halqahs.some(row => row.id === group.id)).map(group => ({ id: group.id, name: group.name }));
  const halqahRowsForInsights = await halqahRows(env, scope, current.sessions, bySession, before.sessions, sessionPresence(before.presence));
  return {
    date, tz: zone, summary,
    previousDay: { sessions: before.sessions.length, attendance: before.presence.length },
    halqahs, noSession,
    insights: insights(summary, { attendance: before.presence.length, sessions: before.sessions.length },
      halqahRowsForInsights.filter(row => row.sessions > 0 || noSession.some(item => item.id === row.id)), weekdayHour(window, current.sessions, bySession), 0)
      .filter(item => !item.title.startsWith("Busiest")),
  };
}

/** GET /v1/markaz/reports/monthly */
export async function monthlyReport(env: Env, memberID: string, url: URL): Promise<Response> {
  if (!(await markazAccess(env, memberID)).canReport) return forbidden();
  const zone = zoneOf(url.searchParams.get("tz"));
  const asked = url.searchParams.get("month");
  let month: string;
  if (asked && /^\d{4}-(0[1-9]|1[0-2])$/.test(asked)) month = asked;
  else {
    const now = today(zone);
    month = addDays(`${now.slice(0, 7)}-01`, -1).slice(0, 7);
  }
  return json(await monthReport(env, month, zone));
}

async function monthReport(env: Env, month: string, zone: string) {
  const from = `${month}-01`;
  const next = new Date(Date.UTC(Number(month.slice(0, 4)), Number(month.slice(5, 7)), 1)).toISOString().slice(0, 10);
  const to = addDays(next, -1);
  const groups = await activeGroups(env);
  const scope: Scope = { kind: "all", id: null, name: "All Halqahs", groups };
  const full = await report(env, { from, to, zone }, scope, "all", groups);
  const joined = await env.DB.prepare(`SELECT COALESCE(m.display_name,'Member') AS name,g.name AS halqah,p.added_at FROM member_group_members p
      JOIN members m ON m.id=p.member_id JOIN member_groups g ON g.id=p.group_id
      WHERE p.added_at>=? AND p.added_at<? ORDER BY p.added_at`)
    .bind(`${addDays(from, -1)}T00:00:00.000Z`, `${addDays(to, 2)}T00:00:00.000Z`).all<{ name: string; halqah: string; added_at: string }>();
  return {
    month, tz: zone, summary: full.summary, previous: full.previous, daily: full.daily, weekdayHour: full.weekdayHour,
    halqahs: full.halqahs, regions: full.regions, regulars: full.regulars, needsCare: full.needsCare,
    attendanceByPerson: full.people,
    newMembers: (joined.results ?? []).filter(row => { const date = local(row.added_at, zone).date; return date >= from && date <= to; })
      .map(row => ({ name: row.name, halqah: row.halqah, joinedAt: row.added_at })),
    insights: full.insights,
  };
}

/** GET /v1/markaz/sessions/{id} */
export async function sessionDetail(env: Env, memberID: string, sessionID: string): Promise<Response> {
  if (!(await markazAccess(env, memberID)).canReport) return forbidden();
  const row = await env.DB.prepare(`SELECT h.session_id,h.group_id,h.kind,h.title,h.started_at,h.ended_at,h.started_by,m.display_name AS starter
      FROM group_live_history h LEFT JOIN members m ON m.id=h.started_by WHERE h.session_id=?`).bind(sessionID).first<SessionRow>();
  if (!row) return notFound();
  const groups = new Map((await activeGroups(env)).map(group => [group.id, group]));
  const [present, cues, duas] = await Promise.all([
    env.DB.prepare(`SELECT p.session_id,p.group_id,p.member_id,p.first_seen_at,p.last_seen_at,
          COALESCE(pp.display_name,m.display_name) AS name,pp.city,pp.country_code AS country,
          CASE WHEN m.apple_subject LIKE 'web-guest:%' THEN 1 ELSE 0 END AS web
        FROM group_live_presence p LEFT JOIN members m ON m.id=p.member_id LEFT JOIN sheikh_public_profiles pp ON pp.member_id=p.member_id
        WHERE p.session_id=? ORDER BY p.first_seen_at`).bind(sessionID).all<Presence>(),
    env.DB.prepare("SELECT title,created_at FROM group_zikr_cues WHERE group_id=? AND hidden_at IS NULL AND created_at>=? AND created_at<=? ORDER BY sequence")
      .bind(row.group_id, row.started_at, row.ended_at).all<{ title: string; created_at: string }>(),
    env.DB.prepare("SELECT COUNT(*) AS n FROM group_dua_requests WHERE group_id=? AND removed_at IS NULL AND created_at>=? AND created_at<=?")
      .bind(row.group_id, row.started_at, row.ended_at).first<{ n: number }>(),
  ]);
  const list = present.results ?? [];
  return json({ session: sessionItem(row, groups, list), attendees: list.map(attendee),
    stages: (cues.results ?? []).map(cue => ({ title: cue.title, at: cue.created_at })), duaRequests: Number(duas?.n ?? 0) });
}

/** GET /v1/markaz/people/{memberID} */
export async function personHistory(env: Env, memberID: string, personID: string, url: URL): Promise<Response> {
  if (!(await markazAccess(env, memberID)).canReport) return forbidden();
  const zone = zoneOf(url.searchParams.get("tz"));
  const person = await env.DB.prepare(`SELECT m.id,COALESCE(pp.display_name,m.display_name) AS name,m.email,m.created_at,m.last_seen_at
      FROM members m LEFT JOIN sheikh_public_profiles pp ON pp.member_id=m.id WHERE m.id=?`).bind(personID)
    .first<{ id: string; name: string | null; email: string | null; created_at: string; last_seen_at: string }>();
  if (!person) return notFound();
  const [places, history] = await Promise.all([
    env.DB.prepare("SELECT g.id,g.name,p.role FROM member_group_members p JOIN member_groups g ON g.id=p.group_id WHERE p.member_id=? AND g.is_active=1 ORDER BY g.name")
      .bind(personID).all<{ id: string; name: string; role: string }>(),
    env.DB.prepare(`SELECT h.started_at,h.title,h.kind,g.name AS group_name,p.first_seen_at,p.last_seen_at FROM group_live_presence p
        JOIN group_live_history h ON h.session_id=p.session_id AND h.is_test=0 JOIN member_groups g ON g.id=h.group_id
        WHERE p.member_id=? ORDER BY h.started_at DESC LIMIT 400`).bind(personID)
      .all<{ started_at: string; title: string | null; kind: string; group_name: string; first_seen_at: string; last_seen_at: string }>(),
  ]);
  const rows = history.results ?? [];
  const dates = [...new Set(rows.map(row => local(row.started_at, zone).date))].sort().reverse();
  let streak = 0;
  for (let day = today(zone); dates.includes(day) || (streak === 0 && dates.includes(addDays(day, -1))); day = addDays(day, -1)) {
    if (dates.includes(day)) streak += 1;
    else if (streak > 0) break;
  }
  const cutoff = new Date(Date.now() - 90 * DAY).toISOString();
  return json({
    memberID: person.id, name: person.name ?? "Member", email: person.email ?? undefined,
    halqahs: (places.results ?? []).map(place => ({ id: place.id, name: place.name, role: halqahRole(place.role) })),
    firstSeenAt: person.created_at, lastSeenAt: person.last_seen_at,
    sessions: rows.length, last90Days: rows.filter(row => row.started_at >= cutoff).length, currentStreakDays: streak,
    history: rows.slice(0, 200).map(row => ({ date: local(row.started_at, zone).date, groupName: row.group_name,
      title: row.title ?? (row.kind === "meeting" ? "Meeting" : "Halqah Zikr"), minutes: minutesOf(row.first_seen_at, row.last_seen_at) })),
  });
}

// MARK: - Export

const csvCell = (value: unknown): string => {
  const text = value === null || value === undefined ? "" : String(value);
  return /[",\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
};
const csv = (rows: unknown[][]): string => "﻿" + rows.map(row => row.map(csvCell).join(",")).join("\r\n") + "\r\n";

/** GET /v1/markaz/export?type=sessions|attendance|halqahs|people */
export async function exportCSV(env: Env, memberID: string, url: URL): Promise<Response> {
  if (!(await markazAccess(env, memberID)).canReport) return forbidden();
  const zone = zoneOf(url.searchParams.get("tz"));
  const window = windowFrom(url, zone);
  if (typeof window === "string") return badRequest(window);
  const groups = await activeGroups(env);
  const scope = scopeOf(groups, url.searchParams.get("scope"));
  if (!scope) return notFound();
  const type = url.searchParams.get("type") ?? "sessions";
  const byID = new Map(groups.map(group => [group.id, group]));
  const time = (iso: string) => {
    const when = local(iso, zone);
    return `${when.date} ${new Intl.DateTimeFormat("en-GB", { timeZone: zone, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(iso))}`;
  };
  let rows: unknown[][];
  if (type === "halqahs" || type === "people") {
    const full = await report(env, window, scope, "all", groups);
    rows = type === "halqahs"
      ? [["Halqah", "Region", "Sessions", "Attendance", "Average", "Different people", "Members", "Attendance rate", "Last session", "Status"],
        ...full.halqahs.map(row => [row.name, row.region ?? "", row.sessions, row.attendance, row.averageAttendance, row.uniqueAttendees, row.members,
          row.attendanceRate === null ? "" : `${Math.round(row.attendanceRate * 100)}%`, row.lastSessionAt ? time(row.lastSessionAt) : "", row.status])]
      : [["Name", "Joined from", "Sessions", "Days", "Halqahs", "Last seen"],
        ...full.people.map(row => [row.name, row.via === "web" ? "Website" : "App", row.sessions, row.days, row.halqahs.join("; "), time(row.lastSeenAt)])];
  } else if (type === "attendance") {
    const data = await load(env, window, new Set(scope.groups.map(group => group.id)), "all");
    const sessions = new Map(data.sessions.map(row => [row.session_id, row]));
    rows = [["Date", "Halqah", "Session", "Name", "City", "Country", "Joined from", "Joined", "Minutes"],
      ...data.presence.sort((a, b) => a.first_seen_at.localeCompare(b.first_seen_at)).map(row => {
        const session = sessions.get(row.session_id);
        return [local(row.first_seen_at, zone).date, byID.get(row.group_id)?.name ?? row.group_id, session?.title ?? "", row.name ?? "Member",
          row.city ?? "", row.country ?? "", row.web ? "Website" : "App", time(row.first_seen_at), minutesOf(row.first_seen_at, row.last_seen_at)];
      })];
  } else {
    const data = await load(env, window, new Set(scope.groups.map(group => group.id)), "all");
    const bySession = sessionPresence(data.presence);
    rows = [["Started", "Ended", "Halqah", "Kind", "Title", "Minutes", "Attendance", "App", "Website", "Started by"],
      ...data.sessions.map(row => {
        const item = sessionItem(row, byID, bySession.get(row.session_id) ?? []);
        return [time(row.started_at), time(row.ended_at), item.groupName, item.kind, item.title, item.minutes, item.attendance, item.app, item.web,
          item.automated ? "Automatic" : item.startedBy ?? ""];
      })];
  }
  const name = `darul-irfan-${type}-${window.from}-to-${window.to}.csv`;
  return new Response(csv(rows), { headers: { "content-type": "text/csv; charset=utf-8", "content-disposition": `attachment; filename="${name}"`, "cache-control": "no-store" } });
}

// MARK: - Organisation

/** GET /v1/markaz/organization */
export async function organization(env: Env, memberID: string): Promise<Response> {
  if (!(await markazAccess(env, memberID)).canReport) return forbidden();
  const groups = await activeGroups(env);
  const since = new Date(Date.now() - 30 * DAY).toISOString(), present = new Date(Date.now() - PRESENT_SECONDS * 1000).toISOString();
  const [counts, last, roles, zikr, recent, live] = await Promise.all([
    memberCounts(env), lastSessions(env),
    env.DB.prepare(`SELECT p.group_id,p.role,COALESCE(m.display_name,'Member') AS name FROM member_group_members p JOIN members m ON m.id=p.member_id
        WHERE p.role IN ('administrator','admin') ORDER BY m.display_name COLLATE NOCASE`).all<{ group_id: string; role: string; name: string }>(),
    env.DB.prepare("SELECT group_id,COUNT(*) AS n FROM group_zikr_sessions WHERE is_active=1 GROUP BY group_id").all<{ group_id: string; n: number }>(),
    env.DB.prepare("SELECT group_id,COUNT(*) AS n FROM group_live_history WHERE is_test=0 AND started_at>=? GROUP BY group_id").bind(since).all<{ group_id: string; n: number }>(),
    env.DB.prepare(`SELECT l.group_id,l.kind,l.started_at,l.session_id,
        (SELECT COUNT(*) FROM group_live_presence p WHERE p.session_id=l.session_id AND p.last_seen_at>=?) AS listening
        FROM group_live l WHERE l.state='live' AND l.is_test=0`).bind(present).all<{ group_id: string; kind: string; started_at: string; listening: number }>(),
  ]);
  const zikrBy = new Map((zikr.results ?? []).map(row => [row.group_id, Number(row.n)]));
  const recentBy = new Map((recent.results ?? []).map(row => [row.group_id, Number(row.n)]));
  const liveBy = new Map((live.results ?? []).map(row => [row.group_id, row]));
  const card = (group: Group) => ({
    id: group.id, name: group.name, kind: group.kind, region: group.region ?? undefined, city: group.city ?? undefined, countryCode: group.country_code ?? undefined,
    members: counts.get(group.id) ?? 0,
    administrators: (roles.results ?? []).filter(row => row.group_id === group.id && row.role === "administrator").map(row => row.name),
    admins: (roles.results ?? []).filter(row => row.group_id === group.id && row.role === "admin").map(row => row.name),
    zikrTimes: zikrBy.get(group.id) ?? 0, lastSessionAt: last.get(group.id) ?? null, sessions30Days: recentBy.get(group.id) ?? 0,
    status: statusOf(last.get(group.id)), isLive: liveBy.has(group.id),
  });
  const halqahs = groups.filter(group => group.kind === "halqah");
  const regions = new Map<string, Group[]>();
  for (const group of halqahs.filter(item => item.region)) regions.set(group.region!, [...(regions.get(group.region!) ?? []), group]);
  const markaz = (roles.results ?? []).filter(row => row.group_id === MARKAZ_ID).length;
  const names = new Map(groups.map(group => [group.id, group.name]));
  return json({
    regions: [...regions.entries()].sort((a, b) => a[0].localeCompare(b[0])).map(([name, list]) => ({ name, halqahs: list.map(card) })),
    unassigned: halqahs.filter(group => !group.region).map(card),
    markaz: { id: MARKAZ_ID, members: counts.get(MARKAZ_ID) ?? 0, officers: markaz },
    liveNow: (live.results ?? []).map(row => ({ groupID: row.group_id, name: names.get(row.group_id) ?? row.group_id, kind: row.kind, startedAt: row.started_at, listening: Number(row.listening) })),
    totals: {
      halqahs: halqahs.length,
      members: Number((await env.DB.prepare(`SELECT COUNT(DISTINCT p.member_id) AS n FROM member_group_members p JOIN member_groups g ON g.id=p.group_id
        WHERE g.is_active=1 AND g.kind='halqah'`).first<{ n: number }>())?.n ?? 0),
      administrators: (roles.results ?? []).filter(row => row.role === "administrator" && row.group_id !== MARKAZ_ID).length,
      admins: (roles.results ?? []).filter(row => row.role === "admin" && row.group_id !== MARKAZ_ID).length,
    },
  });
}

/** PUT /v1/markaz/halqahs/{id} - where a Halqah sits in the organisation. */
export async function placeHalqah(env: Env, memberID: string, groupID: string, input: Record<string, unknown>): Promise<Response> {
  if (!(await markazAccess(env, memberID)).isSuperAdmin) return superOnly();
  const current = await env.DB.prepare("SELECT region,country_code,city FROM member_groups WHERE id=? AND is_active=1").bind(groupID)
    .first<{ region: string | null; country_code: string | null; city: string | null }>();
  if (!current) return notFound();
  const text = (key: string, fallback: string | null, max: number) => input[key] === undefined ? fallback : cleanText(input[key], max) ?? null;
  const country = input.countryCode === undefined ? current.country_code
    : typeof input.countryCode === "string" && /^[A-Za-z]{2}$/.test(input.countryCode.trim()) ? input.countryCode.trim().toUpperCase() : null;
  await env.DB.prepare("UPDATE member_groups SET region=?,country_code=?,city=?,updated_at=? WHERE id=?")
    .bind(text("region", current.region, 60), country, text("city", current.city, 80), new Date().toISOString(), groupID).run();
  return json({ ok: true });
}

/** POST /v1/markaz/sync-admins - every Halqah's Administrators and Admins join the Markaz as members. */
export async function syncAdmins(env: Env, memberID: string): Promise<Response> {
  if (!(await markazAccess(env, memberID)).isSuperAdmin) return superOnly();
  return json(await bringInAdmins(env, memberID));
}

async function bringInAdmins(env: Env, memberID: string): Promise<{ added: number; total: number }> {
  const rows = await env.DB.prepare(`SELECT DISTINCT p.member_id FROM member_group_members p JOIN member_groups g ON g.id=p.group_id
      WHERE g.is_active=1 AND g.kind='halqah' AND p.role IN ('administrator','admin')
      AND p.member_id NOT IN (SELECT member_id FROM member_group_members WHERE group_id=?)`).bind(MARKAZ_ID).all<{ member_id: string }>();
  for (const row of rows.results ?? []) await upsertMembership(env, MARKAZ_ID, row.member_id, "member", `member:${memberID}`, true);
  const total = await env.DB.prepare("SELECT COUNT(*) AS n FROM member_group_members WHERE group_id=?").bind(MARKAZ_ID).first<{ n: number }>();
  return { added: (rows.results ?? []).length, total: Number(total?.n ?? 0) };
}

/** POST /v1/markaz/announce - one notice to many Halqahs, or to every Halqah's admins through the Markaz. */
export async function announce(env: Env, memberID: string, input: Record<string, unknown>): Promise<Response> {
  if (!(await markazAccess(env, memberID)).canReport) return forbidden();
  const title = cleanText(input.title, 200);
  if (!title) return badRequest("Give the notice a title.");
  const body = cleanText(input.body, 4_000) ?? null;
  const audience = input.audience === "admins" ? "admins" : "members";
  const notify = input.notify !== false;
  const groups = (await activeGroups(env)).filter(group => group.kind === "halqah");
  const scope = typeof input.scope === "string" ? input.scope : "all";
  let targets: Group[];
  if (scope === "halqahs") {
    const chosen = new Set(Array.isArray(input.halqahIDs) ? input.halqahIDs.filter((id): id is string => typeof id === "string") : []);
    targets = groups.filter(group => chosen.has(group.id));
  } else if (scope.startsWith("region:")) targets = groups.filter(group => group.region === scope.slice(7));
  else targets = groups;
  if (!targets.length) return badRequest("Choose at least one Halqah.");
  const author = await env.DB.prepare("SELECT COALESCE(email,display_name,id) AS who FROM members WHERE id=?").bind(memberID).first<{ who: string }>();
  const now = new Date().toISOString();
  const id = `markaz-${crypto.randomUUID().slice(0, 12)}`;
  const post = async (groupID: string) => {
    await env.DB.prepare(`INSERT INTO member_group_posts(id,group_id,kind,title,body,published_at,author_email,is_hidden,updated_at,status,source)
      VALUES(?,?,'announcement',?,?,?,?,0,?,'published','admin')`).bind(`${id}-${groupID}`.slice(0, 80), groupID, title, body, now, `member:${memberID}`, now).run();
  };
  let posted = 0, notified = 0;
  if (audience === "admins") {
    await bringInAdmins(env, memberID);
    await post(MARKAZ_ID);
    posted = 1;
    if (notify) notified = await notifyGroup(env, MARKAZ_ID, id, `Silsila Markaz: ${title}`, body ?? title, `darulirfan://groups/${MARKAZ_ID}`);
  } else {
    for (const group of targets) {
      await post(group.id);
      posted += 1;
      if (notify) notified += await notifyGroup(env, group.id, `${id}-${group.id}`, title, body ?? title, `darulirfan://groups/${group.id}`);
    }
  }
  await env.DB.prepare("INSERT INTO markaz_announcements(id,title,body,audience,targets_json,sent_by,sent_at,posted) VALUES(?,?,?,?,?,?,?,?)")
    .bind(id, title, body, audience, JSON.stringify(targets.map(group => group.name)), author?.who ?? memberID, now, posted).run();
  return json({ ok: true, posted, notified });
}

/** GET /v1/markaz/announcements */
export async function announcements(env: Env, memberID: string): Promise<Response> {
  if (!(await markazAccess(env, memberID)).canReport) return forbidden();
  const rows = await env.DB.prepare("SELECT id,title,body,audience,targets_json,sent_by,sent_at,posted FROM markaz_announcements ORDER BY sent_at DESC LIMIT 100")
    .all<{ id: string; title: string; body: string | null; audience: string; targets_json: string; sent_by: string; sent_at: string; posted: number }>();
  return json({ announcements: (rows.results ?? []).map(row => ({ id: row.id, title: row.title, body: row.body ?? undefined, audience: row.audience,
    targets: JSON.parse(row.targets_json) as string[], sentBy: row.sent_by, sentAt: row.sent_at, posted: row.posted })) });
}

// MARK: - The reporting website's sign-in

const LINK_ALPHABET = "ACDEFGHJKMNPQRSTUVWXYZ2345679";
const normaliseLink = (raw: string) => raw.toUpperCase().replace(/[^A-Z0-9]/g, "");
const hex = (bytes: Uint8Array) => [...bytes].map(byte => byte.toString(16).padStart(2, "0")).join("");
const REPORTING_HOURS = 12;

/** POST /v1/reporting/link - a code for the website to show. */
export async function startReportingLink(env: Env): Promise<Response> {
  const random = crypto.getRandomValues(new Uint8Array(8));
  const code = [...random].map(byte => LINK_ALPHABET[byte % LINK_ALPHABET.length]).join("");
  const pollToken = hex(crypto.getRandomValues(new Uint8Array(32)));
  const now = new Date(), expires = new Date(now.getTime() + 5 * 60_000).toISOString();
  await env.DB.prepare("DELETE FROM reporting_links WHERE expires_at<?").bind(new Date(now.getTime() - DAY).toISOString()).run();
  await env.DB.prepare("INSERT INTO reporting_links(code_hash,poll_hash,created_at,expires_at) VALUES(?,?,?,?)")
    .bind(await sha256(code), await sha256(pollToken), now.toISOString(), expires).run();
  return json({ code: `${code.slice(0, 4)}-${code.slice(4)}`, pollToken, expiresAt: expires }, { status: 201 });
}

/** POST /v1/markaz/reporting-link/approve - an officer lets the computer in. */
export async function approveReportingLink(env: Env, memberID: string, input: Record<string, unknown>): Promise<Response> {
  if (!(await markazAccess(env, memberID)).canReport) return forbidden();
  const code = normaliseLink(typeof input.code === "string" ? input.code : "");
  if (code.length !== 8) return badRequest("Type the 8 characters shown on the computer.");
  const result = await env.DB.prepare(`UPDATE reporting_links SET approved_by=?,approved_at=? WHERE code_hash=? AND expires_at>?
      AND approved_by IS NULL AND consumed_at IS NULL`).bind(memberID, new Date().toISOString(), await sha256(code), new Date().toISOString()).run();
  if ((result.meta?.changes ?? 0) === 0) return json({ error: "That code is not valid or has expired. Refresh the page on the computer for a new one." }, { status: 404 });
  await env.DB.prepare("INSERT INTO audit_log(actor_email,action,entity_type,entity_id,before_json,after_json,created_at) VALUES(?,?,?,?,?,?,?)")
    .bind(`member:${memberID}`, "approve", "reporting-link", code.slice(0, 2) + "******", null, null, new Date().toISOString()).run();
  return json({ ok: true });
}

/** POST /v1/reporting/link/poll - the website asks whether it was let in. */
export async function pollReportingLink(env: Env, input: Record<string, unknown>): Promise<Response> {
  const token = typeof input.pollToken === "string" && /^[0-9a-f]{64}$/.test(input.pollToken) ? input.pollToken : "";
  if (!token) return badRequest("Invalid request");
  const hash = await sha256(token);
  const row = await env.DB.prepare("SELECT expires_at,approved_by,consumed_at FROM reporting_links WHERE poll_hash=?").bind(hash)
    .first<{ expires_at: string; approved_by: string | null; consumed_at: string | null }>();
  const now = new Date();
  if (!row || row.consumed_at) return json({ status: "expired" });
  if (!row.approved_by) return json({ status: Date.parse(row.expires_at) > now.getTime() ? "pending" : "expired" });
  // Approved: the website gets a session of its own, once.
  const claimed = await env.DB.prepare("UPDATE reporting_links SET consumed_at=? WHERE poll_hash=? AND consumed_at IS NULL").bind(now.toISOString(), hash).run();
  if ((claimed.meta?.changes ?? 0) === 0) return json({ status: "expired" });
  if (!(await markazAccess(env, row.approved_by)).canReport) return json({ status: "expired" });
  const session = hex(crypto.getRandomValues(new Uint8Array(32)));
  const expires = new Date(now.getTime() + REPORTING_HOURS * 3_600_000).toISOString();
  await env.DB.prepare("INSERT INTO member_sessions(token_hash,member_id,created_at,expires_at,last_seen_at,client) VALUES(?,?,?,?,?,'reporting')")
    .bind(await sha256(session), row.approved_by, now.toISOString(), expires, now.toISOString()).run();
  return json({ status: "approved", token: session, expiresAt: expires });
}

/** GET /v1/markaz/reporting-sessions - the computers signed in to reporting for this officer (all, for a super admin). */
export async function reportingSessions(env: Env, memberID: string, currentHash: string | null): Promise<Response> {
  const who = await markazAccess(env, memberID);
  if (!who.canReport) return forbidden();
  const statement = env.DB.prepare(`SELECT s.token_hash,s.created_at,s.last_seen_at,s.expires_at,COALESCE(m.display_name,m.email,'Member') AS name
      FROM member_sessions s JOIN members m ON m.id=s.member_id WHERE s.client='reporting' AND s.expires_at>? ${who.isSuperAdmin ? "" : "AND s.member_id=?"}
      ORDER BY s.created_at DESC`);
  const rows = await (who.isSuperAdmin ? statement.bind(new Date().toISOString()) : statement.bind(new Date().toISOString(), memberID))
    .all<{ token_hash: string; created_at: string; last_seen_at: string; expires_at: string; name: string }>();
  return json({ sessions: (rows.results ?? []).map(row => ({ id: row.token_hash.slice(0, 12), name: row.name, createdAt: row.created_at,
    lastSeenAt: row.last_seen_at, expiresAt: row.expires_at, current: row.token_hash === currentHash })) });
}

/** DELETE /v1/markaz/reporting-sessions/{id} */
export async function endReportingSession(env: Env, memberID: string, id: string): Promise<Response> {
  const who = await markazAccess(env, memberID);
  if (!who.canReport) return forbidden();
  if (!/^[0-9a-f]{12}$/.test(id)) return notFound();
  const statement = env.DB.prepare(`DELETE FROM member_sessions WHERE client='reporting' AND substr(token_hash,1,12)=? ${who.isSuperAdmin ? "" : "AND member_id=?"}`);
  const result = await (who.isSuperAdmin ? statement.bind(id) : statement.bind(id, memberID)).run();
  return (result.meta?.changes ?? 0) ? new Response(null, { status: 204 }) : notFound();
}

// MARK: - The daily digest

/** Officers' phones, every day at 12:00 UTC: yesterday in one line; on the 1st, the month is ready. */
export async function markazDigest(env: Env, now = new Date()): Promise<void> {
  if (now.getUTCHours() !== 12 || now.getUTCMinutes() !== 0) return;
  const zone = zoneOf(env.MARKAZ_TIME_ZONE ?? "America/New_York");
  const key = `markazDigest:${now.toISOString().slice(0, 10)}`;
  const claimed = await env.DB.prepare("INSERT OR IGNORE INTO app_config(key,value_json,updated_at) VALUES(?,?,?)").bind(key, "true", now.toISOString()).run();
  if ((claimed.meta?.changes ?? 0) === 0) return;
  const yesterday = addDays(local(now.toISOString(), zone).date, -1);
  const day = await dayReport(env, yesterday, zone);
  const change = day.previousDay.attendance ? Math.round(((day.summary.attendance - day.previousDay.attendance) / day.previousDay.attendance) * 100) : null;
  const halqahCount = day.halqahs.length;
  const body = day.summary.sessions
    ? `Yesterday: ${day.summary.sessions} sessions in ${halqahCount} Halqah${halqahCount === 1 ? "" : "s"}, ${day.summary.attendance} attended${change === null ? "" : ` (${change >= 0 ? "+" : ""}${change}%)`}.${day.noSession.length ? ` No session: ${day.noSession.map(item => item.name).join(", ")}.` : ""}`
    : "Yesterday: no sessions were held.";
  const installations = await officerInstallations(env);
  if (!installations.length) return;
  try {
    await sendPushToInstallations(env, `markaz-digest-${yesterday}`, "markaz", installations, "Daily Zikr report", body, "darulirfan://markaz/reports/daily");
    if (local(now.toISOString(), zone).date.endsWith("-01")) {
      const month = yesterday.slice(0, 7);
      const name = new Intl.DateTimeFormat("en-GB", { month: "long", timeZone: "UTC" }).format(new Date(`${month}-15T00:00:00Z`));
      await sendPushToInstallations(env, `markaz-month-${month}`, "markaz", installations, `${name} report is ready`, "Attendance, trends and every Halqah, for the month.", "darulirfan://markaz/reports/monthly");
    }
  } catch {
    // A missing push credential never stops the reports themselves.
  }
}

async function officerInstallations(env: Env): Promise<string[]> {
  const rows = await env.DB.prepare(`SELECT DISTINCT md.installation_id,m.email,
        (SELECT role FROM member_group_members WHERE group_id=? AND member_id=m.id) AS markaz_role
      FROM member_devices md JOIN members m ON m.id=md.member_id JOIN devices d ON upper(d.installation_id)=upper(md.installation_id)`)
    .bind(MARKAZ_ID).all<{ installation_id: string; email: string | null; markaz_role: string | null }>();
  return (rows.results ?? []).filter(row => isSuperAdmin(env, row) || row.markaz_role === "admin" || row.markaz_role === "administrator")
    .map(row => row.installation_id);
}
