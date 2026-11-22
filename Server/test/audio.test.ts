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
  it("returns an empty manifest until audio is uploaded, then the uploaded list", async () => {
    const empty = await (await get(envWith({}), "/v1/audio/quran/manifest")).json() as Manifest;
    expect(empty).toEqual({ version: 0, revision: phoneTag({}), voices: {}, editions: {} });
    const manifest = { version: 3, voices: { ur: { name: "Some Reader" } }, editions: { "akram-ut-tarajum-ur": { translation: ["001001"] } } };
    const loaded = await (await get(envWith({ "audio/quran/manifest.json": JSON.stringify(manifest) }), "/v1/audio/quran/manifest")).json() as Manifest;
    expect(loaded.version).toBe(3);
    expect(loaded.editions).toEqual(manifest.editions);
  });
});

// What the released apps do with the list: iOS decodes exactly this shape
// (and refuses the list without it), and iOS and Android both hash the
// voices' names - 64-bit FNV-1a, base 36 - to name the folder of kept copies.
interface Manifest { version: number; revision: string; voices: Record<string, { name: string }>; editions: Record<string, Record<string, string[]>> }

function fnv36(text: string): string {
  let hash = 0xcbf29ce484222325n;
  for (const byte of new TextEncoder().encode(text)) hash = BigInt.asUintN(64, (hash ^ BigInt(byte)) * 0x100000001b3n);
  return hash.toString(36);
}
const phoneTag = (voices: Record<string, { name: string }>): string =>
  fnv36(Object.keys(voices).sort().map(language => `${language}=${voices[language]?.name ?? ""}`).join(";"));

const stored = (voices: unknown, extra: Record<string, unknown> = {}) => JSON.stringify({
  version: 6231, voices, editions: { "akram-ut-tarajum-ur": { translation: ["001001", "001002"] } }, ...extra,
});
const served = async (body: string) => {
  const response = await get(envWith({ "audio/quran/manifest.json": body }), "/v1/audio/quran/manifest");
  const text = await response.text();
  return { response, text, manifest: JSON.parse(text) as Manifest };
};

describe("the narration list the apps are sent", () => {
  it("carries a revision and plain marks, never what storage says about a voice", async () => {
    const { response, text, manifest } = await served(stored(
      { ur: { name: "Some Reader, made with Some Tool · rev 3" } }, { note: "Some Tool", credits: ["Some Reader"] }));
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("public, max-age=300");
    expect(Object.keys(manifest).sort()).toEqual(["editions", "revision", "version", "voices"]);
    expect(manifest.version).toBe(6231);
    expect(manifest.editions).toEqual({ "akram-ut-tarajum-ur": { translation: ["001001", "001002"] } });
    expect(Object.keys(manifest.voices)).toEqual(["ur"]);
    expect(manifest.voices.ur?.name).toMatch(/^r[0-9a-z]{1,13}$/);
    expect(manifest.revision).toMatch(/^[0-9a-z]{1,13}$/);
    expect(text).not.toMatch(/Reader|Tool|rev 3|note|credits/);
  });

  it("gives the revision the released apps already work out for themselves", async () => {
    // The hash here is the phones' own: 64-bit FNV-1a, checked against its published values.
    expect(fnv36("")).toBe(0xcbf29ce484222325n.toString(36));
    expect(fnv36("a")).toBe(0xaf63dc4c8601ec8cn.toString(36));
    const { manifest } = await served(stored({ ur: { name: "Some Reader" }, en: { name: "Another Reader" } }));
    expect(Object.keys(manifest.voices)).toEqual(["en", "ur"]);
    expect(manifest.revision).toBe(phoneTag(manifest.voices));
  });

  it("keeps the revision while nothing is re-made, and changes it when something is", async () => {
    const first = (await served(stored({ ur: { name: "Some Reader · rev 2" } }))).manifest;
    const again = (await served(stored({ ur: { name: "Some Reader · rev 2" } }, { version: 7000 }))).manifest;
    const remade = (await served(stored({ ur: { name: "Some Reader · rev 3" } }))).manifest;
    expect(again.revision).toBe(first.revision);
    expect(again.voices).toEqual(first.voices);
    expect(remade.revision).not.toBe(first.revision);
    expect(phoneTag(remade.voices)).not.toBe(phoneTag(first.voices));
  });

  it("follows a revision written into the stored list, for old and new apps alike", async () => {
    const two = await served(stored({ ur: { name: "r" } }, { revision: "2" }));
    const three = await served(stored({ ur: { name: "r" } }, { revision: 3 }));
    expect(three.manifest.revision).not.toBe(two.manifest.revision);
    expect(phoneTag(three.manifest.voices)).not.toBe(phoneTag(two.manifest.voices));
    expect(three.manifest.revision).toBe(phoneTag(three.manifest.voices));
    const bare = await served(stored({}, { revision: "internal label" }));
    expect(bare.manifest.voices).toEqual({});
    expect(bare.text).not.toContain("internal label");
    expect(bare.manifest.revision).not.toBe(phoneTag({}));
  });

  it("sends every voice in the shape the released apps decode", async () => {
    const { manifest } = await served(stored({ ur: "Some Reader", en: { label: "Another Reader" }, "not a language": { name: "x" } }));
    expect(Object.keys(manifest.voices)).toEqual(["en", "ur"]);
    for (const voice of Object.values(manifest.voices)) expect(voice).toEqual({ name: expect.stringMatching(/^r[0-9a-z]{1,13}$/) });
    const odd = (await served(JSON.stringify({ version: "many", voices: ["Some Reader"], editions: [] }))).manifest;
    expect(odd).toEqual({ version: 0, revision: phoneTag({}), voices: {}, editions: {} });
  });

  it("lists only files the apps can then fetch, and nothing else stored among them", async () => {
    const { text, manifest } = await served(JSON.stringify({
      version: 4,
      voices: { ur: { name: "Some Reader" } },
      editions: {
        "akram-ut-tarajum-ur": { translation: ["001001", "Some Reader", 7, "001002", "1"], reader: "Some Reader", tafsir: "Some Tool" },
        "akram-ut-tafaseer-ur": { tafsir: ["002001-005"], translation: [], notes: ["Some Tool"] },
        "Some Reader": { translation: ["001001"] },
        "asrar-at-tanzil-en": "Some Tool",
        made: { with: ["Some Tool"] },
      },
    }));
    expect(manifest.editions).toEqual({
      "akram-ut-tarajum-ur": { translation: ["001001", "001002"] },
      "akram-ut-tafaseer-ur": { tafsir: ["002001-005"] },
    });
    expect(text).not.toMatch(/Reader|Tool|notes|made/);
    // Every name listed is one the file route answers for.
    const files: Record<string, Uint8Array> = {};
    const paths: string[] = [];
    for (const [edition, kinds] of Object.entries(manifest.editions)) {
      for (const [kind, names] of Object.entries(kinds)) for (const name of names) paths.push(`${edition}/${kind}/${name}.mp3`);
    }
    for (const path of paths) files[`audio/quran/${path}`] = new Uint8Array([1]);
    expect(paths).toHaveLength(3);
    for (const path of paths) expect((await get(envWith(files), `/v1/audio/quran/${path}`)).status).toBe(200);
  });

  it("changes a language's mark when anything stored for it changes", async () => {
    const first = (await served(stored({ ur: { name: "Some Reader", made: 2 } }))).manifest;
    const same = (await served(stored({ ur: { name: "Some Reader", made: 2 } }))).manifest;
    const remade = await served(stored({ ur: { name: "Some Reader", made: 3 } }));
    expect(same.voices).toEqual(first.voices);
    expect(remade.manifest.voices.ur?.name).not.toBe(first.voices.ur?.name);
    expect(remade.manifest.revision).not.toBe(first.revision);
    expect(remade.manifest.revision).toBe(phoneTag(remade.manifest.voices));
    expect(remade.text).not.toMatch(/Reader|made/);
  });

  it("answers that the list is unavailable, not an empty list, when the stored one cannot be read", async () => {
    const response = await get(envWith({ "audio/quran/manifest.json": "{\"version\":3,\"voices\":{\"ur\":{\"name\":\"Some Rea" }), "/v1/audio/quran/manifest");
    expect(response.status).toBe(503);
    expect(await response.text()).not.toContain("Some Rea");
  });
});

describe("narrated Qur'an audio on the web", () => {
  it("lets the web app read the manifest across origins", async () => {
    const response = await get(envWith({}), "/v1/audio/quran/manifest");
    expect(response.headers.get("access-control-allow-origin")).toBe("*");
  });
});
