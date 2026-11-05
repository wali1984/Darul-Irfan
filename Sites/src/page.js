// The page for one site. Server-rendered with the first data, then the script
// refreshes /data.json every 20 seconds. Everything from the API is set with
// textContent or attribute setters, never as HTML.

// The stages a live Zikr moves through, as the app names them (Server DEFAULT_ZIKR_STAGES).
const STAGES = [
  ["1st Latifa", "پہلا لطیفہ"], ["2nd Latifa", "دوسرا لطیفہ"], ["3rd Latifa", "تیسرا لطیفہ"], ["4th Latifa", "چوتھا لطیفہ"],
  ["5th Latifa", "پانچواں لطیفہ"], ["6th Latifa", "چھٹا لطیفہ"], ["7th Latifa", "ساتواں لطیفہ"], ["Raabta", "رابطہ"],
  ["Muraqaba Ahadiyat", "مراقبہ احدیت"], ["Muraqaba Ma'iyyat", "مراقبہ معیت"], ["Muraqaba Aqrabiyyat", "مراقبہ اقربیت"],
  ["Sair-e-Kaaba", "سیرِ کعبہ"], ["Rauza-e-Athar", "روضۂ اطہر"], ["Masjid-e-Nabawi", "مسجدِ نبوی"],
];

const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

export function page(site, others, initial) {
  const state = JSON.stringify(initial).replace(/</g, "\\u003c");
  const halqahCards = initial.halqahs.map((h, i) => `
      <article class="halqah reveal" style="--d:${i * 70}ms" data-id="${esc(h.id)}">
        <div class="halqah-glow"></div>
        <span class="chip ${h.open ? "chip-open" : ""}">${h.open ? "Open to all" : "By invitation"}</span>
        <h3 data-name>${esc(h.name)}</h3>
        <p>${esc(h.description ?? "")}</p>
        <div class="halqah-foot">
          ${h.open
            ? `<a class="btn btn-ghost" href="#live">Join the live Zikr</a>`
            : `<span class="hint">Sign in through the Darul Irfan app with your invitation.</span>`}
          <a class="link" href="darulirfan://groups/${esc(h.id)}">Open in the app →</a>
        </div>
      </article>`).join("");
  const track = STAGES.map(([en, ur], i) => `
        <li data-stage="${esc(en)}" style="--i:${i}"><span class="dot"></span><span class="en">${esc(en)}</span><span class="ur" lang="ur">${esc(ur)}</span></li>`).join("");
  const regions = others.map(o => `<a href="https://${esc(o.host)}">${esc(o.region)}</a>`).join("");

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(site.title)}</title>
<meta name="description" content="${esc(site.tagline)}. ${esc(site.intro)}">
<meta name="theme-color" content="#04150f">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<meta property="og:title" content="${esc(site.title)}">
<meta property="og:description" content="${esc(site.tagline)}">
${initial.picture ? `<meta property="og:image" content="${esc(initial.picture)}">` : ""}
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@500;600;700&family=Inter:wght@400;500;600&family=Amiri:wght@400;700&family=Noto+Nastaliq+Urdu:wght@400;600&display=swap" rel="stylesheet">
<style>
:root{
  --bg:#04150f;--bg2:#062419;--ink:#eef6f1;--muted:#9fbcb0;--line:rgba(212,175,95,.22);
  --gold:#d9b56a;--gold2:#f3dc9d;--emerald:#10b981;--emerald2:#34d399;--glass:rgba(10,40,30,.55);
  --radius:22px;--serif:"Cormorant Garamond",Georgia,serif;--sans:Inter,system-ui,-apple-system,"Segoe UI",sans-serif;
}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.6 var(--sans);overflow-x:hidden;-webkit-font-smoothing:antialiased}
a{color:inherit}
[lang=ur]{font-family:"Noto Nastaliq Urdu",serif;direction:rtl;line-height:2.1}
.arabic{font-family:Amiri,serif;direction:rtl}
#sky{position:fixed;inset:0;z-index:-2;width:100%;height:100%}
.aurora{position:fixed;inset:-30%;z-index:-3;background:
  radial-gradient(40% 35% at 20% 20%,rgba(16,185,129,.28),transparent 70%),
  radial-gradient(35% 30% at 80% 30%,rgba(217,181,106,.18),transparent 70%),
  radial-gradient(45% 40% at 50% 90%,rgba(6,95,70,.45),transparent 70%),var(--bg);
  animation:drift 28s ease-in-out infinite alternate;filter:saturate(1.1)}
@keyframes drift{to{transform:translate3d(4%,-3%,0) rotate(6deg) scale(1.08)}}
.pattern{position:fixed;z-index:-1;width:120vmax;height:120vmax;left:50%;top:40%;translate:-50% -50%;opacity:.045;animation:spin 240s linear infinite;pointer-events:none}
@keyframes spin{to{rotate:360deg}}

nav{position:sticky;top:0;z-index:20;display:flex;align-items:center;gap:20px;justify-content:space-between;
  padding:14px clamp(16px,4vw,48px);backdrop-filter:blur(14px) saturate(1.3);background:linear-gradient(rgba(4,21,15,.82),rgba(4,21,15,.45));border-bottom:1px solid var(--line)}
.brand{display:flex;align-items:center;gap:12px;text-decoration:none}
.brand svg{width:34px;height:34px}
.brand b{font:600 20px/1 var(--serif);letter-spacing:.04em}
.brand small{display:block;color:var(--gold);font:600 11px/1.4 var(--sans);letter-spacing:.18em;text-transform:uppercase}
.navlinks{display:flex;gap:22px;font-size:14px;color:var(--muted)}
.navlinks a{text-decoration:none;transition:color .2s}.navlinks a:hover{color:var(--gold2)}
@media (max-width:720px){.navlinks{display:none}}

.wrap{width:min(1180px,100% - 32px);margin-inline:auto}
section{padding:clamp(56px,9vw,110px) 0}
.eyebrow{color:var(--gold);font:600 12px/1 var(--sans);letter-spacing:.28em;text-transform:uppercase}
h1,h2,h3{font-family:var(--serif);font-weight:600;margin:0}
h2{font-size:clamp(32px,4.4vw,52px);line-height:1.08;margin:12px 0 14px}
.lead{color:var(--muted);font-size:clamp(16px,1.6vw,19px);max-width:56ch}

.hero{display:grid;grid-template-columns:1.1fr .9fr;gap:clamp(24px,5vw,72px);align-items:center;min-height:min(calc(100svh - 70px),860px);padding-top:40px}
.hero>*,.live-grid>*,.app>*{min-width:0}
h1,h2,h3{overflow-wrap:break-word}
@media (max-width:880px){.hero{grid-template-columns:1fr;text-align:center}.hero .lead{margin-inline:auto}.cta{justify-content:center}}
.hero h1{font-size:clamp(42px,6.4vw,84px);line-height:1.02;margin:18px 0 20px;
  background:linear-gradient(100deg,var(--gold2) 0%,#fff6dc 25%,var(--gold) 50%,var(--gold2) 75%,#fff6dc 100%);background-size:220% 100%;
  -webkit-background-clip:text;background-clip:text;color:transparent;animation:shine 7s linear infinite}
@keyframes shine{to{background-position:-220% 0}}
.cta{display:flex;gap:14px;flex-wrap:wrap;margin-top:30px}
.btn{display:inline-flex;align-items:center;gap:10px;padding:14px 24px;border-radius:999px;text-decoration:none;font-weight:600;font-size:15px;
  transition:transform .25s cubic-bezier(.2,.8,.2,1),box-shadow .25s,background .25s}
.btn-gold{background:linear-gradient(135deg,var(--gold2),var(--gold));color:#1d1406;box-shadow:0 10px 30px -10px rgba(217,181,106,.7)}
.btn-gold:hover{transform:translateY(-2px);box-shadow:0 16px 40px -10px rgba(217,181,106,.9)}
.btn-ghost{border:1px solid var(--line);background:rgba(255,255,255,.03)}
.btn-ghost:hover{border-color:var(--gold);transform:translateY(-2px)}

.portrait{position:relative;aspect-ratio:1;width:min(440px,82vw);margin-inline:auto}
.portrait .ring{position:absolute;inset:0;border-radius:50%;border:1px solid var(--line)}
.portrait .ring.r1{inset:-4%;border:2px solid transparent;background:conic-gradient(from 0deg,var(--gold),transparent 30%,var(--emerald2) 55%,transparent 75%,var(--gold)) border-box;
  -webkit-mask:linear-gradient(#000 0 0) padding-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;mask-composite:exclude;animation:spin 14s linear infinite}
.portrait .ring.r2{inset:-12%;border-style:dashed;opacity:.5;animation:spin 60s linear infinite reverse}
.portrait .orbit{position:absolute;inset:-12%;animation:spin 36s linear infinite}
.portrait .orbit i{position:absolute;left:50%;top:50%;width:9px;height:9px;margin:-4.5px;border-radius:50%;background:var(--gold2);
  box-shadow:0 0 14px 4px rgba(243,220,157,.7);transform:rotate(calc(var(--k) * 51.43deg)) translateY(calc(-1 * min(250px,46.5vw)))}
.portrait .photo{position:absolute;inset:6%;border-radius:50%;overflow:hidden;background:radial-gradient(circle,#0b3a2b,#04150f);
  box-shadow:0 0 0 1px var(--line),0 30px 80px -20px rgba(16,185,129,.55),inset 0 0 60px rgba(0,0,0,.6)}
/* The Daily Zikr thumbnail has Hazrat ji on its right-hand side. */
.portrait img{width:100%;height:100%;object-fit:cover;object-position:80% 30%;filter:saturate(1.05) contrast(1.04)}
.portrait .halo{position:absolute;inset:-18%;border-radius:50%;background:radial-gradient(circle,rgba(217,181,106,.22),transparent 62%);animation:breathe 6s ease-in-out infinite}
@keyframes breathe{50%{transform:scale(1.06);opacity:.6}}

.status{display:inline-flex;align-items:center;gap:10px;padding:8px 16px;border-radius:999px;border:1px solid var(--line);background:var(--glass);font-size:13px;font-weight:600;letter-spacing:.04em}
.status .pulse{width:10px;height:10px;border-radius:50%;background:#6b7d75}
.status.on{border-color:rgba(248,113,113,.5);color:#fecaca}
.status.on .pulse{background:#ef4444;box-shadow:0 0 0 0 rgba(239,68,68,.7);animation:ping 1.6s infinite}
@keyframes ping{70%{box-shadow:0 0 0 14px rgba(239,68,68,0)}100%{box-shadow:0 0 0 0 rgba(239,68,68,0)}}

.live-grid{display:grid;grid-template-columns:1.55fr 1fr;gap:24px;margin-top:34px;align-items:start}
@media (max-width:960px){.live-grid{grid-template-columns:1fr}}
.panel{position:relative;border-radius:var(--radius);border:1px solid var(--line);background:var(--glass);backdrop-filter:blur(10px);overflow:hidden}
.panel::before{content:"";position:absolute;inset:0;border-radius:inherit;padding:1px;pointer-events:none;
  background:linear-gradient(130deg,rgba(243,220,157,.55),transparent 35%,transparent 65%,rgba(52,211,153,.45));
  -webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;mask-composite:exclude}
.video{aspect-ratio:16/9;background:#020b08}
.video iframe{width:100%;height:100%;border:0;display:block}
.video .poster{position:relative;width:100%;height:100%;display:grid;place-items:center;background-size:cover;background-position:center}
.video .poster::after{content:"";position:absolute;inset:0;background:radial-gradient(circle,rgba(4,21,15,.2),rgba(4,21,15,.85))}
.video .play{position:relative;z-index:1;width:86px;height:86px;border-radius:50%;border:0;cursor:pointer;background:linear-gradient(135deg,var(--gold2),var(--gold));
  box-shadow:0 0 0 12px rgba(217,181,106,.15),0 20px 50px -10px rgba(0,0,0,.8);transition:transform .25s}
.video .play:hover{transform:scale(1.07)}
.video .play svg{width:30px;height:30px;margin-left:6px;fill:#1d1406}
.video-cap{display:flex;justify-content:space-between;align-items:center;gap:12px;padding:16px 20px;border-top:1px solid var(--line);font-size:14px;color:var(--muted)}
.video-cap b{color:var(--ink);font-weight:600}

.stage{padding:26px;display:flex;flex-direction:column;gap:18px}
.stage-now{min-height:170px;display:grid;align-content:center;text-align:center;border-radius:16px;padding:22px;
  background:radial-gradient(120% 90% at 50% 0%,rgba(16,185,129,.22),transparent 70%),rgba(2,12,9,.55);border:1px solid var(--line)}
.stage-now .label{color:var(--gold);font:600 11px/1 var(--sans);letter-spacing:.26em;text-transform:uppercase}
.stage-now .title{font:600 clamp(28px,3vw,38px)/1.15 var(--serif);margin-top:12px}
.stage-now .urdu{font-size:22px;color:var(--gold2);margin-top:4px}
.stage-now .arabic{font-size:clamp(24px,2.6vw,32px);line-height:1.9;color:#fff8e6;margin-top:10px;text-shadow:0 0 24px rgba(243,220,157,.35)}
.stage-now.swap{animation:swap .9s cubic-bezier(.2,.8,.2,1)}
@keyframes swap{0%{opacity:0;transform:translateY(14px) scale(.98);filter:blur(6px)}100%{opacity:1;transform:none;filter:none}}
.quiet{color:var(--muted);font-size:15px}
.track{list-style:none;margin:0;padding:0;display:grid;gap:6px}
.track li{display:grid;grid-template-columns:18px 1fr auto;align-items:center;gap:12px;padding:6px 10px;border-radius:10px;color:var(--muted);font-size:14px;transition:background .4s,color .4s}
.track .ur{font-size:13px;line-height:1.6}
.track .dot{width:10px;height:10px;border-radius:50%;border:1px solid var(--line);transition:all .4s}
.track li.done .dot{background:var(--emerald);border-color:var(--emerald)}
.track li.now{background:rgba(217,181,106,.12);color:var(--ink)}
.track li.now .dot{background:var(--gold2);border-color:var(--gold2);box-shadow:0 0 12px 3px rgba(243,220,157,.7)}
.room{display:none;align-items:center;gap:14px;padding:16px;border-radius:14px;border:1px solid rgba(52,211,153,.35);background:rgba(16,185,129,.08)}
.room.show{display:flex}
.room b{display:block}

.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:20px;margin-top:36px}
.halqah{position:relative;padding:26px;border-radius:var(--radius);border:1px solid var(--line);background:linear-gradient(160deg,rgba(16,64,48,.55),rgba(4,21,15,.7));
  overflow:hidden;transition:transform .35s cubic-bezier(.2,.8,.2,1),border-color .35s;transform-style:preserve-3d}
.halqah:hover{border-color:rgba(243,220,157,.55)}
.halqah-glow{position:absolute;width:260px;height:260px;border-radius:50%;left:var(--mx,50%);top:var(--my,0%);translate:-50% -50%;
  background:radial-gradient(circle,rgba(243,220,157,.18),transparent 65%);opacity:0;transition:opacity .3s;pointer-events:none}
.halqah:hover .halqah-glow{opacity:1}
.halqah h3{font-size:28px;margin:16px 0 6px}
.halqah p{color:var(--muted);margin:0 0 20px;font-size:14px}
.halqah-foot{display:flex;flex-direction:column;gap:12px;align-items:flex-start}
.hint{font-size:13px;color:var(--muted)}
.link{color:var(--gold2);font-size:14px;font-weight:600;text-decoration:none}
.link:hover{text-decoration:underline}
.chip{display:inline-block;padding:5px 12px;border-radius:999px;font-size:11px;font-weight:600;letter-spacing:.12em;text-transform:uppercase;border:1px solid var(--line);color:var(--gold)}
.chip-open{border-color:rgba(52,211,153,.5);color:var(--emerald2)}
.chip.live{border-color:rgba(248,113,113,.6);color:#fecaca;margin-left:8px}

.app{display:grid;grid-template-columns:1fr 1fr;gap:clamp(24px,5vw,72px);align-items:center}
@media (max-width:880px){.app{grid-template-columns:1fr}}
.features{display:grid;gap:14px;margin:26px 0 0;padding:0;list-style:none}
.features li{display:flex;gap:14px;align-items:flex-start;padding:16px 18px;border-radius:16px;border:1px solid var(--line);background:rgba(255,255,255,.02)}
.features svg{flex:none;width:22px;height:22px;stroke:var(--gold2);fill:none;stroke-width:1.6;margin-top:2px}
.phone{position:relative;width:min(300px,70vw);aspect-ratio:9/19;margin-inline:auto;border-radius:44px;padding:12px;
  background:linear-gradient(145deg,#1d3a30,#061a13);box-shadow:0 0 0 1px var(--line),0 40px 90px -30px rgba(16,185,129,.6);animation:float 7s ease-in-out infinite}
@keyframes float{50%{transform:translateY(-14px) rotate(-1.2deg)}}
.screen{height:100%;border-radius:34px;overflow:hidden;background:linear-gradient(180deg,#073325,#04150f);padding:26px 18px;display:flex;flex-direction:column;gap:12px}
.screen .card{border-radius:16px;padding:14px;border:1px solid var(--line);background:rgba(255,255,255,.04);font-size:12px;color:var(--muted)}
.screen .card b{display:block;color:var(--ink);font:600 16px/1.3 var(--serif)}
.screen .card.gold{background:linear-gradient(135deg,rgba(243,220,157,.25),rgba(217,181,106,.08))}
.shimmer{height:8px;border-radius:4px;background:linear-gradient(90deg,rgba(255,255,255,.05),rgba(255,255,255,.18),rgba(255,255,255,.05));background-size:200% 100%;animation:sh 2.4s linear infinite;margin-top:8px}
@keyframes sh{to{background-position:-200% 0}}

footer{border-top:1px solid var(--line);padding:40px 0 60px;color:var(--muted);font-size:14px}
footer .row{display:flex;flex-wrap:wrap;gap:16px 28px;justify-content:space-between;align-items:center}
footer nav{all:unset;display:flex;gap:18px;flex-wrap:wrap}
footer a{text-decoration:none}footer a:hover{color:var(--gold2)}

.reveal{opacity:0;transform:translateY(26px);transition:opacity .9s cubic-bezier(.2,.8,.2,1) var(--d,0ms),transform .9s cubic-bezier(.2,.8,.2,1) var(--d,0ms)}
.reveal.in{opacity:1;transform:none}
@media (prefers-reduced-motion:reduce){
  *,*::before,*::after{animation:none!important;transition:none!important}
  .reveal{opacity:1;transform:none}#sky{display:none}
}
</style>
</head>
<body>
<div class="aurora"></div>
<canvas id="sky" aria-hidden="true"></canvas>
<svg class="pattern" viewBox="0 0 640 640" aria-hidden="true"><defs><pattern id="p" width="40" height="40" patternUnits="userSpaceOnUse">
<path d="M20 2 26 14 38 20 26 26 20 38 14 26 2 20 14 14Z" fill="none" stroke="#d9b56a" stroke-width=".8"/>
<rect x="11" y="11" width="18" height="18" fill="none" stroke="#d9b56a" stroke-width=".6" transform="rotate(45 20 20)"/></pattern></defs>
<rect width="640" height="640" fill="url(#p)"/></svg>

<nav>
  <a class="brand" href="/">
    <svg viewBox="0 0 40 40" aria-hidden="true"><path d="M20 3 25 15 37 20 25 25 20 37 15 25 3 20 15 15Z" fill="none" stroke="#d9b56a" stroke-width="1.6"/><circle cx="20" cy="20" r="5" fill="#d9b56a"/></svg>
    <span><small>Naqshbandia Owaisiah</small><b>${esc(site.region)}</b></span>
  </a>
  <div class="navlinks"><a href="#live">Live Zikr</a><a href="#halqahs">Halqahs</a><a href="#app">The app</a></div>
  <span class="status" id="status"><span class="pulse"></span><span id="status-text">Checking…</span></span>
</nav>

<main>
  <div class="wrap hero">
    <div>
      <div class="eyebrow reveal">${esc(site.region)}</div>
      <h1 class="reveal" style="--d:80ms">${esc(site.tagline)}</h1>
      <p class="lead reveal" style="--d:160ms">${esc(site.intro)}</p>
      <div class="cta reveal" style="--d:240ms">
        <a class="btn btn-gold" href="#live"><svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>Watch the live Zikr</a>
        <a class="btn btn-ghost" href="#halqahs">Find your Halqah</a>
      </div>
    </div>
    <div class="portrait reveal" style="--d:200ms" aria-label="Hazrat Ameer Abdul Qadeer Awan (MZA)">
      <div class="halo"></div><div class="ring r2"></div><div class="ring r1"></div>
      <div class="orbit">${Array.from({ length: 7 }, (_, k) => `<i style="--k:${k}"></i>`).join("")}</div>
      <div class="photo"><img id="photo" alt="Hazrat Ameer Abdul Qadeer Awan (MZA)" ${initial.picture ? `src="${esc(initial.picture)}"` : ""}></div>
    </div>
  </div>

  <section id="live">
    <div class="wrap">
      <div class="eyebrow reveal">Our Sheikh · Live</div>
      <h2 class="reveal">Sit in Zikr with Hazrat ji</h2>
      <p class="lead reveal">The Daily Zikr streams here when it is live. During the Zikr, the stage Hazrat ji calls shows beside it: each Latifa, Raabta and the Muraqabat.</p>
      <div class="live-grid">
        <div class="panel reveal">
          <div class="video" id="video"></div>
          <div class="video-cap"><span id="video-label"><b>Latest Daily Zikr</b></span><a class="link" href="https://www.youtube.com/channel/UCefP_tP1ROXmqu2miDVCtCg" target="_blank" rel="noopener">YouTube channel →</a></div>
        </div>
        <div class="panel stage reveal" style="--d:120ms">
          <div class="stage-now" id="stage-now">
            <div class="label">Now</div>
            <div class="quiet" id="stage-quiet">The stage appears here during the live Zikr.</div>
          </div>
          <ol class="track" id="track">${track}</ol>
          <div class="room" id="room">
            <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#34d399" stroke-width="1.6"><path d="M12 3a4 4 0 0 1 4 4v5a4 4 0 0 1-8 0V7a4 4 0 0 1 4-4zM5 11a7 7 0 0 0 14 0M12 18v3"/></svg>
            <div><b>Tahajjud Zikr is open on Paltalk</b><span class="quiet" id="room-count"></span></div>
            <a class="btn btn-ghost" id="room-link" href="#" target="_blank" rel="noopener" style="margin-left:auto">Join</a>
          </div>
        </div>
      </div>
    </div>
  </section>

  <section id="halqahs">
    <div class="wrap">
      <div class="eyebrow reveal">Halqahs</div>
      <h2 class="reveal">${site.halqahs.length > 1 ? `Halqahs in ${esc(site.region)}` : "Our Sheikh's Halqah"}</h2>
      <p class="lead reveal">Our Sheikh's Halqah is open to everyone. The other Halqahs are by invitation: your Halqah's admin sends you an invitation, and you sign in through the Darul Irfan app.</p>
      <div class="grid">${halqahCards}</div>
    </div>
  </section>

  <section id="app">
    <div class="wrap app">
      <div>
        <div class="eyebrow reveal">The Darul Irfan app</div>
        <h2 class="reveal">Your Zikr, your Halqah, in your pocket</h2>
        <ul class="features">
          <li class="reveal"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M10 8l6 4-6 4z"/></svg><span><b>The live Zikr and its stage</b><br><span class="quiet">Follow Hazrat ji's Daily Zikr with each stage as it is called, and send salam or a dua request.</span></span></li>
          <li class="reveal" style="--d:80ms"><svg viewBox="0 0 24 24"><path d="M4 5h7a3 3 0 0 1 3 3v11a2 2 0 0 0-2-2H4zM20 5h-7a3 3 0 0 0-3 3v11a2 2 0 0 1 2-2h8z"/></svg><span><b>The Qur'an with the Silsila's translation</b><br><span class="quiet">Akram-ut-Tarajum in Urdu and English, with Asrar-ut-Tanzil and the bayans.</span></span></li>
          <li class="reveal" style="--d:160ms"><svg viewBox="0 0 24 24"><circle cx="9" cy="8" r="3"/><circle cx="17" cy="9" r="2.5"/><path d="M3 19a6 6 0 0 1 12 0M14 19a5 5 0 0 1 7-4.5"/></svg><span><b>Your Halqah</b><br><span class="quiet">Its Zikr times, sessions together, meetings and notices.</span></span></li>
        </ul>
        <div class="cta reveal"><a class="btn btn-gold" href="darulirfan://groups/our-sheikh">Open in the app</a></div>
        <p class="quiet reveal" style="margin-top:14px">Not on your phone yet? Ask your Halqah for an invitation to the Darul Irfan app.</p>
      </div>
      <div class="phone reveal" style="--d:150ms" aria-hidden="true">
        <div class="screen">
          <div class="card gold"><b>Daily Zikr</b>Live with Our Sheikh<div class="shimmer"></div></div>
          <div class="card"><b id="phone-stage">1st Latifa</b>Current stage</div>
          <div class="card"><b>Akram-ut-Tarajum</b>Today's ayah<div class="shimmer"></div><div class="shimmer" style="width:70%"></div></div>
          <div class="card"><b>${esc(site.halqahs[1]?.name ?? "Our Sheikh")}</b>Zikr times and notices</div>
        </div>
      </div>
    </div>
  </section>
</main>

<footer>
  <div class="wrap row">
    <span>© Naqshbandia Owaisiah · <a href="https://www.naqshbandiaowaisiah.org" target="_blank" rel="noopener">naqshbandiaowaisiah.org</a></span>
    <nav aria-label="Other regions">${regions}</nav>
  </div>
</footer>

<script type="application/json" id="initial">${state}</script>
<script>
(() => {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const $ = id => document.getElementById(id);
  let shownVideo = null, shownStage = null;

  // Light rising like dust in a sunbeam.
  const sky = $("sky"), ctx = sky.getContext("2d");
  let motes = [];
  function size() {
    const r = devicePixelRatio || 1;
    sky.width = innerWidth * r; sky.height = innerHeight * r; ctx.setTransform(r, 0, 0, r, 0, 0);
    motes = Array.from({ length: Math.min(110, Math.floor(innerWidth / 12)) }, () => ({
      x: Math.random() * innerWidth, y: Math.random() * innerHeight, r: Math.random() * 1.8 + .3,
      v: Math.random() * .35 + .08, a: Math.random() * Math.PI * 2, g: Math.random() < .35 }));
  }
  function frame(t) {
    ctx.clearRect(0, 0, innerWidth, innerHeight);
    for (const m of motes) {
      m.y -= m.v; m.x += Math.sin(t / 2400 + m.a) * .25;
      if (m.y < -10) { m.y = innerHeight + 10; m.x = Math.random() * innerWidth; }
      const glow = .35 + .35 * Math.sin(t / 900 + m.a);
      ctx.beginPath(); ctx.arc(m.x, m.y, m.r, 0, 7);
      ctx.fillStyle = m.g ? "rgba(243,220,157," + glow + ")" : "rgba(110,231,183," + glow * .7 + ")";
      ctx.shadowBlur = 8; ctx.shadowColor = ctx.fillStyle; ctx.fill();
    }
    requestAnimationFrame(frame);
  }
  if (!reduce) { size(); addEventListener("resize", size); requestAnimationFrame(frame); }

  // Sections rise into view.
  const io = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } }), { threshold: .12 });
  document.querySelectorAll(".reveal").forEach(el => io.observe(el));

  // Cards follow the pointer.
  document.querySelectorAll(".halqah").forEach(card => {
    card.addEventListener("pointermove", e => {
      const b = card.getBoundingClientRect(), x = (e.clientX - b.left) / b.width, y = (e.clientY - b.top) / b.height;
      card.style.setProperty("--mx", x * 100 + "%"); card.style.setProperty("--my", y * 100 + "%");
      if (!reduce) card.style.transform = "perspective(800px) rotateX(" + (.5 - y) * 6 + "deg) rotateY(" + (x - .5) * 8 + "deg) translateY(-4px)";
    });
    card.addEventListener("pointerleave", () => { card.style.transform = ""; });
  });

  function el(tag, cls, text) { const n = document.createElement(tag); if (cls) n.className = cls; if (text != null) n.textContent = text; return n; }

  function showVideo(id, live) {
    const box = $("video");
    if (!id) { box.replaceChildren(el("div", "quiet", "")); return; }
    if (shownVideo === id) return;
    shownVideo = id;
    const embed = () => {
      const f = document.createElement("iframe");
      f.src = "https://www.youtube-nocookie.com/embed/" + encodeURIComponent(id) + "?autoplay=1&rel=0&modestbranding=1";
      f.allow = "autoplay; encrypted-media; picture-in-picture; fullscreen"; f.allowFullscreen = true;
      f.title = live ? "Daily Zikr, live" : "Latest Daily Zikr";
      box.replaceChildren(f);
    };
    // A picture with a play button: nothing loads from YouTube until it is pressed.
    const poster = el("div", "poster");
    poster.style.backgroundImage = "url(https://i.ytimg.com/vi/" + encodeURIComponent(id) + "/maxresdefault.jpg)";
    const play = el("button", "play"); play.setAttribute("aria-label", live ? "Play the live Zikr" : "Play the latest Daily Zikr");
    play.innerHTML = '<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>';
    play.addEventListener("click", embed);
    poster.append(play); box.replaceChildren(poster);
  }

  function showStage(d) {
    const box = $("stage-now"), s = d.stage;
    const key = (s ? s.title + "|" + s.at : d.halqahLive ? "awaiting" : "off") + (d.halqahTest ? "|test" : "");
    if (key === shownStage) return;
    shownStage = key;
    const parts = [el("div", "label", d.halqahTest ? "Now · test Zikr" : d.halqahLive ? "Now" : "The stage")];
    if (s) {
      parts.push(el("div", "title", s.title));
      if (s.titleUr) { const u = el("div", "urdu", s.titleUr); u.lang = "ur"; parts.push(u); }
      if (s.arabic) { const a = el("div", "arabic", s.arabic); a.lang = "ar"; parts.push(a); }
      $("phone-stage").textContent = s.title;
    } else {
      parts.push(el("div", "quiet", d.halqahLive ? "Awaiting the first stage…" : "The stage appears here during the live Zikr."));
    }
    box.replaceChildren(...parts);
    if (!reduce) { box.classList.remove("swap"); void box.offsetWidth; box.classList.add("swap"); }
    const at = s ? [...document.querySelectorAll("#track li")].findIndex(li => li.dataset.stage === s.title) : -1;
    document.querySelectorAll("#track li").forEach((li, i) => {
      li.classList.toggle("now", i === at);
      li.classList.toggle("done", at > -1 && i < at);
    });
  }

  function render(d) {
    const on = d.live.onAir || d.halqahLive;
    $("status").classList.toggle("on", on);
    const test = d.halqahTest && !d.live.onAir;
    $("status-text").textContent = test ? "Test Zikr" : on ? "Live now" : d.live.room ? "Tahajjud room open" : "Offline";
    showVideo(d.live.videoID || d.latestVideoID, !!d.live.videoID);
    $("video-label").replaceChildren(el("b", "", d.live.videoID ? (d.live.title || "Daily Zikr") + " · live" : "Latest Daily Zikr"));
    showStage(d);
    if (d.picture && $("photo").getAttribute("src") !== d.picture) $("photo").src = d.picture;
    $("photo").onerror = () => { if (d.pictureFallback && $("photo").src !== d.pictureFallback) $("photo").src = d.pictureFallback; };
    const room = $("room");
    room.classList.toggle("show", !!d.live.room);
    if (d.live.room) {
      $("room-count").textContent = d.live.room.listeners ? " · " + d.live.room.listeners + " listening" : "";
      const link = $("room-link");
      if (d.live.room.url) { link.href = d.live.room.url; link.hidden = false; } else link.hidden = true;
    }
    for (const h of d.halqahs) {
      const card = document.querySelector('.halqah[data-id="' + CSS.escape(h.id) + '"]');
      if (!card) continue;
      card.querySelector("[data-name]").textContent = h.name;
      let chip = card.querySelector(".chip.live");
      const isLive = h.id === "our-sheikh" && on;
      if (isLive && !chip) { chip = el("span", "chip live", ""); card.querySelector(".chip").after(chip); }
      if (chip) chip.textContent = d.halqahTest && !d.live.onAir ? "Test" : "Live";
      if (!isLive && chip) chip.remove();
    }
  }

  render(JSON.parse($("initial").textContent));
  async function refresh() {
    try { const r = await fetch("/data.json", { cache: "no-store" }); if (r.ok) render(await r.json()); } catch {}
  }
  setInterval(() => { if (!document.hidden) refresh(); }, 20000);
  document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
})();
</script>
</body>
</html>`;
}
