import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { sqliteD1 } from "./sqlite-d1";

const SECRET = "test-app-secret";

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("");
}

/** A database with three members - an ordinary USA member, a USA admin and
 *  the super admin - each with a session token. */
async function setup(overrides: Partial<Env> = {}) {
  const { db, raw } = sqliteD1();
  const now = new Date().toISOString();
  const later = new Date(Date.now() + 86_400_000).toISOString();
  const people = [
    { id: "a".repeat(32), role: "member", token: "1".repeat(64), groups: ["usa"] },
    { id: "b".repeat(32), role: "admin", token: "2".repeat(64), groups: ["usa"] },
    { id: "c".repeat(32), role: "superadmin", token: "3".repeat(64), groups: [] as string[] },
  ];
  for (const person of people) {
    raw.prepare("INSERT INTO members(id,apple_subject,display_name,created_at,last_seen_at,role) VALUES(?,?,?,?,?,?)")
      .run(person.id, `invite:${person.id}`, person.role, now, now, person.role);
    raw.prepare("INSERT INTO member_sessions(token_hash,member_id,created_at,expires_at,last_seen_at) VALUES(?,?,?,?,?)")
      .run(await sha256(person.token), person.id, now, later, now);
    for (const group of person.groups) {
      raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by) VALUES(?,?,?,?)")
        .run(group, person.id, now, "test");
    }
  }
  const env = {
    DB: db, APNS_TOPIC: "us.naqshbaniaowaisiah", PUBLIC_BASE_URL: "https://api.example.com",
    WHATSAPP_APP_SECRET: SECRET, WHATSAPP_CHANNEL_URL: "https://whatsapp.com/channel/x",
    WHATSAPP_ALLOWED_SENDERS: "923001111111,923002222222",
    ...overrides,
  } as unknown as Env;
  const call = (token: string, method: string, path: string, body?: unknown) =>
    worker.fetch(new Request(`https://api.example.com${path}`, {
      method,
      headers: { authorization: `Bearer ${token}`, ...(body ? { "content-type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    }), env);
  return { env, raw, call, member: people[0]!.token, admin: people[1]!.token, superAdmin: people[2]!.token };
}

afterEach(() => vi.unstubAllGlobals());

describe("community groups", () => {
  it("shows members and admins only their groups, and the super admin every group", async () => {
    const { call, member, admin, superAdmin } = await setup();
    const ids = async (token: string) => ((await (await call(token, "GET", "/v1/groups")).json()) as { groups: { id: string }[] }).groups.map(g => g.id);
    expect(await ids(member)).toEqual(["usa"]);
    expect(await ids(admin)).toEqual(["usa"]);
    expect((await ids(superAdmin)).sort()).toEqual(["canada", "darul-irfan", "usa"]);
    // Another region stays indistinguishable from nothing.
    expect((await call(admin, "GET", "/v1/groups/canada")).status).toBe(404);
    expect((await call(superAdmin, "GET", "/v1/groups/canada")).status).toBe(200);
  });

  it("makes a member whose Apple email is a listed super admin a super admin", async () => {
    const { call, raw, member } = await setup({ SUPER_ADMIN_EMAILS: "owner@example.com, Second@Example.com" } as Partial<Env>);
    const role = async () => ((await (await call(member, "GET", "/v1/members/me")).json()) as { role: string }).role;
    expect(await role()).toBe("member");
    raw.prepare("UPDATE members SET email=? WHERE id=?").run("second@example.com", "a".repeat(32));
    expect(await role()).toBe("superadmin");
    expect((await call(member, "GET", "/v1/groups/canada")).status).toBe(200);
  });

  it("tells the app which integrations are connected, so it can say what is still in progress", async () => {
    const pending = await setup();
    const status = async (call: typeof pending.call, token: string) =>
      ((await (await call(token, "GET", "/v1/groups/usa")).json()) as { integrations: Record<string, boolean> }).integrations;
    expect(await status(pending.call, pending.member)).toEqual({ meetings: false, whatsappForwarding: false, liveBroadcast: false });
    const connected = await setup({
      REALTIME_ACCOUNT_ID: "acct", REALTIME_APP_ID: "app", REALTIME_API_TOKEN: "token", WHATSAPP_ACCESS_TOKEN: "wa",
    } as Partial<Env>);
    expect(await status(connected.call, connected.member)).toEqual({ meetings: true, whatsappForwarding: true, liveBroadcast: false });
  });

  it("lets admins publish and members only read", async () => {
    const { call, member, admin } = await setup();
    expect((await call(member, "POST", "/v1/groups/usa/posts", { title: "Hello" })).status).toBe(403);
    const created = await call(admin, "POST", "/v1/groups/usa/posts", { title: "Friday gathering", body: "After Isha" });
    expect(created.status).toBe(201);
    const posts = (await (await call(member, "GET", "/v1/groups/usa/posts")).json()) as { posts: { title: string }[] };
    expect(posts.posts.map(p => p.title)).toEqual(["Friday gathering"]);
  });

  it("keeps drafts from members until an admin publishes them", async () => {
    const { call, member, admin } = await setup();
    const draft = (await (await call(admin, "POST", "/v1/groups/usa/posts", { title: "Draft notice", publish: false })).json()) as { id: string };
    const memberView = (await (await call(member, "GET", "/v1/groups/usa/posts?drafts=1")).json()) as { posts: unknown[] };
    expect(memberView.posts).toEqual([]);
    const adminDrafts = (await (await call(admin, "GET", "/v1/groups/usa/posts?drafts=1")).json()) as { posts: { id: string; isDraft: boolean }[] };
    expect(adminDrafts.posts.map(p => [p.id, p.isDraft])).toEqual([[draft.id, true]]);
    expect((await call(admin, "POST", `/v1/groups/usa/posts/${draft.id}/publish`, { title: "Notice" })).status).toBe(200);
    const published = (await (await call(member, "GET", "/v1/groups/usa/posts")).json()) as { posts: { title: string }[] };
    expect(published.posts.map(p => p.title)).toEqual(["Notice"]);
  });

  it("routes forwarded WhatsApp messages by tag, then by sender, else to the public feed", async () => {
    const { env, raw } = await setup();
    raw.prepare("INSERT INTO whatsapp_sender_groups(sender,group_id,updated_at,updated_by) VALUES('923002222222','usa',?,?)").run(new Date().toISOString(), "t");
    const send = async (from: string, id: string, text: string) => {
      const body = JSON.stringify({ entry: [{ changes: [{ value: { messages: [{ from, id, type: "text", timestamp: "1760000000", text: { body: text } }] } }] }] });
      const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
      const signed = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)));
      return worker.fetch(new Request("https://api.example.com/v1/whatsapp", {
        method: "POST", body, headers: { "x-hub-signature-256": "sha256=" + [...signed].map(b => b.toString(16).padStart(2, "0")).join("") },
      }), env);
    };
    await send("923001111111", "m1", "#canada Zikr this Sunday at 6");
    await send("923002222222", "m2", "Meeting moved to Saturday");
    await send("923001111111", "m3", "General notice");
    await send("923001111111", "m1", "#canada Zikr this Sunday at 6"); // Meta redelivery
    const drafts = raw.prepare("SELECT group_id,title,status,source FROM member_group_posts ORDER BY group_id").all();
    expect(drafts).toEqual([
      { group_id: "canada", title: "Zikr this Sunday at 6", status: "draft", source: "whatsapp" },
      { group_id: "usa", title: "Meeting moved to Saturday", status: "draft", source: "whatsapp" },
    ]);
    const feed = raw.prepare("SELECT id FROM feed_items WHERE source='whatsapp'").all();
    expect(feed).toEqual([{ id: "whatsapp:m3" }]);
  });

  it("runs a live zikr: the video plays in the app, and a room needs the meeting service", async () => {
    const { call, member, admin } = await setup();
    expect((await call(member, "POST", "/v1/groups/usa/live", { state: "live", videoID: "abcdefghijk" })).status).toBe(403);
    expect((await call(admin, "POST", "/v1/groups/usa/live", { state: "live", title: "Community Zikr", videoID: "abcdefghijk" })).status).toBe(200);
    const detail = (await (await call(member, "GET", "/v1/groups/usa")).json()) as { live?: { videoID?: string; hasRoom: boolean } };
    expect(detail.live).toMatchObject({ videoID: "abcdefghijk", hasRoom: false });
    // No meeting service configured: a room is refused plainly, not half-made.
    expect((await call(admin, "POST", "/v1/groups/usa/live", { state: "live", room: true })).status).toBe(503);
  });

  it("joins members into the group's room through the meeting service", async () => {
    const calls: string[] = [];
    vi.stubGlobal("fetch", async (url: string, init: RequestInit) => {
      calls.push(`${init.method} ${url}`);
      const body = String(url).endsWith("/participants") ? { data: { token: "participant-token" } } : { data: { id: "room-1" } };
      return new Response(JSON.stringify(body), { status: 201, headers: { "content-type": "application/json" } });
    });
    const { call, member, admin } = await setup({ REALTIME_ACCOUNT_ID: "acct", REALTIME_APP_ID: "app", REALTIME_API_TOKEN: "secret" } as Partial<Env>);
    expect((await call(admin, "POST", "/v1/groups/usa/live", { state: "live", room: true })).status).toBe(200);
    const joined = (await (await call(member, "POST", "/v1/groups/usa/join", {})).json()) as { authToken: string; pageURL: string };
    expect(joined).toEqual({ authToken: "participant-token", pageURL: "https://api.example.com/v1/meet" });
    expect(calls).toEqual([
      "POST https://api.cloudflare.com/client/v4/accounts/acct/realtime/kit/app/meetings",
      "POST https://api.cloudflare.com/client/v4/accounts/acct/realtime/kit/app/meetings/room-1/participants",
    ]);
  });

  it("opens a scheduled meeting's room to members only from ten minutes before", async () => {
    const { call, member, admin } = await setup({ REALTIME_ACCOUNT_ID: "a", REALTIME_APP_ID: "b", REALTIME_API_TOKEN: "c" } as Partial<Env>);
    const startsAt = new Date(Date.now() + 2 * 3_600_000).toISOString();
    const meeting = (await (await call(admin, "POST", "/v1/groups/usa/meetings", { title: "Monthly meeting", startsAt })).json()) as { id: string };
    expect((await call(member, "POST", "/v1/groups/usa/join", { meetingID: meeting.id })).status).toBe(409);
    const detail = (await (await call(member, "GET", "/v1/groups/usa")).json()) as { meetings: { title: string }[] };
    expect(detail.meetings.map(m => m.title)).toEqual(["Monthly meeting"]);
  });

  it("keeps group zikr times per group, editable only by its admins", async () => {
    const { call, member, admin } = await setup();
    const session = { title: "Community Zikr", startHour: 20, startMinute: 30, timeZoneIdentifier: "America/Chicago", weekdays: [6] };
    expect((await call(member, "PUT", "/v1/groups/usa/zikr/friday", session)).status).toBe(403);
    expect((await call(admin, "PUT", "/v1/groups/usa/zikr/friday", session)).status).toBe(200);
    expect((await call(admin, "PUT", "/v1/groups/usa/zikr/bad", { ...session, timeZoneIdentifier: "Mars/Olympus" })).status).toBe(400);
    const detail = (await (await call(member, "GET", "/v1/groups/usa")).json()) as { zikrSessions: { title: string; weekdays: number[] }[] };
    expect(detail.zikrSessions).toMatchObject([{ title: "Community Zikr", weekdays: [6] }]);
  });

  it("grants an admin role by code and keeps a signed-in member as one account", async () => {
    const { env, raw, call, member } = await setup();
    const code = "ACDEFGHJKM";
    raw.prepare("INSERT INTO member_invites(code_hash,group_id,created_by,created_at,expires_at,grants_role) VALUES(?,?,?,?,?,?)")
      .run(await sha256(code), "canada", "t", new Date().toISOString(), new Date(Date.now() + 86_400_000).toISOString(), "admin");
    const redeemed = await worker.fetch(new Request("https://api.example.com/v1/members/invite", {
      method: "POST", body: JSON.stringify({ code: "acdef-ghjkm" }),
      headers: { "content-type": "application/json", authorization: `Bearer ${member}`, "cf-connecting-ip": "1.1.1.1" },
    }), env);
    expect(redeemed.status).toBe(201);
    expect(((await redeemed.json()) as { memberID: string }).memberID).toBe("a".repeat(32));
    const me = (await (await call(member, "GET", "/v1/members/me")).json()) as { role: string };
    expect(me.role).toBe("admin");
    const groups = (await (await call(member, "GET", "/v1/groups")).json()) as { groups: { id: string; canManage: boolean }[] };
    expect(groups.groups.map(g => [g.id, g.canManage])).toEqual([["canada", true], ["usa", true]]);
  });

  it("stores a forwarded picture, routes it to its group, and serves it by signed link only", async () => {
    vi.stubGlobal("fetch", async (url: string) => String(url).startsWith("https://graph.facebook.com/")
      ? new Response(JSON.stringify({ url: "https://lookaside.example/img", mime_type: "image/jpeg", file_size: 4 }), { status: 200 })
      : new Response(new Uint8Array([1, 2, 3, 4]), { status: 200 }));
    const stored = new Map<string, ArrayBuffer>();
    const media = {
      async put(key: string, value: ArrayBuffer) { stored.set(key, value); },
      async get(key: string) {
        const value = stored.get(key);
        return value ? { body: value, httpMetadata: { contentType: "image/jpeg" } } : null;
      },
    };
    const { env, raw, call, member } = await setup({ MEDIA: media, WHATSAPP_ACCESS_TOKEN: "t", MEDIA_URL_SECRET: "s" } as unknown as Partial<Env>);
    const body = JSON.stringify({ entry: [{ changes: [{ value: { messages: [{
      from: "923001111111", id: "wamid.photo", type: "image", timestamp: "1760000000",
      image: { id: "123456789", mime_type: "image/jpeg", caption: "#usa Friday gathering" },
    }] } }] }] });
    const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
    const signed = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)));
    await worker.fetch(new Request("https://api.example.com/v1/whatsapp", {
      method: "POST", body, headers: { "x-hub-signature-256": "sha256=" + [...signed].map(b => b.toString(16).padStart(2, "0")).join("") },
    }), env);
    expect([...stored.keys()]).toEqual(["whatsapp/wamid.photo.jpg"]);
    const row = raw.prepare("SELECT id,title,image_key FROM member_group_posts").get() as { id: string; title: string; image_key: string };
    expect(row).toMatchObject({ title: "Friday gathering", image_key: "whatsapp/wamid.photo.jpg" });
    raw.prepare("UPDATE member_group_posts SET status='published'").run();
    const posts = (await (await call(member, "GET", "/v1/groups/usa/posts")).json()) as { posts: { imageURL?: string }[] };
    const link = new URL(posts.posts[0]?.imageURL ?? "");
    const ok = await worker.fetch(new Request(`https://api.example.com${link.pathname}${link.search}`), env);
    expect(ok.status).toBe(200);
    expect(new Uint8Array(await ok.arrayBuffer())).toEqual(new Uint8Array([1, 2, 3, 4]));
    const forged = await worker.fetch(new Request(`https://api.example.com${link.pathname}?exp=${link.searchParams.get("exp")}&sig=${"0".repeat(64)}`), env);
    expect(forged.status).toBe(404);
  });

  it("serves the meeting page with pinned libraries and the token kept out of the URL", async () => {
    const page = await worker.fetch(new Request("https://api.example.com/v1/meet"), {} as Env);
    const html = await page.text();
    expect(html).toContain("@cloudflare/realtimekit@2.0.2");
    expect(html).toContain("location.hash");
    expect(page.headers.get("cache-control")).toBe("no-store");
  });
});
