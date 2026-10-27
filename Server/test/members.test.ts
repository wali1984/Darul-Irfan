import { describe, expect, it } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";

/** A tiny stand-in for D1 that answers from fixture tables, so the isolation
 *  rules can be exercised without a database. Each prepare() is matched by the
 *  distinctive fragment of its SQL. */
interface SessionFixture {
  member: string;
  expiresAt: string;
  /** sha256 of the bearer token, which is what the route looks up. */
  hash: string;
}

interface Fixture {
  sessions: Record<string, SessionFixture>;
  memberships: Array<{ group: string; member: string }>;
  posts: Array<{ group: string; id: string; kind: string; title: string; video?: string }>;
  groups: Array<{ id: string; name: string }>;
}

const TOKEN_A = "a".repeat(64);
const TOKEN_B = "b".repeat(64);
const future = new Date(Date.now() + 86_400_000).toISOString();
const past = new Date(Date.now() - 86_400_000).toISOString();

function envFor(fixture: Fixture, deletes: string[] = []): Env {
  const db = {
    prepare(sql: string) {
      let bound: unknown[] = [];
      const statement = {
        bind(...values: unknown[]) { bound = values; return statement; },
        async first() {
          // The session route is rate limited, and the limiter reads its own
          // counter back; without this it reads nothing and refuses with 429.
          if (sql.includes("FROM rate_limits")) return { request_count: 1 };
          if (sql.includes("FROM member_sessions")) {
            // The route hashes the token, so look up by hash of each known one.
            const match = Object.entries(fixture.sessions)
              .find(([, value]) => value.hash === bound[0]);
            return match ? { member_id: match[1].member, expires_at: match[1].expiresAt } : null;
          }
          if (sql.includes("FROM member_group_members WHERE group_id=? AND member_id=?")) {
            const [group, member] = bound as [string, string];
            return fixture.memberships.some(m => m.group === group && m.member === member) ? { ok: 1 } : null;
          }
          return null;
        },
        async all() {
          if (sql.includes("FROM member_groups g JOIN member_group_members m")) {
            const member = bound[0] as string;
            const mine = fixture.memberships.filter(m => m.member === member).map(m => m.group);
            return { results: fixture.groups.filter(g => mine.includes(g.id)).map(g => ({ id: g.id, name: g.name, description: null, meeting_url: null, meeting_note: null })) };
          }
          if (sql.includes("FROM member_group_posts")) {
            const group = bound[0] as string;
            return { results: fixture.posts.filter(p => p.group === group).map(p => ({ id: p.id, kind: p.kind, title: p.title, body: null, youtube_video_id: p.video ?? null, link_url: null, published_at: "2026-10-01T00:00:00Z" })) };
          }
          return { results: [] };
        },
        async run() {
          if (sql.startsWith("DELETE")) deletes.push(sql.split(" FROM ")[1]?.split(" ")[0] ?? sql);
          return {};
        },
      } as Record<string, unknown> & { bind: (...v: unknown[]) => typeof statement };
      return statement;
    },
  };
  return { DB: db, APNS_TOPIC: "us.naqshbaniaowaisiah" } as unknown as Env;
}

/** sha256, matching what the route computes over the bearer token. */
async function hash(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("");
}

async function baseFixture(): Promise<Fixture> {
  return {
    sessions: {
      usa: { member: "member-usa", expiresAt: future, hash: await hash(TOKEN_A) },
      canada: { member: "member-canada", expiresAt: future, hash: await hash(TOKEN_B) },
    },
    memberships: [{ group: "usa", member: "member-usa" }, { group: "canada", member: "member-canada" }],
    posts: [
      { group: "usa", id: "p-usa", kind: "announcement", title: "United States gathering" },
      { group: "canada", id: "p-canada", kind: "zikr", title: "Canada recorded zikr", video: "dQw4w9WgXcQ" },
      { group: "darul-irfan", id: "p-di", kind: "announcement", title: "Darul Irfan notice" },
    ],
    groups: [{ id: "usa", name: "United States" }, { id: "canada", name: "Canada" }, { id: "darul-irfan", name: "Darul Irfan" }],
  };
}

const get = (path: string, token?: string, env?: Env) =>
  worker.fetch(new Request(`https://api.example.com${path}`, {
    headers: token ? { authorization: `Bearer ${token}` } : {},
  }), env as Env);

describe("private regional groups", () => {
  it("refuses every group route without a member token", async () => {
    const env = envFor(await baseFixture());
    for (const path of ["/v1/groups", "/v1/groups/usa/posts", "/v1/members/me"]) {
      const response = await get(path, undefined, env);
      expect(response.status).toBe(401);
    }
  });

  it("refuses a token that is not a 64-character hex string", async () => {
    const env = envFor(await baseFixture());
    expect((await get("/v1/groups", "not-a-token", env)).status).toBe(401);
  });

  it("refuses an expired session", async () => {
    const fixture = await baseFixture();
    // Replaced rather than mutated through an index: noUncheckedIndexedAccess
    // makes an indexed read optional, so it cannot be assigned into.
    fixture.sessions = { usa: { member: "member-usa", expiresAt: past, hash: await hash(TOKEN_A) } };
    expect((await get("/v1/groups", TOKEN_A, envFor(fixture))).status).toBe(401);
  });

  it("lists only the groups the member belongs to", async () => {
    const env = envFor(await baseFixture());
    const body = await (await get("/v1/groups", TOKEN_A, env)).json() as { groups: Array<{ id: string }> };
    expect(body.groups.map(g => g.id)).toEqual(["usa"]);
  });

  it("serves a group's own posts to its member", async () => {
    const env = envFor(await baseFixture());
    const body = await (await get("/v1/groups/usa/posts", TOKEN_A, env)).json() as { posts: Array<{ title: string }> };
    expect(body.posts.map(p => p.title)).toEqual(["United States gathering"]);
  });

  it("carries the admin's recorded zikr video to that group", async () => {
    const env = envFor(await baseFixture());
    const body = await (await get("/v1/groups/canada/posts", TOKEN_B, env)).json() as { posts: Array<{ kind: string; youtubeVideoID?: string }> };
    expect(body.posts[0]?.kind).toBe("zikr");
    expect(body.posts[0]?.youtubeVideoID).toBe("dQw4w9WgXcQ");
  });

  // The isolation rule, from both directions.
  it("hides one region's posts from another region's member", async () => {
    const env = envFor(await baseFixture());
    const response = await get("/v1/groups/canada/posts", TOKEN_A, env);
    expect(response.status).toBe(404);
    expect(await response.text()).not.toContain("Canada recorded zikr");
  });

  it("hides the Darul Irfan group from a member of neither", async () => {
    const env = envFor(await baseFixture());
    const response = await get("/v1/groups/darul-irfan/posts", TOKEN_B, env);
    expect(response.status).toBe(404);
    expect(await response.text()).not.toContain("Darul Irfan notice");
  });

  it("answers a group the member is not in exactly as a group that does not exist", async () => {
    const env = envFor(await baseFixture());
    const foreign = await get("/v1/groups/canada/posts", TOKEN_A, env);
    const absent = await get("/v1/groups/nowhere/posts", TOKEN_A, env);
    expect(foreign.status).toBe(absent.status);
    expect(await foreign.text()).toBe(await absent.text());
  });

  it("gives a signed-in member with no group nothing at all", async () => {
    const fixture = await baseFixture();
    fixture.memberships = [];
    const env = envFor(fixture);
    const groups = await (await get("/v1/groups", TOKEN_A, env)).json() as { groups: unknown[] };
    expect(groups.groups).toEqual([]);
    expect((await get("/v1/groups/usa/posts", TOKEN_A, env)).status).toBe(404);
  });

  it("deletes the account, its sessions and its memberships", async () => {
    const deletes: string[] = [];
    const env = envFor(await baseFixture(), deletes);
    const response = await worker.fetch(new Request("https://api.example.com/v1/members/me", {
      method: "DELETE", headers: { authorization: `Bearer ${TOKEN_A}` },
    }), env);
    expect(response.status).toBe(204);
    expect(deletes).toEqual(["member_sessions", "member_group_members", "members"]);
  });

  it("rejects an unusable post limit", async () => {
    const env = envFor(await baseFixture());
    for (const limit of ["0", "101", "NaN", "1.5"]) {
      expect((await get(`/v1/groups/usa/posts?limit=${limit}`, TOKEN_A, env)).status).toBe(400);
    }
  });

  it("never grants browser CORS permission to a private group route", async () => {
    const env = envFor(await baseFixture());
    const response = await get("/v1/groups", TOKEN_A, env);
    expect(response.headers.has("access-control-allow-origin")).toBe(false);
  });

  it("refuses an unverifiable Apple identity token", async () => {
    const env = envFor(await baseFixture());
    const response = await worker.fetch(new Request("https://api.example.com/v1/members/session", {
      method: "POST", body: JSON.stringify({ identityToken: "not.a.jwt" }),
    }), env);
    expect(response.status).toBe(401);
  });
});

/** A stub that models the invite tables, so single-use and expiry can be
 *  exercised. `changes` matters: the redeem path relies on a conditional UPDATE
 *  to stop two simultaneous redemptions both succeeding. */
function inviteEnv(invite: { codeHash?: string; group: string; expiresAt: string; redeemedAt?: string | null } | null) {
  const state = invite ? { ...invite } : null;
  const inserted: string[] = [];
  const statement = (sql: string) => {
    let bound: unknown[] = [];
    const self = {
      bind(...values: unknown[]) { bound = values; return self; },
      async first() {
        if (sql.includes("FROM rate_limits")) return { request_count: 1 };
        if (sql.includes("FROM member_invites")) {
          if (!state || state.codeHash !== bound[0]) return null;
          return { group_id: state.group, expires_at: state.expiresAt, redeemed_at: state.redeemedAt ?? null };
        }
        if (sql.includes("FROM member_groups")) return { ok: 1 };
        return null;
      },
      async all() { return { results: [] }; },
      async run() {
        if (sql.startsWith("UPDATE member_invites")) {
          // Only claims an invite that is still open.
          if (state && !state.redeemedAt) { state.redeemedAt = new Date().toISOString(); return { meta: { changes: 1 } }; }
          return { meta: { changes: 0 } };
        }
        if (sql.includes("INTO member_group_members")) inserted.push(String(bound[0]));
        return { meta: { changes: 1 } };
      },
    };
    return self;
  };
  const env = { DB: { prepare: statement }, APNS_TOPIC: "us.naqshbaniaowaisiah" } as unknown as Env;
  return { env, admitted: inserted };
}

const redeem = (code: string, env: Env) =>
  worker.fetch(new Request("https://api.example.com/v1/members/invite", {
    method: "POST", body: JSON.stringify({ code }),
  }), env);

describe("invite codes", () => {
  const future = new Date(Date.now() + 86_400_000).toISOString();
  const past = new Date(Date.now() - 86_400_000).toISOString();

  it("admits a member to exactly the group the code was minted for", async () => {
    const h = await hash("ACDEFGHJKM");
    const { env, admitted } = inviteEnv({ codeHash: h, group: "canada", expiresAt: future });
    const response = await redeem("acdef-ghjkm", env);   // lower case and a dash, as typed
    expect(response.status).toBe(201);
    const body = await response.json() as { token: string; groupID: string };
    expect(body.groupID).toBe("canada");
    expect(body.token).toMatch(/^[0-9a-f]{64}$/);
    expect(admitted).toEqual(["canada"]);
  });

  it("refuses the same code twice", async () => {
    const h = await hash("ACDEFGHJKM");
    const { env } = inviteEnv({ codeHash: h, group: "usa", expiresAt: future });
    expect((await redeem("ACDEFGHJKM", env)).status).toBe(201);
    expect((await redeem("ACDEFGHJKM", env)).status).toBe(403);
  });

  it("refuses an expired code", async () => {
    const h = await hash("ACDEFGHJKM");
    const { env } = inviteEnv({ codeHash: h, group: "usa", expiresAt: past });
    expect((await redeem("ACDEFGHJKM", env)).status).toBe(403);
  });

  it("refuses an unknown code", async () => {
    const { env } = inviteEnv(null);
    expect((await redeem("ZZZZZZZZZZ", env)).status).toBe(403);
  });

  // A wrong code must not be distinguishable from a used or expired one, or the
  // endpoint tells an attacker which guesses were close.
  it("gives an identical refusal for unknown, used and expired codes", async () => {
    const h = await hash("ACDEFGHJKM");
    const unknown = await redeem("ZZZZZZZZZZ", inviteEnv(null).env);
    const expired = await redeem("ACDEFGHJKM", inviteEnv({ codeHash: h, group: "usa", expiresAt: past }).env);
    const used = await redeem("ACDEFGHJKM", inviteEnv({ codeHash: h, group: "usa", expiresAt: future, redeemedAt: future }).env);
    expect(unknown.status).toBe(403);
    expect(expired.status).toBe(403);
    expect(used.status).toBe(403);
    const bodies = await Promise.all([unknown.text(), expired.text(), used.text()]);
    expect(new Set(bodies).size).toBe(1);
  });

  it("rejects a malformed code without touching the store", async () => {
    const { env } = inviteEnv(null);
    expect((await redeem("abc", env)).status).toBe(400);
  });

  it("never grants browser CORS permission to the redeem endpoint", async () => {
    const h = await hash("ACDEFGHJKM");
    const { env } = inviteEnv({ codeHash: h, group: "usa", expiresAt: future });
    const response = await redeem("ACDEFGHJKM", env);
    expect(response.headers.has("access-control-allow-origin")).toBe(false);
  });
});
