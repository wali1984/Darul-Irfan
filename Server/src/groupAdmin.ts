import type { Env } from "./contracts";
import { canAppointAdministrators, canManage, canSee, halqahRole, isSuperAdmin, memberRole, type HalqahRole, type Role } from "./community";
import { mintInvite, upsertMembership } from "./members";
import { cleanText, json } from "./util";

// People in a Halqah, managed from the app: who is in it, adding someone by
// email or by a code sent to their phone, setting their role, removing
// people, and withdrawing invitations not yet used.
//
// Admins and Administrators manage only their own Halqah; the Super admin
// manages every Halqah. Admins make Admins and members; only Administrators
// (and the Super admin) make, change or remove Administrators. Nobody can
// change a Super admin here, and nobody can change their own place, so no one
// locks themselves out by mistake.

const notFound = () => json({ error: "Not found" }, { status: 404 });
const forbidden = () => json({ error: "Group admin role required" }, { status: 403 });

type Gate = { ok: true; role: Role; seniors: boolean } | { ok: false; response: Response };

/** Whether the caller manages this Halqah, and whether they may also deal
 *  with its Administrators. */
async function gate(env: Env, memberID: string, groupID: string): Promise<Gate> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return { ok: false, response: notFound() };
  if (!await canManage(env, memberID, role, groupID)) return { ok: false, response: forbidden() };
  return { ok: true, role, seniors: await canAppointAdministrators(env, memberID, role, groupID) };
}

const seniorsOnly = () => json({ error: "Only an Administrator of this Halqah, or a Super admin, can do that for an Administrator." }, { status: 403 });

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
      WHERE g.group_id=? ORDER BY CASE g.role WHEN 'administrator' THEN 2 WHEN 'admin' THEN 1 ELSE 0 END DESC,
        m.display_name COLLATE NOCASE, g.added_at`).bind(groupID).all(),
    env.DB.prepare(`SELECT rowid AS id,label,grants_role,created_at,expires_at FROM member_invites
      WHERE group_id=? AND redeemed_at IS NULL AND expires_at > ? ORDER BY created_at DESC`).bind(groupID, now).all(),
    env.DB.prepare(`SELECT id,email,role,created_at FROM member_group_grants
      WHERE group_id=? AND claimed_at IS NULL ORDER BY created_at DESC`).bind(groupID).all(),
  ]);
  return json({
    // What this viewer may hand out, so the app offers only that.
    canAppointAdministrators: allowed.seniors,
    members: (people.results ?? []).map(row => ({
      id: row.id,
      name: row.display_name ?? undefined,
      email: row.email ?? undefined,
      role: isSuperAdmin(env, { email: row.email }) ? "superadmin" : halqahRole(row.role),
      addedAt: row.added_at,
      isYou: row.id === memberID,
    })),
    invitations: [
      ...(grants.results ?? []).map(row => ({
        id: `email-${row.id}`, kind: "email", label: row.email, role: halqahRole(row.role),
        createdAt: row.created_at,
      })),
      ...(codes.results ?? []).map(row => ({
        id: `code-${row.id}`, kind: "code", label: row.label ?? undefined,
        role: halqahRole(row.grants_role),
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
  const role = halqahRole(input.role);
  if (role === "administrator" && !allowed.seniors) return seniorsOnly();
  const email = typeof input.email === "string" && input.email.trim() ? input.email.trim().toLowerCase() : null;
  const actor = `member:${memberID}`;

  // The Super admin can place anyone who has signed in, from the directory.
  if (typeof input.memberID === "string") {
    if (allowed.role !== "superadmin") return forbidden();
    const person = await env.DB.prepare("SELECT id,display_name FROM members WHERE id=?").bind(input.memberID)
      .first<{ id: string; display_name: string | null }>();
    if (!person) return notFound();
    await upsertMembership(env, groupID, person.id, role, actor, false);
    return json({ result: "added", name: person.display_name ?? undefined, role }, { status: 201 });
  }

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
  const { code, expiresAt } = await mintInvite(env, actor, groupID, days, label, role === "member" ? null : role);
  return json({ result: "code", code, expiresAt, phone: phone ?? undefined, role }, { status: 201 });
}

/** Sets someone's role in the Halqah: member, Admin or Administrator. */
export async function setPersonRole(
  env: Env, memberID: string, groupID: string, personID: string, input: Record<string, unknown>,
): Promise<Response> {
  const allowed = await gate(env, memberID, groupID);
  if (!allowed.ok) return allowed.response;
  const refusal = await protectedPerson(env, memberID, groupID, personID, allowed.seniors);
  if (refusal) return refusal;
  const role = halqahRole(input.role);
  if (role === "administrator" && !allowed.seniors) return seniorsOnly();
  await env.DB.prepare("UPDATE member_group_members SET role=? WHERE group_id=? AND member_id=?").bind(role, groupID, personID).run();
  return json({ ok: true, role });
}

/** Takes someone out of the group. Their account and other groups stay. */
export async function removePerson(env: Env, memberID: string, groupID: string, personID: string): Promise<Response> {
  const allowed = await gate(env, memberID, groupID);
  if (!allowed.ok) return allowed.response;
  const refusal = await protectedPerson(env, memberID, groupID, personID, allowed.seniors);
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
  if (!allowed.seniors) {
    // An Administrator's invitation is withdrawn only by those who may make one.
    const senior = code
      ? await env.DB.prepare("SELECT 1 AS ok FROM member_invites WHERE rowid=? AND group_id=? AND grants_role='administrator'").bind(Number(code[1]), groupID).first()
      : email
        ? await env.DB.prepare("SELECT 1 AS ok FROM member_group_grants WHERE id=? AND group_id=? AND role='administrator'").bind(email[1], groupID).first()
        : null;
    if (senior) return seniorsOnly();
  }
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

/** Someone the caller may not change: not in the Halqah, themselves, a
 *  Super admin, or - for an Admin - an Administrator. */
async function protectedPerson(
  env: Env, memberID: string, groupID: string, personID: string, seniors: boolean,
): Promise<Response | null> {
  if (personID === memberID) return json({ error: "You cannot change your own place in the Halqah." }, { status: 400 });
  const person = await env.DB.prepare(`SELECT m.email,g.role FROM member_group_members g JOIN members m ON m.id=g.member_id
    WHERE g.group_id=? AND g.member_id=?`).bind(groupID, personID).first<{ email: string | null; role: string }>();
  if (!person) return notFound();
  if (isSuperAdmin(env, person)) return json({ error: "A Super admin cannot be changed here." }, { status: 403 });
  if (halqahRole(person.role) === "administrator" && !seniors) return seniorsOnly();
  return null;
}

export type { HalqahRole };
