// The FCM sender on its own: the service account's JWT and access token, the
// message an Android phone is sent, its channel, and what each FCM answer
// means for the phone.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  FCM_SCOPE, GOOGLE_TOKEN_URL, fcmAccessToken, fcmChannel, fcmConfig, fcmMessage, fcmOutcome, pkcs8FromPEM,
  resetFCMToken, serviceAccountAssertion, type FCMConfig, type FCMErrorBody,
} from "../src/fcm";
import { CUE_ALERT, LIVE_ALERT } from "../src/apns";
import type { Env } from "../src/contracts";

type FCMErrorDetails = NonNullable<NonNullable<FCMErrorBody["error"]>["details"]>;

/** A throwaway RSA key, as a service account's PEM with real line breaks. */
async function serviceAccountKey(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true, ["sign", "verify"],
  ) as CryptoKeyPair;
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey) as ArrayBuffer);
  let binary = ""; der.forEach(byte => binary += String.fromCharCode(byte));
  const lines = btoa(binary).match(/.{1,64}/g) ?? [];
  return { pem: `-----BEGIN PRIVATE KEY-----\n${lines.join("\n")}\n-----END PRIVATE KEY-----\n`, publicKey: pair.publicKey };
}

const fromBase64url = (text: string): Uint8Array<ArrayBuffer> =>
  Uint8Array.from(atob(text.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((text.length + 3) % 4)), char => char.charCodeAt(0));
const decodePart = (text: string) => JSON.parse(new TextDecoder().decode(fromBase64url(text))) as Record<string, unknown>;

const config = (privateKey: string): FCMConfig => ({
  projectID: "darul-irfan-test", clientEmail: "push@darul-irfan-test.iam.gserviceaccount.com", privateKey,
});

beforeEach(() => resetFCMToken());
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });

describe("the service account's key", () => {
  it("reads the PEM with real line breaks, with the key file's literal \\n, and still in quotes", async () => {
    const { pem } = await serviceAccountKey();
    const expected = pkcs8FromPEM(pem);
    expect(expected.byteLength).toBeGreaterThan(1000);
    const literal = pem.replace(/\n/g, "\\n");
    expect(literal).not.toContain("\n");
    expect(pkcs8FromPEM(literal)).toEqual(expected);
    expect(pkcs8FromPEM(`"${literal}"`)).toEqual(expected);
    expect(pkcs8FromPEM(pem.replace(/\n/g, "\r\n"))).toEqual(expected);
  });

  it("refuses a PKCS#1 key and something that is not a key, naming neither", () => {
    expect(() => pkcs8FromPEM("-----BEGIN RSA PRIVATE KEY-----\nMIIE\n-----END RSA PRIVATE KEY-----")).toThrow(/PKCS#8/);
    expect(() => pkcs8FromPEM("not a key at all!")).toThrow(/not a PEM private key/);
  });

  it("is configured only when all three values are set", () => {
    expect(fcmConfig({ FCM_PROJECT_ID: "p", FCM_CLIENT_EMAIL: "e" } as Env)).toBeNull();
    expect(fcmConfig({ FCM_PROJECT_ID: " ", FCM_CLIENT_EMAIL: "e", FCM_PRIVATE_KEY: "k" } as Env)).toBeNull();
    expect(fcmConfig({ FCM_PROJECT_ID: "p", FCM_CLIENT_EMAIL: "e", FCM_PRIVATE_KEY: "k" } as Env))
      .toEqual({ projectID: "p", clientEmail: "e", privateKey: "k" });
  });
});

describe("the JWT exchanged for an access token", () => {
  it("is RS256, signed with the service account's key, for the Firebase Messaging scope, for an hour", async () => {
    const { pem, publicKey } = await serviceAccountKey();
    const jwt = await serviceAccountAssertion(config(pem.replace(/\n/g, "\\n")), 1_793_000_000);
    const [header, claims, signature] = jwt.split(".") as [string, string, string];
    expect(decodePart(header)).toEqual({ alg: "RS256", typ: "JWT" });
    expect(decodePart(claims)).toEqual({
      iss: "push@darul-irfan-test.iam.gserviceaccount.com",
      scope: FCM_SCOPE,
      aud: "https://oauth2.googleapis.com/token",
      iat: 1_793_000_000,
      exp: 1_793_003_600,
    });
    const verified = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", publicKey, fromBase64url(signature),
      new TextEncoder().encode(`${header}.${claims}`));
    expect(verified).toBe(true);
    // Any other key's signature does not verify.
    const other = await serviceAccountKey();
    expect(await crypto.subtle.verify("RSASSA-PKCS1-v1_5", other.publicKey, fromBase64url(signature),
      new TextEncoder().encode(`${header}.${claims}`))).toBe(false);
  });
});

describe("the access token", () => {
  async function tokenServer(answer?: () => Response) {
    const exchanges: URLSearchParams[] = [];
    vi.stubGlobal("fetch", async (input: string, init?: RequestInit) => {
      expect(String(input)).toBe(GOOGLE_TOKEN_URL);
      expect(init?.method).toBe("POST");
      expect(new Headers(init?.headers).get("content-type")).toBe("application/x-www-form-urlencoded");
      exchanges.push(new URLSearchParams(String(init?.body)));
      return answer?.() ?? Response.json({ access_token: `ya29.token-${exchanges.length}`, expires_in: 3599, token_type: "Bearer" });
    });
    return exchanges;
  }

  it("is asked for with the signed JWT, kept, and renewed five minutes before it expires", async () => {
    const { pem } = await serviceAccountKey();
    const exchanges = await tokenServer();
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-10-30T12:00:00Z"));
    expect(await fcmAccessToken(config(pem))).toBe("ya29.token-1");
    expect(exchanges).toHaveLength(1);
    expect(exchanges[0]!.get("grant_type")).toBe("urn:ietf:params:oauth:grant-type:jwt-bearer");
    const claims = decodePart(exchanges[0]!.get("assertion")!.split(".")[1]!);
    expect(claims.iat).toBe(Date.parse("2026-10-30T12:00:00Z") / 1000);

    vi.setSystemTime(new Date("2026-10-30T12:54:00Z"));
    expect(await fcmAccessToken(config(pem))).toBe("ya29.token-1");
    expect(exchanges).toHaveLength(1);
    vi.setSystemTime(new Date("2026-10-30T12:55:00Z"));
    expect(await fcmAccessToken(config(pem))).toBe("ya29.token-2");
    expect(exchanges).toHaveLength(2);
  });

  it("is asked for once when several sends want it at the same moment", async () => {
    const { pem } = await serviceAccountKey();
    const exchanges = await tokenServer();
    const tokens = await Promise.all([fcmAccessToken(config(pem)), fcmAccessToken(config(pem)), fcmAccessToken(config(pem))]);
    expect(new Set(tokens)).toEqual(new Set(["ya29.token-1"]));
    expect(exchanges).toHaveLength(1);
  });

  it("is asked for anew after it is forgotten", async () => {
    const { pem } = await serviceAccountKey();
    const exchanges = await tokenServer();
    await fcmAccessToken(config(pem));
    resetFCMToken();
    expect(await fcmAccessToken(config(pem))).toBe("ya29.token-2");
    expect(exchanges).toHaveLength(2);
  });

  it("fails with Google's reason, and never the key or the assertion", async () => {
    const { pem } = await serviceAccountKey();
    const exchanges = await tokenServer(() => Response.json({ error: "invalid_grant", error_description: "Invalid JWT Signature." }, { status: 400 }));
    const failure = await fcmAccessToken(config(pem)).catch((error: Error) => error);
    expect(failure).toBeInstanceOf(Error);
    const message = (failure as Error).message;
    expect(message).toContain("400");
    expect(message).toContain("invalid_grant: Invalid JWT Signature.");
    expect(message).not.toContain("PRIVATE KEY");
    expect(message).not.toContain(exchanges[0]!.get("assertion")!);
    // Nothing was kept: the next send asks again.
    await fcmAccessToken(config(pem)).catch(() => undefined);
    expect(exchanges).toHaveLength(2);
  });
});

describe("the Android channel of each notice", () => {
  it("puts a Halqah's notices, the live zikr and every other official alert in their own channels", () => {
    expect(fcmChannel("group:usa")).toBe("halqah_notifications");
    expect(fcmChannel("group:darul-irfan")).toBe("halqah_notifications");
    expect(fcmChannel("live-alerts")).toBe("daily_zikr_live");
    expect(fcmChannel("liveZikr")).toBe("daily_zikr_live");
    for (const topic of ["broadcasts", "announcements", "events"]) expect(fcmChannel(topic)).toBe("official_alerts");
  });
});

describe("the message an Android phone is sent", () => {
  it("carries the iPhone's title, body and deep link, high priority, in the Halqah channel", () => {
    expect(fcmMessage("token-1", "post:abc", "group:usa", "Friday", "After Isha", "darulirfan://groups/usa")).toEqual({
      token: "token-1",
      notification: { title: "Friday", body: "After Isha" },
      android: { priority: "high", notification: { channel_id: "halqah_notifications", sound: "default" } },
      data: { path: "darulirfan://groups/usa", eventID: "post:abc", topic: "group:usa" },
    });
  });

  it("gives a live alert its expiry, and replaces the last one, as on the iPhone", () => {
    const message = fcmMessage("token-2", "youtube-live:abc", "liveZikr", "Daily Zikr has started",
      "Join the official daily zikr in Darul Irfan.", "darulirfan://live/official-live", LIVE_ALERT);
    expect(message.android).toEqual({
      priority: "high", ttl: "1800s", collapse_key: "live-zikr",
      notification: { channel_id: "daily_zikr_live", sound: "default", tag: "live-zikr" },
    });
    expect(message.data).toEqual({ path: "darulirfan://live/official-live", eventID: "youtube-live:abc", topic: "liveZikr" });
    expect(fcmMessage("t", "cue:1", "liveZikr", "L-3", "Tahajjud Zikr", "darulirfan://live/official-live", CUE_ALERT).android.notification.tag)
      .toBe("live-cue");
  });

  it("sends an official broadcast in the official channel, with string data only", () => {
    const message = fcmMessage("t", "notice-1", "announcements", "Notice", "Body", "darulirfan://feed");
    expect(message.android.notification.channel_id).toBe("official_alerts");
    expect(Object.values(message.data).every(value => typeof value === "string")).toBe(true);
  });
});

describe("what an FCM answer means for the phone", () => {
  const fcmError = (code: number, status: string, message: string, details: FCMErrorDetails = []): FCMErrorBody =>
    ({ error: { code, status, message, details } });
  const fcmCode = (errorCode: string) => ({ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode });

  it("accepts a 2xx", () => {
    expect(fcmOutcome(200, null)).toBe("accepted");
  });

  it("forgets a phone whose app was removed (UNREGISTERED)", () => {
    expect(fcmOutcome(404, fcmError(404, "NOT_FOUND", "Requested entity was not found.", [fcmCode("UNREGISTERED")]))).toBe("dead");
  });

  it("forgets a phone whose token is not a token (INVALID_ARGUMENT naming it)", () => {
    expect(fcmOutcome(400, fcmError(400, "INVALID_ARGUMENT", "The registration token is not a valid FCM registration token",
      [fcmCode("INVALID_ARGUMENT")]))).toBe("dead");
    expect(fcmOutcome(400, fcmError(400, "INVALID_ARGUMENT", "Request contains an invalid argument.", [
      fcmCode("INVALID_ARGUMENT"),
      { "@type": "type.googleapis.com/google.rpc.BadRequest", fieldViolations: [{ field: "message.token", description: "Invalid registration token" }] },
    ]))).toBe("dead");
  });

  it("keeps the phone when INVALID_ARGUMENT is about the message, not the token", () => {
    expect(fcmOutcome(400, fcmError(400, "INVALID_ARGUMENT", "Invalid value at 'message.android.ttl'", [
      { "@type": "type.googleapis.com/google.rpc.BadRequest", fieldViolations: [{ field: "message.android.ttl", description: "Invalid value" }] },
    ]))).toBe("failed");
    expect(fcmOutcome(400, fcmError(400, "INVALID_ARGUMENT", "Request contains an invalid argument.", [fcmCode("INVALID_ARGUMENT")])))
      .toBe("failed");
  });

  it("renews the access token on 401, and keeps the phone on everything else", () => {
    expect(fcmOutcome(401, fcmError(401, "UNAUTHENTICATED", "Request had invalid authentication credentials."))).toBe("unauthorized");
    expect(fcmOutcome(403, fcmError(403, "PERMISSION_DENIED", "SenderId mismatch", [fcmCode("SENDER_ID_MISMATCH")]))).toBe("failed");
    expect(fcmOutcome(429, fcmError(429, "RESOURCE_EXHAUSTED", "Quota exceeded.", [fcmCode("QUOTA_EXCEEDED")]))).toBe("failed");
    expect(fcmOutcome(503, fcmError(503, "UNAVAILABLE", "The service is currently unavailable.", [fcmCode("UNAVAILABLE")]))).toBe("failed");
    expect(fcmOutcome(500, null)).toBe("failed");
    expect(fcmOutcome(null, null)).toBe("failed");
  });
});
