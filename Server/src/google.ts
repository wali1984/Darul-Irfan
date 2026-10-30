import { importJWK, jwtVerify, type JWK, type JWTVerifyGetKey } from "jose";
import type { Env } from "./contracts";

// Google sign-in for members on Android. The app asks Google for an ID token
// for the Web client id (GOOGLE_CLIENT_IDS) and sends it here; nothing about
// the person is believed unless Google signed it. Google's subject is the
// identity, and its verified email links a Google sign-in to the member that
// address already belongs to, and decides super admin as it does for Apple.

export const GOOGLE_CERTS_URL = "https://www.googleapis.com/oauth2/v3/certs";
export const GOOGLE_ISSUERS = ["accounts.google.com", "https://accounts.google.com"];

/** Keys served without a usable lifetime are kept an hour, and none longer
 *  than a day whatever the headers say. */
const DEFAULT_KEYS_MS = 60 * 60_000;
const MAX_KEYS_MS = 24 * 3_600_000;
/** A token signed by a key we do not hold makes us fetch the keys again (Google
 *  rotates them), but no more than once a minute however many such tokens come. */
const REFETCH_AFTER_MS = 60_000;

/** The OAuth client ids a token may be issued to; empty when unset. */
export function googleClientIDs(env: Env): string[] {
  return (env.GOOGLE_CLIENT_IDS ?? "").split(",").map(value => value.trim()).filter(Boolean);
}

/** How long a response may be used, from its Cache-Control max-age (less
 *  its Age) or else its Expires, as an HTTP cache would. */
export function freshFor(headers: Headers, now = Date.now()): number {
  const directives = new Map<string, string>();
  for (const part of (headers.get("cache-control") ?? "").toLowerCase().split(",")) {
    const [name = "", value = ""] = part.split("=", 2).map(piece => piece.trim());
    if (name) directives.set(name, value.replace(/^"|"$/g, ""));
  }
  if (directives.has("no-store") || directives.has("no-cache")) return 0;
  let lifetime: number;
  const maxAge = Number(directives.get("max-age"));
  if (directives.has("max-age") && Number.isFinite(maxAge)) {
    lifetime = maxAge * 1000 - Math.max(0, Number(headers.get("age")) || 0) * 1000;
  } else if (headers.has("expires")) {
    const expires = Date.parse(headers.get("expires") ?? "");
    const date = Date.parse(headers.get("date") ?? "");
    // An Expires that cannot be read means already expired.
    lifetime = Number.isFinite(expires) ? expires - (Number.isFinite(date) ? date : now) : 0;
  } else {
    lifetime = DEFAULT_KEYS_MS;
  }
  return Math.min(Math.max(lifetime, 0), MAX_KEYS_MS);
}

/** Google's keys could not be read: Google sign-in is unavailable, which is
 *  not the same as the token being bad. */
class GoogleKeysUnavailable extends Error {}

interface KeySet { keys: Map<string, JWK>; fetchedAt: number; freshUntil: number }
let keySet: KeySet | undefined;
const imported = new Map<string, CryptoKey | Uint8Array>();

/** Forgets Google's keys, so the next sign-in fetches them. */
export function resetGoogleKeys(): void {
  keySet = undefined;
  imported.clear();
}

async function googleKeys(now: number, force: boolean): Promise<KeySet> {
  if (keySet && !force && now < keySet.freshUntil) return keySet;
  let response: Response;
  try { response = await fetch(GOOGLE_CERTS_URL, { headers: { accept: "application/json" } }); }
  catch { throw new GoogleKeysUnavailable("Google's signing keys could not be fetched"); }
  if (!response.ok) throw new GoogleKeysUnavailable(`Google's signing keys answered ${response.status}`);
  const body = await response.json<{ keys?: unknown }>().catch(() => ({ keys: undefined }));
  const keys = new Map<string, JWK>();
  for (const key of Array.isArray(body.keys) ? body.keys as JWK[] : []) {
    if (key?.kty === "RSA" && typeof key.kid === "string" && typeof key.n === "string" && typeof key.e === "string"
      && (key.alg === undefined || key.alg === "RS256") && (key.use === undefined || key.use === "sig")) keys.set(key.kid, key);
  }
  if (!keys.size) throw new GoogleKeysUnavailable("Google's signing keys were empty");
  keySet = { keys, fetchedAt: now, freshUntil: now + freshFor(response.headers, now) };
  imported.clear();
  return keySet;
}

/** The key a token names (its kid), from Google's keys as they are now. */
const googleKey: JWTVerifyGetKey = async header => {
  const kid = header.kid;
  if (!kid) throw new Error("The token names no key");
  const now = Date.now();
  let set = await googleKeys(now, false);
  if (!set.keys.has(kid) && now - set.fetchedAt >= REFETCH_AFTER_MS) set = await googleKeys(now, true);
  const jwk = set.keys.get(kid);
  if (!jwk) throw new Error("The token was signed with a key Google does not publish");
  let key = imported.get(kid);
  if (!key) {
    key = await importJWK({ ...jwk, alg: "RS256" }, "RS256");
    imported.set(kid, key);
  }
  return key;
};

export interface GoogleIdentity { subject: string; email: string; name?: string }

export type GoogleVerification =
  | { ok: true; identity: GoogleIdentity }
  /** `invalid`: not a token Google issued to us, or expired. `unverified`:
   *  Google has not verified the account's email. `unavailable`: Google's
   *  keys could not be read. */
  | { ok: false; reason: "invalid" | "unverified" | "unavailable" };

/** Verifies a Google ID token: RS256 by one of Google's published keys, from
 *  Google, for one of our client ids, not expired, and with a verified email. */
export async function verifyGoogleIDToken(token: string, env: Env, resolveKey: JWTVerifyGetKey = googleKey): Promise<GoogleVerification> {
  const audience = googleClientIDs(env);
  if (!audience.length || !token) return { ok: false, reason: "invalid" };
  let payload: Record<string, unknown>;
  try {
    ({ payload } = await jwtVerify(token, resolveKey, {
      issuer: GOOGLE_ISSUERS,
      audience,
      algorithms: ["RS256"],
      requiredClaims: ["exp", "iat", "sub"],
    }));
  } catch (error) {
    return { ok: false, reason: error instanceof GoogleKeysUnavailable ? "unavailable" : "invalid" };
  }
  const subject = typeof payload.sub === "string" ? payload.sub.trim() : "";
  if (!subject) return { ok: false, reason: "invalid" };
  const email = typeof payload.email === "string" ? payload.email.trim().toLowerCase() : "";
  const verified = payload.email_verified === true || payload.email_verified === "true";
  if (!verified || !email.includes("@")) return { ok: false, reason: "unverified" };
  const name = typeof payload.name === "string" ? payload.name : undefined;
  return { ok: true, identity: { subject, email, name } };
}
