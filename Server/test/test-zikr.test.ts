// A test Zikr (owner 2026-11-04): an admin starts it to try the session and
// the stage; members neither see it nor are notified. Admins also take dua
// requests off the list.
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { resetAPNSToken } from "../src/apns";
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

const PHONE = "44444444-4444-4444-8444-444444444444";
const ADMIN = "a".repeat(32), MEMBER = "b".repeat(32);

async function setup() {
  resetAPNSToken();
  const { db, raw } = sqliteD1();
  const pushes: string[] = [];
  vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
    const url = String(input instanceof Request ? input.url : input);
    if (url.includes("push.apple.com")) pushes.push(url);
    return new Response("", { status: 200 });
  });
  const now = new Date().toISOString(), later = new Date(Date.now() + 86_400_000).toISOString();
  for (const [id, token, role] of [[ADMIN, "1".repeat(64), "admin"], [MEMBER, "2".repeat(64), "member"]] as const) {
    raw.prepare("INSERT INTO members(id,apple_subject,display_name,email,created_at,last_seen_at) VALUES(?,?,?,?,?,?)")
      .run(id, `apple:${id}`, "Member", null, now, now);
    raw.prepare("INSERT INTO member_sessions(token_hash,member_id,created_at,expires_at,last_seen_at) VALUES(?,?,?,?,?)")
      .run(await sha256(token), id, now, later, now);
    raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('usa',?,?,'test',?)").run(id, now, role);
  }
  const env = {
    DB: db, APNS_TOPIC: "us.naqshbaniaowaisiah", PUBLIC_BASE_URL: "https://api.example.com",
    APNS_KEY_ID: "KEY", APNS_TEAM_ID: "TEAM", APNS_PRIVATE_KEY: await p256pem(),
  } as unknown as Env;
  const call = (token: string, method: string, path: string, body?: unknown) =>
    worker.fetch(new Request(`https://api.example.com${path}`, {
      method, headers: { authorization: `Bearer ${token}`, "cf-connecting-ip": "7.7.7.7", ...(body ? { "content-type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    }), env);
  // The member's phone, registered for Halqah notices.
  await worker.fetch(new Request("https://api.example.com/v1/devices", {
    method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": "6.6.6.6" },
    body: JSON.stringify({ installationID: PHONE, apnsToken: "e".repeat(64), locale: "en", timeZone: "UTC", topics: [],
      environment: "production", appVersion: "1.12", keepTopics: true }),
  }), env);
  await call("2".repeat(64), "POST", "/v1/members/devices", { installationID: PHONE });
  return { raw, call, pushes, admin: "1".repeat(64), member: "2".repeat(64) };
}

afterEach(() => vi.unstubAllGlobals());

describe("test Zikr", () => {
  it("notifies nobody and is live for the Halqah's admins only", async () => {
    const { raw, call, pushes, admin, member } = await setup();
    const started = await call(admin, "POST", "/v1/groups/usa/live", { state: "live", kind: "zikr", videoID: "abcdefghijk", test: true });
    expect(started.status).toBe(200);
    expect(await started.json()).toMatchObject({ isTest: true });
    expect(pushes).toEqual([]);
    expect((await (await call(member, "GET", "/v1/groups/usa")).json() as any).live).toBeUndefined();
    expect((await (await call(admin, "GET", "/v1/groups/usa")).json() as any).live).toMatchObject({ kind: "zikr", isTest: true });
    const list = await (await call(member, "GET", "/v1/groups")).json() as any;
    expect(list.groups[0]).toMatchObject({ id: "usa", isLive: false });
    expect((await call(admin, "POST", "/v1/groups/usa/live", { state: "offline" })).status).toBe(200);
    expect(raw.prepare("SELECT is_test FROM group_live_history").get()).toEqual({ is_test: 1 });
    expect(raw.prepare("SELECT is_test FROM group_live").get()).toEqual({ is_test: 0 });
  });

  it("a real Zikr still notifies the members", async () => {
    const { call, pushes, admin } = await setup();
    expect((await call(admin, "POST", "/v1/groups/usa/live", { state: "live", kind: "zikr", videoID: "abcdefghijk" })).status).toBe(200);
    expect(pushes.length).toBeGreaterThan(0);
  });
});

describe("removing a dua request", () => {
  it("an admin takes it off the list; a member cannot", async () => {
    const { call, admin, member } = await setup();
    const sent = await (await call(member, "POST", "/v1/groups/usa/duas", { text: "Please pray for my mother" })).json() as any;
    expect((await call(member, "DELETE", `/v1/groups/usa/duas/${sent.id}`)).status).toBe(403);
    expect((await call(admin, "DELETE", `/v1/groups/usa/duas/${sent.id}`)).status).toBe(204);
    expect((await (await call(admin, "GET", "/v1/groups/usa/duas")).json() as any).requests).toEqual([]);
    expect((await (await call(admin, "GET", "/v1/groups/usa")).json() as any).unreadDuaRequests).toBe(0);
  });
});
