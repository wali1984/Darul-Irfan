// The staff page's live broadcast form and health view (audit LIVE-021 and
// LIVE-025). Cloudflare Access is verified in access.test.ts; here it simply
// answers with a staff address.
import { describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { OFFICIAL_LIVE_TITLE } from "../src/sources";
import { sqliteD1 } from "./sqlite-d1";

vi.mock("../src/access", () => ({ authenticatedActor: async () => "editor@example.com" }));

function setup() {
  const { db, raw } = sqliteD1();
  // As production has it since migration 0012, with the title YouTube sets.
  raw.prepare("UPDATE live_broadcasts SET title=?,paltalk_url='https://paltalk.im/egnMPD3Y' WHERE id='official-live'").run(OFFICIAL_LIVE_TITLE);
  const env = { DB: db, ENVIRONMENT: "test", ADMIN_EDITOR_EMAILS: "editor@example.com", APNS_TOPIC: "x" } as unknown as Env;
  const call = (method: string, path: string, body?: unknown) => worker.fetch(new Request(`https://api.example.com${path}`, {
    method, headers: body ? { "content-type": "application/json" } : {}, body: body ? JSON.stringify(body) : undefined,
  }), env);
  const stored = () => raw.prepare("SELECT state,title,paltalk_url,details,source_mode FROM live_broadcasts WHERE id='official-live'").get() as
    { state: string; title: string; paltalk_url: string | null; details: string | null; source_mode: string };
  return { raw, call, stored };
}

describe("LIVE-021: saving the live broadcast form", () => {
  it("changes only what is sent, so the Paltalk room's link and the title stay", async () => {
    const { call, stored } = setup();
    const saved = await call("PUT", "/admin/api/live", { state: "offline", sourceMode: "auto" });
    expect(saved.status).toBe(200);
    expect(stored()).toMatchObject({ state: "offline", title: OFFICIAL_LIVE_TITLE, paltalk_url: "https://paltalk.im/egnMPD3Y" });
    // A field sent empty is cleared; one sent with a value is set.
    expect((await call("PUT", "/admin/api/live", { state: "offline", details: "" })).status).toBe(200);
    expect(stored().details).toBeNull();
    expect((await call("PUT", "/admin/api/live", { state: "scheduled", title: "Special zikr" })).status).toBe(200);
    expect(stored()).toMatchObject({ state: "scheduled", title: "Special zikr", paltalk_url: "https://paltalk.im/egnMPD3Y" });
  });

  it("refuses a link that is not https instead of dropping it", async () => {
    const { call, stored } = setup();
    expect((await call("PUT", "/admin/api/live", { state: "offline", paltalkURL: "http://paltalk.im/egnMPD3Y" })).status).toBe(400);
    expect(stored().paltalk_url).toBe("https://paltalk.im/egnMPD3Y");
  });

  it("fills the form from the stored broadcast, with the room's link and the official title as defaults", async () => {
    const { call } = setup();
    const page = await (await call("GET", "/admin")).text();
    expect(page).toContain(`name="title" value="${OFFICIAL_LIVE_TITLE}"`);
    expect(page).toContain('name="paltalkURL" value="https://paltalk.im/egnMPD3Y"');
    expect(page).toContain("fetch('/admin/api/state')");
  });
});

describe("LIVE-025: the detailed health view is for staff", () => {
  it("shows each job's state and last error, and the listeners", async () => {
    const { raw, call } = setup();
    raw.prepare(`INSERT INTO source_health(source,status,last_attempt_at,consecutive_failures,last_error)
      VALUES('youtube','degraded','2026-10-28T00:00:00Z',2,'YouTube videos 403')`).run();
    raw.prepare("INSERT INTO live_listeners(id,in_room,streaming,last_seen_at) VALUES('listener-pc',0,0,'2026-10-28T19:24:03.940Z')").run();
    const response = await call("GET", "/admin/api/health");
    expect(response.status).toBe(200);
    const body = await response.json() as { ok: boolean; environment: string; sources: { last_error: string }[]; listeners: { id: string }[] };
    expect(body).toMatchObject({ ok: false, environment: "test" });
    expect(body.sources[0]?.last_error).toBe("YouTube videos 403");
    expect(body.listeners.map(listener => listener.id)).toEqual(["listener-pc"]);
  });
});
