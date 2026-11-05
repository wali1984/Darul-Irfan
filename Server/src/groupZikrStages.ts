import { sendPushToInstallations } from "./apns";
import type { Env } from "./contracts";
import { canManage, canSee, memberRole, notifyGroup } from "./community";
import { beginSession, endSession } from "./session";
import { json } from "./util";

export const SHEIKH_HALQA_ID = "our-sheikh";
export interface ZikrStage { id: string; title: string; titleUr?: string; isCustom: boolean }
export const DEFAULT_ZIKR_STAGES: ZikrStage[] = [
  {
    "id": "latifa-1",
    "title": "1st Latifa",
    "titleUr": "پہلا لطیفہ",
    "isCustom": false
  },
  {
    "id": "latifa-2",
    "title": "2nd Latifa",
    "titleUr": "دوسرا لطیفہ",
    "isCustom": false
  },
  {
    "id": "latifa-3",
    "title": "3rd Latifa",
    "titleUr": "تیسرا لطیفہ",
    "isCustom": false
  },
  {
    "id": "latifa-4",
    "title": "4th Latifa",
    "titleUr": "چوتھا لطیفہ",
    "isCustom": false
  },
  {
    "id": "latifa-5",
    "title": "5th Latifa",
    "titleUr": "پانچواں لطیفہ",
    "isCustom": false
  },
  {
    "id": "latifa-6",
    "title": "6th Latifa",
    "titleUr": "چھٹا لطیفہ",
    "isCustom": false
  },
  {
    "id": "latifa-7",
    "title": "7th Latifa",
    "titleUr": "ساتواں لطیفہ",
    "isCustom": false
  },
  {
    "id": "raabta",
    "title": "Raabta",
    "titleUr": "رابطہ",
    "isCustom": false
  },
  {
    "id": "ahadiyat",
    "title": "Muraqaba Ahadiyat",
    "titleUr": "مراقبہ احدیت",
    "isCustom": false
  },
  {
    "id": "maiyyat",
    "title": "Muraqaba Ma'iyyat",
    "titleUr": "مراقبہ معیت",
    "isCustom": false
  },
  {
    "id": "aqrabiyyat",
    "title": "Muraqaba Aqrabiyyat",
    "titleUr": "مراقبہ اقربیت",
    "isCustom": false
  },
  // Called after Aqrabiyyat in the Daily Zikr (heard in the sessions of 2 and 3 Nov 2026).
  { "id": "sair-kaaba", "title": "Sair-e-Kaaba", "titleUr": "سیرِ کعبہ", "isCustom": false },
  { "id": "rauza-athar", "title": "Rauza-e-Athar", "titleUr": "روضۂ اطہر", "isCustom": false },
  { "id": "masjid-nabawi", "title": "Masjid-e-Nabawi", "titleUr": "مسجدِ نبوی", "isCustom": false }
];

/** The recitations that open every Zikr, in order, exactly as the Method of
 * Zikr gives them (method_of_zikr.json): shown in Arabic on the live stage
 * while Hazrat ji recites them. Announced like a stage. */
export interface Recitation { id: string; title: string; titleUr: string; arabic: string }
export const RECITATIONS: Recitation[] = [
  { id: "tasbih", title: "Tasbihat", titleUr: "تسبیحات", arabic: "سُبْحَانَ اللّٰهِ وَالْحَمْدُ لِلّٰهِ وَلَا إِلٰهَ إِلَّا اللّٰهُ وَاللّٰهُ أَكْبَرُ وَلَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللّٰهِ الْعَلِيِّ الْعَظِيمِ" },
  { id: "istighfar", title: "Istighfar", titleUr: "استغفار", arabic: "أَسْتَغْفِرُ اللّٰهَ رَبِّي مِنْ كُلِّ ذَنْبٍ وَأَتُوبُ إِلَيْهِ" },
  { id: "shahadah", title: "Shahadah", titleUr: "کلمہ شہادت", arabic: "أَشْهَدُ أَنْ لَا إِلٰهَ إِلَّا اللّٰهُ وَأَشْهَدُ أَنَّ مُحَمَّدًا عَبْدُهُ وَرَسُولُهُ" },
  { id: "taawwudh", title: "Ta'awwudh", titleUr: "تعوذ", arabic: "أَعُوذُ بِاللّٰهِ مِنَ الشَّيْطَانِ الرَّجِيمِ" },
  { id: "basmalah", title: "Bismillah", titleUr: "تسمیہ", arabic: "بِسْمِ اللّٰهِ الرَّحْمٰنِ الرَّحِيمِ" },
];

/** The dua that closes the Zikr: shown on the stage, notifies nobody; the relay
 *  calling it ends the session five minutes later (owner 2026-11-05). */
export const DUA_STAGE: ZikrStage = { id: "dua", title: "Dua", titleUr: "دعا", isCustom: false };

/** The stage chat's ready-made messages: all a member can send. */
export const STAGE_PRESETS = [
  { id: "salam", title: "Assalamu alaikum wa rahmatullah", titleUr: "السلام علیکم ورحمۃ اللہ" },
  { id: "dua-request", title: "Request for prayers", titleUr: "دعا کی درخواست" },
  { id: "ameen", title: "Ameen", titleUr: "آمین" },
  { id: "jazakallah", title: "JazakAllahu khairan", titleUr: "جزاک اللہ خیراً" },
  { id: "subhanallah", title: "SubhanAllah", titleUr: "سبحان اللہ" },
  { id: "mashallah", title: "MashaAllah", titleUr: "ماشاء اللہ" },
  { id: "cannot-hear", title: "The sound is not clear", titleUr: "آواز صاف نہیں آ رہی" },
];

interface LiveZikr { title: string | null; video_id: string | null; started_at: string | null; is_test: number }

/** The live Zikr as this person may see it: a test Zikr exists only for the Halqah's admins. */
async function liveZikr(env: Env, groupID: string, managing = true): Promise<LiveZikr | null> {
  const live = await env.DB.prepare("SELECT title,video_id,started_at,is_test FROM group_live WHERE group_id=? AND state='live' AND kind='zikr'")
    .bind(groupID).first<LiveZikr>();
  return live && (!live.is_test || managing) ? live : null;
}

async function access(env: Env, memberID: string, groupID: string, write: boolean): Promise<Response | boolean> {
  const role = await memberRole(env, memberID);
  // Every Halqah's live Zikr has a stage (owner 2026-11-04), led by its own admins.
  if (!await canSee(env, memberID, role, groupID)) {
    return json({ error: "Not found" }, { status: 404 });
  }
  const managing = await canManage(env, memberID, role, groupID);
  if (write && !managing) return json({ error: "Group admin role required" }, { status: 403 });
  if (write && !await liveZikr(env, groupID)) return json({ error: "Stage controls are available during this Halqa’s live Zikr only." }, { status: 409 });
  return managing;
}

/** Stage announcements belong to the session they were made in: once it ends
 * the stage is empty, and nothing from it shows anywhere else. */
const SESSION_CUES = "group_id=? AND hidden_at IS NULL AND created_at>=?";
/** When the live Zikr began; a session without a start time keeps its last three hours. */
const sessionStart = (live: LiveZikr) => live.started_at ?? new Date(Date.now() - 3 * 3_600_000).toISOString();

export async function zikrStages(env: Env, memberID: string, groupID: string): Promise<Response> {
  const managing = await access(env, memberID, groupID, false);
  if (managing instanceof Response) return managing;
  const custom = await env.DB.prepare("SELECT id,title,title_ur FROM group_zikr_stages WHERE group_id=? ORDER BY created_at,id")
    .bind(groupID).all<{ id: string; title: string; title_ur: string | null }>();
  return json({ canBroadcast: managing && !!await liveZikr(env, groupID), stages: [...DEFAULT_ZIKR_STAGES, ...(custom.results ?? []).map(row => ({
    id: row.id, title: row.title, titleUr: row.title_ur ?? undefined, isCustom: true,
  }))], recitations: RECITATIONS, presets: STAGE_PRESETS });
}

/** Client retains the UUID across retries; repeated submission cannot create another stage. */
export async function addZikrStage(env: Env, memberID: string, groupID: string, input: Record<string, unknown>): Promise<Response> {
  const permitted = await access(env, memberID, groupID, true);
  if (permitted instanceof Response) return permitted;
  const id = typeof input.id === "string" ? input.id.toLowerCase() : "";
  const title = typeof input.title === "string" ? input.title.trim() : "";
  const titleUr = typeof input.titleUr === "string" ? input.titleUr.trim() : "";
  if (!/^custom-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id) ||
      !title || title.length > 100 || titleUr.length > 100 || /[\u0000-\u001f\u007f]/.test(title + titleUr)) {
    return json({ error: "Enter a stage name up to 100 characters and a valid custom stage ID." }, { status: 400 });
  }
  const result = await env.DB.prepare(`INSERT OR IGNORE INTO group_zikr_stages(group_id,id,title,title_ur,created_by,created_at)
    VALUES(?,?,?,?,?,?)`).bind(groupID, id, title, titleUr || null, memberID, new Date().toISOString()).run();
  const saved = await env.DB.prepare("SELECT title,title_ur FROM group_zikr_stages WHERE group_id=? AND id=?")
    .bind(groupID, id).first<{ title: string; title_ur: string | null }>();
  if (saved?.title !== title || (saved.title_ur ?? "") !== titleUr) {
    return json({ error: "This stage ID already belongs to another stage." }, { status: 409 });
  }
  return json({ id, title, titleUr: titleUr || undefined, isCustom: true }, { status: result.meta.changes ? 201 : 200 });
}


interface CueRow {
  sequence: number; group_id: string; event_id: string; stage_id: string; title: string;
  title_ur: string | null; author_id: string; created_at: string; notification_state: string;
}
function presentCue(row: CueRow) {
  return { sequence: row.sequence, id: row.event_id, stageID: row.stage_id, title: row.title,
    titleUr: row.title_ur ?? undefined, authorID: row.author_id, createdAt: row.created_at,
    notificationState: row.notification_state,
    arabic: RECITATIONS.find(recitation => recitation.id === row.stage_id)?.arabic };
}

/** Persistent stage chat; poll after the last sequence without losing a burst of cues. */
export async function zikrCues(env: Env, memberID: string, groupID: string, after: string | null): Promise<Response> {
  const permitted = await access(env, memberID, groupID, false);
  if (permitted instanceof Response) return permitted;
  if (after !== null && (!/^\d{1,15}$/.test(after) || !Number.isSafeInteger(Number(after)))) {
    return json({ error: "Invalid chat cursor" }, { status: 400 });
  }
  const live = await liveZikr(env, groupID, permitted);
  if (!live) return json({ cues: [], nextSequence: Number(after ?? 0) });
  const since = sessionStart(live);
  const rows = after === null
    ? await env.DB.prepare(`SELECT * FROM group_zikr_cues WHERE ${SESSION_CUES} ORDER BY sequence DESC LIMIT 100`)
        .bind(groupID, since).all<CueRow>()
    : await env.DB.prepare(`SELECT * FROM group_zikr_cues WHERE ${SESSION_CUES} AND sequence>? ORDER BY sequence LIMIT 100`)
        .bind(groupID, since, Number(after)).all<CueRow>();
  const ordered = after === null ? (rows.results ?? []).reverse() : rows.results ?? [];
  return json({ cues: ordered.map(presentCue), nextSequence: ordered.at(-1)?.sequence ?? Number(after ?? 0) });
}

/** One retained event UUID per intentional tap. Names are resolved on the server, never trusted from input. */
export async function broadcastZikrCue(env: Env, memberID: string, groupID: string, input: Record<string, unknown>): Promise<Response> {
  const permitted = await access(env, memberID, groupID, true);
  if (permitted instanceof Response) return permitted;
  return recordCue(env, memberID, groupID, input);
}

/** The live relay starts a Halqah's Zikr when Hazrat ji is live on Paltalk
 *  (owner 2026-11-05) and tells when the dua begins; the session then ends by
 *  itself five minutes later. The relay never ends a session directly.
 *  {state: "live", title?} | {state: "dua"} */
export async function relayLive(env: Env, groupID: string, input: Record<string, unknown>): Promise<Response> {
  const group = await env.DB.prepare("SELECT id FROM member_groups WHERE id=? AND is_active=1").bind(groupID).first();
  if (!group) return json({ error: "Not found" }, { status: 404 });
  const live = await env.DB.prepare("SELECT state,kind,session_id,auto_end_at FROM group_live WHERE group_id=?").bind(groupID)
    .first<{ state: string; kind: string; session_id: string | null; auto_end_at: string | null }>();
  if (input.state === "live") {
    if (live?.state === "live") return json({ state: "live", sessionID: live.session_id, started: false });
    const title = typeof input.title === "string" && input.title.trim() ? input.title.trim().slice(0, 120) : "Zikr";
    await ensureRelayAuthor(env);
    const sessionID = await beginSession(env, groupID, RELAY_AUTHOR, { kind: "zikr", title, videoID: null, roomID: null, queue: [] });
    try {
      await notifyGroup(env, groupID, `live:${groupID}:${sessionID}`, title, "Halqah zikr has started. Join now in Darul Irfan.",
        `darulirfan://groups/${groupID}`);
    } catch { /* The session is live; a notice is best effort. */ }
    return json({ state: "live", sessionID, started: true }, { status: 201 });
  }
  if (input.state === "dua") {
    if (live?.state !== "live" || live.kind !== "zikr") return json({ error: "No live Zikr in this Halqah." }, { status: 409 });
    const endsAt = live.auto_end_at ?? new Date(Date.now() + DUA_MINUTES * 60_000).toISOString();
    if (!live.auto_end_at) {
      await env.DB.prepare("UPDATE group_live SET auto_end_at=? WHERE group_id=? AND state='live' AND auto_end_at IS NULL")
        .bind(endsAt, groupID).run();
      await recordCue(env, RELAY_AUTHOR, groupID, { id: crypto.randomUUID(), stageID: DUA_STAGE.id });
    }
    return json({ state: "dua", endsAt });
  }
  return json({ error: "state must be live or dua" }, { status: 400 });
}

/** Minutes the session stays open after the dua begins. */
export const DUA_MINUTES = 5;

/** Each minute: a session whose dua began five minutes ago ends, and is kept in history. */
export async function endAfterDua(env: Env, now = new Date()): Promise<void> {
  const due = await env.DB.prepare("SELECT group_id FROM group_live WHERE state='live' AND auto_end_at IS NOT NULL AND auto_end_at<=?")
    .bind(now.toISOString()).all<{ group_id: string }>();
  for (const row of due.results ?? []) await endSession(env, row.group_id, RELAY_AUTHOR);
}

async function ensureRelayAuthor(env: Env): Promise<void> {
  const stamp = new Date().toISOString();
  await env.DB.prepare(`INSERT OR IGNORE INTO members(id,apple_subject,display_name,email,created_at,last_seen_at)
    VALUES(?,?,'Paltalk',NULL,?,?)`).bind(RELAY_AUTHOR, `service:${RELAY_AUTHOR}`, stamp, stamp).run();
}

/** The live relay (Tools/LiveRelay) posts the stage Paltalk's hosts call, so the
 *  app, the websites and the YouTube picture show one stage. It authenticates
 *  with the platform's LISTENER_TOKEN and records as the "Paltalk" author. */
export const RELAY_AUTHOR = "service-paltalk-relay";
export async function relayZikrCue(env: Env, groupID: string, input: Record<string, unknown>): Promise<Response> {
  if (!await liveZikr(env, groupID)) return json({ error: "No live Zikr in this Halqah." }, { status: 409 });
  await ensureRelayAuthor(env);
  return recordCue(env, RELAY_AUTHOR, groupID, input);
}

async function recordCue(env: Env, memberID: string, groupID: string, input: Record<string, unknown>): Promise<Response> {
  const eventID = typeof input.id === "string" ? input.id.toLowerCase() : "";
  const stageID = typeof input.stageID === "string" ? input.stageID : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(eventID) || !stageID || stageID.length > 80) {
    return json({ error: "A stage and event ID are required" }, { status: 400 });
  }
  let stage: ZikrStage | undefined = DEFAULT_ZIKR_STAGES.find(value => value.id === stageID);
  const recitation = RECITATIONS.find(value => value.id === stageID);
  if (!stage && stageID === DUA_STAGE.id) stage = DUA_STAGE;
  if (!stage && recitation) stage = { id: recitation.id, title: recitation.title, titleUr: recitation.titleUr, isCustom: false };
  if (!stage) {
    const row = await env.DB.prepare("SELECT id,title,title_ur FROM group_zikr_stages WHERE group_id=? AND id=?")
      .bind(groupID, stageID).first<{ id: string; title: string; title_ur: string | null }>();
    if (row) stage = { id: row.id, title: row.title, titleUr: row.title_ur ?? undefined, isCustom: true };
  }
  if (!stage) return json({ error: "Stage not found" }, { status: 404 });
  // A recitation changes every few minutes; it shows on the stage without a
  // notification (only Latifas and Muraqabat notify). A test Zikr notifies nobody.
  const test = !!(await liveZikr(env, groupID))?.is_test;
  const result = await env.DB.prepare(`INSERT OR IGNORE INTO group_zikr_cues(group_id,event_id,stage_id,title,title_ur,author_id,created_at,notification_state)
    VALUES(?,?,?,?,?,?,?,?)`).bind(groupID, eventID, stage.id, stage.title, stage.titleUr ?? null, memberID, new Date().toISOString(),
    recitation || test || stageID === DUA_STAGE.id ? "complete" : "pending").run();
  const saved = await env.DB.prepare("SELECT * FROM group_zikr_cues WHERE group_id=? AND event_id=?")
    .bind(groupID, eventID).first<CueRow>();
  if (!saved) return json({ error: "Stage announcement could not be saved" }, { status: 503 });
  if (saved.stage_id !== stageID || saved.author_id !== memberID) {
    return json({ error: "This event ID already belongs to another announcement" }, { status: 409 });
  }
  // Chat is durable even if a provider fails; the scheduled dispatcher retries pending delivery.
  try { await dispatchZikrCues(env); } catch { /* Keep pending for the next attempt. */ }
  const updated = await env.DB.prepare("SELECT * FROM group_zikr_cues WHERE group_id=? AND event_id=?")
    .bind(groupID, eventID).first<CueRow>();
  return json({ cue: presentCue(updated ?? saved) }, { status: result.meta.changes ? 201 : 200 });
}


const CUE_MAX_AGE_MS = 5 * 60_000;
/** Short lease serializes retries; providers' accepted-device records avoid resending successful deliveries. */
export async function dispatchZikrCues(env: Env, now = new Date()): Promise<void> {
  const timestamp = now.toISOString();
  await env.DB.prepare(`UPDATE group_zikr_cues SET notification_state='expired'
    WHERE notification_state='pending' AND (NOT EXISTS (SELECT 1 FROM group_live l WHERE l.group_id=group_zikr_cues.group_id AND l.state='live' AND l.kind='zikr') OR created_at<? OR sequence < (
      SELECT MAX(newer.sequence) FROM group_zikr_cues newer WHERE newer.group_id=group_zikr_cues.group_id
        AND newer.stage_id NOT IN (${RECITATIONS.map(() => "?").join(",")})))`)
    .bind(new Date(now.getTime() - CUE_MAX_AGE_MS).toISOString(), ...RECITATIONS.map(recitation => recitation.id)).run();
  const pending = await env.DB.prepare(`SELECT * FROM group_zikr_cues WHERE notification_state='pending'
    AND (notification_lease_until IS NULL OR notification_lease_until<?) ORDER BY sequence LIMIT 10`)
    .bind(timestamp).all<CueRow>();
  for (const cue of pending.results ?? []) {
    const lease = new Date(now.getTime() + 120_000).toISOString();
    const claim = await env.DB.prepare(`UPDATE group_zikr_cues SET notification_lease_until=? WHERE sequence=?
      AND notification_state='pending' AND (notification_lease_until IS NULL OR notification_lease_until<?)`)
      .bind(lease, cue.sequence, timestamp).run();
    if (!claim.meta.changes) continue;
    const eventID = `halqah-cue:${cue.event_id}`;
    const group = cue.group_id ?? SHEIKH_HALQA_ID;
    const sheikh = group === SHEIKH_HALQA_ID;
    const name = sheikh ? null : (await env.DB.prepare("SELECT name FROM member_groups WHERE id=?").bind(group).first<{ name: string }>())?.name;
    try {
      const devices = await env.DB.prepare(`SELECT DISTINCT d.installation_id,d.locale FROM devices d
        JOIN member_devices md ON upper(md.installation_id)=upper(d.installation_id)
        JOIN member_group_members gm ON gm.member_id=md.member_id
        JOIN member_groups g ON g.id=gm.group_id
        WHERE gm.group_id=? AND g.is_active=1`).bind(group)
        .all<{ installation_id: string; locale: string }>();
      const list = devices.results ?? [];
      for (const urdu of [false, true]) {
        const ids = list.filter(d => d.locale.toLowerCase().startsWith("ur") === urdu).map(d => d.installation_id);
        if (!ids.length) continue;
        await sendPushToInstallations(env, eventID, `group:${group}`, ids,
          urdu && cue.title_ur ? cue.title_ur : cue.title,
          sheikh ? (urdu ? "ہمارے شیخ: ذکر کا موجودہ مرحلہ" : "Our Sheikh: current Zikr stage")
            : urdu ? `${name ?? "حلقہ"}: ذکر کا موجودہ مرحلہ` : `${name ?? "Halqah"}: current Zikr stage`,
          `darulirfan://groups/${group}`,
          { sound: "zikr_soft_chime", ttlSeconds: Math.max(1, Math.floor((Date.parse(cue.created_at) + CUE_MAX_AGE_MS - now.getTime()) / 1000)),
            collapseID: sheikh ? "sheikh-zikr-stage" : `zikr-stage-${group}` });
      }
      const delivered = await env.DB.prepare("SELECT installation_id FROM notification_deliveries WHERE event_id=? AND status='accepted'")
        .bind(eventID).all<{ installation_id: string }>();
      const accepted = new Set((delivered.results ?? []).map(d => d.installation_id));
      if (list.every(d => accepted.has(d.installation_id))) {
        await env.DB.prepare("UPDATE group_zikr_cues SET notification_state='complete' WHERE sequence=? AND notification_state='pending' AND notification_lease_until=?")
          .bind(cue.sequence, lease).run();
      }
    } finally {
      await env.DB.prepare("UPDATE group_zikr_cues SET notification_lease_until=NULL WHERE sequence=? AND notification_lease_until=?")
        .bind(cue.sequence, lease).run();
    }
  }
}


interface StageMessageRow {
  sequence: number; id: string; author_id: string; preset_id: string | null; body: string | null;
  created_at: string; name: string | null; city: string | null;
}
function presentMessage(row: StageMessageRow) {
  const preset = STAGE_PRESETS.find(value => value.id === row.preset_id);
  return { sequence: row.sequence, id: row.id, authorID: row.author_id, authorName: row.name ?? "Member",
    city: row.city ?? undefined, presetID: row.preset_id ?? undefined, text: preset?.title ?? row.body ?? "",
    textUr: preset?.titleUr, createdAt: row.created_at };
}
const STAGE_MESSAGE_SELECT = `SELECT m.sequence,m.id,m.author_id,m.preset_id,m.body,m.created_at,
    COALESCE(p.display_name,mb.display_name) AS name,p.city AS city
  FROM group_stage_messages m JOIN members mb ON mb.id=m.author_id
  LEFT JOIN sheikh_public_profiles p ON p.member_id=m.author_id`;

/** Everything the live stage shows, in one small request it repeats every few
 * seconds: the session, the picture, stage announcements and chat after the
 * phone's cursors. The chat starts with the current session. */
export async function zikrStage(env: Env, memberID: string, groupID: string, url: URL): Promise<Response> {
  const managing = await access(env, memberID, groupID, false);
  if (managing instanceof Response) return managing;
  const cursor = (name: string) => {
    const value = url.searchParams.get(name);
    return value === null ? null : /^\d{1,15}$/.test(value) && Number.isSafeInteger(Number(value)) ? Number(value) : NaN;
  };
  const cueAfter = cursor("cues"), chatAfter = cursor("chat");
  if (Number.isNaN(cueAfter) || Number.isNaN(chatAfter)) return json({ error: "Invalid stage cursor" }, { status: 400 });
  const live = await liveZikr(env, groupID, managing);
  const zikr = !!live;
  // Hazrat ji's picture belongs to Our Sheikh's stage only.
  const picture = groupID === SHEIKH_HALQA_ID ? await sheikhPicture(env) : null;
  const since = live ? sessionStart(live) : new Date().toISOString();
  // Only this session's stage announcements; with no live Zikr the stage is empty.
  const cues = !zikr ? [] : cueAfter === null
    ? ((await env.DB.prepare(`SELECT * FROM group_zikr_cues WHERE ${SESSION_CUES} ORDER BY sequence DESC LIMIT 30`)
        .bind(groupID, since).all<CueRow>()).results ?? []).reverse()
    : (await env.DB.prepare(`SELECT * FROM group_zikr_cues WHERE ${SESSION_CUES} AND sequence>? ORDER BY sequence LIMIT 100`)
        .bind(groupID, since, cueAfter).all<CueRow>()).results ?? [];
  // Announcements an admin removed since the phone's cursor, so they leave every screen.
  const hiddenCues = !zikr || cueAfter === null ? [] : ((await env.DB.prepare(`SELECT event_id FROM group_zikr_cues
      WHERE group_id=? AND hidden_at IS NOT NULL AND hidden_at>=?`).bind(groupID, since).all<{ event_id: string }>()).results ?? [])
    .map(row => row.event_id);
  const messages = chatAfter === null
    ? ((await env.DB.prepare(`${STAGE_MESSAGE_SELECT} WHERE m.group_id=? AND m.created_at>=? AND m.hidden_at IS NULL
        ORDER BY m.sequence DESC LIMIT 100`).bind(groupID, since).all<StageMessageRow>()).results ?? []).reverse()
    : (await env.DB.prepare(`${STAGE_MESSAGE_SELECT} WHERE m.group_id=? AND m.created_at>=? AND m.sequence>? AND m.hidden_at IS NULL
        ORDER BY m.sequence LIMIT 100`).bind(groupID, since, chatAfter).all<StageMessageRow>()).results ?? [];
  // Removals since the phone's cursor, so a removed message leaves every screen.
  const hidden = chatAfter === null ? [] : ((await env.DB.prepare(`SELECT id FROM group_stage_messages
      WHERE group_id=? AND hidden_at IS NOT NULL AND hidden_at>=?`).bind(groupID, since).all<{ id: string }>()).results ?? [])
    .map(row => row.id);
  return json({
    live: zikr ? { title: live?.title ?? undefined, videoID: live?.video_id ?? undefined, startedAt: live?.started_at ?? undefined,
      isTest: live?.is_test ? true : undefined } : null,
    pictureURL: picture?.pictureURL, canLead: managing && zikr,
    // Admins and the Super admin may take anything off the stage, live or not.
    canModerate: managing,
    pictureHDURL: picture?.pictureHDURL,
    cues: cues.map(presentCue), nextCue: cues.at(-1)?.sequence ?? cueAfter ?? 0, hiddenCues,
    messages: messages.map(presentMessage), nextChat: messages.at(-1)?.sequence ?? chatAfter ?? 0, hidden,
  });
}

/** Hazrat ji's picture: the thumbnail of the latest official Daily Zikr, and
 * YouTube's full-size frame where the video has one (apps fall back to pictureURL). */
async function sheikhPicture(env: Env): Promise<{ pictureURL: string; pictureHDURL?: string; videoID?: string } | null> {
  const row = await env.DB.prepare(`SELECT image_url,video_id FROM feed_items WHERE source='youtube' AND image_url IS NOT NULL
      AND title LIKE 'Online Zikr with%' ORDER BY published_at DESC LIMIT 1`).first<{ image_url: string; video_id: string | null }>();
  if (!row) return null;
  const videoID = row.video_id && /^[A-Za-z0-9_-]{11}$/.test(row.video_id) ? row.video_id : undefined;
  return { pictureURL: row.image_url, videoID, pictureHDURL: videoID ? `https://i.ytimg.com/vi/${videoID}/maxresdefault.jpg` : undefined };
}

/** An admin takes a stage announcement off the stage (a mistaken tap, a test). */
export async function hideZikrCue(env: Env, memberID: string, groupID: string, eventID: string): Promise<Response> {
  const managing = await access(env, memberID, groupID, false);
  if (managing instanceof Response) return managing;
  if (!managing) return json({ error: "Group admin role required" }, { status: 403 });
  await env.DB.prepare(`UPDATE group_zikr_cues SET hidden_at=?,
      notification_state=CASE WHEN notification_state='pending' THEN 'expired' ELSE notification_state END
    WHERE group_id=? AND event_id=? AND hidden_at IS NULL`).bind(new Date().toISOString(), groupID, eventID.toLowerCase()).run();
  return new Response(null, { status: 204 });
}

/** The public face of Our Sheikh's live Zikr for the websites: what is live and
 * the stage being followed, a test Zikr included and marked as one (owner
 * 2026-11-04, to try the websites). Never the chat or who is there. */
export async function publicSheikhStage(env: Env): Promise<Record<string, unknown>> {
  const live = await liveZikr(env, SHEIKH_HALQA_ID, true);
  const cue = live ? await env.DB.prepare(`SELECT * FROM group_zikr_cues WHERE ${SESSION_CUES} ORDER BY sequence DESC LIMIT 1`)
    .bind(SHEIKH_HALQA_ID, sessionStart(live)).first<CueRow>() : null;
  const picture = await sheikhPicture(env);
  return {
    live: live ? { title: live.title ?? undefined, startedAt: live.started_at ?? undefined, isTest: live.is_test ? true : undefined } : null,
    stage: cue ? { title: cue.title, titleUr: cue.title_ur ?? undefined, at: cue.created_at,
      arabic: RECITATIONS.find(recitation => recitation.id === cue.stage_id)?.arabic } : null,
    pictureURL: picture?.pictureURL, pictureHDURL: picture?.pictureHDURL,
    // The latest Daily Zikr, for the websites to play when nothing is live.
    latestVideoID: picture?.videoID,
  };
}

/** A member sends a ready-made message; an admin may also type one (up to 200
 * characters). Only during the live Zikr. The client's UUID makes a retry safe. */
export async function postStageMessage(env: Env, memberID: string, groupID: string, input: Record<string, unknown>): Promise<Response> {
  const managing = await access(env, memberID, groupID, false);
  if (managing instanceof Response) return managing;
  if (!await liveZikr(env, groupID, managing)) return json({ error: "The chat opens during the live Zikr." }, { status: 409 });
  const id = typeof input.id === "string" ? input.id.toLowerCase() : "";
  const presetID = typeof input.presetID === "string" ? input.presetID : null;
  const text = typeof input.text === "string" ? input.text.trim().replace(/\s+/g, " ") : null;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id)) return json({ error: "A message ID is required" }, { status: 400 });
  if (presetID !== null && text === null) {
    if (!STAGE_PRESETS.some(preset => preset.id === presetID)) return json({ error: "Unknown message" }, { status: 400 });
  } else if (text !== null && presetID === null) {
    if (!managing) return json({ error: "Members send the ready-made messages." }, { status: 403 });
    if (!text || text.length > 200 || /[\u0000-\u001f\u007f]/.test(text)) return json({ error: "Write up to 200 characters." }, { status: 400 });
  } else return json({ error: "Send a ready-made message or text" }, { status: 400 });
  // One message every 3 seconds per member keeps the stage readable.
  const last = await env.DB.prepare("SELECT created_at FROM group_stage_messages WHERE group_id=? AND author_id=? ORDER BY sequence DESC LIMIT 1")
    .bind(groupID, memberID).first<{ created_at: string }>();
  const existing = await env.DB.prepare(`${STAGE_MESSAGE_SELECT} WHERE m.group_id=? AND m.id=?`).bind(groupID, id).first<StageMessageRow>();
  if (existing) {
    return existing.author_id === memberID ? json({ message: presentMessage(existing) })
      : json({ error: "This message ID already belongs to another message" }, { status: 409 });
  }
  if (!managing && last && Date.now() - Date.parse(last.created_at) < 3_000) return json({ error: "Please wait a moment." }, { status: 429 });
  await env.DB.prepare(`INSERT OR IGNORE INTO group_stage_messages(group_id,id,author_id,preset_id,body,created_at) VALUES(?,?,?,?,?,?)`)
    .bind(groupID, id, memberID, presetID, presetID === null ? text : null, new Date().toISOString()).run();
  const saved = await env.DB.prepare(`${STAGE_MESSAGE_SELECT} WHERE m.group_id=? AND m.id=?`).bind(groupID, id).first<StageMessageRow>();
  if (!saved || saved.author_id !== memberID) return json({ error: "The message could not be saved" }, { status: 503 });
  return json({ message: presentMessage(saved) }, { status: 201 });
}

/** An admin takes a message off the stage. */
export async function hideStageMessage(env: Env, memberID: string, groupID: string, messageID: string): Promise<Response> {
  const managing = await access(env, memberID, groupID, false);
  if (managing instanceof Response) return managing;
  if (!managing) return json({ error: "Group admin role required" }, { status: 403 });
  await env.DB.prepare("UPDATE group_stage_messages SET hidden_at=? WHERE group_id=? AND id=? AND hidden_at IS NULL")
    .bind(new Date().toISOString(), groupID, messageID.toLowerCase()).run();
  return new Response(null, { status: 204 });
}
