import type { Env } from "./contracts";

// Which app builds are out, so an app on an older one can offer its user the
// newer (the update banner on Today). TestFlight has no lookup an app can
// ask: Tools/Release/testflight.py announce writes app/releases.json to R2
// once Apple has passed a build for the external testers. An App Store copy
// asks Apple's own lookup instead.

/** GET /v1/app/releases - the newest build out, per platform and channel. */
export async function appReleases(env: Env): Promise<Response> {
  const object = await env.MEDIA?.get("app/releases.json").catch(() => null);
  // A minute at most: the apps check every few minutes while open, and a new
  // release must reach their update banner at once (owner 2026-11-19).
  const headers = { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=60" };
  if (!object) return new Response("{}", { headers });
  return new Response((object as R2ObjectBody).body, { headers });
}
