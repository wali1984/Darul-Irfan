import test, { after } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { environment, loadWorker } from "./fixture.mjs";

const fixture = await loadWorker();
after(fixture.close);
const fetchSite = (path = "/", env = environment(), init = {}, host = "oursheikh.wajidali.us") => fixture.worker.fetch(new Request(`https://${host}${path}`, init), env);

test("all five shared hosts remain available while all official hosts stay closed", async () => {
  for (const name of ["oursheikh", "namerica", "uk", "app-demo", "reporting"]) {
    assert.equal((await fetchSite("/", environment(), {}, `${name}.wajidali.us`)).status, 200);
    const closed = await fetchSite("/", environment(() => { throw new Error("Must not call API"); }), {}, `${name}.naqshbandiaowaisiah.us`);
    assert.equal(closed.status, 404); assert.equal(closed.headers.get("x-robots-tag"), "noindex");
  }
});

test("platform outage is unavailable, never a successful all-offline snapshot", async () => {
  const response = await fetchSite("/data.json", environment(async () => { throw new Error("network"); }));
  assert.equal(response.status, 503);
  assert.equal((await response.json()).available, false);
  const malformed = await fetchSite("/data.json", environment(async () => Response.json({ halqahs: {} })));
  assert.equal(malformed.status, 503);
});

test("only same-site configured Halqahs can receive join requests", async () => {
  let called = false;
  const response = await fetchSite("/join/canada", environment(async () => { called = true; return Response.json({}); }), { method: "POST", body: "{}" });
  assert.equal(response.status, 404); assert.equal(called, false);
});

test("public pages use script hashes, canonical URLs and framing protection", async () => {
  const response = await fetchSite("/method-of-zikr?tracking=ignored");
  const body = await response.text(), policy = response.headers.get("content-security-policy");
  assert.match(body, /rel="canonical" href="https:\/\/oursheikh.wajidali.us\/method-of-zikr"/);
  assert.match(body, /property="og:image" content="https:\/\/oursheikh.wajidali.us\/logo.webp"/);
  assert.match(policy, /frame-ancestors 'none'/);
  assert.doesNotMatch(policy.split(";").find(part => part.includes("script-src")), /unsafe-inline/);
  for (const match of body.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)) {
    assert.ok(policy.includes(`'sha256-${createHash("sha256").update(match[1]).digest("base64")}'`));
  }
});

test("invalid routes are 404 and previews cannot change a public host's role", async () => {
  assert.equal((await fetchSite("/does-not-exist")).status, 404);
  const body = await (await fetchSite("/?site=reporting")).text();
  assert.match(body, /Our Sheikh · Naqshbandia Owaisiah/);
  assert.doesNotMatch(body, /id="app"/);
  assert.match(await (await fetchSite("/sitemap.xml")).text(), /method-of-zikr/);
  assert.equal((await fetchSite("/broadcast")).headers.get("x-robots-tag"), "noindex");
});

test("showcase separates supervised preview from available tester entry points", async () => {
  const response = await fetchSite("/", environment(), {}, "app-demo.wajidali.us");
  const body = await response.text();
  assert.match(body, /Unattended operation and stage-response time are not yet verified/);
  assert.doesNotMatch(body, /two to four seconds|The manual steps are gone|the Zikr starts itself/);
  assert.match(body, /href="https:\/\/testflight.apple.com\/join\/keXtV7jF"/);
  assert.match(body, /Google Play internal testing invitation/);
  assert.match(body, /href="https:\/\/reporting.wajidali.us"/);
  assert.match(body, /id="get-started"/);
});

test("showcase HEAD reads metadata only and full responses are not partial", async () => {
  let downloads = 0, heads = 0;
  const env = { ...environment(), MEDIA: {
    head: async () => { heads += 1; return { size: 4 }; },
    get: async (_key, options) => { downloads += 1; return { size: 4, body: options?.range ? "ab" : "abcd", range: options?.range ? { offset: 0, length: 2 } : undefined }; },
  } };
  const head = await fetchSite("/demo/showcase", env, { method: "HEAD" }, "app-demo.wajidali.us");
  assert.equal(head.status, 200); assert.equal(await head.text(), ""); assert.equal(heads, 1); assert.equal(downloads, 0);
  const full = await fetchSite("/demo/showcase", env, {}, "app-demo.wajidali.us");
  assert.equal(full.status, 200); assert.equal(await full.text(), "abcd");
  const partial = await fetchSite("/demo/showcase", env, { headers: { range: "bytes=0-1" } }, "app-demo.wajidali.us");
  assert.equal(partial.status, 206); assert.equal(partial.headers.get("content-range"), "bytes 0-1/4");
});

test("reporting signout clears the cookie even when remote revocation fails", async () => {
  let calls = 0;
  const env = environment(async () => { if (++calls === 1) return Response.json({ sessions: [{ current: true, id: "s1" }] }); throw new Error("network"); });
  const response = await fetchSite("/auth/signout", env, { method: "POST", headers: { cookie: `__Host-di_report=${"a".repeat(64)}` } }, "reporting.wajidali.us");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("set-cookie"), /Max-Age=0/);
  assert.equal((await response.json()).revoked, false);
});

test("reporting rejects cross-origin mutation before any upstream request", async () => {
  let called = false;
  const response = await fetchSite("/auth/start", environment(async () => { called = true; return Response.json({}); }),
    { method: "POST", headers: { origin: "https://other.wajidali.us" } }, "reporting.wajidali.us");
  assert.equal(response.status, 403); assert.equal(called, false);
});

test("expired, malformed or failed auth approvals never set a session cookie", async () => {
  for (const expiresAt of ["invalid", "2020-01-01T00:00:00Z"]) {
    const env = environment(async () => Response.json({ status: "approved", token: "a".repeat(64), expiresAt }));
    const response = await fetchSite("/auth/poll", env, { method: "POST", body: "{}" }, "reporting.wajidali.us");
    assert.equal(response.headers.get("set-cookie"), null);
    assert.equal((await response.json()).status, "expired");
  }
});
