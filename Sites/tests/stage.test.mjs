// The live stage's markup on every site and on /broadcast, without a browser.
//   node --test Sites/tests/stage.test.mjs
import test, { after } from "node:test";
import assert from "node:assert/strict";
import { loadSites, mockPlatform } from "./stage-harness.mjs";

const sites = await loadSites();
after(sites.close);
const platform = mockPlatform();
const get = async (host, path = "/") => (await sites.worker.fetch(new Request(`https://${host}${path}`), platform.env)).text();
const scripts = body => [...body.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].filter(m => !m[0].includes("application/json")).map(m => m[1]);

test("the order of the Zikr in its parts is exactly the app's stage order", async () => {
  const body = await get("oursheikh.wajidali.us");
  const live = body.slice(body.indexOf("id=\"sheikh-stage\""), body.indexOf("id=\"sheikh-side\""));
  const rail = [...live.matchAll(/<li data-stage="([a-z0-9-]+)" title=/g)].map(m => m[1]);
  // The side list (resting) is built from the same STAGES; the client script orders by it too.
  const track = [...body.matchAll(/<li data-stage="([a-z0-9-]+)"><span class="dot">/g)].map(m => m[1]);
  const order = JSON.parse(/const STAGE_ORDER = (\[[^\]]*\]);/.exec(body)[1]);
  assert.equal(rail.length, 21); assert.deepEqual(rail, track); assert.deepEqual(rail, order);
  assert.deepEqual([...live.matchAll(/<span class="gname"><span class="en">([^<]+)</g)].map(m => m[1]), ["Tasbihat", "Lataif", "Raabta", "Muraqabat", "Shajra", "Dua"]);
});

test("every live site shows Our Sheikh's stage with the picture slot, the order of the Zikr and a polite announcement", async () => {
  for (const name of ["oursheikh", "namerica", "uk"]) {
    const body = await get(`${name}.wajidali.us`);
    for (const id of ["sheikh-stage", "p-stage"]) {
      const screen = body.slice(body.indexOf(`id="${id}"`));
      assert.match(screen, /class="photo"><img alt="Hazrat Ameer Abdul Qadeer Awan \(MZA\)"/, `${name} ${id} picture`);
      assert.match(screen, /<ol class="rail" aria-label="The order of the Zikr">/, `${name} ${id} rail`);
      assert.match(screen, /class="say sr" role="status" aria-live="polite"/, `${name} ${id} announcement`);
    }
    assert.equal((body.match(/data-stage="latifa-7" title="7th Latifa"/g) ?? []).length, 2);
    assert.match(body, /<span class="ur" lang="ur">مراقبات<\/span>/);
    for (const code of scripts(body)) assert.doesNotThrow(() => new Function(code), `${name}: an inline script does not parse`);
    assert.doesNotMatch(body, /naqshbandiaowaisiah\.us/);
  }
});

test("/broadcast keeps its 1920x1080 picture: Hazrat ji's picture and the card, no stage list", async () => {
  const body = await get("oursheikh.wajidali.us", "/broadcast?halqah=our-sheikh");
  assert.match(body, /<meta name="viewport" content="width=1920,height=1080">/);
  assert.match(body, /id="b-stage"[\s\S]*class="photo"/);
  assert.doesNotMatch(body, /class="rail"/);
  for (const code of scripts(body)) assert.doesNotThrow(() => new Function(code));
});

test("a stage title can never close the script it travels in, on /broadcast or the home page", async () => {
  const title = "</script><script>alert(1)</script>";
  const env = { ...platform.env, API: { fetch: async request => {
    if (new URL(request.url).pathname === "/v1/public/live") return Response.json({ halqahs: [{ id: "our-sheikh", name: "Our Sheikh", live: { kind: "zikr" }, stage: { stageID: "maiyyat", title, at: "x" } }] });
    return Response.json({});
  } } };
  for (const path of ["/broadcast", "/"]) {
    const body = await (await sites.worker.fetch(new Request(`https://oursheikh.wajidali.us${path}`), env)).text();
    assert.doesNotMatch(body, /<script>alert\(1\)/, path);
    assert.match(body, /\\u003c\/script>\\u003cscript>alert/, path);
  }
});
