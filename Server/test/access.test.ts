import { describe, expect, it } from "vitest";
import { generateKeyPair, SignJWT } from "jose";
import { authenticatedActor } from "../src/access";
import { adminRequest } from "../src/admin";
import type { Env } from "../src/contracts";

const env = { ACCESS_TEAM_DOMAIN: "example.cloudflareaccess.com", ACCESS_AUD: "staff-app" };
const { privateKey, publicKey } = await generateKeyPair("RS256");
const resolveKey = async () => publicKey;
async function token(options: {audience?: string; issuer?: string; expiry?: string} = {}) {
  return new SignJWT({email: "Editor@example.com"}).setProtectedHeader({alg:"RS256"})
    .setSubject("staff-1").setIssuedAt().setExpirationTime(options.expiry ?? "5m")
    .setIssuer(options.issuer ?? "https://example.cloudflareaccess.com")
    .setAudience(options.audience ?? "staff-app").sign(privateKey);
}
const request = (jwt: string) => new Request("https://api.example.com/admin", {headers:{"cf-access-jwt-assertion":jwt}});

describe("admin authentication", () => {
  it("rejects a forged email header before reading private data", async () => {
    const response = await adminRequest(new Request("https://api.example.com/admin/api/state", {
      headers:{"cf-access-authenticated-user-email":"editor@example.com"},
    }), {} as Env, "/admin/api/state");
    expect(response.status).toBe(401);
  });
  it("fails closed without Access configuration", async () => {
    expect(await authenticatedActor(request(await token()), {}, resolveKey)).toBeNull();
  });
  it("accepts a signed assertion for this application", async () => {
    expect(await authenticatedActor(request(await token()), env, resolveKey)).toBe("editor@example.com");
  });
  it.each([{audience:"another-app"},{issuer:"https://attacker.example"},{expiry:"-1m"}])("rejects invalid claims %j", async options => {
    expect(await authenticatedActor(request(await token(options)), env, resolveKey)).toBeNull();
  });
  it("rejects a forged signature", async () => {
    const jwt = await token();
    const parts = jwt.split("."); parts[2] = "A".repeat(parts[2]!.length);
    expect(await authenticatedActor(request(parts.join(".")), env, resolveKey)).toBeNull();
  });
});
