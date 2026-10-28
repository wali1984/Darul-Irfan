import { describe, expect, it } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";

const statement = { bind: () => statement, first: async () => null, all: async () => ({ results: [] }) };

function bucketWith(files: Record<string, Uint8Array | string>) {
  return {
    async head(key: string) { const f = files[key]; return f === undefined ? null : { size: f.length, httpMetadata: { contentType: "audio/mpeg" } }; },
    async get(key: string, options?: { range?: Headers }) {
      const f = files[key]; if (f === undefined) return null;
      const bytes = typeof f === "string" ? new TextEncoder().encode(f) : f;
      const match = /bytes=(\d+)-(\d*)/.exec(options?.range?.get("range") ?? "");
      const offset = match ? Number(match[1]) : 0; const end = match && match[2] ? Number(match[2]) : bytes.length - 1;
      return { size: bytes.length, httpMetadata: { contentType: "audio/mpeg" }, range: match ? { offset, length: end - offset + 1 } : undefined,
               body: bytes.slice(offset, end + 1) };
    },
  };
}
const envWith = (files: Record<string, Uint8Array | string>) => ({ DB: { prepare: () => statement }, MEDIA: bucketWith(files) }) as unknown as Env;
const get = (env: Env, path: string, headers: Record<string, string> = {}) =>
  worker.fetch(new Request(`https://api.example.com${path}`, { headers }), env);

describe("narrated Qur'an audio", () => {
  it("serves an ayah publicly, in byte ranges, with a long cache", async () => {
    const env = envWith({ "audio/quran/akram-ut-tarajum-ur/translation/067001.mp3": new Uint8Array([1, 2, 3, 4, 5]) });
    const whole = await get(env, "/v1/audio/quran/akram-ut-tarajum-ur/translation/067001.mp3");
    expect(whole.status).toBe(200);
    expect(whole.headers.get("cache-control")).toContain("public");
    const part = await get(env, "/v1/audio/quran/akram-ut-tarajum-ur/translation/067001.mp3", { range: "bytes=1-2" });
    expect(part.status).toBe(206);
    expect(part.headers.get("content-range")).toBe("bytes 1-2/5");
  });
  it("serves a tafsir passage that spans ayat", async () => {
    const env = envWith({ "audio/quran/akram-ut-tafaseer-ur/tafsir/002001-005.mp3": new Uint8Array([9]) });
    expect((await get(env, "/v1/audio/quran/akram-ut-tafaseer-ur/tafsir/002001-005.mp3")).status).toBe(200);
  });
  it.each([
    "/v1/audio/quran/ur-jalandhry/translation/001001.mp3",
    "/v1/audio/quran/akram-ut-tarajum-ur/translation/../../daily/x.mp3",
    "/v1/audio/quran/akram-ut-tarajum-ur/translation/1.mp3",
  ])("refuses %s", async path => {
    expect((await get(envWith({}), path)).status).toBe(404);
  });
  it("returns an empty manifest until audio is uploaded, then the uploaded one", async () => {
    const empty = await (await get(envWith({}), "/v1/audio/quran/manifest")).json() as { editions: object };
    expect(empty.editions).toEqual({});
    const manifest = { version: 3, voices: { ur: "credit" }, editions: { "akram-ut-tarajum-ur": { translation: ["001001"] } } };
    const loaded = await (await get(envWith({ "audio/quran/manifest.json": JSON.stringify(manifest) }), "/v1/audio/quran/manifest")).json();
    expect(loaded).toEqual(manifest);
  });
});

describe("narrated Qur'an audio on the web", () => {
  it("lets the web app read the manifest across origins", async () => {
    const response = await get(envWith({}), "/v1/audio/quran/manifest");
    expect(response.headers.get("access-control-allow-origin")).toBe("*");
  });
});
