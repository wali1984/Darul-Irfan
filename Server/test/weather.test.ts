import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { currentWeather, parseCityWeather, resetWeatherToken, weatherGrid } from "../src/weather";
import type { Env } from "../src/contracts";

const now = Date.parse("2026-10-31T01:00:00Z");
const reading = () => ({ currentWeather: { temperature: 23.5, temperatureApparent: 24.2, humidity: 0.62, daylight: false, asOf: new Date(now).toISOString(), conditionCode: "Clear" } });
const request = (query = "lat=31.52&lon=74.35") => new Request(`https://api.example.com/v1/weather/current?${query}`);
beforeEach(() => { resetWeatherToken(); vi.spyOn(Date, "now").mockReturnValue(now); });
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

async function credentials(): Promise<Env> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`;
  return { PUBLIC_BASE_URL: "https://api.example.com", WEATHERKIT_TEAM_ID: "TESTTEAM01", WEATHERKIT_KEY_ID: "TESTKEY001", WEATHERKIT_SERVICE_ID: "com.example.weather", WEATHERKIT_PRIVATE_KEY: pem } as Env;
}

describe("city weather", () => {
  it("rounds to a city grid and rejects invalid or missing coordinates", () => {
    expect(weatherGrid(new URL(request().url))).toEqual({ latitude: "31.5", longitude: "74.4" });
    expect(weatherGrid(new URL(request("lat=-0.04&lon=0").url))).toEqual({ latitude: "0.0", longitude: "0.0" });
    for (const query of ["lat=&lon=0", "lat=91&lon=0", "lat=0&lon=181", "lat=NaN&lon=0", "lat=https://bad&lon=0", "lat=0"]) expect(weatherGrid(new URL(request(query).url))).toBeNull();
  });
  it("does not turn missing, stale, future, or invalid provider data into zero degrees", () => {
    expect(parseCityWeather(reading(), now)?.temperatureCelsius).toBe(23.5);
    expect(parseCityWeather({}, now)).toBeNull();
    expect(parseCityWeather(reading(), now + 3_600_001)).toBeNull();
    expect(parseCityWeather(reading(), now - 300_001)).toBeNull();
    expect(parseCityWeather({ currentWeather: { ...reading().currentWeather, temperature: null } }, now)).toBeNull();
    expect(parseCityWeather({ currentWeather: { ...reading().currentWeather, humidity: 1.1 } }, now)).toBeNull();
  });
  it("answers safely until credentials are configured", async () => {
    const fetcher = vi.fn(); vi.stubGlobal("fetch", fetcher);
    expect((await currentWeather(request(), {} as Env)).status).toBe(503);
    expect(fetcher).not.toHaveBeenCalled();
  });
  it("signs only on the server, uses rounded coordinates, and keeps secrets out of the answer", async () => {
    const env = await credentials();
    const fetcher = vi.fn(async (_url: unknown, _init: unknown) => new Response(JSON.stringify(reading())));
    vi.stubGlobal("fetch", fetcher);
    const response = await currentWeather(request(), env);
    expect(response.status).toBe(200);
    const [url, init] = fetcher.mock.calls[0]!;
    expect(String(url)).toBe("https://weatherkit.apple.com/api/v1/weather/en-US/31.5/74.4?dataSets=currentWeather");
    const authorization = (init as RequestInit).headers as Record<string, string>;
    const jwt = authorization.authorization!.slice(7);
    const decode = (part: string) => JSON.parse(atob(part.replace(/-/g, "+").replace(/_/g, "/")));
    expect(decode(jwt.split(".")[1]!)).toMatchObject({ iss: "TESTTEAM01", sub: "com.example.weather", iat: now / 1000, exp: now / 1000 + 1800 });
    const text = await response.text();
    expect(text).not.toContain(jwt); expect(text).not.toContain("PRIVATE KEY"); expect(text).not.toContain("TESTKEY001");
    expect(JSON.parse(text).attribution.legalURL).toBe("https://weatherkit.apple.com/legal-attribution.html");
  });
  it("does not expose or cache a provider failure or a quota refusal", async () => {
    const env = await credentials();
    vi.stubGlobal("fetch", vi.fn(async () => new Response('{"reason":"NOT_ENABLED"}', { status: 401 })));
    const failure = await currentWeather(request(), env);
    expect(failure.status).toBe(503); expect(await failure.text()).not.toContain("NOT_ENABLED");
    expect((await currentWeather(request(), env, async () => false)).status).toBe(429);
  });
  it("serves a normalized cached city without consuming another provider call", async () => {
    const env = await credentials(); const fetcher = vi.fn(); vi.stubGlobal("fetch", fetcher);
    const cache = { match: vi.fn(async () => new Response(JSON.stringify(parseCityWeather(reading(), now)))), put: vi.fn() };
    vi.stubGlobal("caches", { open: vi.fn(async () => cache) });
    const quota = vi.fn(async () => false);
    expect((await currentWeather(request(), env, quota)).status).toBe(200);
    expect(cache.match.mock.calls[0]).toBeDefined(); expect(fetcher).not.toHaveBeenCalled(); expect(quota).not.toHaveBeenCalled();
  });
});
