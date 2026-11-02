import { describe, expect, it } from "vitest";
import type { Env } from "../src/contracts";
import { joinOurSheikh } from "../src/sheikhPublicJoin";
import { authenticatedMember, startSession } from "../src/members";
import { sqliteD1 } from "./sqlite-d1";

const profile = { name: "Visitor", city: "Lahore", countryCode: "pk", guestSecret: "a".repeat(64) };
function request(input: unknown = profile, token?: string) {
  return new Request("https://example.test/v1/our-sheikh/join", {
    method: "POST", headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(input),
  });
}
function setup() {
  const { db, raw } = sqliteD1();
  raw.prepare("INSERT INTO member_groups(id,name,updated_at) VALUES('our-sheikh','Our Sheikh','now'),('private','Private','now')").run();
  return { raw, env: { DB: db, SUPER_ADMIN_EMAILS: "owner@example.com" } as Env };
}
describe("public Our Sheikh admission", () => {
  it("grants only member access to the fixed group and never trusts contact email", async () => {
    const { raw, env } = setup();
    const response = await joinOurSheikh(request({ ...profile, email: "owner@example.com", role: "administrator", groupID: "private", memberID: "owner" }), env);
    expect(response.status).toBe(201);
    const body = await response.json() as any;
    expect(body.token).toMatch(/^[a-f0-9]{64}$/);
    expect(await authenticatedMember(request(profile, body.token), env)).toBe(body.memberID);
    expect(raw.prepare("SELECT group_id,role FROM member_group_members").all()).toEqual([{ group_id: "our-sheikh", role: "member" }]);
    expect(raw.prepare("SELECT email FROM members").get()).toEqual({ email: null });
    expect(raw.prepare("SELECT country_code,contact_email FROM sheikh_public_profiles").get()).toEqual({ country_code: "PK", contact_email: "owner@example.com" });
    expect(JSON.stringify(raw.prepare("SELECT * FROM members").all())).not.toContain(profile.guestSecret);
  });
  it("recovers the same guest on retry but isolates a different phone secret", async () => {
    const { raw, env } = setup();
    const first = await (await joinOurSheikh(request(), env)).json() as any;
    const retry = await (await joinOurSheikh(request(), env)).json() as any;
    const other = await (await joinOurSheikh(request({ ...profile, guestSecret: "b".repeat(64) }), env)).json() as any;
    expect(first.memberID).toBe(retry.memberID);
    expect(other.memberID).not.toBe(first.memberID);
    expect(raw.prepare("SELECT count(*) AS n FROM member_group_members").get()).toEqual({ n: 2 });
  });
  it("preserves authenticated administrator access and verified identity", async () => {
    const { raw, env } = setup();
    raw.prepare("INSERT INTO members(id,apple_subject,email,created_at,last_seen_at) VALUES('admin','apple-admin','verified@example.com','now','now')").run();
    raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('our-sheikh','admin','now','owner','administrator')").run();
    const session = await (await startSession(env, "admin", new Date())).json() as any;
    expect((await joinOurSheikh(request({ ...profile, email: "other@example.com" }, session.token), env)).status).toBe(200);
    expect(raw.prepare("SELECT role FROM member_group_members").get()).toEqual({ role: "administrator" });
    expect(raw.prepare("SELECT email FROM members").get()).toEqual({ email: "verified@example.com" });
  });
  it("rejects invalid profiles and invalid sessions without creating identities", async () => {
    const { raw, env } = setup();
    for (const input of [null, [], {}, { ...profile, city: "" }, { ...profile, countryCode: "Pakistan" }, { ...profile, guestSecret: "phone-id" }, { ...profile, email: "invalid" }]) {
      expect((await joinOurSheikh(request(input), env)).status).toBe(400);
    }
    expect((await joinOurSheikh(request(profile, "f".repeat(64)), env)).status).toBe(401);
    expect(raw.prepare("SELECT count(*) AS n FROM members").get()).toEqual({ n: 0 });
  });
  it("does not admit visitors when the official group is inactive", async () => {
    const { raw, env } = setup();
    raw.prepare("UPDATE member_groups SET is_active=0 WHERE id='our-sheikh'").run();
    expect((await joinOurSheikh(request(), env)).status).toBe(404);
    expect(raw.prepare("SELECT count(*) AS n FROM members").get()).toEqual({ n: 0 });
  });
});
