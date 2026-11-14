import type { Env } from "./contracts";
import { canSee, memberRole } from "./community";
import { markazAccess } from "./markaz";
import { cleanText, isUUID, json, sha256, wholeSeconds } from "./util";

// The community terms (adults only, a terms version) are not asked for yet.
// A client that already collects the declaration may record it here; nothing
// reads it back, and no route refuses a member who has none.
export const COMMUNITY_TERMS_VERSION = "2026-11-06";

/** POST /v1/members/community-consent {adult: true, termsVersion}: records that
 *  this member accepted the current terms. No birth date is stored. */
export async function acceptCommunityConsent(env: Env, memberID: string, input: Record<string, unknown>): Promise<Response> {
  if (input.adult !== true || input.termsVersion !== COMMUNITY_TERMS_VERSION) {
    return json({ error: "Send adult: true and the current termsVersion.", termsVersion: COMMUNITY_TERMS_VERSION }, { status: 400 });
  }
  await env.DB.prepare(`INSERT INTO member_community_consent(member_id,terms_version,accepted_at) VALUES(?,?,?)
    ON CONFLICT(member_id) DO UPDATE SET terms_version=excluded.terms_version,accepted_at=excluded.accepted_at`)
    .bind(memberID, COMMUNITY_TERMS_VERSION, wholeSeconds(new Date())).run();
  return json({ ok: true, termsVersion: COMMUNITY_TERMS_VERSION });
}

const targetKinds = new Set(["group", "post", "participant", "chat", "stage-chat", "dua"]);
const reasons = new Set(["harassment", "inappropriate", "privacy", "spam", "other"]);

/** The report ID is author-scoped: a lost response can be retried safely. */
export async function reportCommunityContent(env: Env, memberID: string, groupID: string, input: Record<string, unknown>): Promise<Response> {
  if (!await canSee(env, memberID, await memberRole(env, memberID), groupID)) return json({ error: "Not found" }, { status: 404 });
  if (typeof input.requestID !== "string" || !isUUID(input.requestID)
      || typeof input.targetKind !== "string" || !targetKinds.has(input.targetKind)
      || typeof input.reason !== "string" || !reasons.has(input.reason)
      || typeof input.targetID !== "string" || !input.targetID.trim() || input.targetID.length > 200
      || /[\u0000-\u001f\u007f]/.test(input.targetID)
      || (input.details !== undefined && (typeof input.details !== "string" || input.details.length > 2000))) {
    return json({ error: "Choose a report reason and a valid item." }, { status: 400 });
  }
  const id = await sha256(`${memberID}:${input.requestID.toLowerCase()}`);
  const details = cleanText(input.details, 2000) ?? null;
  const targetID = input.targetID.trim();
  const previous = await env.DB.prepare("SELECT group_id,target_kind,target_id,reason,details FROM community_reports WHERE id=?")
    .bind(id).first<Record<string, unknown>>();
  if (previous) {
    if (previous.group_id !== groupID || previous.target_kind !== input.targetKind || previous.target_id !== targetID
        || previous.reason !== input.reason || previous.details !== details) {
      return json({ error: "This report request was already used with different details." }, { status: 409 });
    }
    return json({ ok: true, id }, { status: 201 });
  }
  await env.DB.prepare(`INSERT INTO community_reports(id,group_id,reporter_id,target_kind,target_id,reason,details,created_at)
    VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(id) DO NOTHING`)
    .bind(id, groupID, memberID, input.targetKind, targetID, input.reason, details, wholeSeconds(new Date())).run();
  // Read back after a concurrent retry so conflicting payloads cannot report success.
  return reportCommunityContent(env, memberID, groupID, input);
}

async function targetPreview(env: Env, groupID: string, kind: string, targetID: string): Promise<string | null> {
  let row: { text: string | null } | null = null;
  if (kind === "group") row = await env.DB.prepare("SELECT name || COALESCE(': ' || description,'') AS text FROM member_groups WHERE id=?")
    .bind(groupID).first();
  if (kind === "post") row = await env.DB.prepare("SELECT title || COALESCE(': ' || body,'') AS text FROM member_group_posts WHERE group_id=? AND id=?")
    .bind(groupID, targetID).first();
  if (kind === "stage-chat") row = await env.DB.prepare("SELECT COALESCE(body,preset_id) AS text FROM group_stage_messages WHERE group_id=? AND id=?")
    .bind(groupID, targetID).first();
  if (kind === "dua") row = await env.DB.prepare("SELECT text FROM group_dua_requests WHERE group_id=? AND id=?")
    .bind(groupID, targetID).first();
  return row?.text?.slice(0, 4000) ?? null;
}

export async function moderationReports(env: Env, memberID: string, url: URL): Promise<Response> {
  if (!(await markazAccess(env, memberID)).canReport) return json({ error: "Markaz access required" }, { status: 403 });
  const status = url.searchParams.get("status") ?? "open";
  if (!["open", "resolved", "dismissed"].includes(status)) return json({ error: "Invalid report status" }, { status: 400 });
  const rows = await env.DB.prepare(`SELECT r.*,g.name AS group_name,m.display_name AS reporter_name
    FROM community_reports r JOIN member_groups g ON g.id=r.group_id LEFT JOIN members m ON m.id=r.reporter_id
    WHERE r.status=? ORDER BY r.created_at DESC,r.id DESC LIMIT 200`).bind(status).all<Record<string, unknown>>();
  const reports = await Promise.all(rows.results.map(async row => {
    const preview = await targetPreview(env, String(row.group_id), String(row.target_kind), String(row.target_id));
    return { id: row.id, groupID: row.group_id, groupName: row.group_name, reporterName: row.reporter_name,
      targetKind: row.target_kind, targetID: row.target_id, reason: row.reason, details: row.details,
      status: row.status, createdAt: row.created_at, resolvedAt: row.resolved_at, reviewNote: row.review_note,
      targetPreview: preview, targetUnavailable: preview === null };
  }));
  return json({ reports });
}

export async function resolveCommunityReport(env: Env, memberID: string, id: string, input: Record<string, unknown>): Promise<Response> {
  if (!(await markazAccess(env, memberID)).canReport) return json({ error: "Markaz access required" }, { status: 403 });
  if (!["resolved", "dismissed"].includes(String(input.status)) || typeof input.note !== "string"
      || !input.note.trim() || input.note.length > 2000) return json({ error: "Choose an outcome and describe the action taken." }, { status: 400 });
  const existing = await env.DB.prepare("SELECT status,review_note FROM community_reports WHERE id=?").bind(id)
    .first<{ status: string; review_note: string | null }>();
  if (!existing) return json({ error: "Not found" }, { status: 404 });
  const note = cleanText(input.note, 2000)!;
  if (existing.status !== "open") return existing.status === input.status && existing.review_note === note
    ? json({ ok: true }) : json({ error: "This report has already been reviewed. Refresh the queue." }, { status: 409 });
  const updated = await env.DB.prepare(`UPDATE community_reports SET status=?,reviewer_id=?,review_note=?,resolved_at=? WHERE id=? AND status='open'`)
    .bind(input.status, memberID, note, wholeSeconds(new Date()), id).run();
  return updated.meta.changes ? json({ ok: true }) : resolveCommunityReport(env, memberID, id, input);
}
