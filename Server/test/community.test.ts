import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { sqliteD1 } from "./sqlite-d1";
import { claimEmailGrants } from "../src/members";
import { autoplayDue } from "../src/session";
import { collectRoomRecordings } from "../src/roomRecordings";
import { dailyTag } from "../src/dailyMedia";

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
    // Super admin comes from the address list alone, as it does live.
    raw.prepare("INSERT INTO members(id,apple_subject,display_name,email,created_at,last_seen_at) VALUES(?,?,?,?,?,?)")
      .run(person.id, `invite:${person.id}`, person.role, person.role === "superadmin" ? "owner@example.com" : null, now, now);
    raw.prepare("INSERT INTO member_sessions(token_hash,member_id,created_at,expires_at,last_seen_at) VALUES(?,?,?,?,?)")
      .run(await sha256(person.token), person.id, now, later, now);
    for (const group of person.groups) {
      raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES(?,?,?,?,?)")
        .run(group, person.id, now, "test", person.role === "admin" ? "admin" : "member");
    }
  }
  const env = {
    DB: db, APNS_TOPIC: "us.naqshbaniaowaisiah", PUBLIC_BASE_URL: "https://api.example.com", SUPER_ADMIN_EMAILS: "owner@example.com",
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
    // Admin of the group the code was for, and of no other.
    const groups = (await (await call(member, "GET", "/v1/groups")).json()) as { groups: { id: string; canManage: boolean }[] };
    expect(groups.groups.map(g => [g.id, g.canManage])).toEqual([["canada", true], ["usa", false]]);
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

describe("group admins manage their group's people", () => {
  type People = {
    members: { id: string; role: string; isYou: boolean }[];
    invitations: { id: string; kind: string; label?: string; role: string }[];
  };
  type Call = Awaited<ReturnType<typeof setup>>["call"];
  const people = async (call: Call, token: string) =>
    (await (await call(token, "GET", "/v1/groups/usa/people")).json()) as People;
  const manages = async (call: Call, token: string, group: string) =>
    ((await (await call(token, "GET", "/v1/groups")).json()) as { groups: { id: string; canManage: boolean }[] })
      .groups.find(g => g.id === group)?.canManage ?? false;
  const redeem = (env: Env, code: string, ip: string) => worker.fetch(new Request("https://api.example.com/v1/members/invite", {
    method: "POST", body: JSON.stringify({ code }),
    headers: { "content-type": "application/json", "cf-connecting-ip": ip },
  }), env);

  it("adds someone by email at once, or when they first sign in with it", async () => {
    const { env, raw, call, member, admin } = await setup();
    raw.prepare("UPDATE members SET email=? WHERE id=?").run("existing@example.com", "a".repeat(32));
    const now = await call(admin, "POST", "/v1/groups/usa/people", { email: "Existing@Example.com", role: "admin" });
    expect(now.status).toBe(201);
    expect(((await now.json()) as { result: string }).result).toBe("added");
    expect(await manages(call, member, "usa")).toBe(true);

    const later = await call(admin, "POST", "/v1/groups/usa/people", { email: "new@example.com" });
    expect(((await later.json()) as { result: string }).result).toBe("pending");
    expect((await people(call, admin)).invitations).toMatchObject([{ kind: "email", label: "new@example.com", role: "member" }]);
    const stamp = new Date().toISOString();
    raw.prepare("INSERT INTO members(id,apple_subject,email,created_at,last_seen_at) VALUES(?,?,?,?,?)")
      .run("d".repeat(32), "apple-d", "new@example.com", stamp, stamp);
    await claimEmailGrants(env, "d".repeat(32), "NEW@example.com");
    expect((await people(call, admin)).members.map(m => m.id)).toContain("d".repeat(32));
    expect((await people(call, admin)).invitations).toEqual([]);
  });

  it("makes a code for a phone number, and withdraws an unused one", async () => {
    const { env, call, admin } = await setup();
    const made = await call(admin, "POST", "/v1/groups/usa/people", { phone: "+1 (508) 502-8015", role: "admin" });
    expect(made.status).toBe(201);
    const body = (await made.json()) as { result: string; code: string; phone: string };
    expect(body).toMatchObject({ result: "code", phone: "15085028015" });
    expect(body.code).toMatch(/^[A-Z0-9]{5}-[A-Z0-9]{5}$/);
    const [invitation] = (await people(call, admin)).invitations;
    expect(invitation).toMatchObject({ kind: "code", label: "+15085028015", role: "admin" });
    expect((await call(admin, "DELETE", `/v1/groups/usa/invitations/${invitation!.id}`)).status).toBe(204);
    expect((await people(call, admin)).invitations).toEqual([]);
    expect((await redeem(env, body.code, "1.1.1.2")).status).toBe(403);
    expect((await call(admin, "POST", "/v1/groups/usa/people", { phone: "12" })).status).toBe(400);
  });

  it("an admin code makes its holder admin of that group only", async () => {
    const { env, call, admin } = await setup();
    const { code } = (await (await call(admin, "POST", "/v1/groups/usa/people", { role: "admin" })).json()) as { code: string };
    const { token } = (await (await redeem(env, code, "1.1.1.3")).json()) as { token: string };
    expect(await manages(call, token, "usa")).toBe(true);
    expect((await call(token, "GET", "/v1/groups/canada")).status).toBe(404);
  });

  it("promotes, demotes and removes, but never the caller or a super admin", async () => {
    const { raw, call, member, admin, superAdmin } = await setup();
    raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by) VALUES(?,?,?,?)")
      .run("usa", "c".repeat(32), new Date().toISOString(), "test");
    expect((await call(admin, "PUT", `/v1/groups/usa/people/${"a".repeat(32)}`, { role: "admin" })).status).toBe(200);
    expect(await manages(call, member, "usa")).toBe(true);
    expect((await people(call, admin)).members.find(m => m.id === "c".repeat(32))?.role).toBe("superadmin");
    expect((await call(admin, "PUT", `/v1/groups/usa/people/${"b".repeat(32)}`, { role: "member" })).status).toBe(400);
    expect((await call(admin, "PUT", `/v1/groups/usa/people/${"c".repeat(32)}`, { role: "member" })).status).toBe(403);
    expect((await call(admin, "DELETE", `/v1/groups/usa/people/${"c".repeat(32)}`)).status).toBe(403);
    expect((await call(superAdmin, "PUT", `/v1/groups/usa/people/${"a".repeat(32)}`, { role: "member" })).status).toBe(200);
    expect(await manages(call, member, "usa")).toBe(false);
    expect((await call(admin, "DELETE", `/v1/groups/usa/people/${"a".repeat(32)}`)).status).toBe(204);
    expect((await call(member, "GET", "/v1/groups/usa")).status).toBe(404);
  });

  it("refuses members, and admins outside their own group", async () => {
    const { call, member, admin } = await setup();
    expect((await call(member, "GET", "/v1/groups/usa/people")).status).toBe(403);
    expect((await call(member, "POST", "/v1/groups/usa/people", { email: "x@example.com" })).status).toBe(403);
    expect((await call(admin, "GET", "/v1/groups/canada/people")).status).toBe(404);
    expect((await call(admin, "POST", "/v1/groups/canada/people", { email: "x@example.com" })).status).toBe(404);
  });

  it("keeps a before-Fajr group zikr time", async () => {
    const { call, admin, member } = await setup();
    const saved = await call(admin, "PUT", "/v1/groups/usa/zikr/tahajjud", {
      title: "Tahajjud Zikr", startHour: 4, startMinute: 0, timeZoneIdentifier: "Asia/Karachi", anchor: "beforeFajr",
    });
    expect(saved.status).toBe(200);
    const detail = (await (await call(member, "GET", "/v1/groups/usa")).json()) as { zikrSessions: { anchor?: string }[] };
    expect(detail.zikrSessions[0]?.anchor).toBe("tahajjud");
  });
});

describe("recorded zikr", () => {
  /** An R2 stand-in that keeps bytes and answers byte ranges like R2 does. */
  function memoryBucket() {
    const stored = new Map<string, { bytes: Uint8Array; type: string }>();
    const bucket = {
      async put(key: string, value: ReadableStream | ArrayBuffer, options: { httpMetadata: { contentType: string } }) {
        const bytes = new Uint8Array(value instanceof ArrayBuffer ? value : await new Response(value).arrayBuffer());
        stored.set(key, { bytes, type: options.httpMetadata.contentType });
      },
      async head(key: string) {
        const item = stored.get(key);
        return item ? { size: item.bytes.length, httpMetadata: { contentType: item.type } } : null;
      },
      async get(key: string, options?: { range?: Headers }) {
        const item = stored.get(key);
        if (!item) return null;
        const match = /bytes=(\d+)-(\d*)/.exec(options?.range?.get("range") ?? "");
        const offset = match ? Number(match[1]) : 0;
        const end = match && match[2] ? Number(match[2]) : item.bytes.length - 1;
        return {
          size: item.bytes.length, httpMetadata: { contentType: item.type },
          range: match ? { offset, length: end - offset + 1 } : undefined,
          body: item.bytes.slice(offset, end + 1),
        };
      },
      async delete(key: string) { stored.delete(key); },
    };
    return { bucket, stored };
  }

  const upload = (env: Env, token: string, bytes: Uint8Array, type = "audio/mpeg", query = "title=Friday%20zikr&durationSeconds=1800") =>
    worker.fetch(new Request(`https://api.example.com/v1/groups/usa/recordings?${query}`, {
      method: "POST", body: bytes as unknown as BodyInit,
      headers: { authorization: `Bearer ${token}`, "content-type": type, "content-length": String(bytes.length) },
    }), env);

  type Live = {
    sessionID: string; recorded: boolean; listeners: number;
    queue: { kind: string; id: string; title: string; url?: string; contentType?: string; durationSeconds?: number }[];
    playback: { index: number; positionSeconds: number; paused: boolean; finished: boolean };
    notice?: { text: string }; attendance?: { name: string; isHere: boolean }[];
  };
  const liveOf = async (call: (t: string, m: string, p: string, b?: unknown) => Promise<Response>, token: string) =>
    ((await (await call(token, "GET", "/v1/groups/usa")).json()) as { live?: Live }).live;

  it("lets a group admin upload a recording and play it to the group, served in byte ranges", async () => {
    const { bucket, stored } = memoryBucket();
    const { env, call, member, admin } = await setup({ MEDIA: bucket, MEDIA_URL_SECRET: "s" } as unknown as Partial<Env>);
    const bytes = new Uint8Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect((await upload(env, member, bytes)).status).toBe(403);
    expect((await upload(env, admin, bytes, "application/pdf")).status).toBe(415);
    const created = await upload(env, admin, bytes);
    expect(created.status).toBe(201);
    const { id } = (await created.json()) as { id: string };
    expect([...stored.keys()]).toEqual([`recordings/usa/${id}.mp3`]);

    const listed = (await (await call(admin, "GET", "/v1/groups/usa/recordings")).json()) as { recordings: { id: string; title: string; durationSeconds: number }[] };
    expect(listed.recordings).toMatchObject([{ id, title: "Friday zikr", durationSeconds: 1800 }]);
    expect((await call(member, "GET", "/v1/groups/usa/recordings")).status).toBe(403);

    const started = (await (await call(admin, "POST", "/v1/groups/usa/live", { state: "live", queue: [{ recordingID: id }] })).json()) as { recorded: boolean };
    expect(started.recorded).toBe(true);
    const live = await liveOf(call, member);
    expect(live).toMatchObject({ recorded: true, queue: [{ kind: "recording", id, contentType: "audio/mpeg", durationSeconds: 1800 }] });
    expect(live?.playback).toMatchObject({ index: 0, paused: false, finished: false });

    const url = new URL(live!.queue[0]!.url!);
    const part = await worker.fetch(new Request(`https://api.example.com${url.pathname}${url.search}`, { headers: { range: "bytes=2-5" } }), env);
    expect(part.status).toBe(206);
    expect(part.headers.get("content-range")).toBe("bytes 2-5/10");
    expect([...new Uint8Array(await part.arrayBuffer())]).toEqual([2, 3, 4, 5]);
    // The signature covers the key: another group's file cannot be reached by editing the link.
    const forged = url.pathname.replace("usa", "canada");
    expect((await worker.fetch(new Request(`https://api.example.com${forged}${url.search}`), env)).status).toBe(404);

    // Not deleted while it plays; deleted once the session ends.
    expect((await call(admin, "DELETE", `/v1/groups/usa/recordings/${id}`)).status).toBe(409);
    await call(admin, "POST", "/v1/groups/usa/live", { state: "offline" });
    expect((await call(admin, "DELETE", `/v1/groups/usa/recordings/${id}`)).status).toBe(204);
    expect(stored.size).toBe(0);
  });

  it("keeps everyone on one clock the admin controls, and stays open after the recording ends", async () => {
    const { bucket } = memoryBucket();
    const { env, raw, call, member, admin } = await setup({ MEDIA: bucket, MEDIA_URL_SECRET: "s" } as unknown as Partial<Env>);
    const first = ((await (await upload(env, admin, new Uint8Array([1]), "audio/mpeg", "title=One&durationSeconds=600")).json()) as { id: string }).id;
    const second = ((await (await upload(env, admin, new Uint8Array([2]), "audio/mpeg", "title=Two&durationSeconds=300")).json()) as { id: string }).id;
    await call(admin, "POST", "/v1/groups/usa/live", { state: "live", queue: [{ recordingID: first }, { recordingID: second }] });
    const control = (body: unknown) => call(admin, "POST", "/v1/groups/usa/control", body);
    expect((await call(member, "POST", "/v1/groups/usa/control", { action: "pause" })).status).toBe(403);

    // Twelve minutes in: the first (ten minutes) is over, two minutes into the second.
    raw.prepare("UPDATE group_live SET position_at=? WHERE group_id='usa'").run(new Date(Date.now() - 720_000).toISOString());
    let live = await liveOf(call, member);
    expect(live?.playback.index).toBe(1);
    expect(live?.playback.positionSeconds).toBeGreaterThan(119);

    await control({ action: "pause" });
    live = await liveOf(call, member);
    expect(live?.playback).toMatchObject({ index: 1, paused: true });
    await control({ action: "seek", seconds: 30 });
    live = await liveOf(call, member);
    expect(live?.playback.positionSeconds).toBe(30);
    await control({ action: "previous" });
    expect((await liveOf(call, member))?.playback).toMatchObject({ index: 1, positionSeconds: 0 });
    await control({ action: "previous" });
    expect((await liveOf(call, member))?.playback).toMatchObject({ index: 0, positionSeconds: 0 });
    await control({ action: "resume" });

    // Long past the end: finished, but still live until an admin ends it.
    raw.prepare("UPDATE group_live SET position_at=? WHERE group_id='usa'").run(new Date(Date.now() - 3 * 3_600_000).toISOString());
    live = await liveOf(call, member);
    expect(live?.playback.finished).toBe(true);
    const groups = (await (await call(member, "GET", "/v1/groups")).json()) as { groups: { isLive: boolean }[] };
    expect(groups.groups[0]?.isLive).toBe(true);

    // Adding to a finished session plays the addition straight away.
    await control({ action: "add", items: [{ recordingID: first }] });
    expect((await liveOf(call, member))?.playback).toMatchObject({ index: 2, finished: false, paused: false });

    await control({ action: "notice", text: "Dua in five minutes" });
    expect((await liveOf(call, member))?.notice?.text).toBe("Dua in five minutes");
    expect((await control({ action: "jump", index: 9 })).status).toBe(400);
  });

  it("counts who is listening, takes dua requests for the admins, and keeps a record of the session", async () => {
    const { bucket } = memoryBucket();
    const { env, call, member, admin } = await setup({ MEDIA: bucket, MEDIA_URL_SECRET: "s" } as unknown as Partial<Env>);
    const id = ((await (await upload(env, admin, new Uint8Array([1]))).json()) as { id: string }).id;
    expect((await call(member, "POST", "/v1/groups/usa/presence")).status).toBe(409);
    await call(admin, "POST", "/v1/groups/usa/live", { state: "live", queue: [{ recordingID: id }] });
    const checked = (await (await call(member, "POST", "/v1/groups/usa/presence")).json()) as { listeners: number };
    expect(checked.listeners).toBe(1);
    await call(admin, "POST", "/v1/groups/usa/presence");
    const seen = await liveOf(call, admin);
    expect(seen?.listeners).toBe(2);
    expect(seen?.attendance?.map(person => person.name).sort()).toEqual(["admin", "member"]);
    // Members see the count, not the names.
    expect((await liveOf(call, member))?.attendance).toBeUndefined();

    expect((await call(member, "POST", "/v1/groups/usa/duas", { text: "For my mother's health" })).status).toBe(201);
    expect((await call(member, "POST", "/v1/groups/usa/duas", { text: "Privately", showName: false })).status).toBe(201);
    expect((await call(member, "GET", "/v1/groups/usa/duas")).status).toBe(403);
    const duas = (await (await call(admin, "GET", "/v1/groups/usa/duas")).json()) as { requests: { id: string; text: string; name?: string; isRead: boolean }[] };
    expect(duas.requests.map(dua => [dua.text, dua.name ?? null]).sort()).toEqual([["For my mother's health", "member"], ["Privately", null]]);
    const detail = (await (await call(admin, "GET", "/v1/groups/usa")).json()) as { unreadDuaRequests: number };
    expect(detail.unreadDuaRequests).toBe(2);
    expect((await call(admin, "POST", `/v1/groups/usa/duas/${duas.requests[0]!.id}/read`)).status).toBe(204);
    expect(((await (await call(admin, "GET", "/v1/groups/usa")).json()) as { unreadDuaRequests: number }).unreadDuaRequests).toBe(1);

    await call(admin, "POST", "/v1/groups/usa/live", { state: "offline" });
    const history = (await (await call(admin, "GET", "/v1/groups/usa/history")).json()) as { sessions: { id: string; attendees: number }[] };
    expect(history.sessions).toMatchObject([{ attendees: 2 }]);
    const attendees = (await (await call(admin, "GET", `/v1/groups/usa/history/${history.sessions[0]!.id}`)).json()) as { attendees: { name: string }[] };
    expect(attendees.attendees).toHaveLength(2);
    expect((await call(member, "GET", "/v1/groups/usa/history")).status).toBe(403);
  });

  it("starts a clock-time zikr by itself with its recording, once, when no session is live", async () => {
    const { bucket } = memoryBucket();
    const { env, raw, call, member, admin } = await setup({ MEDIA: bucket, MEDIA_URL_SECRET: "s" } as unknown as Partial<Env>);
    const id = ((await (await upload(env, admin, new Uint8Array([1]))).json()) as { id: string }).id;
    const now = new Date("2026-10-30T01:02:00Z"); // Thursday 21:02 in New York
    const saved = await call(admin, "PUT", "/v1/groups/usa/zikr/thursday", {
      title: "Thursday zikr", startHour: 21, startMinute: 0, timeZoneIdentifier: "America/New_York", weekdays: [5],
      autoplay: [{ recordingID: id }],
    });
    expect(saved.status).toBe(200);
    expect(((await (await call(member, "GET", "/v1/groups/usa")).json()) as { zikrSessions: { autoplayTitle?: string }[] })
      .zikrSessions[0]?.autoplayTitle).toBe("Friday zikr");
    await autoplayDue(env, new Date("2026-10-30T00:50:00Z")); // ten minutes early
    expect(await liveOf(call, member)).toBeUndefined();
    await autoplayDue(env, now);
    expect((await liveOf(call, member))?.queue.map(item => item.id)).toEqual([id]);
    // Ended by the admin, it does not start again in the same window.
    await call(admin, "POST", "/v1/groups/usa/live", { state: "offline" });
    await autoplayDue(env, new Date(now.getTime() + 120_000));
    expect(await liveOf(call, member)).toBeUndefined();
    expect(raw.prepare("SELECT started_by FROM group_live_history").get()).toMatchObject({ started_by: "schedule" });
  });

  it("offers the channel's past zikr and plays one as a recording, but a live video as live", async () => {
    vi.stubGlobal("fetch", async (url: string) => {
      const ids = new URL(url).searchParams.get("id")?.split(",") ?? [];
      return new Response(JSON.stringify({ items: ids.map(id => ({
        id,
        snippet: { liveBroadcastContent: id === "liveliveliv" ? "live" : "none" },
        contentDetails: { duration: id === "liveliveliv" ? "P0D" : "PT1H5M" },
      })) }), { status: 200 });
    });
    const { raw, call, member, admin } = await setup({ YOUTUBE_API_KEY: "k" } as Partial<Env>);
    const now = new Date().toISOString();
    const video = (id: string, title: string, published: string) =>
      raw.prepare(`INSERT INTO feed_items(id,source,kind,title,source_url,video_id,published_at,updated_at)
        VALUES(?,'youtube','video',?,?,?,?,?)`).run(`youtube:${id}`, title, `https://www.youtube.com/watch?v=${id}`, id, published, now);
    video("pastzikr001", "Online Zikr with Sheikh", "2026-10-20T16:00:00Z");
    video("bayanbayan1", "Surah Al Imran Ayat 185", "2026-10-21T06:00:00Z");
    video("liveliveliv", "Online Zikr with Sheikh", "2026-10-27T16:00:00Z");
    const listed = (await (await call(admin, "GET", "/v1/groups/usa/recordings")).json()) as { pastVideos: { videoID: string; durationSeconds: number }[] };
    expect(listed.pastVideos).toEqual([expect.objectContaining({ videoID: "pastzikr001", durationSeconds: 3900 })]);

    // A pasted past video becomes a recording in the queue.
    await call(admin, "POST", "/v1/groups/usa/live", { state: "live", videoID: "pastzikr001" });
    let live = await liveOf(call, member) as Live & { videoID?: string };
    expect(live).toMatchObject({ recorded: true, queue: [{ kind: "video", id: "pastzikr001", title: "Online Zikr with Sheikh", durationSeconds: 3900 }] });
    expect(live.videoID).toBeUndefined();

    await call(admin, "POST", "/v1/groups/usa/live", { state: "live", videoID: "liveliveliv" });
    live = await liveOf(call, member) as Live & { videoID?: string };
    expect(live).toMatchObject({ recorded: false, videoID: "liveliveliv", queue: [] });
    // A live video cannot be queued as a recording.
    expect((await call(admin, "POST", "/v1/groups/usa/live", { state: "live", queue: [{ videoID: "liveliveliv" }] })).status).toBe(400);
  });
});

describe("recorded rooms", () => {
  it("records a room, copies the finished recording into the group's recordings, and stops with the session", async () => {
    const calls: string[] = [];
    let meetingBody: Record<string, unknown> = {};
    vi.stubGlobal("fetch", async (url: string, init?: RequestInit) => {
      const target = String(url);
      calls.push(`${init?.method ?? "GET"} ${target.replace("https://api.cloudflare.com/client/v4/accounts/a/realtime/kit/b", "")}`);
      const reply = (body: unknown) => new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } });
      if (target.endsWith("/meetings")) { meetingBody = JSON.parse(String(init?.body)); return reply({ data: { id: "room-1" } }); }
      if (target.includes("/recordings?meeting_id=room-1")) return reply({ data: [{ id: "r-1", status: "UPLOADED", started_time: "2026-10-27T16:00:00Z" }] });
      if (target.endsWith("/recordings/r-1")) return reply({ data: { id: "r-1", status: "UPLOADED", recording_duration: 1795.4, audio_download_url: "https://files.example/r-1.m4a", download_url: "https://files.example/r-1.mp4" } });
      if (target === "https://files.example/r-1.m4a") return new Response(new Uint8Array([9, 9, 9]), { headers: { "content-type": "audio/mp4", "content-length": "3" } });
      if (target.endsWith("/recordings/active-recording/room-1")) return reply({ data: { id: "r-2" } });
      return reply({ data: {} });
    });
    const stored = new Map<string, unknown>();
    const media = { async put(key: string, value: unknown) { stored.set(key, value); } };
    const { env, raw, call, member, admin } = await setup({
      REALTIME_ACCOUNT_ID: "a", REALTIME_APP_ID: "b", REALTIME_API_TOKEN: "c", MEDIA: media,
    } as unknown as Partial<Env>);
    await call(admin, "POST", "/v1/groups/usa/live", { state: "live", title: "Thursday zikr", room: true, record: true });
    expect(meetingBody).toMatchObject({ record_on_start: true, recording_config: { file_name_prefix: "usa", audio_config: { export_file: true } } });
    const live = ((await (await call(member, "GET", "/v1/groups/usa")).json()) as { live: { roomRecording: boolean } }).live;
    expect(live.roomRecording).toBe(true);

    await collectRoomRecordings(env);
    const kept = raw.prepare("SELECT title,media_key,content_type,duration_seconds,created_by FROM group_recordings").get();
    expect(kept).toEqual({ title: "Thursday zikr · 2026-10-27", media_key: "recordings/usa/r-1.m4a", content_type: "audio/mp4", duration_seconds: 1795, created_by: "room" });
    expect([...stored.keys()]).toEqual(["recordings/usa/r-1.m4a"]);
    // Copied once only.
    await collectRoomRecordings(env);
    expect(raw.prepare("SELECT COUNT(*) AS n FROM group_recordings").get()).toEqual({ n: 1 });

    await call(admin, "POST", "/v1/groups/usa/live", { state: "offline" });
    expect(calls).toContain("PUT /recordings/r-2");
  });
});

describe("administrators and Halqahs", () => {
  const A = "a".repeat(32), B = "b".repeat(32), C = "c".repeat(32);
  const roleOf = async (call: (t: string, m: string, p: string, b?: unknown) => Promise<Response>, token: string, id: string) =>
    ((await (await call(token, "GET", "/v1/groups/usa/people")).json()) as { members: { id: string; role: string }[] })
      .members.find(person => person.id === id)?.role;

  it("lets only Administrators and the Super admin make, change or remove Administrators", async () => {
    const { raw, call, member, admin, superAdmin } = await setup();
    // An Admin makes Admins, not Administrators.
    expect((await call(admin, "PUT", `/v1/groups/usa/people/${A}`, { role: "administrator" })).status).toBe(403);
    expect((await call(admin, "POST", "/v1/groups/usa/people", { role: "administrator" })).status).toBe(403);
    expect((await call(admin, "PUT", `/v1/groups/usa/people/${A}`, { role: "admin" })).status).toBe(200);
    // The Super admin makes the first Administrator.
    expect((await call(superAdmin, "PUT", `/v1/groups/usa/people/${B}`, { role: "administrator" })).status).toBe(200);
    expect(await roleOf(call, superAdmin, B)).toBe("administrator");
    const people = (await (await call(admin, "GET", "/v1/groups/usa/people")).json()) as { canAppointAdministrators: boolean; members: { id: string }[] };
    expect(people.canAppointAdministrators).toBe(true);
    expect(people.members[0]?.id).toBe(B);
    // The Administrator (b) now appoints another; an Admin (a) cannot undo it.
    expect((await call(admin, "PUT", `/v1/groups/usa/people/${A}`, { role: "administrator" })).status).toBe(200);
    raw.prepare("UPDATE member_group_members SET role='admin' WHERE member_id=?").run(B);
    expect((await call(admin, "PUT", `/v1/groups/usa/people/${A}`, { role: "member" })).status).toBe(403);
    expect((await call(admin, "DELETE", `/v1/groups/usa/people/${A}`)).status).toBe(403);
    expect(((await (await call(admin, "GET", "/v1/groups/usa/people")).json()) as { canAppointAdministrators: boolean }).canAppointAdministrators).toBe(false);
    // An Administrator of one Halqah has nothing in another.
    expect((await call(member, "GET", "/v1/groups/canada/people")).status).toBe(404);
    // Roles reach the app: the highest one, and each Halqah's own.
    const me = (await (await call(member, "GET", "/v1/members/me")).json()) as { role: string };
    expect(me.role).toBe("administrator");
    const groups = (await (await call(member, "GET", "/v1/groups")).json()) as { groups: { id: string; myRole: string; canManage: boolean }[] };
    expect(groups.groups).toMatchObject([{ id: "usa", myRole: "administrator", canManage: true }]);
  });

  it("makes Administrators by code, and never makes a Super admin from a stored role or a code", async () => {
    const { env, raw, call, member, superAdmin } = await setup();
    const { code } = (await (await call(superAdmin, "POST", "/v1/groups/usa/people", { role: "administrator" })).json()) as { code: string };
    const redeemed = await worker.fetch(new Request("https://api.example.com/v1/members/invite", {
      method: "POST", headers: { authorization: `Bearer ${member}`, "content-type": "application/json" }, body: JSON.stringify({ code }),
    }), env);
    expect(redeemed.status).toBe(201);
    expect(await roleOf(call, superAdmin, A)).toBe("administrator");
    // A later member code does not demote.
    const second = (await (await call(superAdmin, "POST", "/v1/groups/usa/people", { role: "member" })).json()) as { code: string };
    await worker.fetch(new Request("https://api.example.com/v1/members/invite", {
      method: "POST", headers: { authorization: `Bearer ${member}`, "content-type": "application/json" }, body: JSON.stringify({ code: second.code }),
    }), env);
    expect(await roleOf(call, superAdmin, A)).toBe("administrator");
    // A stored 'superadmin' is nothing without a listed address.
    raw.prepare("UPDATE members SET role='superadmin' WHERE id=?").run(A);
    expect(((await (await call(member, "GET", "/v1/members/me")).json()) as { role: string }).role).toBe("administrator");
    expect((await call(member, "GET", "/v1/groups/canada")).status).toBe(404);
  });

  it("lets the Super admin make, rename and retire Halqahs and place anyone in any of them", async () => {
    const { raw, call, member, admin, superAdmin } = await setup();
    expect((await call(admin, "POST", "/v1/groups", { name: "New York" })).status).toBe(403);
    const made = await call(superAdmin, "POST", "/v1/groups", { name: "New York", description: "Halqah of New York" });
    expect(made.status).toBe(201);
    const { id } = (await made.json()) as { id: string };
    expect(id).toBe("new-york");
    expect((await call(superAdmin, "POST", "/v1/groups", { name: "new york" })).status).toBe(409);
    expect((await call(superAdmin, "PUT", `/v1/groups/${id}`, { name: "New York City" })).status).toBe(200);

    // Everyone who has signed in, with their Halqahs; only for the Super admin.
    expect((await call(admin, "GET", "/v1/members")).status).toBe(403);
    const directory = (await (await call(superAdmin, "GET", "/v1/members")).json()) as {
      members: { id: string; isSuperAdmin: boolean; halqahs: { groupID: string; role: string }[] }[];
    };
    expect(directory.members.find(person => person.id === B)?.halqahs).toEqual([{ groupID: "usa", groupName: "United States", role: "admin" }]);
    expect(directory.members.find(person => person.id === C)?.isSuperAdmin).toBe(true);
    // Placed from the directory, as an Administrator of the new Halqah.
    expect((await call(admin, "POST", `/v1/groups/usa/people`, { memberID: A })).status).toBe(403);
    expect((await call(superAdmin, "POST", `/v1/groups/${id}/people`, { memberID: A, role: "administrator" })).status).toBe(201);
    const groups = (await (await call(member, "GET", "/v1/groups")).json()) as { groups: { id: string; name: string; myRole: string }[] };
    expect(groups.groups.find(group => group.id === id)).toMatchObject({ name: "New York City", myRole: "administrator" });

    expect((await call(member, "DELETE", `/v1/groups/${id}`)).status).toBe(403);
    expect((await call(superAdmin, "DELETE", `/v1/groups/${id}`)).status).toBe(204);
    const after = (await (await call(member, "GET", "/v1/groups")).json()) as { groups: { id: string }[] };
    expect(after.groups.map(group => group.id)).toEqual(["usa"]);
    // Retired, not deleted: its people are kept.
    expect(raw.prepare("SELECT COUNT(*) AS n FROM member_group_members WHERE group_id=?").get(id)).toEqual({ n: 1 });
  });
});

describe("daily pictures", () => {
  const bucket = () => {
    const stored = new Map<string, Uint8Array>();
    return {
      stored,
      async put(key: string, value: ReadableStream | ArrayBuffer) {
        stored.set(key, new Uint8Array(value instanceof ArrayBuffer ? value : await new Response(value).arrayBuffer()));
      },
      async delete(key: string) { stored.delete(key); },
    };
  };
  const upload = (env: Env, token: string, query: string) =>
    worker.fetch(new Request(`https://api.example.com/v1/daily-media/manage?${query}`, {
      method: "POST", body: new Uint8Array([1, 2, 3]) as unknown as BodyInit,
      headers: { authorization: `Bearer ${token}`, "content-type": "image/jpeg", "content-length": "3" },
    }), env);
  const publicDay = async (env: Env, day: string) =>
    ((await (await worker.fetch(new Request(`https://api.example.com/v1/daily-media?day=${day}`), env)).json()) as
      { items: { id: string; slot: string; imageURL?: string; popup: boolean; caption?: string }[] }).items;

  it("reads the place and day from a forwarded caption's #tag", () => {
    expect(dailyTag("#aqwal 2026-10-30 Remembrance is the life of the heart")).toEqual({ slot: "aqwal", day: "2026-10-30", caption: "Remembrance is the life of the heart" });
    expect(dailyTag("#حدیث")).toEqual({ slot: "hadith", day: null, caption: "" });
    expect(dailyTag("#usa Friday gathering")).toBeNull();
    expect(dailyTag("No tag")).toBeNull();
  });

  it("shows only what the Super admin publishes, and only on its days", async () => {
    const media = bucket();
    const { env, call, admin, superAdmin } = await setup({ MEDIA: media, MEDIA_URL_SECRET: "s" } as unknown as Partial<Env>);
    expect((await upload(env, admin, "slot=aqwal&day=2026-10-30&publish=1")).status).toBe(403);
    expect((await upload(env, superAdmin, "slot=nowhere&day=2026-10-30")).status).toBe(400);
    expect((await upload(env, superAdmin, "slot=aqwal&publish=1")).status).toBe(400);
    const published = (await (await upload(env, superAdmin, "slot=aqwal&day=2026-10-30&publish=1&caption=Today")).json()) as { id: string };
    const draft = (await (await upload(env, superAdmin, "slot=quote&day=2026-10-30&popup=1")).json()) as { id: string };
    expect(media.stored.size).toBe(2);

    let items = await publicDay(env, "2026-10-30");
    expect(items.map(item => item.id)).toEqual([published.id]);
    expect(items[0]).toMatchObject({ slot: "aqwal", caption: "Today", popup: false });
    expect(items[0]?.imageURL).toContain("/v1/media/daily%2F");
    expect(await publicDay(env, "2026-10-31")).toEqual([]);

    // Published as a pop-up quote; an announcement for three days.
    expect((await call(superAdmin, "PUT", `/v1/daily-media/manage/${draft.id}`, { status: "published" })).status).toBe(200);
    const notice = (await (await upload(env, superAdmin, "slot=announcement&day=2026-10-29&endDay=2026-10-31&publish=1")).json()) as { id: string };
    items = await publicDay(env, "2026-10-30");
    expect(items.map(item => item.slot).sort()).toEqual(["announcement", "aqwal", "quote"]);
    expect(items.find(item => item.slot === "quote")?.popup).toBe(true);
    expect((await publicDay(env, "2026-10-31")).map(item => item.id)).toEqual([notice.id]);
    expect((await call(superAdmin, "PUT", `/v1/daily-media/manage/${notice.id}`, { endDay: "2026-10-01" })).status).toBe(400);

    // Hidden, it goes; deleted, its file goes too.
    await call(superAdmin, "PUT", `/v1/daily-media/manage/${published.id}`, { status: "hidden" });
    expect((await publicDay(env, "2026-10-30")).some(item => item.id === published.id)).toBe(false);
    expect((await call(admin, "DELETE", `/v1/daily-media/manage/${notice.id}`)).status).toBe(403);
    expect((await call(superAdmin, "DELETE", `/v1/daily-media/manage/${notice.id}`)).status).toBe(204);
    expect(media.stored.size).toBe(2);
    const manage = (await (await call(superAdmin, "GET", "/v1/daily-media/manage")).json()) as { items: { id: string; status: string }[] };
    expect(manage.items.map(item => item.status).sort()).toEqual(["hidden", "published"]);
  });

  it("records a #tagged picture forwarded on WhatsApp as a draft for its place", async () => {
    vi.stubGlobal("fetch", async (url: string) => String(url).startsWith("https://graph.facebook.com/")
      ? new Response(JSON.stringify({ url: "https://lookaside.example/img", mime_type: "image/jpeg", file_size: 4 }), { status: 200 })
      : new Response(new Uint8Array([1, 2, 3, 4]), { status: 200 }));
    const media = { async put() {} };
    const { env, raw } = await setup({ MEDIA: media, WHATSAPP_ACCESS_TOKEN: "t", MEDIA_URL_SECRET: "s" } as unknown as Partial<Env>);
    const body = JSON.stringify({ entry: [{ changes: [{ value: { messages: [{
      from: "923001111111", id: "wamid.quote", type: "image", timestamp: "1760000000",
      image: { id: "987654321", mime_type: "image/jpeg", caption: "#quote 2026-11-02" },
    }] } }] }] });
    const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
    const signed = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)));
    const send = () => worker.fetch(new Request("https://api.example.com/v1/whatsapp", {
      method: "POST", body, headers: { "x-hub-signature-256": "sha256=" + [...signed].map(b => b.toString(16).padStart(2, "0")).join("") },
    }), env);
    await send();
    await send(); // Meta's retry
    expect(raw.prepare("SELECT slot,day,status,source,media_key FROM daily_media").all()).toEqual([
      { slot: "quote", day: "2026-11-02", status: "draft", source: "whatsapp", media_key: "whatsapp/wamid.quote.jpg" },
    ]);
    expect(raw.prepare("SELECT COUNT(*) AS n FROM member_group_posts").get()).toEqual({ n: 0 });
  });
});

describe("post pictures and videos", () => {
  it("lets an admin attach pictures and videos to a post, kept private to the group", async () => {
    const stored = new Map<string, string>();
    const media = {
      async put(key: string, _value: unknown, options: { httpMetadata: { contentType: string } }) { stored.set(key, options.httpMetadata.contentType); },
      async head(key: string) { return stored.has(key) ? { size: 3, httpMetadata: { contentType: stored.get(key) } } : null; },
    };
    const { env, call, member, admin } = await setup({ MEDIA: media, MEDIA_URL_SECRET: "s" } as unknown as Partial<Env>);
    const send = (token: string, type: string, group = "usa") =>
      worker.fetch(new Request(`https://api.example.com/v1/groups/${group}/media`, {
        method: "POST", body: new Uint8Array([1, 2, 3]) as unknown as BodyInit,
        headers: { authorization: `Bearer ${token}`, "content-type": type, "content-length": "3" },
      }), env);
    expect((await send(member, "image/jpeg")).status).toBe(403);
    expect((await send(admin, "application/zip")).status).toBe(415);
    const picture = (await (await send(admin, "image/jpeg")).json()) as { key: string; kind: string };
    const video = (await (await send(admin, "video/quicktime")).json()) as { key: string; kind: string };
    expect([picture.kind, video.kind]).toEqual(["image", "video"]);
    expect(picture.key).toMatch(/^posts\/usa\/[0-9a-f-]{36}\.jpg$/);

    // Only this group's own uploads, and only ones that arrived.
    expect((await call(admin, "POST", "/v1/groups/usa/posts", { title: "Gathering", media: ["posts/canada/x.jpg"] })).status).toBe(400);
    expect((await call(admin, "POST", "/v1/groups/usa/posts", { title: "Gathering", media: [`posts/usa/${crypto.randomUUID()}.jpg`] })).status).toBe(400);
    expect((await call(admin, "POST", "/v1/groups/usa/posts", { title: "Gathering", media: [picture.key, video.key] })).status).toBe(201);
    const posts = (await (await call(member, "GET", "/v1/groups/usa/posts")).json()) as { posts: { title: string; media?: { url: string; kind: string }[] }[] };
    const post = posts.posts.find(item => item.title === "Gathering");
    expect(post?.media?.map(item => item.kind)).toEqual(["image", "video"]);
    expect(post?.media?.[0]?.url).toContain("/v1/media/posts%2Fusa%2F");
  });
});
