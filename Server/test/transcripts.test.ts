import { gzipSync } from "node:zlib";
import { describe, expect, it } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { isTranscriptID } from "../src/transcripts";

const statement = { bind: () => statement, first: async () => null, all: async () => ({ results: [] }) };

function bucketWith(files: Record<string, Uint8Array>) {
  const asked: string[] = [];
  return {
    asked,
    async head(key: string) { asked.push(key); const f = files[key]; return f === undefined ? null : { size: f.length, httpEtag: "\"e1\"" }; },
    async get(key: string) {
      asked.push(key);
      const f = files[key]; if (f === undefined) return null;
      return { size: f.length, httpEtag: "\"e1\"", body: f };
    },
  };
}
const envWith = (bucket: ReturnType<typeof bucketWith>) => ({ DB: { prepare: () => statement }, MEDIA: bucket }) as unknown as Env;
const request = (env: Env, path: string, method = "GET") =>
  worker.fetch(new Request(`https://api.example.com${path}`, { method }), env);

const ID = "lecture-1-2017-01-02-surah-al-a-la-ayat-4-to-8";
const document = {
  id: ID, title: "Surah Al-A'la Ayat 4 to 8", language: "ur", verification: "machine",
  segments: [
    { s: 0, e: 6, t: "بِسْمِ اللهِ الرَّحْمٰنِ الرَّحِيْمِ", kind: "quran", ref: "1:1" },
    { s: 95.73, e: 99.84, t: "وہ وہ ذات ہے", kind: "speech" },
    { s: 100, e: 101, kind: "arabicUnverified" },
  ],
};

describe("bayan transcripts", () => {
  it("serves the stored gzip as JSON, publicly, with a long edge cache", async () => {
    const bucket = bucketWith({ [`transcripts/${ID}.json.gz`]: gzipSync(JSON.stringify(document)) });
    const response = await request(envWith(bucket), `/v1/transcripts/${ID}`);
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("application/json; charset=utf-8");
    expect(response.headers.get("cache-control")).toContain("s-maxage=2592000");
    expect(response.headers.get("etag")).toBe("\"e1\"");
    expect(response.headers.get("access-control-allow-origin")).toBe("*");
    expect(await response.json()).toEqual(document);
    expect(bucket.asked).toEqual([`transcripts/${ID}.json.gz`]);
  });

  it("answers HEAD without a body", async () => {
    const bucket = bucketWith({ [`transcripts/${ID}.json.gz`]: gzipSync("{}") });
    const response = await request(envWith(bucket), `/v1/transcripts/${ID}`, "HEAD");
    expect(response.status).toBe(200);
    expect(await response.text()).toBe("");
  });

  it("is 404, briefly cached, for a bayan without a transcript", async () => {
    const response = await request(envWith(bucketWith({})), "/v1/transcripts/lecture-2-none");
    expect(response.status).toBe(404);
    expect(response.headers.get("cache-control")).toBe("public, max-age=300");
  });

  it.each([
    "/v1/transcripts/",
    "/v1/transcripts/..%2Fapp%2Freleases",
    "/v1/transcripts/../app/releases.json",
    "/v1/transcripts/Lecture-1",
    "/v1/transcripts/lecture-1.json.gz",
    "/v1/transcripts/a/b",
    `/v1/transcripts/${"a".repeat(161)}`,
  ])("refuses %s without reading the bucket", async (path) => {
    const bucket = bucketWith({ "app/releases.json": gzipSync("{}") });
    const response = await request(envWith(bucket), path);
    expect(response.status).toBe(404);
    expect(bucket.asked).toEqual([]);
  });

  it("accepts every catalogue id shape and nothing that leaves the folder", () => {
    expect(isTranscriptID(ID)).toBe(true);
    expect(isTranscriptID("video_2024-08-03")).toBe(true);
    expect(isTranscriptID("")).toBe(false);
    expect(isTranscriptID("-x")).toBe(false);
    expect(isTranscriptID("a.b")).toBe(false);
    expect(isTranscriptID("a/b")).toBe(false);
  });

  it("is never served for writes", async () => {
    const bucket = bucketWith({ [`transcripts/${ID}.json.gz`]: gzipSync("{}") });
    const response = await request(envWith(bucket), `/v1/transcripts/${ID}`, "DELETE");
    expect(response.status).not.toBe(200);
    expect(bucket.asked).toEqual([]);
  });
});
