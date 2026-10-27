import type { Env } from "./contracts";
import { halqahRole, isSuperAdmin, memberRole } from "./community";
import { cleanText, json } from "./util";

// What only the Super admin does: make Halqahs, rename or retire them, and see
// everyone who has signed in, with their Halqahs, to place them anywhere.
// Placing, role changes and removal then go through each Halqah's people
// (groupAdmin.ts), where the Super admin passes every check.

const forbidden = () => json({ error: "Super admin only" }, { status: 403 });
const notFound = () => json({ error: "Not found" }, { status: 404 });

async function superAdmin(env: Env, memberID: string): Promise<boolean> {
  return await memberRole(env, memberID) === "superadmin";
}

/** "New York Brothers" -> "new-york-brothers", unique among Halqahs. */
async function slug(env: Env, name: string): Promise<string> {
  const base = name.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 32) || "halqah";
  let candidate = base;
  for (let n = 2; await env.DB.prepare("SELECT 1 AS ok FROM member_groups WHERE id=?").bind(candidate).first(); n += 1) {
    candidate = `${base}-${n}`.slice(0, 40);
  }
  return candidate;
}

export async function createHalqah(env: Env, memberID: string, input: Record<string, unknown>): Promise<Response> {
  if (!await superAdmin(env, memberID)) return forbidden();
  const name = cleanText(input.name, 80);
  if (!name) return json({ error: "A Halqah needs a name." }, { status: 400 });
  const duplicate = await env.DB.prepare("SELECT id FROM member_groups WHERE name=? COLLATE NOCASE AND is_active=1").bind(name).first();
  if (duplicate) return json({ error: "There is already a Halqah with that name." }, { status: 409 });
  const id = await slug(env, name);
  await env.DB.prepare("INSERT INTO member_groups(id,name,description,updated_at,created_by) VALUES(?,?,?,?,?)")
    .bind(id, name, cleanText(input.description, 300) ?? null, new Date().toISOString(), `member:${memberID}`).run();
  return json({ ok: true, id, name }, { status: 201 });
}

/** Renames a Halqah or changes its description. */
export async function updateHalqah(env: Env, memberID: string, groupID: string, input: Record<string, unknown>): Promise<Response> {
  if (!await superAdmin(env, memberID)) return forbidden();
  const current = await env.DB.prepare("SELECT name,description FROM member_groups WHERE id=? AND is_active=1").bind(groupID)
    .first<{ name: string; description: string | null }>();
  if (!current) return notFound();
  const name = input.name === undefined ? current.name : cleanText(input.name, 80);
  if (!name) return json({ error: "A Halqah needs a name." }, { status: 400 });
  const description = input.description === undefined ? current.description : cleanText(input.description, 300) ?? null;
  await env.DB.prepare("UPDATE member_groups SET name=?,description=?,updated_at=? WHERE id=?")
    .bind(name, description, new Date().toISOString(), groupID).run();
  return json({ ok: true, id: groupID, name });
}

/** Retires a Halqah: it disappears for everyone, and its people, posts and
 *  history are kept, so it is never lost by a mistaken tap. */
export async function retireHalqah(env: Env, memberID: string, groupID: string): Promise<Response> {
  if (!await superAdmin(env, memberID)) return forbidden();
  const result = await env.DB.prepare("UPDATE member_groups SET is_active=0,updated_at=? WHERE id=? AND is_active=1")
    .bind(new Date().toISOString(), groupID).run();
  if ((result.meta?.changes ?? 0) === 0) return notFound();
  await env.DB.prepare(`UPDATE group_live SET state='offline',updated_at=? WHERE group_id=?`).bind(new Date().toISOString(), groupID).run();
  return new Response(null, { status: 204 });
}

/** Everyone who has signed in or joined, with their Halqahs and roles. */
export async function memberDirectory(env: Env, memberID: string): Promise<Response> {
  if (!await superAdmin(env, memberID)) return forbidden();
  const [people, places] = await Promise.all([
    env.DB.prepare("SELECT id,display_name,email,last_seen_at FROM members ORDER BY display_name COLLATE NOCASE, last_seen_at DESC LIMIT 2000")
      .all<{ id: string; display_name: string | null; email: string | null; last_seen_at: string | null }>(),
    env.DB.prepare(`SELECT p.member_id,p.group_id,p.role,g.name FROM member_group_members p
      JOIN member_groups g ON g.id=p.group_id WHERE g.is_active=1`)
      .all<{ member_id: string; group_id: string; role: string; name: string }>(),
  ]);
  const byMember = new Map<string, { groupID: string; groupName: string; role: string }[]>();
  for (const place of places.results ?? []) {
    const list = byMember.get(place.member_id) ?? [];
    list.push({ groupID: place.group_id, groupName: place.name, role: halqahRole(place.role) });
    byMember.set(place.member_id, list);
  }
  return json({
    members: (people.results ?? []).map(person => ({
      id: person.id,
      name: person.display_name ?? undefined,
      email: person.email ?? undefined,
      lastSeenAt: person.last_seen_at ?? undefined,
      isSuperAdmin: isSuperAdmin(env, person),
      isYou: person.id === memberID,
      halqahs: byMember.get(person.id) ?? [],
    })),
  });
}
