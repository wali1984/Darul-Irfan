import { describe, expect, it } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";

const SECRET = "test-app-secret";
const CHANNEL = "https://whatsapp.com/channel/official";

function envWith(recorded: unknown[], overrides: Partial<Env> = {}): Env {
  const statement = {
    bind: (...values: unknown[]) => { recorded.push(values); return statement; },
    first: async () => null,
    all: async () => ({ results: [] }),
    run: async () => ({}),
  };
  return {
    DB: { prepare: () => statement },
    WHATSAPP_APP_SECRET: SECRET,
    WHATSAPP_VERIFY_TOKEN: "verify-me",
    WHATSAPP_ALLOWED_SENDERS: "923001234567, +923009999999",
    WHATSAPP_CHANNEL_URL: CHANNEL,
    ...overrides,
  } as unknown as Env;
}

async function sign(body: string, secret = SECRET): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signed = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body));
  return "sha256=" + [...new Uint8Array(signed)].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

const message = (from: string, text: string, id = "wamid.1", type = "text") => JSON.stringify({
  entry: [{ changes: [{ value: { messages: [{ from, id, type, timestamp: "1760000000", text: { body: text } }] } }] }],
});

async function post(body: string, env: Env, signature?: string): Promise<Response> {
  return worker.fetch(new Request("https://api.example.com/v1/whatsapp", {
    method: "POST", body, headers: { "x-hub-signature-256": signature ?? await sign(body) },
  }), env);
}

describe("WhatsApp forwarding", () => {
  it("echoes the challenge only for the configured verify token", async () => {
    const env = envWith([]);
    const ok = await worker.fetch(new Request("https://api.example.com/v1/whatsapp?hub.mode=subscribe&hub.verify_token=verify-me&hub.challenge=12345"), env);
    expect(ok.status).toBe(200);
    expect(await ok.text()).toBe("12345");
    const wrong = await worker.fetch(new Request("https://api.example.com/v1/whatsapp?hub.mode=subscribe&hub.verify_token=guess&hub.challenge=12345"), env);
    expect(wrong.status).toBe(403);
  });

  it("rejects a payload whose signature does not match the body", async () => {
    const body = message("923001234567", "Official announcement");
    const response = await post(body, envWith([]), await sign("a different body"));
    expect(response.status).toBe(401);
  });

  it("rejects a signature made with the wrong secret", async () => {
    const body = message("923001234567", "Official announcement");
    const response = await post(body, envWith([]), await sign(body, "attacker-secret"));
    expect(response.status).toBe(401);
  });

  it("records a trusted admin's text as a draft awaiting approval", async () => {
    const recorded: unknown[] = [];
    const response = await post(message("923001234567", "Zikr majlis on Friday"), envWith(recorded));
    expect(response.status).toBe(200);
    expect((await response.json() as { recorded: number }).recorded).toBe(1);
    const row = recorded[0] as unknown[];
    expect(row[0]).toBe("whatsapp:wamid.1");
    expect(row[1]).toBe("Zikr majlis on Friday");
    expect(row[3]).toBe(CHANNEL);
  });

  it("accepts a sender configured with a leading plus", async () => {
    const recorded: unknown[] = [];
    const response = await post(message("923009999999", "Second admin"), envWith(recorded));
    expect((await response.json() as { recorded: number }).recorded).toBe(1);
  });

  it("ignores a message from a number that is not an approved admin", async () => {
    const recorded: unknown[] = [];
    const response = await post(message("923005555555", "Not from an admin"), envWith(recorded));
    expect(response.status).toBe(200);
    expect((await response.json() as { recorded: number }).recorded).toBe(0);
    expect(recorded).toHaveLength(0);
  });

  it.each(["image", "audio", "document"])("ignores %s messages, which need an authenticated media fetch", async type => {
    const recorded: unknown[] = [];
    const body = JSON.stringify({ entry: [{ changes: [{ value: { messages: [{ from: "923001234567", id: "wamid.2", type, timestamp: "1760000000" }] } }] }] });
    const response = await post(body, envWith(recorded));
    expect((await response.json() as { recorded: number }).recorded).toBe(0);
  });

  it("reports unconfigured ingestion instead of accepting unverifiable posts", async () => {
    const body = message("923001234567", "Anything");
    const response = await post(body, envWith([], { WHATSAPP_APP_SECRET: undefined }));
    expect(response.status).toBe(503);
  });

  it("never grants the webhook browser CORS permission", async () => {
    const response = await post(message("923001234567", "Official"), envWith([]));
    expect(response.headers.has("access-control-allow-origin")).toBe(false);
  });
});
