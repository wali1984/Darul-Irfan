// The live stage on every site, in a real browser, against a mock platform:
// resting, each stage called in turn (the return to the 1st Latifa, a custom
// Muraqaba), Hazrat ji's picture beside Our Sheikh's stage, phone portrait,
// Reduce Motion, the joined screen, another Halqah's stage, and /broadcast at
// 1920x1080. Never contacts the platform, the feed or the relay.
//
//   $env:DARUL_PLAYWRIGHT_MODULE = 'C:/path/to/playwright/index.mjs'
//   $env:DARUL_STAGE_SHOTS = 'C:/path/to/screenshots'   # optional
//   node Sites/tests/stage-browser.mjs
import { createServer } from "node:http";
import { mkdir } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import assert from "node:assert/strict";
import { loadSites, mockPlatform, TITLES } from "./stage-harness.mjs";

if (!process.env.DARUL_PLAYWRIGHT_MODULE) throw new Error("Set DARUL_PLAYWRIGHT_MODULE to an existing Playwright index.mjs");
const { chromium } = await import(pathToFileURL(resolve(process.env.DARUL_PLAYWRIGHT_MODULE)).href);
const shots = resolve(process.env.DARUL_STAGE_SHOTS ?? "sites-stage-shots");
await mkdir(shots, { recursive: true });
const sites = await loadSites();
const platform = mockPlatform();
const { state, go } = platform;
const errors = [], passed = [];
const check = async (name, run) => { await run(); passed.push(name); console.log("ok -", name); };

// One local server per site, each answering as that site's host.
async function serve(host) {
  const server = createServer(async (req, res) => {
    try {
      const chunks = []; for await (const c of req) chunks.push(c);
      const r = await sites.worker.fetch(new Request(`https://${host}${req.url}`, { method: req.method, headers: req.headers, ...(chunks.length ? { body: Buffer.concat(chunks) } : {}) }), platform.env);
      res.writeHead(r.status, Object.fromEntries(r.headers)); res.end(Buffer.from(await r.arrayBuffer()));
    } catch (error) { res.writeHead(500); res.end(String(error)); }
  });
  await new Promise(ok => server.listen(0, "127.0.0.1", ok));
  return { server, base: `http://127.0.0.1:${server.address().port}` };
}
const oursheikh = await serve("oursheikh.wajidali.us");
const namerica = await serve("namerica.wajidali.us");
const browser = await chromium.launch({ ...(process.env.DARUL_BROWSER_CHANNEL ? { channel: process.env.DARUL_BROWSER_CHANNEL } : {}) });

async function open(base, path, { width = 1440, height = 900, reducedMotion = "no-preference" } = {}) {
  const context = await browser.newContext({ viewport: { width, height }, reducedMotion, deviceScaleFactor: 1 });
  const page = await context.newPage();
  page.on("pageerror", e => errors.push(`${path} ${width}: ${e.message}`));
  // The live feed's socket is never opened for real.
  await page.addInitScript(() => { window.WebSocket = class { constructor() { this.readyState = 1; } send() {} close() {} }; });
  await page.goto(base + path, { waitUntil: "load" });
  await page.waitForTimeout(400);
  return page;
}
// The home page asks for the stage every 5 s; a visibility change asks at once.
const refresh = page => page.evaluate(() => document.dispatchEvent(new Event("visibilitychange")));
const said = (page, box, text) => page.waitForFunction(([b, t]) => document.querySelector(`#${b} .say`)?.textContent === t, [box, text], { timeout: 12000 });
const box = (page, selector) => page.locator(selector).boundingBox();
// Joining: listening without a profile where the page offers it (the audit
// branch's entry choice), otherwise with a name and a place.
async function join(page, button, city) {
  await page.locator(button).click();
  if (await page.locator("#anonymous-join").count()) return page.locator("#anonymous-join").click();
  await page.locator("#join-fields [name=name]").fill("Test Visitor"); await page.locator("#join-fields [name=city]").fill(city);
  await page.locator("#join-go").click();
}
async function stageFacts(page, id) {
  return page.evaluate(id => {
    const b = document.getElementById(id), shown = el => !!el && getComputedStyle(el).display !== "none";
    return {
      on: b.classList.contains("on"), duo: b.classList.contains("duo"),
      photo: shown(b.querySelector(".photo")), photoSrc: b.querySelector(".photo img")?.getAttribute("src") ?? null,
      rail: shown(b.querySelector(".rail")), current: b.querySelector('.rail [aria-current="step"]')?.dataset.stage ?? null,
      done: [...b.querySelectorAll(".rail li.past")].map(li => li.dataset.stage),
      groupNow: [...b.querySelectorAll(".rail .grp.here")].map(g => g.dataset.group),
      title: b.querySelector(".card .title").textContent, urdu: b.querySelector(".card .urdu").textContent,
      waiting: shown(b.querySelector(".waiting")), say: b.querySelector(".say").textContent,
      burst: b.querySelector(".card").classList.contains("burst"),
      // How far the stage's own parts reach past the screen's edges (the hero's
      // decorative glow is clipped by the page and is not the stage's).
      overflow: Math.max(0, ...[...b.querySelectorAll(".photo, .card, .rail, .rail .grp")].filter(shown)
        .map(el => { const r = el.getBoundingClientRect(); return Math.max(r.right - innerWidth, -r.left); })),
    };
  }, id);
}
const shot = (page, name, selector) => (selector ? page.locator(selector).first() : page).screenshot({ path: `${shots}/${name}.png` });

try {
  await check("resting: no live Zikr shows the calm emblem, no picture, no stage list", async () => {
    state.live = false;
    const page = await open(oursheikh.base, "/");
    const f = await stageFacts(page, "sheikh-stage");
    assert.equal(f.on, false); assert.equal(f.duo, false); assert.equal(f.photo, false); assert.equal(f.rail, false); assert.equal(f.waiting, true);
    await page.locator("#live").scrollIntoViewIfNeeded(); await page.waitForTimeout(1200);
    await shot(page, "01-desktop-resting", "#live");
    await page.context().close();
  });

  await check("desktop: each stage in turn, picture beside the card, the order of the Zikr lit", async () => {
    state.live = true; go("tasbih");
    const page = await open(oursheikh.base, "/");
    await page.locator("#live").scrollIntoViewIfNeeded();
    await said(page, "sheikh-stage", "Now: Tasbihat");
    let f = await stageFacts(page, "sheikh-stage");
    assert.ok(f.on && f.duo && f.photo && f.rail, JSON.stringify(f));
    assert.equal(f.current, "tasbih"); assert.deepEqual(f.done, []); assert.deepEqual(f.groupNow, ["opening"]);
    assert.match(f.photoSrc, /maxresdefault/);
    const photo = await box(page, "#sheikh-stage .photo"), card = await box(page, "#sheikh-stage .card");
    assert.ok(photo.x + photo.width <= card.x + 1, "picture at the side of the card");
    for (const [id, name] of [["latifa-3", "02-desktop-latifa-3"], ["latifa-7", null], ["latifa-1", "03-desktop-latifa-1-return"], ["raabta", null], ["maiyyat", "04-desktop-muraqaba-maiyyat"], ["shajra", "05-desktop-shajra"], ["dua", "06-desktop-dua"]]) {
      go(id); await refresh(page); await said(page, "sheikh-stage", "Now: " + TITLES[id][0]);
      f = await stageFacts(page, "sheikh-stage");
      assert.equal(f.current, id); assert.equal(f.title, TITLES[id][0]); assert.equal(f.urdu, TITLES[id][1]);
      if (id === "latifa-1") {
        // Back to the 1st Latifa for a moment after the 7th: the Lataif done stay done.
        for (const n of [2, 3, 4, 5, 6, 7]) assert.ok(f.done.includes("latifa-" + n), "latifa-" + n + " done");
        assert.ok(!f.done.includes("latifa-1"));
      }
      if (id === "maiyyat") assert.deepEqual(f.groupNow, ["muraqabat"]), assert.ok(f.done.includes("ahadiyat") && f.done.includes("raabta"));
      if (name) { await page.waitForTimeout(id === "shajra" ? 4000 : 1500); await shot(page, name, "#live"); }
    }
    // A Muraqaba the admins added themselves lights the Muraqabat without a dot of its own.
    state.stageID = "custom-fana"; TITLES["custom-fana"] = ["Muraqaba Fana", "مراقبہ فنا"]; go("custom-fana");
    await refresh(page); await said(page, "sheikh-stage", "Now: Muraqaba Fana");
    f = await stageFacts(page, "sheikh-stage");
    assert.equal(f.current, null); assert.deepEqual(f.groupNow, ["muraqabat"]);
    // The Zikr ends: the calm emblem again, and it is said once.
    state.live = false; await refresh(page); await said(page, "sheikh-stage", "The Zikr has ended.");
    f = await stageFacts(page, "sheikh-stage");
    assert.ok(!f.on && !f.duo && !f.rail && f.waiting);
    assert.ok(f.overflow <= 0, "no sideways scroll");
    await page.context().close();
  });

  await check("phone portrait: the picture above the stage, the stage list below, nothing wider than the screen", async () => {
    state.live = true; go("latifa-3");
    const page = await open(oursheikh.base, "/", { width: 390, height: 844 });
    await page.locator("#sheikh-stage").scrollIntoViewIfNeeded(); await said(page, "sheikh-stage", "Now: 3rd Latifa");
    const f = await stageFacts(page, "sheikh-stage");
    assert.ok(f.duo && f.rail); assert.ok(f.overflow <= 0, "overflow " + f.overflow);
    const photo = await box(page, "#sheikh-stage .photo"), card = await box(page, "#sheikh-stage .card"), rail = await box(page, "#sheikh-stage .rail");
    assert.ok(photo.y + photo.height <= card.y + 12, "picture above the card"); assert.ok(card.y + card.height <= rail.y + 12, "list below the card");
    assert.ok(rail.x >= 0 && rail.x + rail.width <= 390);
    // The phone's screen as a visitor sees it: the stage just under the sticky navigation.
    await page.evaluate(() => scrollTo(0, document.getElementById("sheikh-stage").getBoundingClientRect().top + scrollY - 84));
    await page.waitForTimeout(1500);
    await shot(page, "07-phone-latifa-3");
    go("maiyyat"); await refresh(page); await said(page, "sheikh-stage", "Now: Muraqaba Ma'iyyat"); await page.waitForTimeout(1500);
    await shot(page, "08-phone-maiyyat", "#live");
    await page.context().close();
  });

  await check("Reduce Motion: the stage changes with no animation at all", async () => {
    state.live = true; go("latifa-5");
    TITLES["latifa-5"] = ["5th Latifa", "پانچواں لطیفہ"];
    const page = await open(oursheikh.base, "/", { reducedMotion: "reduce" });
    await said(page, "sheikh-stage", "Now: 5th Latifa");
    go("shajra"); await refresh(page); await said(page, "sheikh-stage", "Now: Shajra Sharif");
    const facts = await page.evaluate(() => {
      const b = document.getElementById("sheikh-stage");
      return { burst: b.querySelector(".card").classList.contains("burst"), rolling: b.querySelector(".lines").classList.contains("run"),
        running: document.getAnimations().filter(a => b.contains(a.effect?.target)).length };
    });
    assert.deepEqual(facts, { burst: false, rolling: false, running: 0 });
    await shot(page, "09-desktop-reduce-motion-shajra", "#live");
    await page.context().close();
  });

  await check("joined screen: Our Sheikh's stage with Hazrat ji's picture, following the Zikr, then ended", async () => {
    state.live = true; go("ahadiyat");
    for (const [width, height, name] of [[1366, 900, "10-desktop-joined"], [390, 844, "11-phone-joined"]]) {
      const page = await open(oursheikh.base, "/", { width, height });
      await join(page, "#sheikh-join", "New York");
      await page.locator("#player.open").waitFor();
      await said(page, "p-stage", "Now: Muraqaba Ahadiyat");
      const f = await stageFacts(page, "p-stage");
      assert.ok(f.duo && f.photo && f.rail, JSON.stringify(f)); assert.equal(f.current, "ahadiyat");
      if (width < 500) {
        const photo = await box(page, "#p-stage .photo"), card = await box(page, "#p-stage .card");
        assert.ok(photo.y + photo.height <= card.y + 12);
      }
      await page.waitForTimeout(1500);
      await shot(page, name);
      if (width > 500) {
        go("sair-kaaba"); await said(page, "p-stage", "Now: Sair-e-Kaaba");
        assert.equal((await stageFacts(page, "p-stage")).current, "sair-kaaba");
        state.live = false; await said(page, "p-stage", "The Zikr has ended.");
        assert.equal((await stageFacts(page, "p-stage")).on, false);
        state.live = true; go("ahadiyat");
      }
      await page.context().close();
    }
  });

  await check("another Halqah (North America site): its stage and the order of the Zikr, without Hazrat ji's picture", async () => {
    state.live = true; state.otherLive = "north-america"; go("latifa-3");
    const page = await open(namerica.base, "/");
    await said(page, "sheikh-stage", "Now: 3rd Latifa");
    assert.ok((await stageFacts(page, "sheikh-stage")).duo, "Our Sheikh's stage still carries the picture on every site");
    await join(page, '[data-join="north-america"]', "Worcester");
    await said(page, "p-stage", "Now: 3rd Latifa");
    const f = await stageFacts(page, "p-stage");
    assert.ok(f.on && !f.duo && !f.photo && f.rail && f.current === "latifa-3", JSON.stringify(f));
    await page.waitForTimeout(1500);
    await shot(page, "12-namerica-halqah-joined");
    await page.context().close();
    state.otherLive = null;
  });

  await check("/broadcast stays the YouTube picture: 1920x1080, picture at 96px, no stage list", async () => {
    state.live = true; go("maiyyat");
    const page = await open(oursheikh.base, "/broadcast?halqah=our-sheikh", { width: 1920, height: 1080 });
    await page.waitForTimeout(1500);
    const f = await page.evaluate(() => ({ rails: document.querySelectorAll(".rail").length, duo: document.getElementById("b-stage").classList.contains("duo"),
      width: document.scrollingElement.scrollWidth, height: document.scrollingElement.scrollHeight }));
    assert.deepEqual(f, { rails: 0, duo: true, width: 1920, height: 1080 });
    const photo = await box(page, "#b-stage .photo");
    assert.equal(Math.round(photo.x), 96); assert.equal(Math.round(photo.width), 840);
    await shot(page, "13-broadcast-1920x1080");
    await page.context().close();
  });

  assert.deepEqual(errors, []);
  console.log(`\n${passed.length} checks passed; screenshots in ${shots}`);
} finally {
  await browser.close(); oursheikh.server.close(); namerica.server.close(); await sites.close();
}
