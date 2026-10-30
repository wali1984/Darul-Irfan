// Google sign-in on Android: POST /v1/members/session with
// {"provider":"google","idToken":...}. Google's keys are generated here and
// served from a stubbed fetch of Google's JWKS, so every check the Worker
// makes on a real ID token is made on these.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT, type JWK } from "jose";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { createSession } from "../src/members";
import { GOOGLE_CERTS_URL, freshFor, resetGoogleKeys } from "../src/google";
import { sqliteD1 } from "./sqlite-d1";

const WEB_CLIENT = "123456789012-web.apps.googleusercontent.com";
const OTHER_CLIENT = "123456789012-other.apps.googleusercontent.com";
const OWNER = "owner@example.com";

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

async function rsaKey(kid: string): Promise<{ privateKey: CryptoKey; jwk: JWK }> {
  const { publicKey, privateKey } = await generateKeyPair("RS256", { extractable: true });
  return { privateKey, jwk: { ...await exportJWK(publicKey), kid, alg: "RS256", use: "sig" } };
}

interface TokenClaims {
  sub?: string; email?: string; verified?: unknown; iss?: string; aud?: string; kid?: string;
  exp?: number; iat?: number; name?: string;
}

/** An ID token as Google signs one for the Android app. */
async function idToken(key: CryptoKey, claims: TokenClaims = {}): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const payload: Record<string, unknown> = {
    email: claims.email ?? "member@example.com", azp: "123456789012-android.apps.googleusercontent.com",
  };
  if (!("verified" in claims)) payload.email_verified = true;
  else if (claims.verified !== undefined) payload.email_verified = claims.verified;
  if (claims.name) payload.name = claims.name;
  return new SignJWT(payload)
    .setProtectedHeader({ alg: "RS256", kid: claims.kid ?? "google-key-1", typ: "JWT" })
    .setIssuer(claims.iss ?? "https://accounts.google.com")
    .setAudience(claims.aud ?? WEB_CLIENT)
    .setSubject(claims.sub ?? "104935628104935628104")
    .setIssuedAt(claims.iat ?? now)
    .setExpirationTime(claims.exp ?? now + 3_600)
    .sign(key);
}

interface Setup { clientIDs?: string | null; cacheControl?: string; age?: string; certsStatus?: number }

async function setup(options: Setup = {}) {
  const { db, raw } = sqliteD1();
  const google = await rsaKey("google-key-1");
  const published: JWK[] = [google.jwk];
  let certsFetches = 0;
  const unexpected: string[] = [];
  vi.stubGlobal("fetch", async (input: string) => {
    const url = String(input);
    if (url !== GOOGLE_CERTS_URL) { unexpected.push(url); return new Response("", { status: 404 }); }
    certsFetches += 1;
    if (options.certsStatus) return new Response("", { status: options.certsStatus });
    const headers: Record<string, string> = { "cache-control": options.cacheControl ?? "public, max-age=19956, must-revalidate, no-transform" };
    if (options.age) headers.age = options.age;
    return Response.json({ keys: published }, { headers });
  });
  const env = {
    DB: db, APNS_TOPIC: "us.naqshbaniaowaisiah", SUPER_ADMIN_EMAILS: `someone-else@example.com,${OWNER}`,
    ...(options.clientIDs === null ? {} : { GOOGLE_CLIENT_IDS: options.clientIDs ?? `${WEB_CLIENT}, ${OTHER_CLIENT}` }),
  } as unknown as Env;
  const signIn = (body: Record<string, unknown>) => worker.fetch(new Request("https://api.example.com/v1/members/session", {
    method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": "8.8.4.4" }, body: JSON.stringify(body),
  }), env);
  const google_ = (claims?: TokenClaims, extra: Record<string, unknown> = {}) =>
    idToken(google.privateKey, claims).then(token => signIn({ provider: "google", idToken: token, ...extra }));
  const call = (token: string, method: string, path: string, body?: unknown) => worker.fetch(new Request(`https://api.example.com${path}`, {
    method, headers: { authorization: `Bearer ${token}`, ...(body ? { "content-type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  }), env);
  const member = (id: string) => raw.prepare(
    "SELECT id,apple_subject,google_subject,google_email,email,display_name FROM members WHERE id=?").get(id) as Record<string, string | null> | undefined;
  const memberCount = () => (raw.prepare("SELECT COUNT(*) AS n FROM members").get() as { n: number }).n;
  return {
    env, raw, google, published, signIn, signInWithGoogle: google_, call, member, memberCount, unexpected,
    certsFetches: () => certsFetches,
  };
}

type Session = { token: string; expiresAt: string; memberID: string };

beforeEach(() => resetGoogleKeys());
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });

describe("a Google sign-in", () => {
  it("makes a new member, and answers exactly as a Sign in with Apple does", async () => {
    const { signInWithGoogle, member, call, unexpected } = await setup();
    const response = await signInWithGoogle({ sub: "1001", email: "New.Member@Example.com" }, { name: "  New   Member " });
    expect(response.status).toBe(201);
    expect(response.headers.get("content-type")).toContain("application/json");
    expect(response.headers.get("cache-control")).toBe("no-store");
    const session = await response.json() as Session;
    expect(Object.keys(session).sort()).toEqual(["expiresAt", "memberID", "token"]);
    expect(session.token).toMatch(/^[0-9a-f]{64}$/);
    expect(session.memberID).toBe((await sha256("member:google:1001")).slice(0, 32));
    expect(Date.parse(session.expiresAt) - Date.now()).toBeGreaterThan(89 * 86_400_000);
    expect(member(session.memberID)).toEqual({
      id: session.memberID, apple_subject: "google:1001", google_subject: "1001", google_email: "new.member@example.com",
      email: "new.member@example.com", display_name: "New Member",
    });
    // The bearer token works like any other member's, and grants nothing yet.
    const me = await call(session.token, "GET", "/v1/members/me");
    expect(await me.json()).toEqual({ memberID: session.memberID, role: "member", displayName: "New Member" });
    expect(await (await call(session.token, "GET", "/v1/groups")).json()).toMatchObject({ groups: [] });
    expect(unexpected).toEqual([]);
  });

  it("gives a member the name on the Google account when the app sends none, and keeps one they chose", async () => {
    const { signInWithGoogle, member, call } = await setup();
    const first = await (await signInWithGoogle({ sub: "1002", name: "Name On Google" })).json() as Session;
    expect(member(first.memberID)?.display_name).toBe("Name On Google");
    await call(first.token, "PUT", "/v1/members/me", { displayName: "Chosen Name" });
    const again = await (await signInWithGoogle({ sub: "1002", name: "Name On Google" }, { name: "Another" })).json() as Session;
    expect(again.memberID).toBe(first.memberID);
    expect(member(first.memberID)?.display_name).toBe("Chosen Name");
  });

  it("signs the same Google account in as the same member, following a changed email", async () => {
    const { signInWithGoogle, member, memberCount } = await setup();
    const first = await (await signInWithGoogle({ sub: "1003", email: "old@example.com" })).json() as Session;
    const again = await (await signInWithGoogle({ sub: "1003", email: "new@example.com" })).json() as Session;
    expect(again.memberID).toBe(first.memberID);
    expect(memberCount()).toBe(1);
    expect(member(first.memberID)).toMatchObject({ email: "new@example.com", google_email: "new@example.com" });
  });

  it("links to the member who signed in with Apple under the same verified email", async () => {
    const context = await setup();
    const { env, raw, signInWithGoogle, member, call, memberCount } = context;
    // Sign in with Apple, as the iPhone does, with Apple's own (here generated) key.
    const apple = await rsaKey("apple-key");
    const appleSession = async (displayName?: string) => {
      const now = Math.floor(Date.now() / 1000);
      const identityToken = await new SignJWT({ email: "both@example.com" })
        .setProtectedHeader({ alg: "RS256", kid: "apple-key" }).setIssuer("https://appleid.apple.com")
        .setAudience("us.naqshbaniaowaisiah").setSubject("001234.apple-subject.0101").setIssuedAt(now).setExpirationTime(now + 600)
        .sign(apple.privateKey);
      const response = await createSession(new Request("https://api.example.com/v1/members/session", {
        method: "POST", body: JSON.stringify({ identityToken, ...(displayName ? { displayName } : {}) }),
      }), env, createLocalJWKSet({ keys: [apple.jwk] }));
      expect(response.status).toBe(201);
      return await response.json() as Session;
    };
    const fromApple = await appleSession("Apple Name");
    expect(Object.keys(fromApple).sort()).toEqual(["expiresAt", "memberID", "token"]);
    expect(fromApple.memberID).toBe((await sha256("member:001234.apple-subject.0101")).slice(0, 32));
    const now = new Date().toISOString();
    raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('usa',?,?,'test','member')").run(fromApple.memberID, now);

    const fromGoogle = await (await signInWithGoogle({ sub: "1004", email: "Both@Example.com", name: "Google Name" })).json() as Session;
    expect(fromGoogle.memberID).toBe(fromApple.memberID);
    expect(memberCount()).toBe(1);
    expect(member(fromApple.memberID)).toEqual({
      id: fromApple.memberID, apple_subject: "001234.apple-subject.0101", google_subject: "1004", google_email: "both@example.com",
      email: "both@example.com", display_name: "Apple Name",
    });
    // The Halqah the Apple member was admitted to is theirs on Android too.
    const groups = await (await call(fromGoogle.token, "GET", "/v1/groups")).json() as { groups: Array<{ id: string }> };
    expect(groups.groups.map(group => group.id)).toEqual(["usa"]);

    // A later change of the Google account's email leaves Apple's alone, and
    // Sign in with Apple still finds the member exactly as before.
    expect((await (await signInWithGoogle({ sub: "1004", email: "renamed@example.com" })).json() as Session).memberID).toBe(fromApple.memberID);
    expect(member(fromApple.memberID)).toMatchObject({ email: "both@example.com", google_email: "renamed@example.com" });
    expect((await appleSession()).memberID).toBe(fromApple.memberID);
    expect(memberCount()).toBe(1);
  });

  it("does not link to a member already linked to another Google account", async () => {
    const { signInWithGoogle, memberCount } = await setup();
    const first = await (await signInWithGoogle({ sub: "1005", email: "shared@example.com" })).json() as Session;
    const second = await (await signInWithGoogle({ sub: "1006", email: "shared@example.com" })).json() as Session;
    expect(second.memberID).not.toBe(first.memberID);
    expect(memberCount()).toBe(2);
  });

  it("makes the owner super admin by the Google account's email, and nobody else", async () => {
    const { signInWithGoogle, call } = await setup();
    const owner = await (await signInWithGoogle({ sub: "1007", email: "Owner@Example.com" })).json() as Session;
    expect(await (await call(owner.token, "GET", "/v1/members/me")).json()).toMatchObject({ role: "superadmin" });
    const other = await (await signInWithGoogle({ sub: "1008", email: "member@example.com" })).json() as Session;
    expect(await (await call(other.token, "GET", "/v1/members/me")).json()).toMatchObject({ role: "member" });
  });

  it("admits the member to the Halqahs an admin added their email to", async () => {
    const { raw, signInWithGoogle } = await setup();
    raw.prepare(`INSERT INTO member_group_grants(id,group_id,email,role,created_by,created_at)
      VALUES('grant-1','canada','invited@example.com','admin','admin-member',?)`).run(new Date().toISOString());
    const session = await (await signInWithGoogle({ sub: "1009", email: "invited@example.com" })).json() as Session;
    expect(raw.prepare("SELECT group_id,role FROM member_group_members WHERE member_id=?").all(session.memberID))
      .toEqual([{ group_id: "canada", role: "admin" }]);
    expect(raw.prepare("SELECT claimed_by FROM member_group_grants WHERE id='grant-1'").get()).toEqual({ claimed_by: session.memberID });
  });

  it("accepts either issuer Google uses, any listed client id, and email_verified written as a string", async () => {
    const { signInWithGoogle } = await setup();
    expect((await signInWithGoogle({ sub: "1010", iss: "accounts.google.com" })).status).toBe(201);
    expect((await signInWithGoogle({ sub: "1011", aud: OTHER_CLIENT })).status).toBe(201);
    expect((await signInWithGoogle({ sub: "1012", verified: "true" })).status).toBe(201);
  });
});

describe("a Google sign-in refused", () => {
  const refused = async (response: Response, status: number, error: RegExp) => {
    expect(response.status).toBe(status);
    expect((await response.json() as { error: string }).error).toMatch(error);
  };

  it("answers 401 for a token issued to another app", async () => {
    const { signInWithGoogle, memberCount } = await setup();
    await refused(await signInWithGoogle({ aud: "999-not-ours.apps.googleusercontent.com" }), 401, /could not be verified/);
    expect(memberCount()).toBe(0);
  });

  it("answers 401 for an expired token", async () => {
    const { signInWithGoogle, memberCount } = await setup();
    const now = Math.floor(Date.now() / 1000);
    await refused(await signInWithGoogle({ iat: now - 7_200, exp: now - 60 }), 401, /could not be verified/);
    expect(memberCount()).toBe(0);
  });

  it("answers 401 when Google has not verified the account's email", async () => {
    const { signInWithGoogle, memberCount } = await setup();
    await refused(await signInWithGoogle({ verified: false }), 401, /email address is not verified/);
    await refused(await signInWithGoogle({ verified: undefined }), 401, /email address is not verified/);
    await refused(await signInWithGoogle({ verified: "false" }), 401, /email address is not verified/);
    expect(memberCount()).toBe(0);
  });

  it("answers 401 for another issuer, a forged signature, a key Google does not publish, and no token", async () => {
    const { signIn, signInWithGoogle, memberCount } = await setup();
    await refused(await signInWithGoogle({ iss: "https://accounts.example.com" }), 401, /could not be verified/);
    const forger = await rsaKey("google-key-1");
    await refused(await signIn({ provider: "google", idToken: await idToken(forger.privateKey) }), 401, /could not be verified/);
    const stranger = await rsaKey("not-google");
    await refused(await signIn({ provider: "google", idToken: await idToken(stranger.privateKey, { kid: "not-google" }) }), 401, /could not be verified/);
    await refused(await signIn({ provider: "google", idToken: "not.a.jwt" }), 401, /could not be verified/);
    await refused(await signIn({ provider: "google" }), 401, /could not be verified/);
    expect(memberCount()).toBe(0);
  });

  it("answers 503 while GOOGLE_CLIENT_IDS is unset, without asking Google, and leaves Apple's answer as it was", async () => {
    const { signIn, signInWithGoogle, certsFetches } = await setup({ clientIDs: null });
    await refused(await signInWithGoogle(), 503, /not configured/);
    expect(certsFetches()).toBe(0);
    await refused(await signIn({ identityToken: "not.a.jwt" }), 401, /Apple identity could not be verified/);
    await refused(await signIn({ provider: "apple", identityToken: "not.a.jwt" }), 401, /Apple identity could not be verified/);
  });

  it("answers 503 when Google's keys cannot be read", async () => {
    const { signInWithGoogle } = await setup({ certsStatus: 500 });
    await refused(await signInWithGoogle(), 503, /unavailable/);
  });

  it("answers 400 for a provider it does not know", async () => {
    const { signIn } = await setup();
    await refused(await signIn({ provider: "facebook", idToken: "x" }), 400, /Unknown sign-in provider/);
  });
});

describe("Google's signing keys", () => {
  it("are kept as long as their Cache-Control says, less their Age", async () => {
    const { signInWithGoogle, certsFetches } = await setup({ cacheControl: "public, max-age=100, must-revalidate, no-transform", age: "40" });
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-10-30T12:00:00Z"));
    expect((await signInWithGoogle({ sub: "2001" })).status).toBe(201);
    vi.setSystemTime(new Date("2026-10-30T12:00:59Z"));
    expect((await signInWithGoogle({ sub: "2001" })).status).toBe(201);
    expect(certsFetches()).toBe(1);
    vi.setSystemTime(new Date("2026-10-30T12:01:01Z"));
    expect((await signInWithGoogle({ sub: "2001" })).status).toBe(201);
    expect(certsFetches()).toBe(2);
  });

  it("are fetched again when Google rotates them, but at most once a minute for unknown keys", async () => {
    const { signIn, signInWithGoogle, published, certsFetches } = await setup();
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-10-30T12:00:00Z"));
    expect((await signInWithGoogle({ sub: "2002" })).status).toBe(201);
    expect(certsFetches()).toBe(1);
    // Google starts signing with a new key.
    const rotated = await rsaKey("google-key-2");
    published.push(rotated.jwk);
    vi.setSystemTime(new Date("2026-10-30T12:02:00Z"));
    expect((await signIn({ provider: "google", idToken: await idToken(rotated.privateKey, { sub: "2002", kid: "google-key-2" }) })).status).toBe(201);
    expect(certsFetches()).toBe(2);
    // A flood of tokens naming keys nobody publishes does not become a flood of fetches.
    const stranger = await rsaKey("rogue");
    vi.setSystemTime(new Date("2026-10-30T12:02:10Z"));
    for (let attempt = 0; attempt < 3; attempt += 1) {
      expect((await signIn({ provider: "google", idToken: await idToken(stranger.privateKey, { kid: "rogue" }) })).status).toBe(401);
    }
    expect(certsFetches()).toBe(2);
  });

  it("read their lifetime as an HTTP cache would", () => {
    const headers = (values: Record<string, string>) => new Headers(values);
    expect(freshFor(headers({ "cache-control": "public, max-age=19956, must-revalidate, no-transform" }))).toBe(19_956_000);
    expect(freshFor(headers({ "cache-control": "public, max-age=19956", age: "956" }))).toBe(19_000_000);
    expect(freshFor(headers({ "cache-control": "no-store" }))).toBe(0);
    expect(freshFor(headers({ "cache-control": "no-cache, max-age=600" }))).toBe(0);
    expect(freshFor(headers({ expires: "Fri, 30 Oct 2026 13:00:00 GMT", date: "Fri, 30 Oct 2026 12:30:00 GMT" }))).toBe(1_800_000);
    expect(freshFor(headers({ expires: "0" }))).toBe(0);
    expect(freshFor(headers({}))).toBe(3_600_000);
    expect(freshFor(headers({ "cache-control": "max-age=9999999" }))).toBe(86_400_000);
  });
});
