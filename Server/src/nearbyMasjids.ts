import type { Env } from "./contracts";
import { reserveNearbyRequest } from "./nearbyBudget";
import { json } from "./util";

const fields = "places.id,places.displayName,places.formattedAddress,places.location,places.attributions";
const response = (body: unknown, status = 200) => {
  const result = json(body, { status });
  result.headers.set("Cache-Control", "no-store");
  return result;
};
const unavailable = () => response({ error: "nearby_unavailable" }, 503);

// Bound streamed/decompressed data rather than trusting Content-Length.
async function providerJSON(upstream: Response): Promise<unknown> {
  if (!upstream.body) throw new Error("missing_provider_body");
  const reader = upstream.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > 512 * 1024) {
        await reader.cancel();
        throw new Error("provider_body_too_large");
      }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
}

export function nearbyCoordinates(url: URL): { latitude: number; longitude: number } | null {
  const coordinate = (name: string, limit: number) => {
    const value = url.searchParams.get(name);
    if (!value || !/^-?\d{1,3}(?:\.\d{1,10})?$/.test(value)) return null;
    const number = Number(value);
    return Number.isFinite(number) && Math.abs(number) <= limit ? number : null;
  };
  const latitude = coordinate("lat", 90), longitude = coordinate("lon", 180);
  return latitude === null || longitude === null ? null : { latitude, longitude };
}

/** One explicit user search, one Pro-only provider request. No prefetch,
 * persistent content cache, automatic retries, or caller-controlled fields.
 */
export async function nearbyMasjids(request: Request, env: Env,
  allowed: () => Promise<boolean>): Promise<Response> {
  const url = new URL(request.url), center = nearbyCoordinates(url);
  if (!center) return response({ error: "invalid_location" }, 400);
  if (env.PLACES_ENABLED !== "true" || !env.PLACES_API_KEY) return unavailable();
  const daily = Number(env.PLACES_DAILY_LIMIT), monthly = Number(env.PLACES_MONTHLY_LIMIT);
  if (!Number.isInteger(daily) || daily < 1 || daily > 150 ||
      !Number.isInteger(monthly) || monthly < 1 || monthly > 4500) return unavailable();
  try {
    if (!await allowed() || !await reserveNearbyRequest(env.DB, { daily, monthly }))
      return response({ error: "nearby_limit_reached" }, 429);
    // Workers reject redirect: "error" (every call threw, so the route always
    // answered 503); "manual" leaves a redirect as a non-ok response, refused below.
    const upstream = await fetch("https://places.googleapis.com/v1/places:searchNearby", {
      method: "POST", redirect: "manual", signal: AbortSignal.timeout(10_000),
      headers: { "Content-Type": "application/json", "X-Goog-Api-Key": env.PLACES_API_KEY,
        "X-Goog-FieldMask": fields },
      body: JSON.stringify({ includedTypes: ["mosque"], maxResultCount: 20,
        rankPreference: "POPULARITY", languageCode: url.searchParams.get("lang") === "ur" ? "ur" : "en",
        locationRestriction: { circle: { center, radius: 10_000 } } }),
    });
    if (!upstream.ok) { await upstream.body?.cancel(); return unavailable(); }
    const payload = await providerJSON(upstream) as { places?: unknown };
    if (!payload || typeof payload !== "object" || Array.isArray(payload) ||
        (payload.places !== undefined && !Array.isArray(payload.places))) return unavailable();
    const places = (payload.places ?? []) as Record<string, any>[];
    const items = places.slice(0, 20).flatMap(place => {
      if (!place || typeof place.id !== "string" || !place.id ||
          typeof place.displayName?.text !== "string" || !place.displayName.text.trim() ||
          typeof place.location?.latitude !== "number" || !Number.isFinite(place.location.latitude) ||
          Math.abs(place.location.latitude) > 90 || typeof place.location?.longitude !== "number" ||
          !Number.isFinite(place.location.longitude) || Math.abs(place.location.longitude) > 180) return [];
      const attributions = Array.isArray(place.attributions) ? place.attributions.flatMap((item: any) => {
        if (typeof item?.provider !== "string") return [];
        let uri: string | undefined;
        try { const parsed = new URL(item.providerUri); if (parsed.protocol === "https:") uri = parsed.href; } catch { /* name still attributed */ }
        return [{ provider: item.provider, ...(uri ? { uri } : {}) }];
      }) : [];
      return [{ id: place.id, name: place.displayName.text,
        address: typeof place.formattedAddress === "string" ? place.formattedAddress : "",
        latitude: place.location.latitude, longitude: place.location.longitude, attributions }];
    });
    if ((places.length && !items.length) || new Set(items.map(item => item.id)).size !== items.length)
      return unavailable();
    return response({ items: placed(items, center), radiusMeters: 10_000, attribution: "Google Maps" });
  } catch { return unavailable(); }
}

/** Google pins places it has no exact spot for to the area's centre, many to
 * one point (19 of Lahore's nearest 20 were there), so a point shared by three
 * or more results is that placeholder, not a masjid's location. Those are
 * dropped; the rest come nearest first. */
function placed<T extends { latitude: number; longitude: number }>(items: T[],
  center: { latitude: number; longitude: number }): T[] {
  const spot = (item: T) => `${item.latitude.toFixed(4)},${item.longitude.toFixed(4)}`;
  const counts = new Map<string, number>();
  for (const item of items) counts.set(spot(item), (counts.get(spot(item)) ?? 0) + 1);
  const scale = Math.cos(center.latitude * Math.PI / 180);
  const distance = (item: T) =>
    (item.latitude - center.latitude) ** 2 + ((item.longitude - center.longitude) * scale) ** 2;
  return items.filter(item => counts.get(spot(item))! < 3).sort((a, b) => distance(a) - distance(b));
}
