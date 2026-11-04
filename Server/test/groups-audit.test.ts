// Fixes from the October 2026 audit (SCRATCH ios-live.md) to the private
// Halqahs: uploads, who may change an Administrator, sign-out, names, codes
// at a crowded Ijtema, and retired Halqahs.
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { notifyGroup } from "../src/community";
import { mintInvite } from "../src/members";
import { resetAPNSToken, sendTopicPush } from "../src/apns";
import { sqliteD1 } from "./sqlite-d1";

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

async function p256pem(): Promise<string> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey) as ArrayBuffer);
  let binary = ""; der.forEach(byte => binary += String.fromCharCode(byte));
  return `-----BEGIN PRIVATE KEY-----${btoa(binary)}-----END PRIVATE KEY-----`;
}

/** An R2 stand-in that keeps what is put in it. */
function bucket() {
  const stored = new Map<string, number>();
  return {
    stored,
    async put(key: string, value: ReadableStream | ArrayBuffer) {
      stored.set(key, (value instanceof ArrayBuffer ? value : await new Response(value).arrayBuffer()).byteLength);
    },
    async head(key: string) { return stored.has(key) ? { size: stored.get(key), httpMetadata: { contentType: "image/jpeg" } } : null; },
    async delete(key: string) { stored.delete(key); },
  };
}

const A = "a".repeat(32), B = "b".repeat(32), C = "c".repeat(32), D = "d".repeat(32);

/** A USA member (a), a USA Admin (b), the Super admin (c) and a USA
 *  Administrator (d), each signed in. */
async function setup() {
  resetAPNSToken();
  const { db, raw } = sqliteD1();
  const sent: string[] = [];
  vi.stubGlobal("fetch", async (url: string) => { sent.push(String(url)); return new Response("", { status: 200 }); });
  const now = new Date().toISOString();
  const later = new Date(Date.now() + 86_400_000).toISOString();
  const people = [
    { id: A, token: "1".repeat(64), role: "member", email: "member@example.com", name: "Member" as string | null },
    { id: B, token: "2".repeat(64), role: "admin", email: "admin@example.com", name: "Admin" },
    { id: C, token: "3".repeat(64), role: null, email: "owner@example.com", name: "Owner" },
    { id: D, token: "4".repeat(64), role: "administrator", email: "senior@example.com", name: "Senior" },
  ];
  for (const person of people) {
    raw.prepare("INSERT INTO members(id,apple_subject,display_name,email,created_at,last_seen_at) VALUES(?,?,?,?,?,?)")
      .run(person.id, `apple:${person.id}`, person.name, person.email, now, now);
    raw.prepare("INSERT INTO member_sessions(token_hash,member_id,created_at,expires_at,last_seen_at) VALUES(?,?,?,?,?)")
      .run(await sha256(person.token), person.id, now, later, now);
    if (person.role) {
      raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('usa',?,?,'test',?)")
        .run(person.id, now, person.role);
    }
  }
  const media = bucket();
  const env = {
    DB: db, MEDIA: media, APNS_TOPIC: "us.naqshbaniaowaisiah", PUBLIC_BASE_URL: "https://api.example.com",
    SUPER_ADMIN_EMAILS: "owner@example.com", MEDIA_URL_SECRET: "s",
    APNS_KEY_ID: "KEY", APNS_TEAM_ID: "TEAM", APNS_PRIVATE_KEY: await p256pem(),
  } as unknown as Env;
  const call = (token: string | null, method: string, path: string, body?: unknown, headers: Record<string, string> = {}) =>
    worker.fetch(new Request(`https://api.example.com${path}`, {
      method,
      headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body !== undefined ? { "content-type": "application/json" } : {}), ...headers },
      body: body !== undefined ? JSON.stringify(body) : undefined,
    }), env);
  const roleOf = (id: string) =>
    (raw.prepare("SELECT role FROM member_group_members WHERE group_id='usa' AND member_id=?").get(id) as { role: string } | undefined)?.role;
  const apns = () => sent.filter(url => url.includes("push.apple.com"));
  return { env, raw, media, call, roleOf, apns, member: "1".repeat(64), admin: "2".repeat(64), owner: "3".repeat(64), senior: "4".repeat(64) };
}

afterEach(() => vi.unstubAllGlobals());

describe("LIVE-002: files larger than 256 KB reach the upload routes", () => {
  const upload = (env: Env, token: string, path: string, type: string, bytes: number, length = String(bytes)) =>
    worker.fetch(new Request(`https://api.example.com${path}`, {
      method: "POST", body: new Uint8Array(bytes) as unknown as BodyInit,
      headers: { authorization: `Bearer ${token}`, "content-type": type, "content-length": length },
    }), env);

  it("stores a 600 KB recording, post picture and Today picture", async () => {
    const { env, media, admin, owner } = await setup();
    expect((await upload(env, admin, "/v1/groups/usa/recordings?title=Friday", "audio/mpeg", 600_000)).status).toBe(201);
    expect((await upload(env, admin, "/v1/groups/usa/media", "image/jpeg", 600_000)).status).toBe(201);
    expect((await upload(env, owner, "/v1/daily-media/manage?slot=ayah", "image/jpeg", 600_000)).status).toBe(201);
    expect([...media.stored.values()]).toEqual([600_000, 600_000, 600_000]);
  });

  it("still refuses a large body anywhere else, and each upload keeps its own limit", async () => {
    const { env, call, admin, owner } = await setup();
    const big = await call(admin, "POST", "/v1/groups/usa/posts", { title: "x", body: "y".repeat(600_000) },
      { "content-length": "600030" });
    expect(big.status).toBe(413);
    expect((await upload(env, admin, "/v1/groups/usa/recordings", "audio/mpeg", 16, String(100 * 1024 * 1024))).status).toBe(413);
    expect((await upload(env, owner, "/v1/daily-media/manage?slot=ayah", "image/jpeg", 16, String(13 * 1024 * 1024))).status).toBe(413);
  });
});

describe("LIVE-003: an Admin cannot demote or replace an Administrator by adding them", () => {
  it("refuses an Admin who adds an Administrator's email as a member, and keeps the role", async () => {
    const { call, roleOf, admin } = await setup();
    const response = await call(admin, "POST", "/v1/groups/usa/people", { email: "Senior@Example.com", role: "member" });
    expect(response.status).toBe(403);
    expect(roleOf(D)).toBe("administrator");
    // So the Administrator cannot be removed afterwards either.
    expect((await call(admin, "DELETE", `/v1/groups/usa/people/${D}`)).status).toBe(403);
  });

  it("keeps an Administrator's invitation from being overwritten by an Admin", async () => {
    const { raw, call, admin, senior } = await setup();
    expect((await call(senior, "POST", "/v1/groups/usa/people", { email: "next@example.com", role: "administrator" })).status).toBe(201);
    expect((await call(admin, "POST", "/v1/groups/usa/people", { email: "next@example.com", role: "member" })).status).toBe(403);
    expect(raw.prepare("SELECT role FROM member_group_grants WHERE email='next@example.com'").get()).toEqual({ role: "administrator" });
  });

  it("still lets an Administrator or the Super admin change an Administrator, and anyone add the rest", async () => {
    const { call, roleOf, admin, senior, owner } = await setup();
    expect((await call(admin, "POST", "/v1/groups/usa/people", { email: "member@example.com", role: "admin" })).status).toBe(201);
    expect(roleOf(A)).toBe("admin");
    expect(((await (await call(admin, "POST", "/v1/groups/usa/people", { email: "new@example.com" })).json()) as { result: string }).result)
      .toBe("pending");
    expect((await call(senior, "POST", "/v1/groups/usa/people", { email: "admin@example.com", role: "administrator" })).status).toBe(201);
    expect(roleOf(B)).toBe("administrator");
    expect((await call(owner, "POST", "/v1/groups/usa/people", { memberID: D, role: "member" })).status).toBe(201);
    expect(roleOf(D)).toBe("member");
    // Nobody changes their own place, the Super admin included.
    expect((await call(owner, "POST", "/v1/groups/usa/people", { memberID: C, role: "member" })).status).toBe(201);
    expect((await call(owner, "POST", "/v1/groups/usa/people", { memberID: C, role: "admin" })).status).toBe(400);
  });
});

const PHONE = "22222222-2222-4222-8222-222222222222";

/** The phone's own notification registration, as the app makes it for
 *  Halqah notices alone: no official topics. */
const registerPhone = (env: Env, topics: string[] = []) =>
  worker.fetch(new Request("https://api.example.com/v1/devices", {
    method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": "5.5.5.5" },
    body: JSON.stringify({ installationID: PHONE, apnsToken: "f".repeat(64), locale: "en", timeZone: "UTC", topics, environment: "production", appVersion: "1.12" }),
  }), env);

describe("LIVE-005: a phone registered for Halqah notices only", () => {
  it("gets its Halqah's notices and none of the official alerts", async () => {
    const { env, call, apns, member } = await setup();
    expect((await registerPhone(env)).status).toBe(201);
    expect((await call(member, "POST", "/v1/members/devices", { installationID: PHONE })).status).toBe(204);
    expect(await notifyGroup(env, "usa", "post:1", "Friday", "After Isha", "darulirfan://groups/usa")).toBe(1);
    expect(apns()).toHaveLength(1);
    expect(await sendTopicPush(env, "live:1", "liveZikr", "Daily Zikr has started", "Join", "darulirfan://live/official-live")).toBe(0);
    expect(apns()).toHaveLength(1);
  });
});

describe("LIVE-006: signing out, or handing the phone on, stops the notices on it", () => {
  it("ends this phone's session and its link to the member's notices, and nothing else", async () => {
    const { env, raw, call, apns, member } = await setup();
    await registerPhone(env);
    await call(member, "POST", "/v1/members/devices", { installationID: PHONE });
    // The same member on another phone stays signed in.
    const other = "9".repeat(64);
    raw.prepare("INSERT INTO member_sessions(token_hash,member_id,created_at,expires_at,last_seen_at) VALUES(?,?,?,?,?)")
      .run(await sha256(other), A, new Date().toISOString(), new Date(Date.now() + 86_400_000).toISOString(), new Date().toISOString());
    expect((await call(member, "POST", "/v1/members/signout", { installationID: PHONE.toLowerCase() })).status).toBe(204);
    expect((await call(member, "GET", "/v1/members/me")).status).toBe(401);
    expect((await call(other, "GET", "/v1/members/me")).status).toBe(200);
    expect(await notifyGroup(env, "usa", "post:2", "Friday", "After Isha", "darulirfan://groups/usa")).toBe(0);
    expect(apns()).toHaveLength(0);
  });

  it("links a phone to the member signed in on it last", async () => {
    const { env, raw, call, member, admin } = await setup();
    await registerPhone(env);
    await call(member, "POST", "/v1/members/devices", { installationID: PHONE });
    await call(admin, "POST", "/v1/members/devices", { installationID: PHONE });
    expect(raw.prepare("SELECT member_id FROM member_devices").all()).toEqual([{ member_id: B }]);
  });
});

describe("LIVE-007: a member's own name", () => {
  it("lets the member set their name, and refuses an empty one", async () => {
    const { call, member } = await setup();
    const renamed = await call(member, "PUT", "/v1/members/me", { displayName: "  Imran   Ali " });
    expect(renamed.status).toBe(200);
    expect(await renamed.json()).toEqual({ memberID: A, role: "member", displayName: "Imran Ali", isVisitor: false });
    expect(((await (await call(member, "GET", "/v1/members/me")).json()) as { displayName: string }).displayName).toBe("Imran Ali");
    const empty = await call(member, "PUT", "/v1/members/me", { displayName: "   " });
    expect(empty.status).toBe(400);
    expect(await empty.json()).toEqual({ error: "Enter your name." });
  });

  it("takes the name given with a second code only when none is known yet", async () => {
    const { env, raw, call, member } = await setup();
    raw.prepare("UPDATE members SET display_name=NULL WHERE id=?").run(A);
    const first = await mintInvite(env, "t", "canada", 7, null, null);
    expect((await call(member, "POST", "/v1/members/invite", { code: first.code, displayName: "Imran" })).status).toBe(201);
    expect(raw.prepare("SELECT display_name FROM members WHERE id=?").get(A)).toEqual({ display_name: "Imran" });
    const second = await mintInvite(env, "t", "darul-irfan", 7, null, null);
    await call(member, "POST", "/v1/members/invite", { code: second.code, displayName: "Someone else" });
    expect(raw.prepare("SELECT display_name FROM members WHERE id=?").get(A)).toEqual({ display_name: "Imran" });
  });
});

describe("LIVE-026: codes at a crowded Ijtema", () => {
  const redeem = (env: Env, code: string, ip: string) => worker.fetch(new Request("https://api.example.com/v1/members/invite", {
    method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": ip }, body: JSON.stringify({ code }),
  }), env);

  it("admits everyone with a good code behind one address, and stops a guesser after ten wrong codes", async () => {
    const { env } = await setup();
    for (let n = 0; n < 12; n += 1) {
      const { code } = await mintInvite(env, "t", "usa", 7, null, null);
      expect((await redeem(env, code, "9.9.9.9")).status).toBe(201);
    }
    for (let n = 0; n < 10; n += 1) expect((await redeem(env, "ZZZZZ-ZZZZZ", "8.8.8.8")).status).toBe(403);
    expect((await redeem(env, "ZZZZZ-ZZZZZ", "8.8.8.8")).status).toBe(429);
    const { code } = await mintInvite(env, "t", "usa", 7, null, null);
    expect((await redeem(env, code, "8.8.8.8")).status).toBe(429);
    expect((await redeem(env, code, "7.7.7.7")).status).toBe(201);
  });
});

describe("LIVE-032: a retired Halqah", () => {
  it("is gone for its members too, not only from their list", async () => {
    const { raw, call, member, owner } = await setup();
    expect((await call(member, "GET", "/v1/groups/usa")).status).toBe(200);
    raw.prepare("UPDATE member_groups SET is_active=0 WHERE id='usa'").run();
    expect((await call(member, "GET", "/v1/groups/usa")).status).toBe(404);
    expect((await call(member, "GET", "/v1/groups/usa/posts")).status).toBe(404);
    expect((await call(owner, "GET", "/v1/groups/usa")).status).toBe(404);
  });
});


describe("post creation retries", () => {
  const path = "/v1/groups/usa/posts";
  const body = { requestID: "91ba7dfe-47d4-4dfe-b813-96b7573ab357", title: "Retry-safe post", body: "Original", publish: true };

  it("converges concurrent retries on one post and one notification lookup", async () => {
    const { call, raw, env, admin } = await setup();
    const prepare = env.DB.prepare.bind(env.DB);
    let lookups = 0;
    vi.spyOn(env.DB, "prepare").mockImplementation(sql => {
      if (sql.includes("SELECT DISTINCT d.installation_id")) lookups++;
      return prepare(sql);
    });
    const responses = await Promise.all(Array.from({ length: 8 }, () => call(admin, "POST", path, body)));
    expect(responses.map(r => r.status)).toEqual(Array(8).fill(201));
    const results = await Promise.all(responses.map(r => r.json() as Promise<{ id: string }>));
    expect(new Set(results.map(r => r.id)).size).toBe(1);
    expect(raw.prepare("SELECT count(*) AS n FROM member_group_posts WHERE source='admin'").get()).toEqual({ n: 1 });
    expect(lookups).toBe(1);
  });

  it.each([{ title: "Changed" }, { body: "Changed" }, { publish: false }, { youtubeVideoID: "abcdefghijk" },
    { linkURL: "https://example.com/changed" }])("rejects changed details without creating another post: %j", async change => {
    const { call, raw, admin } = await setup();
    expect((await call(admin, "POST", path, body)).status).toBe(201);
    const conflict = await call(admin, "POST", path, { ...body, ...change });
    expect(conflict.status).toBe(409);
    expect(await conflict.json()).toMatchObject({ code: "post_request_conflict" });
    expect(raw.prepare("SELECT count(*) AS n FROM member_group_posts WHERE source='admin'").get()).toEqual({ n: 1 });
  });

  it("reuses the same attachment keys and rejects changed attachment order on retry", async () => {
    const { call, raw, media, admin } = await setup();
    const firstKey = "posts/usa/11111111-1111-4111-8111-111111111111.jpg";
    const secondKey = "posts/usa/22222222-2222-4222-8222-222222222222.jpg";
    media.stored.set(firstKey, 123);
    media.stored.set(secondKey, 456);
    const input = { ...body, media: [firstKey, secondKey] };
    const first = await call(admin, "POST", path, input);
    expect(first.status).toBe(201);
    const retry = await call(admin, "POST", path, input);
    expect(retry.status).toBe(201);
    expect(await retry.json()).toEqual(await first.json());
    expect((await call(admin, "POST", path, { ...input, media: [secondKey, firstKey] })).status).toBe(409);
    expect(raw.prepare("SELECT count(*) AS n FROM member_group_posts WHERE source='admin'").get()).toEqual({ n: 1 });
  });

  it("does not restore hidden posts and rechecks author permissions", async () => {
    const { call, raw, admin, senior, member } = await setup();
    const first = await call(admin, "POST", path, body);
    const { id } = await first.json() as { id: string };
    expect((await call(admin, "DELETE", `${path}/${id}`)).status).toBe(204);
    expect((await call(admin, "POST", path, body)).status).toBe(201);
    expect(raw.prepare("SELECT is_hidden FROM member_group_posts WHERE id=?").get(id)).toEqual({ is_hidden: 1 });
    expect((await call(senior, "POST", path, body)).status).toBe(201);
    expect((await call(member, "POST", path, body)).status).toBe(403);
    raw.prepare("UPDATE member_group_members SET role='member' WHERE member_id=?").run(B);
    expect((await call(admin, "POST", path, body)).status).toBe(403);
  });

  it("validates request identities and retains legacy clients", async () => {
    const { call, admin } = await setup();
    for (const requestID of ["", "bad", null, 123]) {
      expect((await call(admin, "POST", path, { ...body, requestID })).status).toBe(400);
    }
    const { requestID, ...legacy } = body;
    expect((await call(admin, "POST", path, legacy)).status).toBe(201);
  });
});

describe("post publication push failures", () => {
  it.each([false, true])("acknowledges the committed post when push lookup fails (draft first: %s)", async draftFirst => {
    const { call, raw, env, admin } = await setup();
    const prepare = env.DB.prepare.bind(env.DB);
    let lookups = 0;
    vi.spyOn(env.DB, "prepare").mockImplementation(sql => {
      if (sql.includes("SELECT DISTINCT d.installation_id")) {
        lookups++;
        throw new Error("Push lookup unavailable");
      }
      return prepare(sql);
    });
    const created = await call(admin, "POST", "/v1/groups/usa/posts", {
      title: "Audit announcement", body: "Preserve this post", publish: !draftFirst,
    });
    expect(created.status).toBe(201);
    const { id } = await created.json() as { id: string };
    if (draftFirst) {
      expect(lookups).toBe(0);
      const published = await call(admin, "POST", `/v1/groups/usa/posts/${id}/publish`, {
        title: "Audit announcement", body: "Preserve this post",
      });
      expect(published.status).toBe(200);
    }
    expect(lookups).toBe(1);
    expect(raw.prepare("SELECT title,body,status FROM member_group_posts WHERE id=?").get(id)).toEqual({
      title: "Audit announcement", body: "Preserve this post", status: "published",
    });
  });
});

describe("meeting creation retries", () => {
  const path = "/v1/groups/usa/meetings";
  const body = { requestID: "91ba7dfe-47d4-4dfe-b813-96b7573ab357", title: "Weekly meeting",
    startsAt: "2030-11-01T15:00:00.000Z", durationMinutes: 60 };

  it("acknowledges a committed request whose first response was lost without creating another meeting", async () => {
    const { call, raw, admin } = await setup();
    const first = await call(admin, "POST", path, body);
    expect(first.status).toBe(201);
    const retry = await call(admin, "POST", path, body);
    expect(retry.status).toBe(201);
    expect(await retry.json()).toEqual(await first.json());
    expect(raw.prepare("SELECT count(*) AS n FROM group_meetings").get()).toEqual({ n: 1 });
  });

  it("atomically converges concurrent identical submissions on one meeting", async () => {
    const { call, raw, admin } = await setup();
    const responses = await Promise.all(Array.from({ length: 8 }, () => call(admin, "POST", path, body)));
    expect(responses.map(r => r.status)).toEqual(Array(8).fill(201));
    const results = await Promise.all(responses.map(r => r.json() as Promise<{ id: string }>));
    expect(new Set(results.map(r => r.id)).size).toBe(1);
    expect(raw.prepare("SELECT count(*) AS n FROM group_meetings").get()).toEqual({ n: 1 });
  });

  it.each([{ title: "Changed" }, { durationMinutes: 90 }, { startsAt: "2030-11-02T15:00:00.000Z" }])(
    "refuses changed details under a committed request ID: %j", async change => {
      const { call, raw, admin } = await setup();
      expect((await call(admin, "POST", path, body)).status).toBe(201);
      const conflict = await call(admin, "POST", path, { ...body, ...change });
      expect(conflict.status).toBe(409);
      expect(await conflict.json()).toMatchObject({ code: "meeting_request_conflict" });
      expect(raw.prepare("SELECT title,duration_minutes,starts_at FROM group_meetings").all()).toEqual([
        { title: body.title, duration_minutes: body.durationMinutes, starts_at: body.startsAt }]);
    });

  it("does not resurrect a cancelled meeting when its original creation is replayed", async () => {
    const { call, raw, admin } = await setup();
    const { id } = await (await call(admin, "POST", path, body)).json() as { id: string };
    expect((await call(admin, "DELETE", `${path}/${id}`)).status).toBe(204);
    expect((await call(admin, "POST", path, body)).status).toBe(201);
    expect(raw.prepare("SELECT is_cancelled FROM group_meetings WHERE id=?").get(id)).toEqual({ is_cancelled: 1 });
  });

  it("keeps request IDs separate between authors and enforces permissions on every replay", async () => {
    const { call, raw, admin, senior, member } = await setup();
    expect((await call(admin, "POST", path, body)).status).toBe(201);
    expect((await call(senior, "POST", path, body)).status).toBe(201);
    expect((await call(member, "POST", path, body)).status).toBe(403);
    raw.prepare("UPDATE member_group_members SET role='member' WHERE member_id=?").run(B);
    expect((await call(admin, "POST", path, body)).status).toBe(403);
    expect(raw.prepare("SELECT count(*) AS n FROM group_meetings").get()).toEqual({ n: 2 });
  });

  it("acknowledges creation even when push device lookup fails, and never repeats it on replay", async () => {
    const { call, raw, env, admin } = await setup();
    const prepare = env.DB.prepare.bind(env.DB);
    let lookups = 0;
    vi.spyOn(env.DB, "prepare").mockImplementation(sql => {
      if (sql.includes("SELECT DISTINCT d.installation_id")) {
        lookups++;
        throw new Error("Push lookup unavailable");
      }
      return prepare(sql);
    });
    expect((await call(admin, "POST", path, body)).status).toBe(201);
    expect((await call(admin, "POST", path, body)).status).toBe(201);
    expect(lookups).toBe(1);
    expect(raw.prepare("SELECT count(*) AS n FROM group_meetings").get()).toEqual({ n: 1 });
  });

  it("validates IDs but still supports clients that omit them", async () => {
    const { call, raw, admin } = await setup();
    for (const requestID of ["", "bad", null, 123]) {
      expect((await call(admin, "POST", path, { ...body, requestID })).status).toBe(400);
    }
    const { requestID, ...legacy } = body;
    expect((await call(admin, "POST", path, legacy)).status).toBe(201);
    expect((await call(admin, "POST", path, legacy)).status).toBe(201);
    expect(raw.prepare("SELECT count(*) AS n FROM group_meetings").get()).toEqual({ n: 2 });
  });
});
