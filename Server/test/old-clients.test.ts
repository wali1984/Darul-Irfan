// The apps and websites already in people's hands send no age declaration and
// no terms version. The community terms are not asked for, so every call they
// make is answered as it always was: nothing is refused for a missing
// declaration, and nothing about one is stored.
import { afterEach, describe, expect, it, vi } from "vitest";
import { exportJWK, generateKeyPair, SignJWT, type JWK } from "jose";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { GOOGLE_CERTS_URL, resetGoogleKeys } from "../src/google";
import { sqliteD1 } from "./sqlite-d1";

const WEB_CLIENT = "123456789012-web.apps.googleusercontent.com";
const BUNDLE = "us.naqshbaniaowaisiah";
const RELAY = "relay-secret";

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

async function signer(kid: string): Promise<{ privateKey: CryptoKey; jwk: JWK }> {
  const { publicKey, privateKey } = await generateKeyPair("RS256", { extractable: true });
  return { privateKey, jwk: { ...await exportJWK(publicKey), kid, alg: "RS256", use: "sig" } };
}

type Answer = { status: number; body: any; text: string };

async function setup() {
  const { db, raw } = sqliteD1();
  const google = await signer("google-key-1"), apple = await signer("apple-key-1");
  vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
    const url = String(input instanceof Request ? input.url : input);
    if (url === GOOGLE_CERTS_URL) return Response.json({ keys: [google.jwk] }, { headers: { "cache-control": "public, max-age=3600" } });
    if (url === "https://appleid.apple.com/auth/keys") return Response.json({ keys: [apple.jwk] });
    return new Response("{}", { status: 200 });
  });
  resetGoogleKeys();
  const now = new Date().toISOString();
  raw.prepare("INSERT INTO member_groups(id,name,updated_at) VALUES('our-sheikh','Our Sheikh',?)").run(now);
  // A Zikr is live in the USA Halqah, started by its admin.
  raw.prepare(`INSERT INTO group_live(group_id,state,kind,title,started_at,updated_at,session_id,queue_json)
    VALUES('usa','live','zikr','Thursday Zikr',?,?,'session-1','[]')`).run(now, now);
  const invite = async (code: string, role: string | null) => raw.prepare(
    "INSERT INTO member_invites(code_hash,group_id,created_by,created_at,expires_at,grants_role) VALUES(?,?,?,?,?,?)")
    .run(await sha256(code), "usa", "test", now, new Date(Date.now() + 86_400_000).toISOString(), role);
  await invite("ACDEFGHJKM", null);
  await invite("NPQRSTUVWX", "admin");
  const env = {
    DB: db, APNS_TOPIC: BUNDLE, PUBLIC_BASE_URL: "https://api.example.com", GOOGLE_CLIENT_IDS: WEB_CLIENT, RELAY_TOKEN: RELAY,
  } as unknown as Env;
  const answers: Answer[] = [];
  /** One request as a client sends it; every answer is kept to be read through at the end. */
  const call = async (method: string, path: string, body?: unknown, token?: string): Promise<Answer> => {
    const response = await worker.fetch(new Request(`https://api.example.com${path}`, {
      method,
      headers: {
        "cf-connecting-ip": "9.9.9.9", ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...(body !== undefined ? { "content-type": "application/json" } : {}),
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
    }), env);
    const text = await response.text();
    let parsed: unknown = null;
    try { parsed = text ? JSON.parse(text) : null; } catch { /* not JSON */ }
    const answer = { status: response.status, body: parsed as any, text };
    answers.push(answer);
    return answer;
  };
  const seconds = Math.floor(Date.now() / 1000);
  const googleToken = () => new SignJWT({ email: "member@example.com", email_verified: true, azp: "android" })
    .setProtectedHeader({ alg: "RS256", kid: "google-key-1", typ: "JWT" }).setIssuer("https://accounts.google.com")
    .setAudience(WEB_CLIENT).setSubject("104935628104935628104").setIssuedAt(seconds).setExpirationTime(seconds + 3_600).sign(google.privateKey);
  const appleToken = () => new SignJWT({ email: "iphone@example.com" })
    .setProtectedHeader({ alg: "RS256", kid: "apple-key-1" }).setIssuer("https://appleid.apple.com")
    .setAudience(BUNDLE).setSubject("001234.apple-subject.0101").setIssuedAt(seconds).setExpirationTime(seconds + 600).sign(apple.privateKey);
  const consents = () => (raw.prepare("SELECT COUNT(*) AS n FROM member_community_consent").get() as { n: number }).n;
  return { raw, call, answers, googleToken, appleToken, consents };
}

const SESSION_KEYS = ["expiresAt", "memberID", "token"];
const VISITOR = { name: "Visitor", city: "Lahore", countryCode: "pk", guestSecret: "b".repeat(64) };
const WEB_VISITOR = { name: "Ahmed", city: "Boston", countryCode: "us", guestSecret: "c".repeat(64) };
const INSTALLATION = "0F0E0D0C-0B0A-4908-8706-050403020100";

afterEach(() => { vi.unstubAllGlobals(); });

describe("clients that send no age declaration and no terms version", () => {
  it("sign in, join, write and listen exactly as before, and are never asked for the community terms", async () => {
    const { raw, call, answers, googleToken, appleToken, consents } = await setup();

    // Sign-in: Google (Android), Apple (iPhone), an invitation code.
    const google = await call("POST", "/v1/members/session", { provider: "google", idToken: await googleToken() });
    expect(google.status).toBe(201);
    expect(Object.keys(google.body).sort()).toEqual(SESSION_KEYS);
    const apple = await call("POST", "/v1/members/session", { identityToken: await appleToken(), displayName: "Ali" });
    expect(apple.status).toBe(201);
    expect(Object.keys(apple.body).sort()).toEqual(SESSION_KEYS);
    expect((await call("POST", "/v1/members/session", { identityToken: "not.a.jwt" })).status).toBe(401);
    const invited = await call("POST", "/v1/members/invite", { code: "acdef-ghjkm", displayName: "Imran" });
    expect(invited.status).toBe(201);
    expect(Object.keys(invited.body).sort()).toEqual(["expiresAt", "groupID", "memberID", "token"]);
    const admin = await call("POST", "/v1/members/invite", { code: "NPQRSTUVWX", displayName: "Ameer" });
    expect(admin.status).toBe(201);
    expect((await call("POST", "/v1/members/invite", { code: "ZZZZZZZZZZ" })).status).toBe(403);
    expect(answers.at(-1)!.body).toEqual({ error: "That invitation code is not valid, or has already been used." });

    // Our Sheikh: a visitor gets a session; a signed-in member is admitted on their own account.
    const visitor = await call("POST", "/v1/our-sheikh/join", VISITOR);
    expect(visitor.status).toBe(201);
    expect(Object.keys(visitor.body).sort()).toEqual(SESSION_KEYS);
    const admitted = await call("POST", "/v1/our-sheikh/join", { name: "Ali", city: "Leeds", countryCode: "GB" }, apple.body.token);
    expect(admitted.status).toBe(200);
    expect(admitted.body).toEqual({ memberID: apple.body.memberID, groupID: "our-sheikh" });

    // Reading while signed in.
    const member: string = invited.body.token;
    expect((await call("GET", "/v1/members/me", undefined, member)).status).toBe(200);
    expect((await call("GET", "/v1/groups", undefined, member)).body.groups.map((group: { id: string }) => group.id)).toEqual(["usa"]);
    expect((await call("GET", "/v1/groups/usa", undefined, member)).status).toBe(200);
    expect((await call("GET", "/v1/groups/usa/stage", undefined, member)).status).toBe(200);

    // A member's writes.
    expect((await call("PUT", "/v1/members/me", { displayName: "Imran Khan" }, member)).status).toBe(200);
    expect((await call("POST", "/v1/members/devices", { installationID: INSTALLATION }, member)).status).toBe(204);
    expect((await call("POST", "/v1/groups/usa/presence", {}, member)).status).toBe(200);
    expect((await call("POST", "/v1/groups/usa/duas", { text: "Please pray for my mother." }, member)).status).toBe(201);
    expect((await call("POST", "/v1/groups/usa/stage-chat", { id: crypto.randomUUID(), presetID: "salam" }, member)).status).toBe(201);
    // A visitor's writes on Our Sheikh's stage.
    raw.prepare(`INSERT INTO group_live(group_id,state,kind,title,started_at,updated_at,session_id,queue_json)
      VALUES('our-sheikh','live','zikr','Daily Zikr',?,?,'session-2','[]')`).run(new Date().toISOString(), new Date().toISOString());
    expect((await call("POST", "/v1/groups/our-sheikh/presence", {}, visitor.body.token)).status).toBe(200);
    expect((await call("POST", "/v1/groups/our-sheikh/stage-chat", { id: crypto.randomUUID(), presetID: "ameen" }, visitor.body.token)).status).toBe(201);
    // An admin's writes: a stage, a notice to the session, a post.
    const leader: string = admin.body.token;
    expect((await call("POST", "/v1/groups/usa/zikr-cues", { id: crypto.randomUUID(), stageID: "latifa-1" }, leader)).status).toBe(201);
    expect((await call("POST", "/v1/groups/usa/control", { action: "notice", text: "Starting shortly" }, leader)).status).toBe(200);
    expect((await call("POST", "/v1/groups/usa/posts", { kind: "announcement", title: "Jumu'ah", body: "After Maghrib." }, leader)).status).toBe(201);

    // Push registration, which has no sign-in at all.
    expect((await call("POST", "/v1/devices", {
      installationID: INSTALLATION, apnsToken: "ab".repeat(32), environment: "production", topics: ["liveZikr"], locale: "en", timeZone: "UTC",
    })).status).toBe(201);

    // The websites: what is live, and a visitor joining and staying.
    expect((await call("GET", "/v1/public/live?ids=usa")).body.halqahs[0].live).toMatchObject({ kind: "zikr", sessionID: "session-1" });
    expect((await call("GET", "/v1/public/sheikh-stage")).status).toBe(200);
    expect((await call("GET", "/v1/live")).status).toBe(200);
    expect((await call("GET", "/v1/bootstrap")).status).toBe(200);
    const joined = await call("POST", "/v1/public/halqahs/usa/join", WEB_VISITOR);
    expect(joined.status).toBe(200);
    expect(joined.body).toMatchObject({ live: { title: "Thursday Zikr" }, stage: { stageID: "latifa-1" } });
    expect((await call("POST", "/v1/public/halqahs/usa/presence", { guestSecret: WEB_VISITOR.guestSecret })).status).toBe(200);

    // The relay.
    expect((await call("POST", "/v1/service/groups/usa/zikr-cues", { id: crypto.randomUUID(), stageID: "latifa-2" }, RELAY)).status).toBe(201);
    expect((await call("POST", "/v1/service/groups/usa/live", { state: "live" }, RELAY)).body).toEqual({ state: "live", sessionID: "session-1", started: false });

    // Leaving.
    expect((await call("POST", "/v1/members/signout", { installationID: INSTALLATION }, google.body.token)).status).toBe(204);
    expect((await call("DELETE", "/v1/members/me", undefined, member)).status).toBe(204);
    expect((await call("GET", "/v1/members/me", undefined, member)).status).toBe(401);

    // Not one answer asked for the terms, and nothing was stored about them.
    expect(answers.length).toBeGreaterThanOrEqual(30);
    for (const answer of answers) {
      expect(answer.text).not.toContain("community_consent_required");
      expect(answer.text).not.toContain("termsVersion");
    }
    expect(consents()).toBe(0);
  });

  it("answer a client that does send the declaration the same way, without storing it", async () => {
    const { call, answers, googleToken, consents } = await setup();
    const declared = { adult: true, termsVersion: "2026-11-06" };
    const google = await call("POST", "/v1/members/session", { provider: "google", idToken: await googleToken(), ...declared });
    expect(google.status).toBe(201);
    expect(Object.keys(google.body).sort()).toEqual(SESSION_KEYS);
    expect((await call("POST", "/v1/members/invite", { code: "ACDEFGHJKM", ...declared })).status).toBe(201);
    expect((await call("POST", "/v1/our-sheikh/join", { ...VISITOR, ...declared })).status).toBe(201);
    // A signed-in member joining again with the declaration: the usual answer, on their own account.
    expect((await call("POST", "/v1/our-sheikh/join", { name: "Ali", city: "Leeds", countryCode: "GB", ...declared }, google.body.token)).body)
      .toEqual({ memberID: google.body.memberID, groupID: "our-sheikh" });
    expect((await call("POST", "/v1/public/halqahs/usa/join", { ...WEB_VISITOR, ...declared })).status).toBe(200);
    // A declaration that is wrong or out of date changes nothing either.
    expect((await call("POST", "/v1/our-sheikh/join", { ...VISITOR, adult: false, termsVersion: "1999-01-01" })).status).toBe(201);
    for (const answer of answers) expect(answer.text).not.toContain("community_consent_required");
    expect(consents()).toBe(0);
  });
});
