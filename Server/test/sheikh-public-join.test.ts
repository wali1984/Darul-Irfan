import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { joinOurSheikh } from "../src/sheikhPublicJoin";
import { authenticatedMember, startSession } from "../src/members";
import { sqliteD1 } from "./sqlite-d1";
import { communityGroups, groupDetail, memberRole, setLive } from "../src/community";
import { addZikrStage } from "../src/groupZikrStages";

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
  it("keeps admitted guests out of private groups and all broadcast controls", async () => {
    const { raw, env } = setup();
    const admission = await (await joinOurSheikh(request({ ...profile, email: "owner@example.com" }), env)).json() as any;
    expect(await memberRole(env, admission.memberID)).toBe("member");
    const list = await (await communityGroups(env, admission.memberID)).json() as any;
    expect(list.groups.map((group: any) => group.id)).toEqual(["our-sheikh"]);
    expect(list.groups[0].canManage).toBe(false);
    expect((await groupDetail(env, admission.memberID, "private")).status).toBe(404);
    expect((await setLive(env, admission.memberID, "our-sheikh", { state: "live", kind: "zikr" })).status).toBe(403);
    raw.prepare("INSERT INTO group_live(group_id,state,kind,updated_at) VALUES('our-sheikh','live','zikr','now')").run();
    expect((await addZikrStage(env, admission.memberID, "our-sheikh", { id: "custom-12345678-1234-1234-1234-123456789abc", title: "Not authorized" })).status).toBe(403);
  });

  it("rolls back guest and profile creation if membership cannot be inserted", async () => {
    const { raw, env } = setup();
    raw.exec("CREATE TRIGGER reject_admission BEFORE INSERT ON member_group_members BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    await expect(joinOurSheikh(request(), env)).rejects.toThrow();
    for (const table of ["members", "sheikh_public_profiles", "member_sessions"]) {
      expect(raw.prepare(`SELECT count(*) AS n FROM ${table}`).get()).toEqual({ n: 0 });
    }
  });
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


describe("public Our Sheikh HTTP routes", () => {
  afterEach(() => vi.useRealTimers());
  const at = (input: unknown, ip: string, token?: string) => {
    const result = request(input, token);
    result.headers.set("cf-connecting-ip", ip);
    return result;
  };

  it("admits a guest through the router but denies private groups and live controls", async () => {
    const { env } = setup();
    const joined = await worker.fetch(at({ ...profile, role: "administrator", groupID: "private", email: "owner@example.com" }, "192.0.2.1"), env);
    expect(joined.status).toBe(201);
    expect(joined.headers.get("access-control-allow-origin")).toBeNull();
    const identity = await joined.json() as { token: string };
    const call = (path: string, method = "GET", input?: unknown) => worker.fetch(new Request(`https://example.test${path}`, {
      method, headers: { Authorization: `Bearer ${identity.token}`, "Content-Type": "application/json" },
      ...(input === undefined ? {} : { body: JSON.stringify(input) }),
    }), env);
    const groups = await (await call("/v1/groups")).json() as any;
    expect(groups.groups.map((group: any) => group.id)).toEqual(["our-sheikh"]);
    expect(groups.groups[0].canManage).toBe(false);
    expect((await call("/v1/groups/private")).status).toBe(404);
    expect((await call("/v1/groups/our-sheikh/live", "POST", { state: "live", kind: "zikr" })).status).toBe(403);
  });

  it("limits invalid attempts too, isolates client addresses and resets at the next hour", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-11-02T06:10:00Z"));
    const { raw, env } = setup();
    for (let i = 0; i < 60; i++) {
      expect((await worker.fetch(at({}, "192.0.2.10"), env)).status).toBe(400);
    }
    expect((await worker.fetch(at(profile, "192.0.2.10"), env)).status).toBe(429);
    expect(raw.prepare("SELECT count(*) AS n FROM members").get()).toEqual({ n: 0 });
    expect((await worker.fetch(at(profile, "192.0.2.11"), env)).status).toBe(201);
    vi.setSystemTime(new Date("2026-11-02T07:00:00Z"));
    expect((await worker.fetch(at(profile, "192.0.2.10"), env)).status).toBe(201);
    expect(raw.prepare("SELECT count(*) AS n FROM members").get()).toEqual({ n: 1 });
  });

  it("does not downgrade an expired bearer to a new guest at the public route", async () => {
    const { raw, env } = setup();
    expect((await worker.fetch(at(profile, "192.0.2.20", "f".repeat(64)), env)).status).toBe(401);
    for (const table of ["members", "sheikh_public_profiles", "member_sessions", "member_group_members"]) {
      expect(raw.prepare(`SELECT count(*) AS n FROM ${table}`).get()).toEqual({ n: 0 });
    }
  });

  it("rejects declared oversized admission bodies before creating a profile", async () => {
    const { raw, env } = setup();
    const oversized = at(profile, "192.0.2.30");
    oversized.headers.set("content-length", "256001");
    expect((await worker.fetch(oversized, env)).status).toBe(413);
    expect(raw.prepare("SELECT count(*) AS n FROM members").get()).toEqual({ n: 0 });
    expect(raw.prepare("SELECT count(*) AS n FROM rate_limits").get()).toEqual({ n: 0 });
  });
  it("bounds actual bytes with missing or dishonest length headers", async () => {
    for (const declared of [null, "1"]) {
      const { raw, env } = setup();
      const body = at({ ...profile, extra: "\u0639".repeat(9000) }, "192.0.2.40");
      if (declared !== null) body.headers.set("content-length", declared);
      expect((await worker.fetch(body, env)).status).toBe(413);
      expect(raw.prepare("SELECT count(*) AS n FROM members").get()).toEqual({ n: 0 });
    }
  });

  it("cancels an oversized stream before profile or session writes", async () => {
    const { raw, env } = setup();
    let canceled = false;
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) { controller.enqueue(new Uint8Array(8193).fill(32)); },
      cancel() { canceled = true; },
    });
    const init = { method: "POST", body: stream, duplex: "half" } as RequestInit & { duplex: "half" };
    expect((await worker.fetch(new Request("https://example.test/v1/our-sheikh/join", init), env)).status).toBe(413);
    expect(canceled).toBe(true);
    for (const table of ["members", "sheikh_public_profiles", "member_sessions"]) {
      expect(raw.prepare(`SELECT count(*) AS n FROM ${table}`).get()).toEqual({ n: 0 });
    }
  });

  it("accepts a valid Urdu profile even when UTF-8 characters span chunks", async () => {
    const { raw, env } = setup();
    const value = { ...profile, name: "\u0632\u0627\u0626\u0631", city: "\u0644\u0627\u06c1\u0648\u0631" };
    const bytes = new TextEncoder().encode(JSON.stringify(value));
    let offset = 0;
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) {
        if (offset === bytes.length) { controller.close(); return; }
        controller.enqueue(bytes.slice(offset, ++offset));
      },
    });
    const init = { method: "POST", body: stream, duplex: "half" } as RequestInit & { duplex: "half" };
    expect((await worker.fetch(new Request("https://example.test/v1/our-sheikh/join", init), env)).status).toBe(201);
    expect(raw.prepare("SELECT display_name,city FROM sheikh_public_profiles").get()).toEqual({ display_name: value.name, city: value.city });
  });

});
