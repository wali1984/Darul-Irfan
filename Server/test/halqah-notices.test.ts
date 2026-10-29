// Halqah notices on a phone whose official alerts are off (audit LIVE-005):
// the app registers the phone for them without touching its official topics,
// and the member can turn them off on that phone without signing out.
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { notifyGroup } from "../src/community";
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

const PHONE = "33333333-3333-4333-8333-333333333333";
const MEMBER = "a".repeat(32), OTHER = "b".repeat(32);

async function setup() {
  resetAPNSToken();
  const { db, raw } = sqliteD1();
  vi.stubGlobal("fetch", async () => new Response("", { status: 200 }));
  const now = new Date().toISOString();
  const later = new Date(Date.now() + 86_400_000).toISOString();
  for (const [id, token] of [[MEMBER, "1".repeat(64)], [OTHER, "2".repeat(64)]] as const) {
    raw.prepare("INSERT INTO members(id,apple_subject,display_name,email,created_at,last_seen_at) VALUES(?,?,?,?,?,?)")
      .run(id, `apple:${id}`, "Member", null, now, now);
    raw.prepare("INSERT INTO member_sessions(token_hash,member_id,created_at,expires_at,last_seen_at) VALUES(?,?,?,?,?)")
      .run(await sha256(token), id, now, later, now);
    raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('usa',?,?,'test','member')").run(id, now);
  }
  const env = {
    DB: db, APNS_TOPIC: "us.naqshbaniaowaisiah", PUBLIC_BASE_URL: "https://api.example.com",
    APNS_KEY_ID: "KEY", APNS_TEAM_ID: "TEAM", APNS_PRIVATE_KEY: await p256pem(),
  } as unknown as Env;
  const register = (topics: string[], token: string, keepTopics?: boolean) =>
    worker.fetch(new Request("https://api.example.com/v1/devices", {
      method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": "6.6.6.6" },
      body: JSON.stringify({ installationID: PHONE, apnsToken: token, locale: "en", timeZone: "UTC", topics,
        environment: "production", appVersion: "1.12", ...(keepTopics === undefined ? {} : { keepTopics }) }),
    }), env);
  const call = (token: string, method: string, path: string, body?: unknown) =>
    worker.fetch(new Request(`https://api.example.com${path}`, {
      method, headers: { authorization: `Bearer ${token}`, ...(body ? { "content-type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    }), env);
  const device = () => raw.prepare("SELECT apns_token,topics_json FROM devices WHERE installation_id=?").get(PHONE) as
    { apns_token: string; topics_json: string } | undefined;
  return { env, raw, register, call, device, member: "1".repeat(64), other: "2".repeat(64) };
}

afterEach(() => vi.unstubAllGlobals());

describe("registering a phone for Halqah notices", () => {
  it("keeps the official alert topics the phone already has", async () => {
    const { register, device } = await setup();
    expect((await register(["liveZikr", "announcements"], "a".repeat(64))).status).toBe(201);
    expect((await register([], "b".repeat(64), true)).status).toBe(201);
    expect(device()).toEqual({ apns_token: "b".repeat(64), topics_json: JSON.stringify(["liveZikr", "announcements"]) });
  });

  it("registers a new phone with no official topic", async () => {
    const { register, device } = await setup();
    expect((await register([], "c".repeat(64), true)).status).toBe(201);
    expect(device()).toEqual({ apns_token: "c".repeat(64), topics_json: "[]" });
  });

  it("still lets the official alerts be switched off by a plain registration", async () => {
    const { register, device } = await setup();
    await register(["liveZikr"], "d".repeat(64));
    await register([], "d".repeat(64));
    expect(device()?.topics_json).toBe("[]");
  });
});

describe("turning Halqah notices off on a phone", () => {
  it("stops the member's notices there, keeps them signed in and keeps the phone registered", async () => {
    const { env, register, call, device, member } = await setup();
    await register(["liveZikr"], "e".repeat(64));
    await call(member, "POST", "/v1/members/devices", { installationID: PHONE });
    expect(await notifyGroup(env, "usa", "post:1", "Friday", "After Isha", "darulirfan://groups/usa")).toBe(1);
    expect((await call(member, "DELETE", `/v1/members/devices/${PHONE.toLowerCase()}`)).status).toBe(204);
    expect(await notifyGroup(env, "usa", "post:2", "Friday", "After Isha", "darulirfan://groups/usa")).toBe(0);
    expect((await call(member, "GET", "/v1/members/me")).status).toBe(200);
    expect(device()?.topics_json).toBe(JSON.stringify(["liveZikr"]));
  });

  it("removes only the caller's own link", async () => {
    const { raw, register, call, member, other } = await setup();
    await register([], "f".repeat(64));
    await call(member, "POST", "/v1/members/devices", { installationID: PHONE });
    expect((await call(other, "DELETE", `/v1/members/devices/${PHONE}`)).status).toBe(204);
    expect(raw.prepare("SELECT member_id FROM member_devices").all()).toEqual([{ member_id: MEMBER }]);
  });
});
