import type { Env } from "./contracts";
import { authenticatedMember, startSession } from "./members";
import { json, sha256 } from "./util";

const GROUP = "our-sheikh";
function field(value: unknown, maximum: number): string | null {
  if (typeof value !== "string") return null;
  const text = value.trim();
  return text && text.length <= maximum && !/[\u0000-\u001f\u007f]/.test(text) ? text : null;
}

/** Public admission is restricted to this one Halqa. Guest credentials are
 *  random 32-byte secrets generated and securely retained by the phone, never
 *  a device ID, name or email. Repeating a request recovers the same identity.
 *  Verified Apple/Google callers use their existing bearer session instead. */
export async function joinOurSheikh(request: Request, env: Env): Promise<Response> {
  let input: Record<string, unknown>;
  try {
    const value: unknown = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error();
    input = value as Record<string, unknown>;
  } catch { return json({ error: "Invalid profile" }, { status: 400 }); }
  const name = field(input.name, 80);
  const city = field(input.city, 100);
  const country = field(input.countryCode, 2)?.toUpperCase();
  const email = input.email == null || input.email === "" ? null : field(input.email, 254);
  if (!name || !city || !country || !/^[A-Z]{2}$/.test(country)
      || (input.email != null && input.email !== "" && (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)))) {
    return json({ error: "Enter your name, city, country and a valid optional email" }, { status: 400 });
  }
  let memberID = await authenticatedMember(request, env);
  // An expired authenticated identity must not silently turn into a guest.
  if (request.headers.has("authorization") && !memberID) return json({ error: "Sign in again" }, { status: 401 });
  const guest = !memberID;
  if (guest && (typeof input.guestSecret !== "string" || !/^[0-9a-f]{64}$/.test(input.guestSecret))) {
    return json({ error: "A secure guest credential is required" }, { status: 400 });
  }
  const group = await env.DB.prepare("SELECT id FROM member_groups WHERE id=? AND is_active=1").bind(GROUP).first();
  if (!group) return json({ error: "Our Sheikh is unavailable" }, { status: 404 });
  const now = new Date();
  const stamp = now.toISOString();
  if (guest) memberID = (await sha256(`sheikh-guest:${input.guestSecret}`)).slice(0, 32);
  const statements: D1PreparedStatement[] = [];
  if (guest) statements.push(env.DB.prepare(`INSERT INTO members(id,apple_subject,display_name,email,created_at,last_seen_at)
    VALUES(?,?,?,NULL,?,?) ON CONFLICT(id) DO UPDATE SET last_seen_at=excluded.last_seen_at`)
    .bind(memberID, `sheikh-guest:${memberID}`, name, stamp, stamp));
  statements.push(env.DB.prepare(`INSERT INTO sheikh_public_profiles(member_id,display_name,city,country_code,contact_email,updated_at)
    VALUES(?,?,?,?,?,?) ON CONFLICT(member_id) DO UPDATE SET display_name=excluded.display_name,
    city=excluded.city,country_code=excluded.country_code,contact_email=excluded.contact_email,updated_at=excluded.updated_at`)
    .bind(memberID, name, city, country, email, stamp));
  // Preserve every existing role. Caller-supplied role, group and member IDs
  // have no bearing on admission and cannot overwrite an administrator.
  statements.push(env.DB.prepare(`INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role)
    VALUES(?,?,?,'public-self-join','member') ON CONFLICT(group_id,member_id) DO NOTHING`)
    .bind(GROUP, memberID, stamp));
  await env.DB.batch(statements);
  if (guest) return startSession(env, memberID!, now);
  return json({ memberID, groupID: GROUP });
}
