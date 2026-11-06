// One live programme: which source is on air, the relay's lease, stage cues.
// Every page and the relay hold a WebSocket here and get the whole state on
// each change, so nobody polls.

export type Role = "host" | "relay" | "listen";
type SourceName = "app" | "paltalk";

interface Source {
  sessionId: string;
  trackName: string;
  since: number;
  lastSeen: number;
  by: string;
  // When the publisher went live on its device: the newest device wins.
  startedAt: number;
}

interface Stage {
  seq: number;
  stage: string;
  origin: "app" | "paltalk" | "voice" | "admin";
  at: number;
}

interface State {
  session: { state: "idle" | "live" | "ended"; id: string | null; startedAt: number | null; endedAt: number | null; startedBy: string | null };
  sources: Partial<Record<SourceName, Source>>;
  override: "auto" | SourceName;
  active: { source: SourceName | null; sessionId: string | null; trackName: string | null; since: number };
  lease: { relayId: string; until: number } | null;
  relay: { relayId: string; status: Record<string, unknown>; lastSeen: number } | null;
  stages: Stage[];
  seq: number;
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

function fresh(source: Source | undefined, now: number): source is Source {
  return !!source && now - source.lastSeen < FRESH_MS;
}

function emptyState(): State {
  return {
    session: { state: "idle", id: null, startedAt: null, endedAt: null, startedBy: null },
    sources: {},
    override: "auto",
    active: { source: null, sessionId: null, trackName: null, since: 0 },
    lease: null,
    relay: null,
    stages: [],
    seq: 0,
  };
}

export class Control implements DurableObject {
  private state: State | null = null;

  constructor(private ctx: DurableObjectState, private env: unknown) {}

  private async load(): Promise<State> {
    if (!this.state) this.state = (await this.ctx.storage.get<State>("state")) ?? emptyState();
    return this.state;
  }

  private async save(s: State, changed = true): Promise<void> {
    this.state = s;
    await this.ctx.storage.put("state", s);
    if (changed) this.broadcast(s);
    if (s.sources.app || s.sources.paltalk || s.lease) {
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
    const s = await this.load();
    const now = Date.now();
    let changed = this.decide(s, now);
    for (const name of ["app", "paltalk"] as SourceName[]) {
      const source = s.sources[name];
      if (source && now - source.lastSeen > 5 * 60_000) {
        delete s.sources[name];
        changed = true;
      }
    }
    if (s.lease && s.lease.until < now) {
      s.lease = null;
      changed = true;
    }
    await this.save(s, changed);
    if (s.sources.app || s.sources.paltalk || s.lease) await this.ctx.storage.setAlarm(Date.now() + TICK_MS);
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const role = request.headers.get("x-live-role") as Role;
    const s = await this.load();
    const now = Date.now();

    if (url.pathname === "/api/ws") {
      const pair = new WebSocketPair();
      this.ctx.acceptWebSocket(pair[1], [role]);
      pair[1].send(JSON.stringify({ type: "state", state: publicState(s) }));
      return new Response(null, { status: 101, webSocket: pair[0] });
    }
    if (url.pathname === "/api/state") return json(publicState(s));

    const body = request.method === "POST" ? ((await request.json().catch(() => ({}))) as Record<string, any>) : {};

    switch (url.pathname) {
      case "/api/session": {
        if (body.action === "start") {
          if (role !== "host" && role !== "relay") return json({ error: "not allowed" }, 403);
          if (s.session.state !== "live") {
            s.session = { state: "live", id: crypto.randomUUID(), startedAt: now, endedAt: null, startedBy: role };
            s.stages = [];
          }
        } else if (body.action === "end") {
          // Only an admin ends a session; the relay never does.
          if (role !== "host") return json({ error: "only an admin ends the session" }, 403);
          s.session = { ...s.session, state: "ended", endedAt: now };
        } else {
          return json({ error: "action must be start or end" }, 400);
        }
        this.decide(s, now);
        await this.save(s);
        return json(publicState(s));
      }

      case "/api/source": {
        // A publisher registers its track and then keeps it alive with the
        // same call every few seconds.
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
          const startedAt = Number(body.startedAt) || now;
          // Hazrat Ji moved to another device: the device that went live
          // last keeps the air, the older one is told to stop.
          if (current && !same && fresh(current, now) && startedAt < current.startedAt) {
            return json({ superseded: true, by: current.by }, 409);
          }
          s.sources[name] = { sessionId: body.sessionId, trackName: body.trackName, since: same ? current!.since : now, lastSeen: now, by: String(body.by ?? role), startedAt };
          // Going live from the app, or a talker in the Paltalk room, starts
          // the session; nobody has to press Start first.
          if (s.session.state !== "live") {
            s.session = { state: "live", id: crypto.randomUUID(), startedAt: now, endedAt: null, startedBy: name };
            s.stages = [];
          }
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
        const origin = (["app", "paltalk", "voice", "admin"].includes(body.origin) ? body.origin : role === "relay" ? "paltalk" : "app") as Stage["origin"];
        const last = s.stages[s.stages.length - 1];
        if (last && last.stage.toLowerCase() === stage.toLowerCase() && now - last.at < DUPLICATE_MS) {
          return json({ duplicate: true, event: last });
        }
        s.seq += 1;
        const event: Stage = { seq: s.seq, stage, origin, at: now };
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
        const blank = emptyState();
        await this.save(blank);
        return json(publicState(blank));
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
