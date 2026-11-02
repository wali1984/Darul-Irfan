import { sendPushToInstallations } from "./apns";
import type { Env } from "./contracts";
import { canManage, canSee, memberRole } from "./community";
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
  }
];

async function access(env: Env, memberID: string, groupID: string, write: boolean): Promise<Response | boolean> {
  const role = await memberRole(env, memberID);
  if (groupID !== SHEIKH_HALQA_ID || !await canSee(env, memberID, role, groupID)) {
    return json({ error: "Not found" }, { status: 404 });
  }
  const managing = await canManage(env, memberID, role, groupID);
  if (write && !managing) return json({ error: "Group admin role required" }, { status: 403 });
  return managing;
}

export async function zikrStages(env: Env, memberID: string, groupID: string): Promise<Response> {
  const managing = await access(env, memberID, groupID, false);
  if (managing instanceof Response) return managing;
  const custom = await env.DB.prepare("SELECT id,title,title_ur FROM group_zikr_stages WHERE group_id=? ORDER BY created_at,id")
    .bind(groupID).all<{ id: string; title: string; title_ur: string | null }>();
  return json({ canBroadcast: managing, stages: [...DEFAULT_ZIKR_STAGES, ...(custom.results ?? []).map(row => ({
    id: row.id, title: row.title, titleUr: row.title_ur ?? undefined, isCustom: true,
  }))] });
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
  sequence: number; event_id: string; stage_id: string; title: string;
  title_ur: string | null; author_id: string; created_at: string; notification_state: string;
}
function presentCue(row: CueRow) {
  return { sequence: row.sequence, id: row.event_id, stageID: row.stage_id, title: row.title,
    titleUr: row.title_ur ?? undefined, authorID: row.author_id, createdAt: row.created_at,
    notificationState: row.notification_state };
}

/** Persistent stage chat; poll after the last sequence without losing a burst of cues. */
export async function zikrCues(env: Env, memberID: string, groupID: string, after: string | null): Promise<Response> {
  const permitted = await access(env, memberID, groupID, false);
  if (permitted instanceof Response) return permitted;
  if (after !== null && (!/^\d{1,15}$/.test(after) || !Number.isSafeInteger(Number(after)))) {
    return json({ error: "Invalid chat cursor" }, { status: 400 });
  }
  const rows = after === null
    ? await env.DB.prepare("SELECT * FROM group_zikr_cues WHERE group_id=? ORDER BY sequence DESC LIMIT 100")
        .bind(groupID).all<CueRow>()
    : await env.DB.prepare("SELECT * FROM group_zikr_cues WHERE group_id=? AND sequence>? ORDER BY sequence LIMIT 100")
        .bind(groupID, Number(after)).all<CueRow>();
  const ordered = after === null ? (rows.results ?? []).reverse() : rows.results ?? [];
  return json({ cues: ordered.map(presentCue), nextSequence: ordered.at(-1)?.sequence ?? Number(after ?? 0) });
}

/** One retained event UUID per intentional tap. Names are resolved on the server, never trusted from input. */
export async function broadcastZikrCue(env: Env, memberID: string, groupID: string, input: Record<string, unknown>): Promise<Response> {
  const permitted = await access(env, memberID, groupID, true);
  if (permitted instanceof Response) return permitted;
  const eventID = typeof input.id === "string" ? input.id.toLowerCase() : "";
  const stageID = typeof input.stageID === "string" ? input.stageID : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(eventID) || !stageID || stageID.length > 80) {
    return json({ error: "A stage and event ID are required" }, { status: 400 });
  }
  let stage = DEFAULT_ZIKR_STAGES.find(value => value.id === stageID);
  if (!stage) {
    const row = await env.DB.prepare("SELECT id,title,title_ur FROM group_zikr_stages WHERE group_id=? AND id=?")
      .bind(groupID, stageID).first<{ id: string; title: string; title_ur: string | null }>();
    if (row) stage = { id: row.id, title: row.title, titleUr: row.title_ur ?? undefined, isCustom: true };
  }
  if (!stage) return json({ error: "Stage not found" }, { status: 404 });
  const result = await env.DB.prepare(`INSERT OR IGNORE INTO group_zikr_cues(group_id,event_id,stage_id,title,title_ur,author_id,created_at)
    VALUES(?,?,?,?,?,?,?)`).bind(groupID, eventID, stage.id, stage.title, stage.titleUr ?? null, memberID, new Date().toISOString()).run();
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
    WHERE notification_state='pending' AND (created_at<? OR sequence < (
      SELECT MAX(newer.sequence) FROM group_zikr_cues newer WHERE newer.group_id=group_zikr_cues.group_id))`)
    .bind(new Date(now.getTime() - CUE_MAX_AGE_MS).toISOString()).run();
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
    try {
      const devices = await env.DB.prepare(`SELECT DISTINCT d.installation_id,d.locale FROM devices d
        JOIN member_devices md ON upper(md.installation_id)=upper(d.installation_id)
        JOIN member_group_members gm ON gm.member_id=md.member_id
        JOIN member_groups g ON g.id=gm.group_id
        WHERE gm.group_id=? AND g.is_active=1`).bind(SHEIKH_HALQA_ID)
        .all<{ installation_id: string; locale: string }>();
      const list = devices.results ?? [];
      for (const urdu of [false, true]) {
        const ids = list.filter(d => d.locale.toLowerCase().startsWith("ur") === urdu).map(d => d.installation_id);
        if (!ids.length) continue;
        await sendPushToInstallations(env, eventID, `group:${SHEIKH_HALQA_ID}`, ids,
          urdu && cue.title_ur ? cue.title_ur : cue.title,
          urdu ? "????? ??? ? ??? ?? ?????? ?????" : "Our Sheikh ? current Zikr stage",
          `darulirfan://groups/${SHEIKH_HALQA_ID}`,
          { sound: "zikr_soft_chime", ttlSeconds: Math.max(1, Math.floor((Date.parse(cue.created_at) + CUE_MAX_AGE_MS - now.getTime()) / 1000)),
            collapseID: "sheikh-zikr-stage" });
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
