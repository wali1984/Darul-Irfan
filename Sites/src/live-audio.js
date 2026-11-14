// Embedded in the public page and tested independently. A generation owns all
// of its requests, peer and media: a late result can never restart stopped audio.
export function createLiveReceiver({ feed, audio, status, fetcher = fetch,
  Peer = globalThis.RTCPeerConnection, Stream = globalThis.MediaStream, timeoutMs = 15000, retryMs = 3000 }) {
  let enabled = false, source = null, generation = 0, current = null, retry = null;
  const key = value => value ? value.sessionId + "/" + value.trackName : null;
  function clear() {
    generation += 1;
    clearTimeout(retry); retry = null;
    if (current) {
      clearTimeout(current.deadline); clearTimeout(current.disconnected);
      current.abort.abort();
      current.peer.ontrack = null; current.peer.onconnectionstatechange = null;
      current.peer.close(); current = null;
    }
    audio.pause(); audio.srcObject = null;
  }
  function schedule(message) {
    clear();
    if (!enabled) return;
    status(message);
    retry = setTimeout(connect, retryMs);
  }
  async function connect() {
    if (!enabled || current) return;
    if (!source) { status("Waiting for the live sound…"); return; }
    const id = generation, selected = source;
    let peer;
    try { peer = new Peer({ iceServers: [{ urls: "stun:stun.cloudflare.com:3478" }], bundlePolicy: "max-bundle" }); }
    catch { status("Live sound is unavailable in this browser. Please use an updated browser."); return; }
    const attempt = { peer, abort: new AbortController(), deadline: null, disconnected: null };
    current = attempt;
    const alive = () => enabled && generation === id && current === attempt;
    const check = () => { if (!alive()) throw new Error("Cancelled"); };
    // This bounds the complete negotiation, including a missing ontrack event.
    attempt.deadline = setTimeout(() => { if (alive()) schedule("The sound could not connect. Retrying…"); }, timeoutMs);
    const stream = new Promise((resolve, reject) => {
      peer.ontrack = event => resolve(event.streams[0] || new Stream([event.track]));
      attempt.abort.signal.addEventListener("abort", () => reject(new Error("Cancelled")), { once: true });
    });
    // An abort can happen before negotiation reaches the await below.
    stream.catch(() => {});
    let sessionToken = null;
    const call = async (method, path, body) => {
      check();
      const response = await fetcher(feed.base + path, { method, signal: attempt.abort.signal,
        headers: { "content-type": "application/json", "x-live-key": feed.key, ...(sessionToken ? { "x-live-session": sessionToken } : {}) },
        body: body === undefined ? undefined : JSON.stringify(body) });
      const data = await response.json().catch(() => ({}));
      check();
      if (!response.ok || data.errorCode) throw new Error("Connection failed");
      return data;
    };
    status("Connecting to the live sound…");
    try {
      const created = await call("POST", "/api/sfu/sessions/new");
      const { sessionId } = created;
      sessionToken = created.sessionToken || null;
      if (!sessionId) throw new Error("Missing session");
      const result = await call("POST", "/api/sfu/sessions/" + sessionId + "/tracks/new",
        { tracks: [{ location: "remote", sessionId: selected.sessionId, trackName: selected.trackName }] });
      if (!result.sessionDescription || result.tracks?.some(track => track.errorCode)) throw new Error("Missing track");
      await peer.setRemoteDescription(result.sessionDescription); check();
      await peer.setLocalDescription(await peer.createAnswer()); check();
      await call("PUT", "/api/sfu/sessions/" + sessionId + "/renegotiate",
        { sessionDescription: { type: "answer", sdp: peer.localDescription.sdp } });
      const received = await stream; check();
      clearTimeout(attempt.deadline);
      peer.onconnectionstatechange = () => {
        if (!alive()) return;
        clearTimeout(attempt.disconnected);
        if (peer.connectionState === "failed" || peer.connectionState === "closed") schedule("The connection was interrupted. Reconnecting…");
        else if (peer.connectionState === "disconnected") {
          status("The connection was interrupted. Reconnecting…");
          attempt.disconnected = setTimeout(() => { if (alive()) schedule("Reconnecting to the live sound…"); }, 5000);
        } else if (peer.connectionState === "connected") status("Live sound of the Zikr");
      };
      audio.srcObject = received;
      await audio.play();
      if (alive()) status("Live sound of the Zikr");
    } catch (error) {
      if (!alive()) return;
      if (audio.srcObject) status("Tap Play sound to hear the Zikr.");
      else schedule("The sound could not connect. Retrying…");
    }
  }
  return {
    update(next) {
      const valid = next?.sessionId && next?.trackName ? next : null;
      if (key(valid) === key(source)) return;
      source = valid; clear();
      if (enabled) void connect();
    },
    start() { enabled = true; void connect(); },
    stop() { enabled = false; clear(); },
    async play() {
      if (!enabled) return;
      if (!audio.srcObject) { clear(); void connect(); return; }
      const id = generation;
      try { await audio.play(); if (enabled && generation === id) status("Live sound of the Zikr"); }
      catch { if (enabled && generation === id) status("Sound is blocked. Tap Play sound again."); }
    },
  };
}
