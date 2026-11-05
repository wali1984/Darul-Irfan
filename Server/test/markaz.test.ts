// The Silsila Markaz (owner 2026-11-05): reports and analytics for super admins
// and the Markaz's officers, the organisation by region, notices to many
// Halqahs, and the reporting website's sign-in by a code approved in the app.
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { markazDigest } from "../src/markaz";
import { sqliteD1 } from "./sqlite-d1";

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

const SUPER = "s".repeat(32), OFFICER = "o".repeat(32), ADMIN = "a".repeat(32), MEMBER = "m".repeat(32), GUEST = "g".repeat(32);
const TOKENS = { [SUPER]: "1".repeat(64), [OFFICER]: "2".repeat(64), [ADMIN]: "3".repeat(64), [MEMBER]: "4".repeat(64) };

async function setup() {
  const { db, raw } = sqliteD1();
  vi.stubGlobal("fetch", async () => new Response("", { status: 200 }));
  const now = new Date().toISOString(), later = new Date(Date.now() + 86_400_000).toISOString();
  const people: [string, string, string | null][] = [[SUPER, "Super", "boss@example.com"], [OFFICER, "Officer", null], [ADMIN, "Ameer", null], [MEMBER, "Ali", null]];
  for (const [id, name, email] of people) {
    raw.prepare("INSERT INTO members(id,apple_subject,display_name,email,created_at,last_seen_at) VALUES(?,?,?,?,?,?)").run(id, `apple:${id}`, name, email, now, now);
    raw.prepare("INSERT INTO member_sessions(token_hash,member_id,created_at,expires_at,last_seen_at) VALUES(?,?,?,?,?)")
      .run(await sha256(TOKENS[id]!), id, now, later, now);
  }
  raw.prepare("INSERT INTO members(id,apple_subject,display_name,created_at,last_seen_at) VALUES(?,?,?,?,?)").run(GUEST, `web-guest:${GUEST}`, "Visitor", now, now);
  raw.prepare("INSERT INTO sheikh_public_profiles(member_id,display_name,city,country_code,updated_at) VALUES(?,?,?,?,?)").run(GUEST, "Visitor", "Leeds", "GB", now);
  raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('silsila-markaz',?,?,'test','admin')").run(OFFICER, now);
  raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('usa',?,?,'test','administrator')").run(ADMIN, now);
  raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('usa',?,?,'test','member')").run(MEMBER, now);
  raw.prepare("UPDATE member_groups SET region='North America',country_code='US' WHERE id IN ('usa','canada')").run();
  const env = { DB: db, SUPER_ADMIN_EMAILS: "boss@example.com", PUBLIC_BASE_URL: "https://api.example.com" } as unknown as Env;
  const call = (token: string, method: string, path: string, body?: unknown) =>
    worker.fetch(new Request(`https://api.example.com${path}`, {
      method, headers: { authorization: `Bearer ${token}`, "cf-connecting-ip": "7.7.7.7", ...(body ? { "content-type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    }), env);
  return { raw, env, call };
}

/** A finished session in a group, `daysAgo` days back at 01:00 UTC, with who came. */
function held(raw: ReturnType<typeof sqliteD1>["raw"], id: string, group: string, daysAgo: number, present: string[], test = 0, startedBy = ADMIN) {
  const start = new Date(Date.UTC(new Date().getUTCFullYear(), new Date().getUTCMonth(), new Date().getUTCDate() - daysAgo, 1, 0));
  const end = new Date(start.getTime() + 45 * 60_000);
  raw.prepare(`INSERT INTO group_live_history(session_id,group_id,kind,title,started_at,started_by,ended_at,ended_by,attendees,is_test)
    VALUES(?,?,'zikr','Halqah Zikr',?,?,?,?,?,?)`).run(id, group, start.toISOString(), startedBy, end.toISOString(), ADMIN, present.length, test);
  for (const person of present) {
    raw.prepare("INSERT INTO group_live_presence(session_id,group_id,member_id,first_seen_at,last_seen_at) VALUES(?,?,?,?,?)")
      .run(id, group, person, new Date(start.getTime() + 60_000).toISOString(), new Date(end.getTime() - 60_000).toISOString());
  }
}

afterEach(() => vi.unstubAllGlobals());

describe("Markaz access", () => {
  it("is for super admins and the Markaz's officers only", async () => {
    const { call } = await setup();
    expect(await (await call(TOKENS[SUPER]!, "GET", "/v1/markaz/access")).json()).toMatchObject({ canReport: true, isSuperAdmin: true });
    expect(await (await call(TOKENS[OFFICER]!, "GET", "/v1/markaz/access")).json()).toMatchObject({ canReport: true, isSuperAdmin: false, markazRole: "admin" });
    expect(await (await call(TOKENS[ADMIN]!, "GET", "/v1/markaz/access")).json()).toMatchObject({ canReport: false });
    for (const path of ["analytics", "reports/daily", "reports/monthly", "organization", "export", "announcements"]) {
      expect((await call(TOKENS[ADMIN]!, "GET", `/v1/markaz/${path}`)).status).toBe(403);
      expect((await call(TOKENS[MEMBER]!, "GET", `/v1/markaz/${path}`)).status).toBe(403);
    }
    expect((await worker.fetch(new Request("https://api.example.com/v1/markaz/analytics"), (await setup()).env)).status).toBe(401);
  });
});

describe("Markaz analytics", () => {
  it("counts sessions, people and visitors, never tests, with the period before", async () => {
    const { raw, call } = await setup();
    held(raw, "s1", "usa", 2, [MEMBER, ADMIN, GUEST]);
    held(raw, "s2", "usa", 1, [MEMBER], 0, "service-paltalk-relay");
    held(raw, "s3", "canada", 1, [MEMBER]);
    held(raw, "t1", "usa", 1, [MEMBER, ADMIN], 1);
    held(raw, "old", "usa", 40, [MEMBER]);
    const body = await (await call(TOKENS[OFFICER]!, "GET", "/v1/markaz/analytics?tz=UTC")).json() as Record<string, any>;
    expect(body.summary).toMatchObject({ sessions: 3, attendance: 5, uniqueAttendees: 3, webAttendance: 1, appAttendance: 4,
      automatedStarts: 1, activeHalqahs: 2, averageMinutes: 45 });
    expect(body.previous).toMatchObject({ sessions: 1, attendance: 1 });
    expect(body.daily).toHaveLength(30);
    expect(body.sessions.map((row: { id: string }) => row.id).sort()).toEqual(["s1", "s2", "s3"]);
    expect(body.sessions.find((row: { id: string }) => row.id === "s2")).toMatchObject({ automated: true, startedBy: null });
    const usa = body.halqahs.find((row: { id: string }) => row.id === "usa");
    expect(usa).toMatchObject({ sessions: 2, attendance: 4, members: 2, status: "active", region: "North America" });
    expect(body.countries).toEqual([{ code: "GB", attendees: 1 }]);
    expect(body.regulars[0]).toMatchObject({ name: "Ali", sessions: 3 });
    expect(body.insights.some((item: { title: string }) => item.title.includes("ran by themselves"))).toBe(true);

    const region = await (await call(TOKENS[SUPER]!, "GET", "/v1/markaz/analytics?tz=UTC&scope=halqah:canada")).json() as Record<string, any>;
    expect(region.summary.sessions).toBe(1);
    expect((await call(TOKENS[SUPER]!, "GET", "/v1/markaz/analytics?scope=halqah:nowhere")).status).toBe(404);
    expect((await call(TOKENS[SUPER]!, "GET", "/v1/markaz/analytics?from=2020-01-01&to=2026-01-01")).status).toBe(400);
  });

  it("finds regulars who have stopped coming", async () => {
    const { raw, call } = await setup();
    for (const days of [60, 50, 40, 30]) held(raw, `p${days}`, "usa", days, [MEMBER]);
    held(raw, "now", "usa", 1, [ADMIN]);
    const body = await (await call(TOKENS[SUPER]!, "GET", "/v1/markaz/analytics?tz=UTC")).json() as Record<string, any>;
    expect(body.needsCare).toEqual([expect.objectContaining({ memberID: MEMBER, name: "Ali", sessionsBefore: 4, halqah: "United States" })]);
  });

  it("reports a day, a month, one session and one person, and exports CSV", async () => {
    const { raw, call } = await setup();
    held(raw, "s1", "usa", 1, [MEMBER, GUEST]);
    raw.prepare("INSERT INTO group_zikr_sessions(id,group_id,title,weekdays_json,start_hour,start_minute,time_zone,updated_at) VALUES('z','canada','Zikr','[1,2,3,4,5,6,7]',21,0,'UTC',?)")
      .run(new Date().toISOString());
    const day = await (await call(TOKENS[SUPER]!, "GET", "/v1/markaz/reports/daily?tz=UTC")).json() as Record<string, any>;
    expect(day.summary.sessions).toBe(1);
    expect(day.halqahs[0].sessions[0].attendees.map((row: { via: string }) => row.via).sort()).toEqual(["app", "web"]);
    expect(day.noSession).toEqual([{ id: "canada", name: "Canada" }]);
    const month = await (await call(TOKENS[SUPER]!, "GET", "/v1/markaz/reports/monthly?month=2026-10&tz=UTC")).json() as Record<string, any>;
    expect(month.month).toBe("2026-10");
    expect(month.daily).toHaveLength(31);
    const session = await (await call(TOKENS[SUPER]!, "GET", "/v1/markaz/sessions/s1")).json() as Record<string, any>;
    expect(session.attendees).toHaveLength(2);
    const person = await (await call(TOKENS[SUPER]!, "GET", `/v1/markaz/people/${MEMBER}?tz=UTC`)).json() as Record<string, any>;
    expect(person).toMatchObject({ name: "Ali", sessions: 1, halqahs: [{ id: "usa", role: "member" }] });
    const exported = await call(TOKENS[SUPER]!, "GET", "/v1/markaz/export?type=attendance&tz=UTC");
    expect(exported.headers.get("content-type")).toContain("text/csv");
    const bytes = new Uint8Array(await exported.arrayBuffer());
    // A byte-order mark, so Excel reads Urdu names as UTF-8.
    expect([...bytes.slice(0, 3)]).toEqual([0xef, 0xbb, 0xbf]);
    const text = new TextDecoder().decode(bytes);
    expect(text.startsWith("Date,Halqah")).toBe(true);
    expect(text).toContain("Leeds");
    for (const type of ["sessions", "halqahs", "people"]) expect((await call(TOKENS[SUPER]!, "GET", `/v1/markaz/export?type=${type}`)).status).toBe(200);
  });
});

describe("Markaz organisation", () => {
  it("lists regions, places Halqahs, brings admins in and sends notices", async () => {
    const { raw, call } = await setup();
    const org = await (await call(TOKENS[OFFICER]!, "GET", "/v1/markaz/organization")).json() as Record<string, any>;
    expect(org.regions[0].name).toBe("North America");
    expect(org.regions[0].halqahs.find((row: { id: string }) => row.id === "usa").administrators).toEqual(["Ameer"]);
    expect(org.markaz).toMatchObject({ id: "silsila-markaz", officers: 1 });

    expect((await call(TOKENS[OFFICER]!, "PUT", "/v1/markaz/halqahs/darul-irfan", { region: "Pakistan" })).status).toBe(403);
    expect((await call(TOKENS[SUPER]!, "PUT", "/v1/markaz/halqahs/darul-irfan", { region: "Pakistan", countryCode: "pk", city: "Chakwal" })).status).toBe(200);
    expect(raw.prepare("SELECT region,country_code,city FROM member_groups WHERE id='darul-irfan'").get()).toEqual({ region: "Pakistan", country_code: "PK", city: "Chakwal" });

    expect(await (await call(TOKENS[SUPER]!, "POST", "/v1/markaz/sync-admins")).json()).toMatchObject({ added: 1 });
    expect(raw.prepare("SELECT role FROM member_group_members WHERE group_id='silsila-markaz' AND member_id=?").get(ADMIN)).toEqual({ role: "member" });

    const sent = await (await call(TOKENS[OFFICER]!, "POST", "/v1/markaz/announce", { title: "Ijtema", body: "Monthly Ijtema on Sunday", scope: "region:North America" })).json();
    expect(sent).toMatchObject({ ok: true, posted: 2 });
    expect(raw.prepare("SELECT COUNT(*) AS n FROM member_group_posts WHERE title='Ijtema'").get()).toEqual({ n: 2 });
    await call(TOKENS[OFFICER]!, "POST", "/v1/markaz/announce", { title: "Admins", audience: "admins" });
    expect(raw.prepare("SELECT group_id FROM member_group_posts WHERE title='Admins'").all()).toEqual([{ group_id: "silsila-markaz" }]);
    const list = await (await call(TOKENS[SUPER]!, "GET", "/v1/markaz/announcements")).json() as Record<string, any>;
    expect(list.announcements).toHaveLength(2);
    expect((await call(TOKENS[OFFICER]!, "POST", "/v1/markaz/announce", { title: "x", scope: "halqahs", halqahIDs: [] })).status).toBe(400);
  });
});

describe("Reporting website sign-in", () => {
  it("lets a computer in once an officer approves its code, for the reports only", async () => {
    const { env, call } = await setup();
    const site = (path: string, body?: unknown) => worker.fetch(new Request(`https://api.example.com${path}`, {
      method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": "8.8.8.8" }, body: JSON.stringify(body ?? {}) }), env);
    const link = await (await site("/v1/reporting/link")).json() as { code: string; pollToken: string };
    expect(link.code).toMatch(/^[A-Z0-9]{4}-[A-Z0-9]{4}$/);
    expect(await (await site("/v1/reporting/link/poll", { pollToken: link.pollToken })).json()).toEqual({ status: "pending" });
    expect((await call(TOKENS[ADMIN]!, "POST", "/v1/markaz/reporting-link/approve", { code: link.code })).status).toBe(403);
    expect((await call(TOKENS[OFFICER]!, "POST", "/v1/markaz/reporting-link/approve", { code: "WRON-GCOD" })).status).toBe(404);
    expect((await call(TOKENS[OFFICER]!, "POST", "/v1/markaz/reporting-link/approve", { code: link.code.toLowerCase().replace("-", " ") })).status).toBe(200);
    const approved = await (await site("/v1/reporting/link/poll", { pollToken: link.pollToken })).json() as { status: string; token: string };
    expect(approved.status).toBe("approved");
    // Once only.
    expect(await (await site("/v1/reporting/link/poll", { pollToken: link.pollToken })).json()).toEqual({ status: "expired" });

    expect((await call(approved.token, "GET", "/v1/markaz/analytics")).status).toBe(200);
    expect((await call(approved.token, "GET", "/v1/groups")).status).toBe(401);
    expect((await call(approved.token, "POST", "/v1/markaz/reporting-link/approve", { code: "AAAA-AAAA" })).status).toBe(403);
    const sessions = await (await call(approved.token, "GET", "/v1/markaz/reporting-sessions")).json() as { sessions: { id: string; current: boolean }[] };
    expect(sessions.sessions).toEqual([expect.objectContaining({ current: true })]);
    expect((await call(TOKENS[OFFICER]!, "DELETE", `/v1/markaz/reporting-sessions/${sessions.sessions[0]!.id}`)).status).toBe(204);
    expect((await call(approved.token, "GET", "/v1/markaz/analytics")).status).toBe(401);
  });
});

describe("Daily digest", () => {
  it("runs once at 12:00 UTC", async () => {
    const { raw, env } = await setup();
    const at = (hour: number) => new Date(Date.UTC(2026, 10, 5, hour, 0));
    await markazDigest(env, at(11));
    expect(raw.prepare("SELECT COUNT(*) AS n FROM app_config WHERE key LIKE 'markazDigest:%'").get()).toEqual({ n: 0 });
    await markazDigest(env, at(12));
    await markazDigest(env, at(12));
    expect(raw.prepare("SELECT COUNT(*) AS n FROM app_config WHERE key LIKE 'markazDigest:%'").get()).toEqual({ n: 1 });
  });
});
