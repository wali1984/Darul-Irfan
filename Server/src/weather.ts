import type { Env } from "./contracts";
import { base64url, json, wholeSeconds } from "./util";

const APPLE = "https://weatherkit.apple.com";
const TTL = 600;
export const WEATHER_ATTRIBUTION = {
  serviceName: "Apple Weather",
  legalURL: `${APPLE}/legal-attribution.html`,
  logoURL: `${APPLE}/assets/branding/en/Apple_Weather_wht_en_3X_090122.png`,
};

/** Only a city-sized grid leaves the phone, and the edge normalizes it again. */
export function weatherGrid(url: URL): { latitude: string; longitude: string } | null {
  function coordinate(name: string, maximum: number): string | null {
    const raw = url.searchParams.get(name);
    if (!raw || !/^-?\d{1,3}(?:\.\d{1,10})?$/.test(raw)) return null;
    const value = Number(raw);
    if (!Number.isFinite(value) || Math.abs(value) > maximum) return null;
    return (Math.round(value * 10) / 10 || 0).toFixed(1);
  }
  const latitude = coordinate("lat", 90), longitude = coordinate("lon", 180);
  return latitude !== null && longitude !== null ? { latitude, longitude } : null;
}

let keptToken: { identity: string; value: string; expires: number } | undefined;
export function resetWeatherToken(): void { keptToken = undefined; }

async function token(env: Env): Promise<string> {
  const { WEATHERKIT_TEAM_ID: team, WEATHERKIT_KEY_ID: kid, WEATHERKIT_SERVICE_ID: service, WEATHERKIT_PRIVATE_KEY: pem } = env;
  if (!team || !kid || !service || !pem) throw new Error("Weather credentials unavailable");
  const now = Math.floor(Date.now() / 1000), identity = `${team}:${kid}:${service}`;
  if (keptToken?.identity === identity && keptToken.expires > now + 60) return keptToken.value;
  const der = Uint8Array.from(atob(pem.replace(/\\n/g, "\n").replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "")), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const expires = now + 1_800;
  const header = base64url(JSON.stringify({ alg: "ES256", kid, id: `${team}.${service}` }));
  const body = base64url(JSON.stringify({ iss: team, iat: now, exp: expires, sub: service }));
  const unsigned = `${header}.${body}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned));
  const value = `${unsigned}.${base64url(signature)}`;
  keptToken = { identity, value, expires };
  return value;
}

export interface CityWeather {
  temperatureCelsius: number;
  feelsLikeCelsius: number;
  humidity: number;
  conditionCode: string;
  isDaylight: boolean;
  observedAt: string;
  expiresAt: string;
  attribution: typeof WEATHER_ATTRIBUTION;
}

/** Reject incomplete, invalid, stale, or future readings instead of inventing 0°. */
export function parseCityWeather(payload: unknown, now = Date.now()): CityWeather | null {
  if (!payload || typeof payload !== "object") return null;
  const current = (payload as { currentWeather?: Record<string, unknown> }).currentWeather;
  if (!current || typeof current.temperature !== "number" || !Number.isFinite(current.temperature) || current.temperature < -100 || current.temperature > 70
      || typeof current.temperatureApparent !== "number" || !Number.isFinite(current.temperatureApparent)
      || typeof current.humidity !== "number" || !Number.isFinite(current.humidity) || current.humidity < 0 || current.humidity > 1
      || typeof current.daylight !== "boolean" || typeof current.asOf !== "string") return null;
  const observed = Date.parse(current.asOf);
  if (!Number.isFinite(observed) || observed < now - 3_600_000 || observed > now + 300_000) return null;
  return {
    temperatureCelsius: current.temperature, feelsLikeCelsius: current.temperatureApparent,
    humidity: current.humidity, conditionCode: typeof current.conditionCode === "string" ? current.conditionCode.slice(0, 60) : "Unknown",
    isDaylight: current.daylight, observedAt: wholeSeconds(new Date(observed)), expiresAt: wholeSeconds(new Date(now + TTL * 1000)),
    attribution: WEATHER_ATTRIBUTION,
  };
}

/** GET /v1/weather/current: the signing key and developer token stay in the Worker. */
export async function currentWeather(request: Request, env: Env, allowMiss: () => Promise<boolean> = async () => true): Promise<Response> {
  const grid = weatherGrid(new URL(request.url));
  if (!grid) return json({ error: "Invalid city coordinates" }, { status: 400 });
  if (!env.WEATHERKIT_TEAM_ID || !env.WEATHERKIT_KEY_ID || !env.WEATHERKIT_SERVICE_ID || !env.WEATHERKIT_PRIVATE_KEY)
    return json({ error: "Weather is unavailable" }, { status: 503, headers: { "retry-after": "300" } });
  const key = new Request(`${env.PUBLIC_BASE_URL || "https://weather-cache.invalid"}/v1/weather/current?lat=${grid.latitude}&lon=${grid.longitude}`);
  const cache = typeof caches !== "undefined" ? await caches.open("city-weather-v1").catch(() => undefined) : undefined;
  const cached = await cache?.match(key).catch(() => undefined);
  if (cached) return new Response(cached.body, cached);
  if (!await allowMiss()) return json({ error: "Weather is temporarily unavailable" }, { status: 429, headers: { "retry-after": "600" } });
  try {
    const response = await fetch(`${APPLE}/api/v1/weather/en-US/${grid.latitude}/${grid.longitude}?dataSets=currentWeather`, {
      headers: { authorization: `Bearer ${await token(env)}` }, signal: AbortSignal.timeout(8_000),
    });
    if (!response.ok) return json({ error: "Weather is unavailable" }, { status: 503, headers: { "retry-after": "300" } });
    const value = parseCityWeather(await response.json());
    if (!value) return json({ error: "Weather is unavailable" }, { status: 503 });
    const answer = json(value, { headers: { "cache-control": `public, max-age=${TTL}` } });
    await cache?.put(key, answer.clone()).catch(() => undefined);
    return answer;
  } catch {
    return json({ error: "Weather is unavailable" }, { status: 503, headers: { "retry-after": "300" } });
  }
}
