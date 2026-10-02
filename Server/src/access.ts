import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";
import type { Env } from "./contracts";

const keySets = new Map<string, ReturnType<typeof createRemoteJWKSet>>();

/** An email header is not authentication: verify Access's signed assertion. */
export async function authenticatedActor(
  request: Request,
  env: Pick<Env, "ACCESS_TEAM_DOMAIN" | "ACCESS_AUD">,
  resolveKey?: JWTVerifyGetKey,
): Promise<string | null> {
  const domain = env.ACCESS_TEAM_DOMAIN;
  const audience = env.ACCESS_AUD;
  const assertion = request.headers.get("cf-access-jwt-assertion");
  if (!domain || !/^[a-z0-9-]+\.cloudflareaccess\.com$/.test(domain) || !audience || !assertion) return null;
  try {
    const issuer = `https://${domain}`;
    let keys = resolveKey ?? keySets.get(issuer);
    if (!keys) {
      const remoteKeys = createRemoteJWKSet(new URL(`${issuer}/cdn-cgi/access/certs`));
      keySets.set(issuer, remoteKeys);
      keys = remoteKeys;
    }
    const { payload } = await jwtVerify(assertion, keys, {
      issuer, audience, algorithms: ["RS256"], requiredClaims: ["exp", "iat", "sub", "email"],
    });
    return typeof payload.email === "string" && payload.email.includes("@")
      ? payload.email.trim().toLowerCase() : null;
  } catch {
    return null;
  }
}
