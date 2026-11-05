// The home page of a site: Our Sheikh's live Zikr and stage, the region's
// Halqahs each with its own live Zikr, and joining any of them. Live only
// (owner 2026-11-04): no recording and no past video is ever played here; the
// sound comes only from the Silsila's live feed. Everything from the API is set
// with textContent or attributes, never as HTML.
import { animatedLogo, esc, shell } from "./layout.js";

// The stages a Zikr moves through, in order, as the app names them (Server
// RECITATIONS and DEFAULT_ZIKR_STAGES). A custom Muraqaba shows only when called.
const STAGES = [
  ["tasbih", "Tasbihat", "تسبیحات"], ["istighfar", "Istighfar", "استغفار"], ["shahadah", "Shahadah", "کلمہ شہادت"],
  ["taawwudh", "Ta'awwudh", "تعوذ"], ["basmalah", "Bismillah", "تسمیہ"],
  ["latifa-1", "1st Latifa", "پہلا لطیفہ"], ["latifa-2", "2nd Latifa", "دوسرا لطیفہ"], ["latifa-3", "3rd Latifa", "تیسرا لطیفہ"],
  ["latifa-4", "4th Latifa", "چوتھا لطیفہ"], ["latifa-5", "5th Latifa", "پانچواں لطیفہ"], ["latifa-6", "6th Latifa", "چھٹا لطیفہ"],
  ["latifa-7", "7th Latifa", "ساتواں لطیفہ"], ["raabta", "Raabta", "رابطہ"],
  ["ahadiyat", "Muraqaba Ahadiyat", "مراقبہ احدیت"], ["maiyyat", "Muraqaba Ma'iyyat", "مراقبہ معیت"],
  ["aqrabiyyat", "Muraqaba Aqrabiyyat", "مراقبہ اقربیت"], ["sair-kaaba", "Sair-e-Kaaba", "سیرِ کعبہ"],
  ["rauza-athar", "Rauza-e-Athar", "روضۂ اطہر"], ["masjid-nabawi", "Masjid-e-Nabawi", "مسجدِ نبوی"],
];

const STYLE = `
.hero{display:grid;grid-template-columns:1fr 1.05fr;gap:clamp(24px,5vw,64px);align-items:center;min-height:min(calc(100svh - 74px),860px);padding-top:30px}
.hero>*{min-width:0}
@media (max-width:900px){.hero{grid-template-columns:1fr;text-align:center}.hero .lead{margin-inline:auto}.cta{justify-content:center}}
.hero h1{font-size:clamp(40px,5.8vw,78px);line-height:1.04;margin:18px 0 20px}
.cta{display:flex;gap:14px;flex-wrap:wrap;margin-top:30px}
.stage-grid{display:grid;grid-template-columns:1.25fr .75fr;gap:24px;margin-top:34px;align-items:start}
.stage-grid>*{min-width:0}
@media (max-width:960px){.stage-grid{grid-template-columns:1fr}}

/* The stage. Waiting: the living emblem, large. Live: the emblem goes small to
   the corner and only the stage being done now fills the screen. */
.stage{position:relative;min-height:440px;display:grid;place-items:center;padding:clamp(24px,4vw,44px);text-align:center;overflow:hidden}
.stage .mark{transition:transform 1s cubic-bezier(.2,.8,.2,1),opacity .6s;transform-origin:top left}
.stage .mark .emblem{--s:min(260px,62vw)}
.stage.on .mark{position:absolute;top:18px;left:18px;transform:scale(.3)}
.stage .waiting{display:grid;gap:16px;justify-items:center}
.stage.on .waiting{display:none}
.stage .now{display:none;width:100%}
.stage.on .now{display:block}
.now .label{color:var(--gold);font:600 12px/1 var(--sans);letter-spacing:.3em;text-transform:uppercase}
.now .title{font:600 clamp(48px,7vw,104px)/1.02 var(--serif);margin-top:16px;
  background:linear-gradient(100deg,var(--gold2),#fff6dc 30%,var(--gold) 55%,var(--gold2) 80%);background-size:220% 100%;
  -webkit-background-clip:text;background-clip:text;color:transparent;animation:shine 6s linear infinite;
  filter:drop-shadow(0 0 26px rgba(243,220,157,.35))}
.now .urdu{font-size:clamp(30px,4vw,54px);color:var(--gold2);margin-top:6px;text-shadow:0 0 22px rgba(243,220,157,.35)}
.now .arabic{font-size:clamp(28px,3.6vw,46px);line-height:1.9;color:#fff8e6;margin-top:14px;text-shadow:0 0 28px rgba(243,220,157,.5)}
.now .test{display:inline-block;margin-top:18px}
.now .card{position:relative;margin-inline:auto;width:min(760px,100%);padding:clamp(26px,4vw,48px) 22px;border-radius:26px;
  border:1px solid rgba(243,220,157,.45);background:radial-gradient(120% 100% at 50% 0%,rgba(16,185,129,.28),transparent 70%),rgba(2,12,9,.55);
  box-shadow:0 0 60px -10px rgba(243,220,157,.35),inset 0 0 40px rgba(16,185,129,.15);animation:bob 5s ease-in-out infinite}
@keyframes bob{50%{transform:translateY(-10px)}}
.now .card::after{content:"";position:absolute;inset:-2px;border-radius:27px;padding:2px;pointer-events:none;
  background:conic-gradient(from var(--a,0deg),transparent 0 70%,var(--gold2) 80%,transparent 90%);
  -webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;mask-composite:exclude;animation:edge 4s linear infinite}
@property --a{syntax:"<angle>";inherits:false;initial-value:0deg}
@keyframes edge{to{--a:360deg}}
.now .card.burst{animation:burst 1.1s cubic-bezier(.2,.8,.2,1),bob 5s ease-in-out 1.1s infinite}
@keyframes burst{0%{opacity:0;transform:scale(.86);filter:blur(10px) brightness(2.2)}60%{filter:blur(0) brightness(1.4)}100%{opacity:1;transform:none;filter:none}}
.now .ring{position:absolute;left:50%;top:50%;width:120%;aspect-ratio:1;translate:-50% -50%;border-radius:50%;pointer-events:none;
  background:radial-gradient(circle,rgba(243,220,157,.16),transparent 60%);animation:breathe 5s ease-in-out infinite;z-index:-1}

.side{padding:24px;display:grid;gap:16px}
.join-note{font-size:14px;color:var(--muted)}
.track{list-style:none;margin:0;padding:0;display:grid;gap:4px;width:100%}
.track li{display:grid;grid-template-columns:18px 1fr auto;align-items:center;gap:12px;padding:5px 10px;border-radius:10px;color:var(--muted);font-size:14px}
.track .ur{font-size:13px;line-height:1.6}.track .dot{width:10px;height:10px;border-radius:50%;border:1px solid var(--line)}
.side.on .track{display:none}
.room{display:none;align-items:center;gap:14px;padding:16px;border-radius:14px;border:1px solid rgba(52,211,153,.35);background:rgba(16,185,129,.08)}
.room.show{display:flex}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(270px,1fr));gap:20px;margin-top:36px}
.halqah{position:relative;padding:24px;border-radius:var(--radius);border:1px solid var(--line);background:linear-gradient(160deg,rgba(16,64,48,.55),rgba(4,21,15,.7));
  overflow:hidden;transition:transform .35s cubic-bezier(.2,.8,.2,1),border-color .35s;display:flex;flex-direction:column;gap:10px}
.halqah:hover{border-color:rgba(243,220,157,.55);transform:translateY(-4px)}
.halqah.is-live{border-color:rgba(243,220,157,.6);box-shadow:0 0 40px -10px rgba(243,220,157,.5)}
.halqah h3{font-size:27px}.halqah p{color:var(--muted);margin:0;font-size:14px}
.halqah [data-now]{min-height:24px;color:var(--gold2);font-weight:600;font-size:15px}
.halqah .btn{margin-top:auto;align-self:flex-start;padding:11px 20px;font-size:14px}
dialog{border:1px solid var(--line);border-radius:22px;background:#06221a;color:var(--ink);padding:28px;width:min(440px,92vw);box-shadow:0 30px 90px rgba(0,0,0,.6)}
dialog::backdrop{background:rgba(2,10,7,.7);backdrop-filter:blur(4px)}
dialog h3{font-size:28px;margin-bottom:6px}
.field{display:grid;gap:6px;margin-top:14px;font-size:14px;color:var(--muted)}
.field input,.field select{font:16px var(--sans);padding:12px 14px;border-radius:12px;border:1px solid var(--line);background:#031510;color:var(--ink)}
.row2{display:flex;gap:12px;justify-content:flex-end;margin-top:22px}
.err{color:#fca5a5;font-size:14px;min-height:20px;margin-top:10px}
#player{position:fixed;inset:0;z-index:50;display:none;flex-direction:column;background:radial-gradient(120% 80% at 50% 0%,#0a3b2c,#03120d 70%)}
#player.open{display:flex}
#player header{display:flex;align-items:center;gap:14px;padding:14px clamp(14px,3vw,30px);border-bottom:1px solid var(--line)}
#player header b{font:600 22px var(--serif)}
#player .stage{flex:1;border-radius:0;border:0;background:transparent;min-height:0}
#p-sound{font-size:14px;color:var(--muted);text-align:center;padding:10px 16px 18px}
`;

const COUNTRIES = "US,CA,GB,PK,IN,AE,SA,QA,KW,BH,OM,AU,NZ,DE,FR,NL,BE,NO,SE,DK,IE,IT,ES,TR,MY,SG,ZA,KE,NG,EG,BD,AF,IR,IQ,JO,MA,DZ,TN,LY,SD,ID,JP,CN,HK,BR,MX,AR,CH,AT,PL,PT,GR,FI,RU,UA";

/** One stage screen: the living emblem while waiting; live, the stage being done alone. */
function stageScreen(id, waiting) {
  return `<div class="stage" id="${id}">
      <div class="mark">${animatedLogo("min(260px,62vw)")}</div>
      <div class="waiting"><div class="quiet">${esc(waiting)}</div></div>
      <div class="now"><div class="card"><div class="ring"></div><div class="label">Now</div><div class="title"></div>
        <div class="urdu" lang="ur"></div><div class="arabic" lang="ar"></div><span class="chip test" hidden>Test Zikr</span></div></div>
    </div>`;
}

function portrait(picture) {
  const sparks = [[6, 12], [92, 18], [4, 78], [95, 72], [50, -3], [30, 101], [74, 99]]
    .map(([x, y], i) => `<i class="spark" style="left:${x}%;top:${y}%;animation-delay:${i * 0.45}s"></i>`).join("");
  return picture
    ? `<div class="portrait"><div class="glow"></div><div class="frame"><img id="photo" src="${esc(picture)}" alt="Hazrat Ameer Abdul Qadeer Awan (MZA)"><div class="sweep"></div></div><div class="edge"></div>${sparks}</div>`
    : animatedLogo();
}

export function homePage(site, others, initial, feed) {
  const state = JSON.stringify({ ...initial, feed }).replace(/</g, "\\u003c");
  const sheikhSite = site.halqahs.length === 1;
  const cards = initial.halqahs.filter(h => !sheikhSite || h.id !== "our-sheikh").map((h, i) => `
    <article class="halqah reveal" style="--d:${i * 60}ms" data-id="${esc(h.id)}">
      <div><span class="chip off" data-chip>Not live</span></div>
      <h3 data-name>${esc(h.name)}</h3>
      <p>${esc(h.description ?? "")}</p>
      <div data-now></div>
      <button class="btn btn-gold" data-join="${esc(h.id)}" disabled>Join Live Zikr</button>
    </article>`).join("");
  const track = STAGES.map(([id, en, ur]) => `<li data-stage="${id}"><span class="dot"></span><span class="en">${esc(en)}</span><span class="ur" lang="ur">${esc(ur)}</span></li>`).join("");
  const body = `
  <div class="wrap hero">
    <div>
      <div class="eyebrow reveal">${esc(site.region)}</div>
      <h1 class="reveal shine" style="--d:80ms">${esc(site.tagline)}</h1>
      <p class="lead reveal" style="--d:160ms">${esc(site.intro)}</p>
      <div class="cta reveal" style="--d:240ms">
        <a class="btn btn-gold" href="#live">Our Sheikh's live Zikr</a>
        ${sheikhSite ? `<a class="btn btn-ghost" href="/method-of-zikr">Method of Zikr</a>` : `<a class="btn btn-ghost" href="#halqahs">Halqahs</a>`}
      </div>
    </div>
    <div class="reveal" style="--d:200ms">${portrait(initial.picture)}</div>
  </div>

  <section id="live"><div class="wrap">
    <div class="eyebrow reveal">Our Sheikh · Live Zikr</div>
    <h2 class="reveal">Sit in Zikr with Hazrat ji</h2>
    <p class="lead reveal">When Our Sheikh's Zikr is live, its stage shows here as it happens: the opening Tasbihat, each Latifa and each Muraqaba.</p>
    <div class="stage-grid">
      <div class="panel reveal">${stageScreen("sheikh-stage", "The stage appears here when Our Sheikh's Zikr is live.")}</div>
      <div class="panel side reveal" id="sheikh-side" style="--d:120ms">
        <div><span class="chip off" id="sheikh-chip">Not live</span></div>
        <button class="btn btn-gold" id="sheikh-join" data-join="our-sheikh" disabled>Join Live Zikr</button>
        <div class="join-note" id="sheikh-note">The button opens when Our Sheikh's Zikr is live.</div>
        <ol class="track">${track}</ol>
        <div class="room" id="tahajjud">
          <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#34d399" stroke-width="1.6"><path d="M12 3a4 4 0 0 1 4 4v5a4 4 0 0 1-8 0V7a4 4 0 0 1 4-4zM5 11a7 7 0 0 0 14 0M12 18v3"/></svg>
          <div><b>Tahajjud Zikr is open on Paltalk</b><div class="quiet" id="tahajjud-count"></div></div>
          <a class="btn btn-ghost" id="tahajjud-link" href="#" target="_blank" rel="noopener" style="margin-left:auto">Join</a>
        </div>
      </div>
    </div>
  </div></section>

  ${cards ? `<section id="halqahs"><div class="wrap">
    <div class="eyebrow reveal">Halqahs</div>
    <h2 class="reveal">Halqahs in ${esc(site.region)}</h2>
    <p class="lead reveal">Each Halqah's Zikr shows here whenever it is live. Anyone may join.</p>
    <div class="grid">${cards}</div>
  </div></section>` : ""}

  <dialog id="join-form">
    <form method="dialog" id="join-fields">
      <h3 id="join-title">Join the Zikr</h3>
      <div class="quiet">Your name and place are shared with the Halqah's admins only.</div>
      <label class="field">Your name<input name="name" maxlength="80" required autocomplete="name"></label>
      <label class="field">City<input name="city" maxlength="100" required autocomplete="address-level2"></label>
      <label class="field">Country<select name="country" required></select></label>
      <div class="err" id="join-error"></div>
      <div class="row2"><button class="btn btn-ghost" value="cancel" formnovalidate>Cancel</button><button class="btn btn-gold" id="join-go" value="join">Join</button></div>
    </form>
  </dialog>

  <div id="player" role="dialog" aria-modal="true" aria-label="Live Zikr">
    <header><b id="p-name"></b><span class="chip live" id="p-chip">Live</span>
      <button class="btn btn-ghost" id="p-leave" style="margin-left:auto;padding:10px 18px">Leave</button></header>
    ${stageScreen("p-stage", "Awaiting the first stage…")}
    <div id="p-sound"></div><audio id="p-audio" autoplay playsinline></audio>
  </div>`;
  return shell({
    site, others, title: site.title, description: `${site.tagline}. ${site.intro}`, active: "live", extraStyle: STYLE, body,
    script: `<script type="application/json" id="initial">${state}</script><script>${CLIENT.replace("__COUNTRIES__", COUNTRIES)}</script>`,
  });
}

const CLIENT = `
(() => {
  const $ = id => document.getElementById(id);
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const el = (tag, cls, text) => { const n = document.createElement(tag); if (cls) n.className = cls; if (text != null) n.textContent = text; return n; };
  const store = { get(k) { try { return localStorage.getItem(k); } catch { return null; } }, set(k, v) { try { localStorage.setItem(k, v); } catch {} } };
  let data = JSON.parse($("initial").textContent), joined = null, poll = null, presence = null, shown = {};

  // A stage screen: live, the emblem goes to the corner and the stage being done shows alone.
  function stage(box, s, live) {
    box.classList.toggle("on", !!live);
    const key = live ? (s ? s.stageID + "|" + s.at : "awaiting") + (live.isTest ? "|t" : "") : "off";
    if (shown[box.id] === key) return; shown[box.id] = key;
    const card = box.querySelector(".card");
    card.querySelector(".title").textContent = s ? s.title : "Awaiting the first stage…";
    card.querySelector(".urdu").textContent = s && s.titleUr ? s.titleUr : "";
    card.querySelector(".arabic").textContent = s && s.arabic ? s.arabic : "";
    card.querySelector(".test").hidden = !(live && live.isTest);
    if (live && !reduce) { card.classList.remove("burst"); void card.offsetWidth; card.classList.add("burst"); }
  }
  function chip(node, live) {
    node.className = "chip " + (live ? (live.isTest ? "test" : "live") : "off");
    node.textContent = live ? (live.isTest ? "Test Zikr" : "Live now") : "Not live";
  }
  // Our Sheikh's live sound: the Silsila's SFU feed, listen only (Tools/LiveRelay client).
  const feed = data.feed;
  let feedState = null, onAir = false, pc = null, pulling = false, wantSound = false, pulled = null;
  async function call(method, path, body) {
    const r = await fetch(feed.base + path, { method, headers: { "content-type": "application/json", "x-live-key": feed.key },
      body: body === undefined ? undefined : JSON.stringify(body) });
    const d = await r.json().catch(() => ({}));
    if (!r.ok || d.errorCode) throw new Error(d.error || d.errorDescription || ("HTTP " + r.status));
    return d;
  }
  function watchFeed() {
    if (!feed || !feed.base) return;
    let socket;
    const open = () => {
      socket = new WebSocket(feed.base.replace(/^http/, "ws") + "/api/ws?key=" + encodeURIComponent(feed.key));
      socket.onmessage = e => {
        try { const m = JSON.parse(e.data); if (m.type === "state") { feedState = m.state; onFeed(); } } catch {}
      };
      socket.onclose = () => setTimeout(open, 2000);
    };
    open();
    setInterval(() => { try { socket.readyState === 1 && socket.send("ping"); } catch {} }, 25000);
  }
  function onFeed() {
    const a = feedState && feedState.active;
    onAir = !!(feedState && feedState.session && feedState.session.state === "live" && a && a.source);
    render();
    if (wantSound) follow();
  }
  function drop() { try { pc && pc.close(); } catch {} pc = null; }
  function sound(text) { $("p-sound").textContent = text; }
  // Pull the track on air; pull again when it changes (app <-> Paltalk, a new device) or fails.
  async function follow() {
    if (!wantSound || pulling) return;
    const a = onAir ? feedState.active : null;
    const id = a ? a.sessionId + "/" + a.trackName : null;
    if (id === pulled && pc) return;
    drop(); pulled = null;
    if (!a) { sound("Waiting for the live sound…"); return; }
    pulling = true;
    try {
      const peer = new RTCPeerConnection({ iceServers: [{ urls: "stun:stun.cloudflare.com:3478" }], bundlePolicy: "max-bundle" });
      const stream = new Promise(ok => { peer.ontrack = e => ok(e.streams[0] || new MediaStream([e.track])); });
      const { sessionId } = await call("POST", "/api/sfu/sessions/new");
      const result = await call("POST", "/api/sfu/sessions/" + sessionId + "/tracks/new",
        { tracks: [{ location: "remote", sessionId: a.sessionId, trackName: a.trackName }] });
      if (result.tracks && result.tracks[0] && result.tracks[0].errorCode) throw new Error(result.tracks[0].errorDescription);
      await peer.setRemoteDescription(result.sessionDescription);
      await peer.setLocalDescription(await peer.createAnswer());
      await call("PUT", "/api/sfu/sessions/" + sessionId + "/renegotiate", { sessionDescription: { type: "answer", sdp: peer.localDescription.sdp } });
      pc = peer; pulled = id;
      peer.onconnectionstatechange = () => { if (peer.connectionState === "failed") { drop(); pulled = null; setTimeout(follow, 1000); } };
      const audio = $("p-audio"); audio.srcObject = await stream;
      audio.play().then(() => sound("Live sound of the Zikr")).catch(() => sound("Tap anywhere to hear the Zikr."));
    } catch { setTimeout(follow, 3000); }
    finally { pulling = false; }
  }
  document.addEventListener("click", () => { const a = $("p-audio"); if (wantSound && a.paused && a.srcObject) a.play().then(() => sound("Live sound of the Zikr")).catch(() => {}); });
  watchFeed();

  function render() {
    const sheikh = data.halqahs.find(h => h.id === "our-sheikh");
    // Our Sheikh is live when the app says so or when the live feed is on air.
    if (sheikh && onAir && !sheikh.live) sheikh.live = { kind: "zikr" };
    if (sheikh) {
      chip($("sheikh-chip"), sheikh.live);
      stage($("sheikh-stage"), sheikh.stage, sheikh.live);
      $("sheikh-side").classList.toggle("on", !!sheikh.live);
      const button = $("sheikh-join");
      button.disabled = !sheikh.live; button.classList.toggle("live", !!sheikh.live);
      $("sheikh-note").textContent = sheikh.live ? "Our Sheikh's Zikr is live now." : "The button opens when Our Sheikh's Zikr is live.";
    }
    for (const h of data.halqahs) {
      const card = document.querySelector('.halqah[data-id="' + CSS.escape(h.id) + '"]');
      if (!card) continue;
      card.querySelector("[data-name]").textContent = h.name;
      chip(card.querySelector("[data-chip]"), h.live);
      card.classList.toggle("is-live", !!h.live);
      card.querySelector("[data-now]").textContent = h.live ? (h.stage ? "Now: " + h.stage.title : "Zikr is live") : "";
      const b = card.querySelector("[data-join]"); b.disabled = !h.live; b.classList.toggle("live", !!h.live);
    }
    const t = data.tahajjud;
    $("tahajjud").classList.toggle("show", !!t);
    if (t) { $("tahajjud-count").textContent = t.listeners ? t.listeners + " listening" : ""; const a = $("tahajjud-link"); if (t.url) a.href = t.url; a.hidden = !t.url; }
    const photo = $("photo");
    if (photo) {
      if (data.picture && photo.getAttribute("src") !== data.picture) photo.src = data.picture;
      photo.onerror = () => { if (data.pictureFallback && photo.src !== data.pictureFallback) photo.src = data.pictureFallback; };
    }
    const any = data.halqahs.some(h => h.live);
    const s = $("nav-status"); s.className = "chip " + (any ? "live" : "off"); s.textContent = any ? "Live now" : "Offline";
  }
  async function refresh() {
    try { const r = await fetch("/data.json", { cache: "no-store" }); if (r.ok) { data = await r.json(); render(); } } catch {}
  }
  render();
  // Every 5 seconds, so a stage called shows here within moments.
  setInterval(() => { if (!document.hidden && !joined) refresh(); }, 5000);
  document.addEventListener("visibilitychange", () => { if (!document.hidden && !joined) refresh(); });

  // Joining: a name and a place, remembered on this browser with a random secret that is the visitor's identity.
  const form = $("join-form"), fields = $("join-fields");
  const names = new Intl.DisplayNames([navigator.language || "en"], { type: "region" });
  const select = fields.country;
  for (const code of "__COUNTRIES__".split(",").sort((a, b) => names.of(a).localeCompare(names.of(b)))) {
    const o = el("option", "", names.of(code)); o.value = code; select.append(o);
  }
  const saved = JSON.parse(store.get("zikr.visitor") || "{}");
  fields.name.value = saved.name || ""; fields.city.value = saved.city || ""; select.value = saved.country || "US";
  function secret() {
    let s = store.get("zikr.secret");
    if (!s || !/^[0-9a-f]{64}$/.test(s)) { s = [...crypto.getRandomValues(new Uint8Array(32))].map(b => b.toString(16).padStart(2, "0")).join(""); store.set("zikr.secret", s); }
    return s;
  }
  let joining = null;
  document.addEventListener("click", e => {
    const b = e.target.closest("[data-join]");
    if (!b || b.disabled) return;
    joining = data.halqahs.find(h => h.id === b.dataset.join);
    $("join-title").textContent = "Join " + (joining ? joining.name : "the Zikr");
    $("join-error").textContent = "";
    form.showModal();
  });
  $("join-go").addEventListener("click", async e => {
    e.preventDefault();
    if (!fields.reportValidity() || !joining) return;
    const visitor = { name: fields.name.value.trim(), city: fields.city.value.trim(), country: select.value };
    store.set("zikr.visitor", JSON.stringify(visitor));
    $("join-go").disabled = true; $("join-error").textContent = "";
    try {
      const r = await fetch("/join/" + joining.id, { method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: visitor.name, city: visitor.city, countryCode: visitor.country, guestSecret: secret() }) });
      const body = await r.json().catch(() => ({}));
      if (!r.ok) { $("join-error").textContent = body.error || "Could not join. Please try again."; return; }
      form.close(); openPlayer(joining, body);
    } catch { $("join-error").textContent = "Could not join. Check your connection and try again."; }
    finally { $("join-go").disabled = false; }
  });

  // The joined screen: the stage live, full screen, with no controls. Its sound
  // comes only from the Silsila's live feed (never a recording).
  function openPlayer(h, session) {
    joined = h; shown["p-stage"] = null;
    // Sound is unlocked inside the tap that joined; Our Sheikh's feed is pulled.
    wantSound = h.id === "our-sheikh" && !!(feed && feed.base);
    if (wantSound) { $("p-audio").play().catch(() => {}); follow(); }
    $("p-name").textContent = h.name;
    $("player").classList.add("open"); document.body.style.overflow = "hidden";
    apply(session);
    // The stage every 5 seconds from the page's data; still here every 30 for the admins' attendance.
    poll = setInterval(async () => {
      try {
        const r = await fetch("/data.json", { cache: "no-store" });
        if (!r.ok) return;
        data = await r.json();
        const now = data.halqahs.find(x => x.id === h.id);
        if (!now || (!now.live && !(now.id === "our-sheikh" && onAir))) return ended();
        apply(now);
      } catch {}
    }, 5000);
    presence = setInterval(() => {
      fetch("/presence/" + h.id, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ guestSecret: secret() }) }).catch(() => {});
    }, 30000);
  }
  function apply(session) {
    chip($("p-chip"), session.live);
    stage($("p-stage"), session.stage, session.live);
    if (!wantSound) sound("This Halqah's live sound is in the Darul Irfan app. Its stage follows the Zikr live here.");
  }
  function ended() {
    clearInterval(poll); clearInterval(presence); wantSound = false; drop(); pulled = null;
    stage($("p-stage"), null, null);
    $("p-stage").querySelector(".waiting .quiet").textContent = "The Zikr has ended. JazakAllahu khairan.";
    $("p-sound").textContent = "";
  }
  $("p-leave").addEventListener("click", () => {
    clearInterval(poll); clearInterval(presence); joined = null; wantSound = false; drop(); pulled = null; $("p-audio").srcObject = null;
    $("player").classList.remove("open"); document.body.style.overflow = ""; refresh();
  });
})();
`;
