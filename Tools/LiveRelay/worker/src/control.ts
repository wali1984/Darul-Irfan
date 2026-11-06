// One live programme: which source is on air, the relay's lease, stage cues.
// Every page and the relay hold a WebSocket here and get the whole state on
// each change, so nobody polls.
//
// The Zikr session itself belongs to the platform (the Darul Irfan server).
// This object only mirrors it: a publisher's heartbeat says a transport is
// alive, never that a Zikr has started, and nothing here can end one.

export type Role = "host" | "relay" | "listen";
type SourceName = "app" | "paltalk";

// What the Durable Object needs from the Worker's environment.
export interface ControlEnv {
  PLATFORM: Fetcher;
  PLATFORM_URL: string;
  HALQAH_ID: string;
}

interface Source {
  sessionId: string;
  trackName: string;
  since: number;
  lastSeen: number;
  by: string;
  // When this publisher first registered, by our clock: the newest wins.
  startedAt: number;
}

interface Stage {
  seq: number;
  stage: string;
  origin: "app" | "paltalk" | "voice" | "admin";
  at: number;
}

interface Platform {
  live: boolean;
  sessionID: string | null;
  title: string | null;
  isTest: boolean;
  checkedAt: number;
  // False when the last check failed; the session then keeps its last state.
  ok: boolean;
}

interface State {
  session: { state: "idle" | "live" | "ended"; id: string | null; startedAt: number | null; endedAt: number | null; startedBy: string | null };
  platform: Platform;
  sources: Partial<Record<SourceName, Source>>;
  override: "auto" | SourceName;
  active: { source: SourceName | null; sessionId: string | null; trackName: string | null; since: number };
  lease: { relayId: string; until: number } | null;
  relay: { relayId: string; status: Record<string, unknown>; lastSeen: number } | null;
  stages: Stage[];
  seq: number;
  // Session ids of ended Zikr sessions: an ended one never comes back.
  ended: string[];
  // Publisher SFU session -> when we first and last heard from it (server
  // receipt time). Priority goes by first; forgetting goes by last.
  publishers: Record<string, Publisher>;
}

interface Publisher {
  first: number;
  last: number;
}

// A source is on air while it has sent a heartbeat this recently.
const FRESH_MS = 10_000;
// The app must be steady this long before it takes over from Paltalk, so a
// phone that connects and drops straight away does not flip the programme.
const TAKEOVER_MS = 3_000;
const LEASE_MS = 20_000;
// The same stage again within this window is the same cue (two inputs, or
// the relay reading back its own message).
const DUPLICATE_MS = 60_000;
const TICK_MS = 2_000;
// A state read or a new socket asks the platform again when the last answer
// is older than this.
const PLATFORM_STALE_MS = 10_000;
const PLATFORM_TIMEOUT_MS = 8_000;
// Publishers we have not heard from for this long are forgotten.
const FORGET_MS = 5 * 60_000;
const ENDED_KEPT = 20;
// Publisher stamps kept beyond the current sources: the state is one stored
// value, so a host key cannot grow it without bound.
const PUBLISHERS_KEPT = 20;
// The id used when the platform names a session by neither id nor start.
// It cannot tell sessions apart, so it is never remembered as ended.
const UNKNOWN_ID = "platform-unknown";

function fresh(source: Source | undefined, now: number): source is Source {
  return !!source && now - source.lastSeen < FRESH_MS;
}

function emptyPlatform(): Platform {
  return { live: false, sessionID: null, title: null, isTest: false, checkedAt: 0, ok: false };
}

// Remembers a session as ended, so a stale answer cannot bring it back.
function retire(s: State, id: string | null): void {
  if (!id || id === UNKNOWN_ID || s.ended.includes(id)) return;
  s.ended = [...s.ended, id].slice(-ENDED_KEPT);
}

function emptyState(): State {
  return {
    session: { state: "idle", id: null, startedAt: null, endedAt: null, startedBy: null },
    platform: emptyPlatform(),
    sources: {},
    override: "auto",
    active: { source: null, sessionId: null, trackName: null, since: 0 },
    lease: null,
    relay: null,
    stages: [],
    seq: 0,
    ended: [],
    publishers: {},
  };
}

export class Control implements DurableObject {
  private state: State | null = null;
  private refreshing: Promise<boolean> | null = null;

  constructor(private ctx: DurableObjectState, private env: ControlEnv) {}

  // The one state object. Nothing ever swaps it for another, so a write
  // that lands while we wait on the platform is never undone.
  private async load(): Promise<State> {
    if (!this.state) {
      // State saved before the platform projection existed gets the new fields.
      const stored = await this.ctx.storage.get<Partial<State> & { publishers?: Record<string, number | Publisher> }>("state");
      const s: State = { ...emptyState(), ...(stored ?? {}), publishers: {} };
      // Older stamps were one number: when we first heard from the device.
      for (const [id, stamp] of Object.entries(stored?.publishers ?? {})) {
        s.publishers[id] = typeof stamp === "number" ? { first: stamp, last: stamp } : stamp;
      }
      this.state = s;
    }
    return this.state;
  }

  private ticking(s: State): boolean {
    return !!(s.sources.app || s.sources.paltalk || s.lease || s.session.state === "live");
  }

  private async save(s: State, changed = true): Promise<void> {
    this.state = s;
    await this.ctx.storage.put("state", s);
    if (changed) this.broadcast(s);
    if (this.ticking(s)) {
      const alarm = await this.ctx.storage.getAlarm();
      if (alarm === null) await this.ctx.storage.setAlarm(Date.now() + TICK_MS);
    }
  }

  private broadcast(s: State): void {
    const message = JSON.stringify({ type: "state", state: publicState(s) });
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.send(message);
      } catch {
        // A closed socket is cleaned up by the runtime.
      }
    }
  }

  // MARK: - The platform's session, mirrored

  // Asks the platform whether the Halqah's Zikr is live and projects the
  // answer onto our session. One request at a time; a failed request keeps
  // the last state. Returns whether the session changed.
  refreshPlatform(): Promise<boolean> {
    if (!this.refreshing) {
      this.refreshing = this.fetchPlatform().finally(() => {
        this.refreshing = null;
      });
    }
    return this.refreshing;
  }

  private async fetchPlatform(): Promise<boolean> {
    let live: { sessionID?: unknown; startedAt?: unknown; title?: unknown; isTest?: unknown } | null | undefined;
    let failed = false;
    try {
      const url = `${this.env.PLATFORM_URL}/v1/public/live?ids=${encodeURIComponent(this.env.HALQAH_ID)}`;
      const answer = await this.env.PLATFORM.fetch(url, { headers: { "user-agent": "DarulIrfanLive/1.0" }, signal: AbortSignal.timeout(PLATFORM_TIMEOUT_MS) });
      if (!answer.ok) throw new Error(`platform answered ${answer.status}`);
      const data = (await answer.json()) as { halqahs?: { live?: typeof live }[] };
      const halqah = Array.isArray(data?.halqahs) ? data.halqahs[0] : undefined;
      if (!halqah || !("live" in halqah)) throw new Error("no halqah in the answer");
      live = halqah.live ?? null;
    } catch {
      failed = true;
    }
    // Other requests ran while we waited: take the state as it is now.
    const s = await this.load();
    if (failed) {
      s.platform = { ...s.platform, checkedAt: Date.now(), ok: false };
      await this.save(s, false);
      return false;
    }
    return this.project(s, live ?? null, Date.now());
  }

  // The platform's answer becomes our session. A new id starts a session; a
  // null answer ends the current one; an id that already ended stays ended.
  private async project(s: State, live: { sessionID?: unknown; startedAt?: unknown; title?: unknown; isTest?: unknown } | null, now: number): Promise<boolean> {
    const id = live ? (typeof live.sessionID === "string" && live.sessionID ? live.sessionID : typeof live.startedAt === "string" && live.startedAt ? `platform-${live.startedAt}` : UNKNOWN_ID) : null;
    s.platform = {
      live: !!live,
      sessionID: id,
      title: live && typeof live.title === "string" ? live.title : null,
      isTest: !!live?.isTest,
      checkedAt: now,
      ok: true,
    };
    let changed = false;
    if (id) {
      const current = s.session.state === "live" && s.session.id === id;
      if (!current && !s.ended.includes(id)) {
        // A different session takes over a live one: the old one is over too.
        if (s.session.state === "live") retire(s, s.session.id);
        s.session = { state: "live", id, startedAt: now, endedAt: null, startedBy: "platform" };
        s.stages = [];
        changed = true;
      }
    } else if (s.session.state === "live") {
      s.session = { ...s.session, state: "ended", endedAt: now };
      retire(s, s.session.id);
      changed = true;
    }
    if (this.decide(s, now)) changed = true;
    await this.save(s, changed);
    return changed;
  }

  private async refreshIfStale(s: State, now: number): Promise<void> {
    if (now - s.platform.checkedAt > PLATFORM_STALE_MS) await this.refreshPlatform();
  }

  // Picks what listeners hear. The app wins over Paltalk once it is steady;
  // an admin override wins over both while its source is alive.
  private decide(s: State, now: number): boolean {
    const before = `${s.active.source}|${s.active.sessionId}|${s.active.trackName}`;
    const app = s.sources.app;
    const paltalk = s.sources.paltalk;
    let next: SourceName | null = null;
    if (s.session.state !== "live") {
      next = null;
    } else if (s.override !== "auto") {
      next = fresh(s.sources[s.override], now) ? s.override : null;
    } else if (fresh(app, now) && (s.active.source === "app" || now - app.since >= TAKEOVER_MS || !fresh(paltalk, now))) {
      next = "app";
    } else if (fresh(paltalk, now)) {
      next = "paltalk";
    }
    const chosen = next ? s.sources[next]! : null;
    const after = `${next}|${chosen?.sessionId ?? null}|${chosen?.trackName ?? null}`;
    if (before === after) return false;
    s.active = { source: next, sessionId: chosen?.sessionId ?? null, trackName: chosen?.trackName ?? null, since: now };
    return true;
  }

  async alarm(): Promise<void> {
    // The platform first, so a dead relay cannot leave listeners on a stale
    // live: when the platform has ended the Zikr, so do we. While nothing is
    // live a slower look is enough to notice a start.
    const before = await this.load();
    if (before.session.state === "live") await this.refreshPlatform();
    else await this.refreshIfStale(before, Date.now());
    const s = await this.load();
    const now = Date.now();
    let changed = this.decide(s, now);
    for (const name of ["app", "paltalk"] as SourceName[]) {
      const source = s.sources[name];
      if (source && now - source.lastSeen > FORGET_MS) {
        delete s.sources[name];
        changed = true;
      }
    }
    this.forgetPublishers(s, now);
    if (s.lease && s.lease.until < now) {
      s.lease = null;
      changed = true;
    }
    await this.save(s, changed);
    if (this.ticking(s)) await this.ctx.storage.setAlarm(Date.now() + TICK_MS);
  }

  // Drops publishers that went quiet, never one that is a source now, and
  // keeps only the newest few beyond those.
  private forgetPublishers(s: State, now: number): void {
    const inUse = new Set(Object.values(s.sources).map((source) => source.sessionId));
    const spare: [string, Publisher][] = [];
    for (const [sessionId, stamp] of Object.entries(s.publishers)) {
      if (inUse.has(sessionId)) continue;
      if (now - stamp.last > FORGET_MS) delete s.publishers[sessionId];
      else spare.push([sessionId, stamp]);
    }
    spare.sort((a, b) => b[1].last - a[1].last);
    for (const [sessionId] of spare.slice(PUBLISHERS_KEPT)) delete s.publishers[sessionId];
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const role = request.headers.get("x-live-role") as Role;
    const s = await this.load();
    const now = Date.now();

    if (url.pathname === "/api/ws") {
      await this.refreshIfStale(s, now);
      const pair = new WebSocketPair();
      this.ctx.acceptWebSocket(pair[1], [role]);
      pair[1].send(JSON.stringify({ type: "state", state: publicState(s) }));
      return new Response(null, { status: 101, webSocket: pair[0] });
    }
    if (url.pathname === "/api/state") {
      await this.refreshIfStale(s, now);
      return json(publicState(s));
    }

    const body = request.method === "POST" ? ((await request.json().catch(() => ({}))) as Record<string, any>) : {};

    switch (url.pathname) {
      case "/api/session": {
        // Starting and ending happen on the platform; this object only mirrors them.
        return json({ error: "the platform owns the session" }, 409);
      }

      case "/api/source": {
        // A publisher registers its track and then keeps it alive with the
        // same call every few seconds. That says the transport is up; the
        // session itself comes from the platform.
        const name = body.source as SourceName;
        if (name === "app" && role !== "host") return json({ error: "not allowed" }, 403);
        if (name === "paltalk") {
          if (role !== "relay") return json({ error: "not allowed" }, 403);
          if (!s.lease || s.lease.relayId !== body.relayId || s.lease.until < now) return json({ error: "relay does not hold the lease" }, 409);
        }
        if (name !== "app" && name !== "paltalk") return json({ error: "unknown source" }, 400);
        if (body.live === false) {
          if (s.sources[name]?.sessionId === body.sessionId) delete s.sources[name];
        } else {
          if (typeof body.sessionId !== "string" || typeof body.trackName !== "string") return json({ error: "sessionId and trackName required" }, 400);
          const current = s.sources[name];
          const same = current && current.sessionId === body.sessionId && current.trackName === body.trackName;
          // Priority goes by when we first heard from each publisher, never
          // by a time the client claims. Each heartbeat keeps the stamp
          // alive without moving it.
          const startedAt = s.publishers[body.sessionId]?.first ?? now;
          s.publishers[body.sessionId] = { first: startedAt, last: now };
          this.forgetPublishers(s, now);
          // Hazrat Ji moved to another device: the device that went live
          // last keeps the air, the older one is told to stop.
          if (current && !same && fresh(current, now) && startedAt < current.startedAt) {
            return json({ superseded: true, by: current.by }, 409);
          }
          s.sources[name] = { sessionId: body.sessionId, trackName: body.trackName, since: same ? current!.since : now, lastSeen: now, by: String(body.by ?? role), startedAt };
        }
        const changed = this.decide(s, now) || !s.sources[name] || s.sources[name]!.since === now;
        await this.save(s, changed || body.live === false);
        return json({ ok: true, active: s.active });
      }

      case "/api/override": {
        if (role !== "host") return json({ error: "not allowed" }, 403);
        if (!["auto", "app", "paltalk"].includes(body.source)) return json({ error: "source must be auto, app or paltalk" }, 400);
        s.override = body.source;
        this.decide(s, now);
        await this.save(s);
        return json(publicState(s));
      }

      case "/api/stage": {
        if (role === "listen") return json({ error: "not allowed" }, 403);
        const stage = String(body.stage ?? "").trim().slice(0, 80);
        if (!stage) return json({ error: "stage required" }, 400);
        // A cue belongs to one session. The sender may name the session it
        // saw; a cue for another one, or for no live session, is refused.
        // Our view of the platform may lag a start by a few seconds, so we
        // ask it again before refusing.
        const named = typeof body.sessionId === "string" && body.sessionId ? body.sessionId : null;
        const fits = () => s.session.state === "live" && (!named || named === s.session.id);
        if (!fits()) await this.refreshPlatform();
        if (s.session.state !== "live") return json({ error: "no live session" }, 409);
        if (!fits()) return json({ error: "stale session" }, 409);
        const at = Date.now();
        const origin = (["app", "paltalk", "voice", "admin"].includes(body.origin) ? body.origin : role === "relay" ? "paltalk" : "app") as Stage["origin"];
        const last = s.stages[s.stages.length - 1];
        if (last && last.stage.toLowerCase() === stage.toLowerCase() && at - last.at < DUPLICATE_MS) {
          return json({ duplicate: true, event: last });
        }
        s.seq += 1;
        const event: Stage = { seq: s.seq, stage, origin, at };
        s.stages = [...s.stages, event].slice(-50);
        await this.save(s);
        return json({ event });
      }

      case "/api/lease": {
        if (role !== "relay") return json({ error: "not allowed" }, 403);
        const relayId = String(body.relayId ?? "");
        if (!relayId) return json({ error: "relayId required" }, 400);
        if (body.release) {
          if (s.lease?.relayId === relayId) s.lease = null;
          await this.save(s);
          return json({ granted: false });
        }
        if (!s.lease || s.lease.until < now || s.lease.relayId === relayId) {
          const changed = s.lease?.relayId !== relayId;
          s.lease = { relayId, until: now + LEASE_MS };
          await this.save(s, changed);
          return json({ granted: true, until: s.lease.until, state: publicState(s) });
        }
        return json({ granted: false, holder: s.lease.relayId, until: s.lease.until, state: publicState(s) });
      }

      case "/api/relay-status": {
        if (role !== "relay") return json({ error: "not allowed" }, 403);
        if (!s.lease || s.lease.relayId !== body.relayId) return json({ error: "relay does not hold the lease" }, 409);
        const before = JSON.stringify(s.relay?.status ?? null);
        s.relay = { relayId: body.relayId, status: body.status ?? {}, lastSeen: now };
        await this.save(s, before !== JSON.stringify(s.relay.status));
        return json({ ok: true });
      }

      case "/api/reset": {
        if (role !== "host") return json({ error: "not allowed" }, 403);
        // Clears the transport side only; the session stays whatever the
        // platform says it is. Done in place: the same object stays live.
        Object.assign(s, emptyState(), { session: s.session, platform: s.platform, ended: s.ended });
        this.decide(s, now);
        await this.save(s);
        return json(publicState(s));
      }
    }
    return json({ error: "not found" }, 404);
  }

  webSocketMessage(): void {
    // Clients only listen; keep-alive pings need no answer.
  }

  webSocketClose(ws: WebSocket, code: number): void {
    try {
      ws.close(code, "closed");
    } catch {
      // Already closed.
    }
  }
}

function publicState(s: State) {
  const now = Date.now();
  return {
    now,
    session: s.session,
    platform: s.platform,
    override: s.override,
    active: s.active,
    sources: Object.fromEntries(
      Object.entries(s.sources).map(([name, source]) => [name, { ...source, fresh: fresh(source, now) }]),
    ),
    lease: s.lease ? { ...s.lease, valid: s.lease.until > now } : null,
    relay: s.relay ? { ...s.relay, fresh: now - s.relay.lastSeen < FRESH_MS } : null,
    stages: s.stages,
  };
}

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}
