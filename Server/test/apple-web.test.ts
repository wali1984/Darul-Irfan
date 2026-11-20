import { describe, expect, it } from "vitest";
import { exportJWK, generateKeyPair, SignJWT, createLocalJWKSet, type JWK } from "jose";
import type { Env } from "../src/contracts";
import { appleSubject } from "../src/members";

// Sign in with Apple on the websites: the token's audience is the website's
// Services ID, accepted next to the app's bundle id (owner 2026-11-19).
describe("Apple identity tokens", () => {
  it("accepts the app and the websites' Services ID, and nothing else", async () => {
    const { publicKey, privateKey } = await generateKeyPair("RS256", { extractable: true });
    const jwk = { ...(await exportJWK(publicKey)), kid: "k1", alg: "RS256" } as JWK;
    const keys = createLocalJWKSet({ keys: [jwk] });
    const token = (aud: string) => new SignJWT({ email: "Member@Example.com" }).setProtectedHeader({ alg: "RS256", kid: "k1" })
      .setIssuer("https://appleid.apple.com").setAudience(aud).setSubject("apple-sub-1").setIssuedAt().setExpirationTime("5m").sign(privateKey);
    const env = { APNS_TOPIC: "us.naqshbaniaowaisiah", APPLE_WEB_CLIENT_IDS: "us.naqshbaniaowaisiah.web" } as Env;
    expect(await appleSubject(await token("us.naqshbaniaowaisiah"), env, keys)).toEqual({ subject: "apple-sub-1", email: "member@example.com" });
    expect(await appleSubject(await token("us.naqshbaniaowaisiah.web"), env, keys)).toEqual({ subject: "apple-sub-1", email: "member@example.com" });
    expect(await appleSubject(await token("someone.else"), env, keys)).toBeNull();
    expect(await appleSubject(await token("us.naqshbaniaowaisiah.web"), { APNS_TOPIC: "us.naqshbaniaowaisiah" } as Env, keys)).toBeNull();
  });
});
