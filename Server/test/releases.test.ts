import { describe, expect, it } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";

const statement = { bind: () => statement, first: async () => null, all: async () => ({ results: [] }) };
const envWith = (files: Record<string, string>) => ({
  DB: { prepare: () => statement },
  MEDIA: { async get(key: string) { return key in files ? { body: new TextEncoder().encode(files[key]) } : null; } },
}) as unknown as Env;
const get = (env: Env) => worker.fetch(new Request("https://api.example.com/v1/app/releases"), env);

describe("app releases for the update banner", () => {
  it("is an empty object until a build is announced", async () => {
    const response = await get(envWith({}));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({});
  });
  it("serves the announced build publicly, briefly cached", async () => {
    const announced = { ios: { testflight: { version: "1.11.1", build: 68, releasedAt: "2026-10-29T17:39:00Z" } } };
    const response = await get(envWith({ "app/releases.json": JSON.stringify(announced) }));
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("public, max-age=300");
    expect(await response.json()).toEqual(announced);
  });
});
