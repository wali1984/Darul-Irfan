// The shell every page shares: the app's emerald and gold, a moving sky of
// light, the turning eight-pointed pattern, the navigation and the footer.

export const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

/** The Silsila's logo, alive: turning gold rings, seven orbiting lights, a breathing halo.
 *  The picture (/logo.webp) is the seal as the main website shows it: with its ring of words, on a
 *  round white ground with a fine gold edge. One logo for every site (owner, 2026-11-13). */
export function animatedLogo(size = "min(420px,78vw)", extraClass = "") {
  return `<div class="emblem ${extraClass}" style="--s:${size}" aria-label="Naqshbandia Owaisiah">
    <div class="halo"></div><div class="rays"></div><div class="ring r3"></div><div class="ring r2"></div><div class="ring r1"></div>
    <div class="orbit">${Array.from({ length: 7 }, (_, k) => `<i style="--k:${k}"></i>`).join("")}</div>
    <img src="/logo.webp" alt="" width="560" height="560">
  </div>`;
}

export const STYLE = `
:root{--bg:#04150f;--ink:#eef6f1;--muted:#9fbcb0;--line:rgba(212,175,95,.22);--gold:#d9b56a;--gold2:#f3dc9d;
  --emerald:#10b981;--emerald2:#34d399;--glass:rgba(10,40,30,.55);--radius:22px;
  --serif:"Cormorant Garamond",Georgia,serif;--sans:Inter,system-ui,-apple-system,"Segoe UI",sans-serif}
*{box-sizing:border-box}html{scroll-behavior:smooth}[hidden]{display:none!important}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.6 var(--sans);overflow-x:hidden;-webkit-font-smoothing:antialiased}
a{color:inherit}[lang=ur]{font-family:"Noto Nastaliq Urdu",serif;direction:rtl;line-height:2.1}
.arabic{font-family:Amiri,serif;direction:rtl}
#sky{position:fixed;inset:0;z-index:-2;width:100%;height:100%;pointer-events:none}
.aurora{position:fixed;inset:-30%;z-index:-3;background:radial-gradient(40% 35% at 20% 20%,rgba(16,185,129,.28),transparent 70%),
  radial-gradient(35% 30% at 80% 30%,rgba(217,181,106,.18),transparent 70%),radial-gradient(45% 40% at 50% 90%,rgba(6,95,70,.45),transparent 70%),var(--bg);
  animation:drift 28s ease-in-out infinite alternate}
@keyframes drift{to{transform:translate3d(4%,-3%,0) rotate(6deg) scale(1.08)}}
.pattern{position:fixed;z-index:-1;width:120vmax;height:120vmax;left:50%;top:40%;translate:-50% -50%;opacity:.045;animation:spin 240s linear infinite;pointer-events:none}
@keyframes spin{to{rotate:360deg}}
nav.top{position:sticky;top:0;z-index:20;display:flex;align-items:center;gap:20px;justify-content:space-between;padding:12px clamp(16px,4vw,48px);
  backdrop-filter:blur(14px) saturate(1.3);background:linear-gradient(rgba(4,21,15,.85),rgba(4,21,15,.5));border-bottom:1px solid var(--line)}
.brand{display:flex;align-items:center;gap:12px;text-decoration:none}
.brand .emblem{flex:none;margin:0}
.emblem.mini .orbit i{width:4px;height:4px;margin:-2px;box-shadow:0 0 6px 2px rgba(243,220,157,.7)}
.emblem.mini .r1{border-width:1px}
.emblem.mini img{inset:5%;width:90%;height:90%}
.brand b{font:600 20px/1 var(--serif);letter-spacing:.04em}
.brand small{display:block;color:var(--gold);font:600 11px/1.4 var(--sans);letter-spacing:.18em;text-transform:uppercase}
.navlinks{display:flex;gap:22px;font-size:14px;color:var(--muted)}.navlinks a{text-decoration:none;transition:color .2s}.navlinks a:hover,.navlinks a.on{color:var(--gold2)}
@media (max-width:760px){.navlinks{display:none}}
.wrap{width:min(1180px,100% - 32px);margin-inline:auto}
section{padding:clamp(56px,9vw,110px) 0}
.eyebrow{color:var(--gold);font:600 12px/1 var(--sans);letter-spacing:.28em;text-transform:uppercase}
h1,h2,h3{font-family:var(--serif);font-weight:600;margin:0;overflow-wrap:break-word}
h2{font-size:clamp(32px,4.4vw,52px);line-height:1.08;margin:12px 0 14px}
.lead{color:var(--muted);font-size:clamp(16px,1.6vw,19px);max-width:58ch}
.shine{background:linear-gradient(100deg,var(--gold2) 0%,#fff6dc 25%,var(--gold) 50%,var(--gold2) 75%,#fff6dc 100%);background-size:220% 100%;
  -webkit-background-clip:text;background-clip:text;color:transparent;animation:shine 7s linear infinite}
@keyframes shine{to{background-position:-220% 0}}
.btn{display:inline-flex;align-items:center;justify-content:center;gap:10px;padding:14px 24px;border-radius:999px;border:0;text-decoration:none;font:600 15px var(--sans);
  cursor:pointer;transition:transform .25s cubic-bezier(.2,.8,.2,1),box-shadow .25s,opacity .25s;color:inherit}
.btn-gold{background:linear-gradient(135deg,var(--gold2),var(--gold));color:#1d1406;box-shadow:0 10px 30px -10px rgba(217,181,106,.7)}
.btn-gold:hover:not(:disabled){transform:translateY(-2px);box-shadow:0 16px 40px -10px rgba(217,181,106,.9)}
.btn-gold.live{animation:beckon 2.4s ease-in-out infinite}
@keyframes beckon{50%{box-shadow:0 0 0 10px rgba(243,220,157,.12),0 16px 40px -10px rgba(217,181,106,.9)}}
.btn-ghost{border:1px solid var(--line);background:rgba(255,255,255,.03)}.btn-ghost:hover{border-color:var(--gold)}
.btn:disabled{background:rgba(255,255,255,.06);color:#6f8a80;box-shadow:none;cursor:not-allowed;border:1px solid rgba(255,255,255,.08)}
.emblem{position:relative;width:var(--s);aspect-ratio:1;margin-inline:auto}
.emblem img{position:absolute;inset:12%;width:76%;height:76%;border-radius:50%;animation:float 7s ease-in-out infinite;
  filter:drop-shadow(0 20px 50px rgba(16,185,129,.45)) drop-shadow(0 0 30px rgba(243,220,157,.35))}
@keyframes float{50%{transform:translateY(-10px) scale(1.015)}}
.emblem .halo{position:absolute;inset:-8%;border-radius:50%;background:radial-gradient(circle,rgba(243,220,157,.30),transparent 62%);animation:breathe 6s ease-in-out infinite}
@keyframes breathe{50%{transform:scale(1.08);opacity:.55}}
.emblem .rays{position:absolute;inset:-4%;border-radius:50%;background:repeating-conic-gradient(from 0deg,rgba(243,220,157,.14) 0 2deg,transparent 2deg 12deg);
  -webkit-mask:radial-gradient(circle,transparent 46%,#000 52%,transparent 72%);mask:radial-gradient(circle,transparent 46%,#000 52%,transparent 72%);animation:spin 60s linear infinite}
.emblem .ring{position:absolute;border-radius:50%}
.emblem .r1{inset:6%;border:2px solid transparent;background:conic-gradient(from 0deg,var(--gold),transparent 30%,var(--emerald2) 55%,transparent 75%,var(--gold)) border-box;
  -webkit-mask:linear-gradient(#000 0 0) padding-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;mask-composite:exclude;animation:spin 14s linear infinite}
.emblem .r2{inset:1%;border:1px dashed rgba(217,181,106,.4);animation:spin 70s linear infinite reverse}
.emblem .r3{inset:-5%;border:1px solid rgba(52,211,153,.18)}
.emblem .orbit{position:absolute;inset:-5%;animation:spin 36s linear infinite}
.emblem .orbit i{position:absolute;left:50%;top:50%;width:9px;height:9px;margin:-4.5px;border-radius:50%;background:var(--gold2);
  box-shadow:0 0 14px 4px rgba(243,220,157,.7);transform:rotate(calc(var(--k) * 51.43deg)) translateY(calc(var(--s) * -.55))}
.portrait{position:relative;width:min(560px,100%);margin-inline:auto;animation:float 8s ease-in-out infinite}
.portrait .frame{position:relative;border-radius:24px;overflow:hidden;box-shadow:0 30px 80px -20px rgba(16,185,129,.55),0 0 50px -10px rgba(243,220,157,.45)}
.portrait img{display:block;width:100%;height:auto;aspect-ratio:16/9;object-fit:contain;background:#062419}
.portrait .sweep{position:absolute;inset:0;background:linear-gradient(105deg,transparent 35%,rgba(255,246,220,.28) 50%,transparent 65%);
  background-size:250% 100%;animation:sweep 6s ease-in-out infinite;mix-blend-mode:screen;pointer-events:none}
@keyframes sweep{0%{background-position:150% 0}60%,100%{background-position:-60% 0}}
.portrait .edge{position:absolute;inset:-3px;border-radius:27px;padding:3px;pointer-events:none;
  background:conic-gradient(from var(--pa,0deg),var(--gold) 0%,transparent 20%,var(--emerald2) 45%,transparent 60%,var(--gold2) 80%,var(--gold) 100%);
  -webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;mask-composite:exclude;animation:pedge 8s linear infinite}
@property --pa{syntax:"<angle>";inherits:false;initial-value:0deg}
@keyframes pedge{to{--pa:360deg}}
.portrait .glow{position:absolute;inset:-12%;border-radius:40%;background:radial-gradient(closest-side,rgba(243,220,157,.25),transparent);z-index:-1;animation:breathe 6s ease-in-out infinite}
.portrait .spark{position:absolute;width:6px;height:6px;border-radius:50%;background:var(--gold2);box-shadow:0 0 12px 4px rgba(243,220,157,.8);animation:twinkle 3s ease-in-out infinite}
@keyframes twinkle{0%,100%{opacity:0;transform:scale(.4)}50%{opacity:1;transform:scale(1)}}
.chip{display:inline-block;padding:5px 12px;border-radius:999px;font-size:11px;font-weight:600;letter-spacing:.12em;text-transform:uppercase;border:1px solid var(--line);color:var(--gold)}
.chip.live{border-color:rgba(248,113,113,.6);color:#fecaca;background:rgba(239,68,68,.12)}
.chip.test{border-color:rgba(251,191,36,.6);color:#fde68a;background:rgba(251,191,36,.12)}
.chip.off{color:var(--muted)}
.quiet{color:var(--muted);font-size:15px}
.panel{position:relative;border-radius:var(--radius);border:1px solid var(--line);background:var(--glass);backdrop-filter:blur(10px);overflow:hidden}
.panel::before{content:"";position:absolute;inset:0;border-radius:inherit;padding:1px;pointer-events:none;
  background:linear-gradient(130deg,rgba(243,220,157,.55),transparent 35%,transparent 65%,rgba(52,211,153,.45));
  -webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;mask-composite:exclude}
.reveal{opacity:0;transform:translateY(26px);transition:opacity .9s cubic-bezier(.2,.8,.2,1) var(--d,0ms),transform .9s cubic-bezier(.2,.8,.2,1) var(--d,0ms)}
.reveal.in{opacity:1;transform:none}
footer{border-top:1px solid var(--line);padding:40px 0 60px;color:var(--muted);font-size:14px}
footer .row{display:flex;flex-wrap:wrap;gap:16px 28px;justify-content:space-between;align-items:center}
footer .links{display:flex;gap:18px;flex-wrap:wrap}footer a{text-decoration:none}footer a:hover{color:var(--gold2)}
@media (prefers-reduced-motion:reduce){*,*::before,*::after{animation:none!important;transition:none!important}.reveal{opacity:1;transform:none}#sky{display:none}}
`;

/** Rising motes of light, section reveals: shared by every page. */
export const SKY_SCRIPT = `
(() => {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const sky = document.getElementById("sky"), ctx = sky.getContext("2d");
  let motes = [];
  function size() {
    const r = devicePixelRatio || 1;
    sky.width = innerWidth * r; sky.height = innerHeight * r; ctx.setTransform(r, 0, 0, r, 0, 0);
    motes = Array.from({ length: Math.min(120, Math.floor(innerWidth / 11)) }, () => ({
      x: Math.random() * innerWidth, y: Math.random() * innerHeight, r: Math.random() * 1.9 + .3,
      v: Math.random() * .35 + .08, a: Math.random() * Math.PI * 2, g: Math.random() < .4 }));
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
  const io = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } }), { threshold: .1 });
  document.querySelectorAll(".reveal").forEach(el => io.observe(el));
})();
`;

export function shell({ site, others, title, description, active, body, extraStyle = "", script = "" }) {
  const regions = others.map(o => `<a href="https://${esc(o.host)}">${esc(o.region)}</a>`).join("");
  const link = (href, label, key) => `<a href="${href}"${active === key ? ' class="on"' : ""}>${label}</a>`;
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<meta name="theme-color" content="#04150f">
<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(description)}">
<meta property="og:image" content="/logo.webp">
<link rel="icon" href="/logo.webp" type="image/webp">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@500;600;700&family=Inter:wght@400;500;600&family=Amiri:wght@400;700&family=Noto+Nastaliq+Urdu:wght@400;600&display=swap" rel="stylesheet">
<style>${STYLE}${extraStyle}</style>
</head>
<body>
<div class="aurora"></div><canvas id="sky" aria-hidden="true"></canvas>
<svg class="pattern" viewBox="0 0 640 640" aria-hidden="true"><defs><pattern id="p" width="40" height="40" patternUnits="userSpaceOnUse">
<path d="M20 2 26 14 38 20 26 26 20 38 14 26 2 20 14 14Z" fill="none" stroke="#d9b56a" stroke-width=".8"/>
<rect x="11" y="11" width="18" height="18" fill="none" stroke="#d9b56a" stroke-width=".6" transform="rotate(45 20 20)"/></pattern></defs>
<rect width="640" height="640" fill="url(#p)"/></svg>
<nav class="top">
  <a class="brand" href="/">${animatedLogo("48px", "mini")}<span><small>Naqshbandia Owaisiah</small><b>${esc(site.region)}</b></span></a>
  <div class="navlinks">${link("/#live", "Live Zikr", "live")}${link("/#halqahs", "Halqahs", "halqahs")}${link("/method-of-zikr", "Method of Zikr", "method")}${link("/shajra", "Shajra", "shajra")}</div>
  <span id="nav-status"></span>
</nav>
<main>${body}</main>
<footer><div class="wrap row">
  <span>© Naqshbandia Owaisiah · <a href="https://www.naqshbandiaowaisiah.org" target="_blank" rel="noopener">naqshbandiaowaisiah.org</a></span>
  <span class="links"><a href="/method-of-zikr">Method of Zikr</a><a href="/shajra">Shajra</a>${regions}</span>
</div></footer>
<script>${SKY_SCRIPT}</script>
${script}
</body>
</html>`;
}
