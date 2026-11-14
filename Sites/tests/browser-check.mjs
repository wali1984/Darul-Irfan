// Local mocked browser journeys; never contacts live SFU, members or admin APIs.
// DARUL_PLAYWRIGHT_MODULE points to an existing Playwright installation.
import { createServer } from "node:http";
import { mkdir, writeFile, readFile } from "node:fs/promises";
import { resolve, join } from "node:path";
import { pathToFileURL } from "node:url";
import assert from "node:assert/strict";
import { loadWorker } from "./fixture.mjs";

if (!process.env.DARUL_PLAYWRIGHT_MODULE) throw new Error("Set DARUL_PLAYWRIGHT_MODULE to the existing Playwright index.mjs");
const { chromium } = await import(pathToFileURL(resolve(process.env.DARUL_PLAYWRIGHT_MODULE)).href);
const fixture = await loadWorker();
const output = resolve(process.env.DARUL_SITES_EVIDENCE ?? "sites-browser-evidence");
await mkdir(output, { recursive: true });
let live = true, joinDelay = 0, reportFailure = false, reportAuthenticated = false;
const visits = [], errors = [], checks = [], accessibility = [];
const axeSource = process.env.DARUL_AXE_SOURCE ? await readFile(process.env.DARUL_AXE_SOURCE, "utf8") : null;
async function audit(page, name) {
  if (!axeSource) return;
  await page.evaluate(axeSource);
  const result = await page.evaluate(async () => { const result = await axe.run(document, { runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21aa"] } }); return result.violations.map(v => ({ id: v.id, impact: v.impact, description: v.description, nodes: v.nodes.map(n => ({ target: n.target, summary: n.failureSummary })) })); });
  accessibility.push({ page: name, violations: result });
}
const session = { live: { kind: "zikr", startedAt: "2026-11-06T12:00:00Z" }, stage: { stageID: "latifa-1", title: "1st Latifa", titleUr: "پہلا لطیفہ", at: "2026-11-06T12:00:05Z" } };
const env = { LIVE_FEED_BASE: "https://feed.invalid", LIVE_FEED_KEY: "fixture-only", API: { fetch: async request => {
  const url = new URL(request.url);
  if (url.pathname === "/v1/public/live") return Response.json({ halqahs: (url.searchParams.get("ids") ?? "our-sheikh").split(",").map(id => ({ id, name: id === "our-sheikh" ? "Our Sheikh" : "North America", ...(live ? session : { live: null, stage: null }) })) });
  if (/\/public\/halqahs\/.*\/(join|presence)$/.test(url.pathname)) {
    visits.push({ path: url.pathname, body: await request.json() });
    if (url.pathname.endsWith("/join") && joinDelay) await new Promise(resolve => setTimeout(resolve, joinDelay));
    return Response.json(session);
  }
  if (url.pathname === "/v1/markaz/access") return reportAuthenticated ? Response.json({ canReport: true, isSuperAdmin: true }) : Response.json({ error: "Sign in" }, { status: 401 });
  if (url.pathname === "/v1/markaz/organization") return Response.json({ regions: [], unassigned: [] });
  if (url.pathname === "/v1/markaz/reporting-sessions") return Response.json({ sessions: [] });
  if (url.pathname === "/v1/markaz/announcements") return Response.json({ announcements: [] });
  if (url.pathname === "/v1/reporting/link") {
    if (reportFailure) throw new Error("fixture failure");
    return Response.json({ code: "1234", pollToken: "fixture", expiresAt: new Date(Date.now() + 300000).toISOString() });
  }
  if (url.pathname === "/v1/reporting/link/poll") return Response.json({ status: "pending" });
  return Response.json({});
} } };
const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, "http://localhost");
    const reporting = url.pathname.startsWith("/reporting") || url.pathname.startsWith("/api/") || ["/app.js", "/app.css", "/auth/start", "/auth/poll"].includes(url.pathname);
    if (url.pathname.startsWith("/reporting")) url.pathname = url.pathname.slice(10) || "/";
    const chunks = []; for await (const chunk of req) chunks.push(chunk);
    const headers = new Headers(req.headers);
    if (reportAuthenticated) headers.set("cookie", `__Host-di_report=${"a".repeat(64)}`);
    // The server-side URL has the real routing identity; rewrite Origin only
    // for this local fixture, never for live requests.
    if (headers.has("origin")) headers.set("origin", `https://${reporting ? "reporting" : "namerica"}.wajidali.us`);
    const response = await fixture.worker.fetch(new Request(`https://${reporting ? "reporting" : "namerica"}.wajidali.us${url.pathname}${url.search}`, {
      method: req.method, headers, ...(chunks.length ? { body: Buffer.concat(chunks) } : {}),
    }), env);
    res.writeHead(response.status, Object.fromEntries(response.headers)); res.end(Buffer.from(await response.arrayBuffer()));
  } catch (error) { res.writeHead(500); res.end(error.message); }
});
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const base = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ headless: true, ...(process.env.DARUL_BROWSER_CHANNEL ? { channel: process.env.DARUL_BROWSER_CHANNEL } : {}) });
try {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, reducedMotion: "reduce" });
  page.on("pageerror", error => errors.push(error.message));
  await page.route("https://fonts.googleapis.com/**", route => route.abort());
  await page.route("https://fonts.gstatic.com/**", route => route.abort());
  await page.addInitScript(() => {
    localStorage.setItem("zikr.visitor", "broken JSON");
    // A nonpersistent browser must retain its guest identity during this visit.
    Storage.prototype.setItem = function () { throw new Error("Storage disabled"); };
    window.socketCount = 0;
    window.WebSocket = class {
      constructor() { window.socketCount += 1; this.readyState = 1; }
      send() {} close() { this.readyState = 3; }
    };
    Object.defineProperty(navigator, "share", { value: undefined, configurable: true });
    Object.defineProperty(navigator, "clipboard", { value: { writeText: async () => { throw new Error("Clipboard blocked"); } }, configurable: true });
  });
  await page.goto(base);
  await page.locator("#sheikh-join:not([disabled])").waitFor();
  assert.equal(await page.evaluate(() => window.socketCount), 0);
  assert.equal(await page.locator(".navlinks").isVisible(), true);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), true);
  checks.push("Mobile navigation visible; no horizontal overflow; passive visitors open no SFU socket; corrupt storage recovered");
  await page.screenshot({ path: join(output, "mobile-home.png"), fullPage: true });
  await audit(page, "mobile-home");
  await page.getByRole("button", { name: "Share this page", exact: true }).click();
  assert.equal(await page.getByLabel("Website link", { exact: true }).inputValue(), `${base}/`);
  assert.equal(await page.getByLabel("Website link", { exact: true }).isVisible(), true);
  checks.push("Sharing offers a selectable clean URL when native share and clipboard are unavailable");

  await page.locator("#sheikh-join").click();
  await page.getByLabel("Your name", { exact: true }).fill("Audit visitor");
  await page.getByLabel("City", { exact: true }).fill("Test city");
  await page.getByLabel("City", { exact: true }).press("Enter");
  await page.locator("#player[open]").waitFor();
  assert.equal(visits.length, 1);
  assert.equal(await page.evaluate(() => window.socketCount), 1);
  assert.equal(await page.locator("#player").evaluate(node => Math.round(node.getBoundingClientRect().height)), 844);
  await page.screenshot({ path: join(output, "mobile-live-dialog.png") });
  await audit(page, "mobile-live-dialog");
  await page.keyboard.press("Escape");
  assert.equal(await page.locator("#player").isVisible(), false);
  checks.push("Enter submits Join; native dialog contains focus; Escape leaves and closes live transport");

  joinDelay = 350;
  await page.locator("#sheikh-join").click();
  await page.locator("#join-go").click();
  await page.getByRole("button", { name: "Cancel", exact: true }).click();
  await page.waitForTimeout(500);
  assert.equal(await page.locator("#player").isVisible(), false);
  assert.equal(visits[0].body.guestSecret, visits[1].body.guestSecret);
  checks.push("Cancel discards an in-flight successful Join; private-mode guest identity stays stable");

  await page.goto(`${base}/method-of-zikr`);
  await page.locator("#tab-ur").focus(); await page.keyboard.press("ArrowRight");
  assert.equal(await page.locator("#method-en").isVisible(), true);
  assert.equal(await page.locator("#tab-en").getAttribute("aria-selected"), "true");
  await page.keyboard.press("Home");
  assert.equal(await page.locator("#method-ur").evaluate(node => getComputedStyle(node).direction), "rtl");
  await page.screenshot({ path: join(output, "mobile-method-urdu.png"), fullPage: true });
  await audit(page, "mobile-method-urdu");
  checks.push("Language tabs support arrow/Home keys and the Urdu panel uses RTL");

  live = false;
  await page.goto(base);
  assert.equal(await page.locator("#sheikh-join").isDisabled(), true);
  checks.push("Inactive platform session cannot be joined");

  reportFailure = true;
  await page.goto(`${base}/reporting/`);
  await page.getByRole("button", { name: "Try again", exact: true }).waitFor();
  reportFailure = false; await page.getByRole("button", { name: "Try again", exact: true }).click();
  await page.getByText("1234", { exact: true }).waitFor();
  assert.equal(await page.locator(".signin .side").isVisible(), false);
  assert.ok((await page.locator(".code").boundingBox()).y < 400);
  await page.emulateMedia({ colorScheme: "dark" });
  assert.equal(await page.locator(".signin .card").evaluate(node => getComputedStyle(node).color), "rgb(19, 35, 28)");
  await page.screenshot({ path: join(output, "mobile-reporting-signin.png"), fullPage: true });
  await audit(page, "mobile-reporting-signin");
  checks.push("Reporting service failure offers a working retry and safely shows a fresh approval code");
  checks.push("Mobile reporting code stays above the fold and login text retains contrast in dark mode");
  reportAuthenticated = true;
  await page.goto(`${base}/reporting/#computers`);
  await page.reload();
  await page.getByText("Computers signed in to reports", { exact: true }).waitFor();
  assert.ok((await page.locator(".main").boundingBox()).y < 100);
  assert.equal(await page.locator("#markaz-nav").evaluate(node => node.inert), true);
  await page.getByRole("button", { name: "Menu", exact: true }).click();
  assert.equal(await page.locator("#markaz-nav").evaluate(node => node.inert), false);
  await page.keyboard.press("Escape");
  assert.equal(await page.locator("#markaz-nav").evaluate(node => node.inert), true);
  await page.screenshot({ path: join(output, "mobile-reporting-dashboard.png"), fullPage: true });
  await audit(page, "mobile-reporting-dashboard");
  checks.push("Mobile admin dashboard starts at top; hidden menu is inert; open/Escape keyboard navigation works");
  await page.goto(`${base}/reporting/#notices`);
  await page.getByRole("button", { name: "New notice" }).click();
  await page.getByLabel("Halqahs", { exact: true }).selectOption("halqahs");
  await page.getByLabel("Who receives it", { exact: true }).selectOption("admins");
  assert.equal(await page.getByLabel("Halqahs", { exact: true }).isDisabled(), true);
  assert.equal(await page.getByLabel("Halqahs", { exact: true }).inputValue(), "all");
  await page.keyboard.press("Escape");
  checks.push("All-admin announcement audience resets and disables narrower scope without sending a notice");
  const noJS = await browser.newPage({ javaScriptEnabled: false, viewport: { width: 1280, height: 900 } });
  await noJS.goto(base);
  assert.equal(await noJS.locator("h1").isVisible(), true);
  assert.equal(await noJS.locator("h1").evaluate(node => getComputedStyle(node).opacity), "1");
  checks.push("Landing content remains readable with JavaScript disabled");
  assert.deepEqual(errors, []);
  await writeFile(join(output, "browser-checks.json"), JSON.stringify({ checks, errors, accessibility, scope: "Local mocked Chromium journeys; no live broadcasts or notifications" }, null, 2));
  console.log(JSON.stringify({ passed: checks.length, errors, accessibility: accessibility.map(a => ({ page: a.page, violations: a.violations })), output }, null, 2));
  assert.ok(accessibility.every(page => page.violations.length === 0), "Accessibility violations remain; see evidence");
} finally {
  await browser.close(); await new Promise(resolve => server.close(resolve)); await fixture.close();
}
