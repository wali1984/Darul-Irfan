import type { Env } from "./contracts";
import { canManage, canSee, isSuperAdmin, memberRole } from "./community";
import { mintInvite, upsertMembership } from "./members";
import { cleanText, json } from "./util";

// People in a group, managed by its admins from the app: who is in it, adding
// someone by email or by a code sent to their phone, making and unmaking the
// group's admins, removing people, and withdrawing invitations not yet used.
//
// A group admin manages only the groups they are admin of; the super admin
// manages every group. Nobody can change a super admin from here, and nobody
// can change their own place, so an admin cannot lock themselves out by
// mistake.

const notFound = () => json({ error: "Not found" }, { status: 404 });
const forbidden = () => json({ error: "Group admin role required" }, { status: 403 });

type Gate = { ok: true; role: Awaited<ReturnType<typeof memberRole>> } | { ok: false; response: Response };

async function gate(env: Env, memberID: string, groupID: string): Promise<Gate> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return { ok: false, response: notFound() };
  if (!await canManage(env, memberID, role, groupID)) return { ok: false, response: forbidden() };
  return { ok: true, role };
}

const EMAIL = /^[^\s@<>()",;:]{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,24}$/;

/** Digits only, with the country code, as a phone app dials it. */
function phoneNumber(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const digits = value.replace(/[^\d]/g, "");
  return digits.length >= 7 && digits.length <= 15 ? digits : null;
}

/** The group's people and its open invitations. */
export async function groupPeople(env: Env, memberID: string, groupID: string): Promise<Response> {
  const allowed = await gate(env, memberID, groupID);
  if (!allowed.ok) return allowed.response;
  const now = new Date().toISOString();
  const [people, codes, grants] = await Promise.all([
    env.DB.prepare(`SELECT m.id,m.display_name,m.email,m.role AS member_role,g.role,g.added_at
      FROM member_group_members g JOIN members m ON m.id=g.member_id
      WHERE g.group_id=? ORDER BY g.role='admin' DESC, m.display_name COLLATE NOCASE, g.added_at`).bind(groupID).all(),
    env.DB.prepare(`SELECT rowid AS id,label,grants_role,created_at,expires_at FROM member_invites
      WHERE group_id=? AND redeemed_at IS NULL AND expires_at > ? ORDER BY created_at DESC`).bind(groupID, now).all(),
    env.DB.prepare(`SELECT id,email,role,created_at FROM member_group_grants
      WHERE group_id=? AND claimed_at IS NULL ORDER BY created_at DESC`).bind(groupID).all(),
  ]);
  return json({
    members: (people.results ?? []).map(row => ({
      id: row.id,
      name: row.display_name ?? undefined,
      email: row.email ?? undefined,
      role: isSuperAdmin(env, { role: row.member_role, email: row.email }) ? "superadmin" : row.role === "admin" ? "admin" : "member",
      addedAt: row.added_at,
      isYou: row.id === memberID,
    })),
    invitations: [
      ...(grants.results ?? []).map(row => ({
        id: `email-${row.id}`, kind: "email", label: row.email, role: row.role === "admin" ? "admin" : "member",
        createdAt: row.created_at,
      })),
      ...(codes.results ?? []).map(row => ({
        id: `code-${row.id}`, kind: "code", label: row.label ?? undefined,
        role: row.grants_role === "admin" ? "admin" : row.grants_role === "superadmin" ? "superadmin" : "member",
        createdAt: row.created_at, expiresAt: row.expires_at,
      })),
    ],
  });
}

/** Adds someone to the group, as a member or as its admin.
 *
 *  By email: someone who has already signed in with that email is added at
 *  once; anyone else is added the moment they sign in with Apple under it.
 *  Otherwise (a phone number, or nothing): a single-use code, which the admin
 *  sends from their own phone. Signing in cannot prove a phone number, so a
 *  phone is only where the code goes and the note it is filed under. */
export async function addPerson(env: Env, memberID: string, groupID: string, input: Record<string, unknown>): Promise<Response> {
  const allowed = await gate(env, memberID, groupID);
  if (!allowed.ok) return allowed.response;
  const role = input.role === "admin" ? "admin" : "member";
  const email = typeof input.email === "string" && input.email.trim() ? input.email.trim().toLowerCase() : null;
  const actor = `member:${memberID}`;

  if (email) {
    if (!EMAIL.test(email)) return json({ error: "That email address does not look right." }, { status: 400 });
    const existing = await env.DB.prepare("SELECT id,display_name FROM members WHERE email=? ORDER BY last_seen_at DESC LIMIT 1")
      .bind(email).first<{ id: string; display_name: string | null }>();
    if (existing) {
      if (existing.id === memberID) return json({ error: "You are already in this group." }, { status: 400 });
      await upsertMembership(env, groupID, existing.id, role, actor, false);
      return json({ result: "added", name: existing.display_name ?? undefined, role }, { status: 201 });
    }
    await env.DB.prepare(`INSERT INTO member_group_grants(id,group_id,email,role,created_by,created_at) VALUES(?,?,?,?,?,?)
      ON CONFLICT(group_id,email) DO UPDATE SET role=excluded.role,created_by=excluded.created_by,
        created_at=excluded.created_at,claimed_by=NULL,claimed_at=NULL`)
      .bind(crypto.randomUUID(), groupID, email, role, actor, new Date().toISOString()).run();
    return json({ result: "pending", role }, { status: 201 });
  }

  const days = Number(input.expiresInDays ?? 14);
  if (!Number.isInteger(days) || days < 1 || days > 90) {
    return json({ error: "A code lasts from 1 to 90 days." }, { status: 400 });
  }
  const phone = input.phone === undefined || input.phone === "" ? null : phoneNumber(input.phone);
  if (input.phone !== undefined && input.phone !== "" && !phone) {
    return json({ error: "That phone number does not look right. Include the country code." }, { status: 400 });
  }
  const label = phone ? `+${phone}` : cleanText(input.label, 120) ?? null;
  const { code, expiresAt } = await mintInvite(env, actor, groupID, days, label, role === "admin" ? "admin" : null);
  return json({ result: "code", code, expiresAt, phone: phone ?? undefined, role }, { status: 201 });
}

/** Makes someone in the group its admin, or a member again. */
export async function setPersonRole(
  env: Env, memberID: string, groupID: string, personID: string, input: Record<string, unknown>,
): Promise<Response> {
  const allowed = await gate(env, memberID, groupID);
  if (!allowed.ok) return allowed.response;
  const refusal = await protectedPerson(env, memberID, groupID, personID);
  if (refusal) return refusal;
  const role = input.role === "admin" ? "admin" : "member";
  await env.DB.prepare("UPDATE member_group_members SET role=? WHERE group_id=? AND member_id=?").bind(role, groupID, personID).run();
  return json({ ok: true, role });
}

/** Takes someone out of the group. Their account and other groups stay. */
export async function removePerson(env: Env, memberID: string, groupID: string, personID: string): Promise<Response> {
  const allowed = await gate(env, memberID, groupID);
  if (!allowed.ok) return allowed.response;
  const refusal = await protectedPerson(env, memberID, groupID, personID);
  if (refusal) return refusal;
  await env.DB.prepare("DELETE FROM member_group_members WHERE group_id=? AND member_id=?").bind(groupID, personID).run();
  return new Response(null, { status: 204 });
}

/** Withdraws a code or an email invitation that has not been used yet. */
export async function revokeInvitation(env: Env, memberID: string, groupID: string, invitationID: string): Promise<Response> {
  const allowed = await gate(env, memberID, groupID);
  if (!allowed.ok) return allowed.response;
  const code = /^code-(\d{1,12})$/.exec(invitationID);
  const email = /^email-([0-9a-f-]{36})$/.exec(invitationID);
  const result = code
    ? await env.DB.prepare("DELETE FROM member_invites WHERE rowid=? AND group_id=? AND redeemed_at IS NULL")
      .bind(Number(code[1]), groupID).run()
    : email
      ? await env.DB.prepare("DELETE FROM member_group_grants WHERE id=? AND group_id=? AND claimed_at IS NULL")
        .bind(email[1], groupID).run()
      : null;
  if (!result || (result.meta?.changes ?? 0) === 0) return notFound();
  return new Response(null, { status: 204 });
}

/** Someone a group admin may not change: not in the group, themselves, or a
 *  super admin. The super admin may change anyone but themselves. */
async function protectedPerson(env: Env, memberID: string, groupID: string, personID: string): Promise<Response | null> {
  if (personID === memberID) return json({ error: "You cannot change your own place in the group." }, { status: 400 });
  const person = await env.DB.prepare(`SELECT m.role,m.email FROM member_group_members g JOIN members m ON m.id=g.member_id
    WHERE g.group_id=? AND g.member_id=?`).bind(groupID, personID).first<{ role: string; email: string | null }>();
  if (!person) return notFound();
  if (isSuperAdmin(env, person)) return json({ error: "A super admin cannot be changed here." }, { status: 403 });
  return null;
}
