import { afterEach, describe, expect, it, vi } from "vitest";
import { nearbyMasjids } from "../src/nearbyMasjids";
import type { Env } from "../src/contracts";
import { sqliteD1 } from "./sqlite-d1";

const request = (query = "lat=31.52&lon=74.35&lang=ur") => new Request(`https://example.test/v1/masjids/nearby?${query}`);
afterEach(() => vi.unstubAllGlobals());
describe("nearby masjid provider", () => {
  it("cancels oversized streamed responses without retrying or refunding capacity", async () => {
    const { db, raw } = sqliteD1();
    const cancel = vi.fn();
    const fetcher = vi.fn(async () => new Response(new ReadableStream({
      pull(controller) { controller.enqueue(new Uint8Array(64 * 1024)); }, cancel,
    }), { headers: { "Content-Length": "2" } }));
    vi.stubGlobal("fetch", fetcher);
    const env = { DB: db, PLACES_ENABLED: "true", PLACES_API_KEY: "test",
      PLACES_DAILY_LIMIT: "1", PLACES_MONTHLY_LIMIT: "1" } as Env;
    try {
      const result = await nearbyMasjids(request(), env, async () => true);
      expect(result.status).toBe(503);
      expect(cancel).toHaveBeenCalledTimes(1);
      expect((await nearbyMasjids(request(), env, async () => true)).status).toBe(429);
      expect(fetcher).toHaveBeenCalledTimes(1);
    } finally { raw.close(); }
  });
  it("distinguishes valid empty results from malformed bodies and duplicate place identities", async () => {
    const { db, raw } = sqliteD1();
    const env = { DB: db, PLACES_ENABLED: "true", PLACES_API_KEY: "test",
      PLACES_DAILY_LIMIT: "20", PLACES_MONTHLY_LIMIT: "20" } as Env;
    const place = { id: "same", displayName: { text: "Masjid" }, location: { latitude: 31, longitude: 74 } };
    const bodies = [null, [], { places: "invalid" }, { places: [{ ...place, location: { latitude: 91, longitude: 0 } }] },
      { places: [place, place] }, {}, { places: [] }];
    const fetcher = vi.fn(async () => Response.json(bodies.shift()));
    vi.stubGlobal("fetch", fetcher);
    try {
      for (let i = 0; i < 5; i++) expect((await nearbyMasjids(request(), env, async () => true)).status).toBe(503);
      for (let i = 0; i < 2; i++) {
        const result = await nearbyMasjids(request(), env, async () => true);
        expect(result.status).toBe(200);
        expect(await result.json()).toMatchObject({ items: [], attribution: "Google Maps" });
      }
    } finally { raw.close(); }
  });
  it("does not spend the shared allowance when the caller rate limit denies access", async () => {
    const { db, raw } = sqliteD1();
    const fetcher = vi.fn(); vi.stubGlobal("fetch", fetcher);
    try {
      const result = await nearbyMasjids(request(), { DB: db, PLACES_ENABLED: "true", PLACES_API_KEY: "test",
        PLACES_DAILY_LIMIT: "1", PLACES_MONTHLY_LIMIT: "1" } as Env, async () => false);
      expect(result.status).toBe(429); expect(fetcher).not.toHaveBeenCalled();
      expect(raw.prepare("SELECT COUNT(*) AS count FROM nearby_request_budget").get()).toMatchObject({ count: 0 });
    } finally { raw.close(); }
  });
  it("makes no upstream request for disabled service or invalid coordinates", async () => {
    const fetcher = vi.fn(); vi.stubGlobal("fetch", fetcher);
    expect((await nearbyMasjids(request(), {} as Env, async () => true)).status).toBe(503);
    for (const query of ["", "lat=&lon=0", "lat=91&lon=0", "lat=0&lon=181", "lat=NaN&lon=0"])
      expect((await nearbyMasjids(request(query), {} as Env, async () => true)).status).toBe(400);
    expect(fetcher).not.toHaveBeenCalled();
  });
  it("rejects missing, fractional and over-ceiling allocations before spending or fetching", async () => {
    const { db, raw } = sqliteD1();
    const fetcher = vi.fn(); vi.stubGlobal("fetch", fetcher);
    const allowed = vi.fn(async () => true);
    const invalid = [
      [undefined, "4500"], ["150", undefined], ["", "4500"], ["150", ""],
      ["0", "4500"], ["150", "0"], ["151", "4500"], ["150", "4501"],
      ["1.5", "4500"], ["150", "1.5"], ["NaN", "4500"], ["150", "Infinity"],
    ];
    try {
      for (const [daily, monthly] of invalid) {
        const result = await nearbyMasjids(
          request("lat=31.52&lon=74.35&PLACES_DAILY_LIMIT=1&PLACES_MONTHLY_LIMIT=1"),
          { DB: db, PLACES_ENABLED: "true", PLACES_API_KEY: "test",
            PLACES_DAILY_LIMIT: daily, PLACES_MONTHLY_LIMIT: monthly } as Env, allowed);
        expect(result.status).toBe(503);
      }
      expect(allowed).not.toHaveBeenCalled();
      expect(fetcher).not.toHaveBeenCalled();
      expect(raw.prepare("SELECT COUNT(*) AS count FROM nearby_request_budget").get()).toMatchObject({ count: 0 });
    } finally { raw.close(); }
  });
  it("reserves capacity before sending a fixed Pro-only request and returns attribution", async () => {
    const { db, raw } = sqliteD1();
    const env = { DB: db, PLACES_ENABLED: "true", PLACES_API_KEY: "secret-test",
      PLACES_DAILY_LIMIT: "1", PLACES_MONTHLY_LIMIT: "2" } as Env;
    const fetcher = vi.fn(async (_url: unknown, init: RequestInit) => {
      expect(raw.prepare("SELECT month_used FROM nearby_request_budget").get()).toMatchObject({ month_used: 1 });
      expect(JSON.parse(init.body as string)).toMatchObject({ includedTypes: ["mosque"], rankPreference: "POPULARITY", languageCode: "ur" });
      expect(new Headers(init.headers).get("X-Goog-FieldMask")).toBe(
        "places.id,places.displayName,places.formattedAddress,places.location,places.attributions");
      return Response.json({ places: [{ id: "place-one", displayName: { text: "Masjid" },
        location: { latitude: 31.52, longitude: 74.35 }, attributions: [{ provider: "Source", providerUri: "https://example.test" }] }] });
    });
    vi.stubGlobal("fetch", fetcher);
    try {
      const result = await nearbyMasjids(request(), env, async () => true);
      expect(result.status).toBe(200); expect(result.headers.get("Cache-Control")).toBe("no-store");
      const text = await result.text(); expect(text).not.toContain("secret-test");
      expect(JSON.parse(text)).toMatchObject({ attribution: "Google Maps", items: [{ id: "place-one", name: "Masjid", attributions: [{ provider: "Source" }] }] });
      expect((await nearbyMasjids(request(), env, async () => true)).status).toBe(429);
      expect(fetcher).toHaveBeenCalledTimes(1);
    } finally { raw.close(); }
  });
  it("drops places stacked on one placeholder point and lists the rest nearest first", async () => {
    const { db, raw } = sqliteD1();
    const env = { DB: db, PLACES_ENABLED: "true", PLACES_API_KEY: "test",
      PLACES_DAILY_LIMIT: "1", PLACES_MONTHLY_LIMIT: "1" } as Env;
    const at = (id: string, latitude: number, longitude: number) =>
      ({ id, displayName: { text: id }, location: { latitude, longitude } });
    vi.stubGlobal("fetch", vi.fn(async () => Response.json({ places: [
      at("far", 31.60, 74.35), at("pin-1", 31.52004, 74.35004), at("pin-2", 31.52004, 74.35004),
      at("pin-3", 31.52004, 74.35004), at("near", 31.53, 74.35),
    ] })));
    try {
      const result = await nearbyMasjids(request(), env, async () => true);
      expect((await result.json() as { items: { id: string }[] }).items.map(item => item.id)).toEqual(["near", "far"]);
    } finally { raw.close(); }
  });
  it("does not refund or retry provider failures and never exposes provider error text", async () => {
    const { db, raw } = sqliteD1();
    const env = { DB: db, PLACES_ENABLED: "true", PLACES_API_KEY: "test",
      PLACES_DAILY_LIMIT: "1", PLACES_MONTHLY_LIMIT: "1" } as Env;
    const fetcher = vi.fn(async () => new Response("sensitive provider diagnostic", { status: 500 }));
    vi.stubGlobal("fetch", fetcher);
    try {
      const result = await nearbyMasjids(request(), env, async () => true);
      expect(result.status).toBe(503); expect(await result.text()).not.toContain("sensitive");
      expect((await nearbyMasjids(request(), env, async () => true)).status).toBe(429);
      expect(fetcher).toHaveBeenCalledTimes(1);
    } finally { raw.close(); }
  });
});
