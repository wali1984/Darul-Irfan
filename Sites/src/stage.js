// The live stage, as the YouTube and Facebook picture shows it (/broadcast) and
// as every site's live page shows it (owner 2026-11-09): Hazrat ji's picture at
// the side, the stage being done now in its card (a Latifa's number on a turning
// gold star, a recitation's Arabic, the Shajra's lines rolling), and on the
// websites the whole order of the Zikr beneath it with the stage now lit.
// One markup, one style and one script for both, so they never drift apart.
import { animatedLogo, esc } from "./layout.js";
import SHAJRA from "./content/shajra.json";

// The stages a Zikr moves through, in order, as the app names them (Server
// RECITATIONS and DEFAULT_ZIKR_STAGES). A custom Muraqaba shows only when called.
export const STAGES = [
  ["tasbih", "Tasbihat", "تسبیحات"], ["istighfar", "Istighfar", "استغفار"], ["shahadah", "Shahadah", "کلمہ شہادت"],
  ["taawwudh", "Ta'awwudh", "تعوذ"], ["basmalah", "Bismillah", "تسمیہ"],
  ["latifa-1", "1st Latifa", "پہلا لطیفہ"], ["latifa-2", "2nd Latifa", "دوسرا لطیفہ"], ["latifa-3", "3rd Latifa", "تیسرا لطیفہ"],
  ["latifa-4", "4th Latifa", "چوتھا لطیفہ"], ["latifa-5", "5th Latifa", "پانچواں لطیفہ"], ["latifa-6", "6th Latifa", "چھٹا لطیفہ"],
  ["latifa-7", "7th Latifa", "ساتواں لطیفہ"], ["raabta", "Raabta", "رابطہ"],
  ["ahadiyat", "Muraqaba Ahadiyat", "مراقبہ احدیت"], ["maiyyat", "Muraqaba Ma'iyyat", "مراقبہ معیت"],
  ["aqrabiyyat", "Muraqaba Aqrabiyyat", "مراقبہ اقربیت"], ["sair-kaaba", "Sair-e-Kaaba", "سیرِ کعبہ"],
  ["rauza-athar", "Rauza-e-Athar", "روضۂ اطہر"], ["masjid-nabawi", "Masjid-e-Nabawi", "مسجدِ نبوی"],
  ["shajra", "Shajra Sharif", "شجرہ شریف"], ["dua", "Dua", "دعا"],
];

// The order of the Zikr in its parts, as the owner names them: the Tasbihat,
// the seven Lataif, Raabta, the Muraqabat, the Shajra and the Dua.
export const STAGE_GROUPS = [
  ["opening", "Tasbihat", "تسبیحات", ["tasbih", "istighfar", "shahadah", "taawwudh", "basmalah"]],
  ["lataif", "Lataif", "لطائف", ["latifa-1", "latifa-2", "latifa-3", "latifa-4", "latifa-5", "latifa-6", "latifa-7"]],
  ["raabta", "Raabta", "رابطہ", ["raabta"]],
  ["muraqabat", "Muraqabat", "مراقبات", ["ahadiyat", "maiyyat", "aqrabiyyat", "sair-kaaba", "rauza-athar", "masjid-nabawi"]],
  ["shajra", "Shajra", "شجرہ", ["shajra"]],
  ["dua", "Dua", "دعا", ["dua"]],
];

const NAMES = new Map(STAGES.map(([id, en, ur]) => [id, { en, ur }]));
const json = value => JSON.stringify(value).replace(/</g, "\\u003c");

/** The script both pages share: fillStage fills a stage card the way the app
 *  shows each kind of stage; showStage shows a whole stage screen (picture,
 *  card, the order of the Zikr, the polite announcement) and returns the key of
 *  what it shows, so a caller only redraws on a change. */
export const STAGE_SCRIPT = `
const SHAJRA_LINES = ${json([...SHAJRA.entries.map(e => e.urdu), SHAJRA.closingArabic])};
const STAGE_ORDER = ${json(STAGES.map(([id]) => id))};
function stageKind(id) {
  if (!id) return "awaiting";
  if (/^latifa-[1-7]$/.test(id)) return "latifa";
  if (["tasbih", "istighfar", "shahadah", "taawwudh", "basmalah"].includes(id)) return "recite";
  if (id === "shajra" || id === "dua") return id;
  return "muraqaba";
}
function stageStill() { return matchMedia("(prefers-reduced-motion: reduce)").matches; }
function fillStage(card, s, emptyTitle) {
  const id = s ? s.stageID : null, kind = stageKind(id);
  card.className = card.className.replace(/\\bkind-\\w+/g, "").trim() + " kind-" + kind;
  card.querySelector(".label").textContent = { recite: "Recitation", latifa: "Latifa", muraqaba: "Muraqaba", shajra: "Shajra", dua: "Dua", awaiting: "Bayan" }[kind] || "Now";
  const medal = card.querySelector(".medal");
  medal.hidden = kind !== "latifa";
  medal.querySelector("b").textContent = kind === "latifa" ? id.slice(7) : "";
  // Live before the first stage: the Bayan is playing and the Zikr follows it (owner 2026-11-10).
  card.querySelector(".title").textContent = s ? s.title : (emptyTitle || "Playing Bayan");
  card.querySelector(".urdu").textContent = s ? (s.titleUr || "") : "بیان جاری ہے";
  const next = card.querySelector(".next");
  if (next) next.textContent = s ? "" : "Zikr will start soon · ذکر جلد شروع ہوگا";
  card.querySelector(".arabic").textContent = s && s.arabic ? s.arabic : "";
  const roll = card.querySelector(".roll"), lines = roll.querySelector(".lines");
  lines.classList.remove("run"); lines.style.removeProperty("--dist");
  lines.textContent = "";
  roll.hidden = kind !== "shajra";
  if (kind === "shajra") {
    SHAJRA_LINES.forEach((text, i) => {
      const line = document.createElement("div");
      line.className = i === SHAJRA_LINES.length - 1 ? "line closing" : "line";
      line.lang = i === SHAJRA_LINES.length - 1 ? "ar" : "ur";
      line.textContent = text;
      lines.append(line);
    });
    // From the first line to the last in under a minute (owner 2026-11-06),
    // then it rests on the last line until the Dua.
    requestAnimationFrame(() => {
      const dist = Math.max(0, lines.scrollHeight - roll.clientHeight);
      lines.style.setProperty("--dist", -dist + "px");
      lines.style.setProperty("--dur", Math.round(SHAJRA_LINES.length * 3.5) + "s");
      if (dist && !stageStill()) lines.classList.add("run");
    });
  }
}
// The order of the Zikr: what is done, the stage now (aria-current), what is to
// come. After the 7th Latifa the Zikr returns to the 1st for a moment: the
// Lataif already done stay done. A custom Muraqaba lights the Muraqabat.
function stageRail(box, s, live) {
  const rail = box.querySelector(".rail");
  if (!rail) return;
  const session = live ? String(live.sessionID || live.startedAt || "live") : "";
  if (rail.dataset.session !== session) { rail.dataset.session = session; rail.dataset.reached = "-1"; }
  const at = s ? STAGE_ORDER.indexOf(s.stageID) : -1;
  const reached = Math.max(Number(rail.dataset.reached), at);
  rail.dataset.reached = String(reached);
  rail.querySelectorAll("li[data-stage]").forEach(li => {
    const i = STAGE_ORDER.indexOf(li.dataset.stage);
    li.classList.toggle("here", i === at);
    li.classList.toggle("past", i !== at && i <= reached);
    if (i === at) li.setAttribute("aria-current", "step"); else li.removeAttribute("aria-current");
  });
  const custom = at < 0 && s && stageKind(s.stageID) === "muraqaba";
  rail.querySelectorAll(".grp").forEach(g => {
    const dots = [...g.querySelectorAll("li[data-stage]")];
    g.classList.toggle("here", dots.some(li => li.classList.contains("here")) || (custom && g.dataset.group === "muraqabat"));
    g.classList.toggle("past", dots.every(li => li.classList.contains("past")));
  });
}
function showStage(box, s, live, o) {
  o = o || {};
  box.classList.toggle("on", !!live);
  // Hazrat ji's picture beside the stage (Our Sheikh's only), as on the YouTube picture.
  const photo = box.querySelector(".photo img");
  if (photo && o.picture && photo.dataset.want !== o.picture) {
    photo.dataset.want = o.picture;
    photo.onerror = () => { if (o.fallback && photo.getAttribute("src") !== o.fallback) photo.src = o.fallback; };
    photo.src = o.picture;
  }
  box.classList.toggle("duo", !!(photo && o.picture && live));
  const key = live ? (s ? s.stageID + "|" + s.at : "awaiting") + (live.isTest ? "|t" : "") : "off";
  if (key === o.last) return key;
  const card = box.querySelector(".card"), title = card.querySelector(".title");
  fillStage(card, s, o.waiting);
  card.querySelector(".test").hidden = !(live && live.isTest);
  stageRail(box, s, live);
  // A long name never runs past the card: the title shrinks until it fits.
  title.style.fontSize = "";
  for (let size = parseFloat(getComputedStyle(title).fontSize); title.scrollWidth > title.clientWidth && size > (o.minTitle || 24); size -= 2) title.style.fontSize = size + "px";
  // Said once, politely, to a screen reader: the stage now, or that the Zikr ended.
  const say = box.querySelector(".say");
  if (say) say.textContent = live ? (s ? "Now: " + s.title : "The Zikr is live. Playing Bayan; the Zikr will start soon.") : (o.last && o.last !== "off" ? "The Zikr has ended." : "");
  if (live && !stageStill()) { card.classList.remove("burst"); void card.offsetWidth; card.classList.add("burst"); }
  return key;
}
`;

/** The order of the Zikr, every stage a light, grouped as the owner names the parts. */
function rail() {
  const groups = STAGE_GROUPS.map(([key, en, ur, ids]) => `<li class="grp" data-group="${key}">
        <span class="gname"><span class="en">${esc(en)}</span> <span class="ur" lang="ur">${esc(ur)}</span></span>
        <ol class="dots">${ids.map(id => `<li data-stage="${id}" title="${esc(NAMES.get(id).en)}"><span class="sr">${esc(NAMES.get(id).en)}</span></li>`).join("")}</ol></li>`).join("");
  return `<ol class="rail" aria-label="The order of the Zikr">${groups}</ol>`;
}

/** One stage screen: the living emblem while waiting; live, the stage being done,
 *  Hazrat ji's picture beside it when it is Our Sheikh's, and (rail) the order
 *  of the Zikr beneath. */
export function stageScreen(id, waiting, { rail: withRail = true } = {}) {
  return `<div class="stage" id="${id}">
      <div class="mark">${animatedLogo("min(260px,62vw)")}</div>
      <div class="photo"><img alt="Hazrat Ameer Abdul Qadeer Awan (MZA)" decoding="async"></div>
      <div class="waiting"><div class="quiet">${esc(waiting)}</div></div>
      <div class="now"><div class="card"><div class="ring"></div><div class="medal" hidden><i></i><b></b></div><div class="label">Now</div><div class="title"></div>
        <div class="urdu" lang="ur"></div><div class="next"></div><div class="arabic" lang="ar"></div><div class="roll" hidden><div class="lines"></div></div>
        <span class="chip test" hidden>Test Zikr</span></div></div>
      ${withRail ? rail() : ""}
      <p class="say sr" role="status" aria-live="polite" aria-atomic="true"></p>
    </div>`;
}

export const STAGE_STYLE = `
/* The stage. Waiting: the living emblem, large. Live: the emblem goes small to
   the corner and only the stage being done now fills the screen. */
.stage{position:relative;min-height:440px;display:grid;place-items:center;padding:clamp(24px,4vw,44px);text-align:center;overflow:hidden}
.stage .sr{position:absolute;width:1px;height:1px;margin:-1px;padding:0;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap;border:0}
.stage .mark{transition:transform 1s cubic-bezier(.2,.8,.2,1),opacity .6s;transform-origin:top left}
.stage .mark .emblem{--s:min(260px,62vw)}
.stage.on .mark{position:absolute;top:18px;left:18px;transform:scale(.3)}
.stage .waiting{display:grid;gap:16px;justify-items:center}
.stage.on .waiting{display:none}
.stage .now{display:none;width:100%}
.stage.on .now{display:block}
.stage.on{align-content:center;row-gap:clamp(18px,2.6vw,30px)}
.now .label{color:var(--gold);font:600 12px/1 var(--sans);letter-spacing:.3em;text-transform:uppercase}
.now .title{font:600 clamp(48px,7vw,104px)/1.02 var(--serif);margin-top:16px;
  background:linear-gradient(100deg,var(--gold2),#fff6dc 30%,var(--gold) 55%,var(--gold2) 80%);background-size:220% 100%;
  -webkit-background-clip:text;background-clip:text;color:transparent;animation:shine 6s linear infinite;
  filter:drop-shadow(0 0 26px rgba(243,220,157,.35))}
.now .urdu{font-size:clamp(30px,4vw,54px);color:var(--gold2);margin-top:6px;text-shadow:0 0 22px rgba(243,220,157,.35)}
.now .next{font:500 clamp(18px,2vw,26px)/1.5 var(--sans);color:var(--gold);letter-spacing:.04em;margin-top:18px;animation:nextGlow 2.8s ease-in-out infinite}
.now .next:empty{display:none}
@keyframes nextGlow{50%{opacity:.55}}
@media (prefers-reduced-motion: reduce){.now .next{animation:none}}
.now .arabic{font-size:clamp(28px,3.6vw,46px);line-height:1.9;color:#fff8e6;margin-top:14px;text-shadow:0 0 28px rgba(243,220,157,.5)}
.now .test{display:inline-block;margin-top:18px}
/* Each kind of stage, as the app shows it: a Latifa's number on a turning
   gold star, the Arabic of a recitation, the Shajra's lines rolling. */
.now .medal{position:relative;width:96px;height:96px;margin:0 auto 6px;display:grid;place-items:center}
.now .medal[hidden]{display:none}
.now .medal i{position:absolute;inset:0;background:linear-gradient(180deg,#ffe9a8,#e0b75f 55%,#b48a2c);
  clip-path:polygon(50% 0,61% 22%,85% 15%,78% 39%,100% 50%,78% 61%,85% 85%,61% 78%,50% 100%,39% 78%,15% 85%,22% 61%,0 50%,22% 39%,15% 15%,39% 22%);
  animation:turn 30s linear infinite;filter:drop-shadow(0 0 18px rgba(243,220,157,.55))}
.now .medal b{position:relative;width:58%;height:58%;border-radius:50%;background:#062a1f;display:grid;place-items:center;
  color:var(--gold2);font:700 38px/1 var(--sans);box-shadow:inset 0 0 12px rgba(0,0,0,.6)}
@keyframes turn{to{transform:rotate(360deg)}}
.now .roll{position:relative;max-height:min(46vh,420px);overflow:hidden;margin-top:18px;
  -webkit-mask:linear-gradient(transparent,#000 14%,#000 86%,transparent);mask:linear-gradient(transparent,#000 14%,#000 86%,transparent)}
.now .roll[hidden]{display:none}
.now .lines{padding:40px 0;display:grid;gap:6px}
.now .lines.run{animation:roll var(--dur,50s) linear 1s forwards}
@keyframes roll{to{transform:translateY(var(--dist,0))}}
.now .line{font-size:clamp(20px,2.4vw,30px);color:#fff8e6;text-shadow:0 0 18px rgba(243,220,157,.35)}
.now .line.closing{font-family:Amiri,serif;color:var(--gold2);margin-top:10px}
.now .card.kind-recite .arabic{font-size:clamp(30px,4vw,52px)}
.now .card.kind-dua{box-shadow:0 0 90px -6px rgba(243,220,157,.55),inset 0 0 50px rgba(243,220,157,.12)}
.now .card.kind-shajra .title,.now .card.kind-dua .title{letter-spacing:.02em}
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

/* Hazrat ji's picture beside the stage, as on the YouTube picture: shown only
   while Our Sheikh's Zikr is live (duo). On a phone it stands above the stage. */
.stage .photo{display:none;width:100%;aspect-ratio:16/9;border-radius:24px;overflow:hidden;background:#062419;
  border:2px solid rgba(243,220,157,.65);box-shadow:0 0 70px -12px rgba(243,220,157,.45);animation:bob 5s ease-in-out infinite}
.stage .photo img{width:100%;height:100%;object-fit:cover;display:block}
.stage.duo .photo{display:block}
.stage.duo{grid-template-columns:minmax(0,1fr) minmax(0,1.1fr);gap:clamp(18px,3vw,40px);align-items:center}
.stage.duo .mark{opacity:0;visibility:hidden}
.stage.duo .now .card{width:100%;padding:clamp(24px,3vw,40px) 18px}
.stage.duo .now .title{font-size:clamp(36px,4.6vw,72px)}
.stage.duo .now .urdu{font-size:clamp(26px,3vw,44px)}
.stage.duo .now .arabic{font-size:clamp(22px,2.6vw,38px)}
@media (max-width:820px){.stage.duo{grid-template-columns:minmax(0,1fr)}}

/* The order of the Zikr beneath the stage: done, now (lit and breathing), to come. */
.stage .rail{display:none;list-style:none;margin:6px 0 0;padding:0;grid-column:1/-1;width:100%;
  flex-wrap:wrap;justify-content:center;gap:14px 26px}
.stage.on .rail{display:flex}
.rail .grp{display:grid;gap:8px;justify-items:center;color:var(--muted);transition:color .6s}
.rail .gname{font:600 11px/1.2 var(--sans);letter-spacing:.2em;text-transform:uppercase;white-space:nowrap}
.rail .gname .ur{font:15px/1.5 "Noto Nastaliq Urdu",serif;letter-spacing:0;text-transform:none;margin-inline-start:6px}
.rail .grp.past{color:rgba(217,181,106,.75)}
.rail .grp.here{color:var(--gold2);text-shadow:0 0 16px rgba(243,220,157,.55)}
.rail .dots{position:relative;list-style:none;margin:0;padding:0;display:flex;gap:9px;align-items:center;min-height:18px}
.rail .dots::before{content:"";position:absolute;left:5px;right:5px;top:50%;height:1px;background:var(--line)}
.rail .dots li{position:relative;width:11px;height:11px;border-radius:50%;border:1px solid rgba(217,181,106,.55);background:#04150f;
  transition:transform .5s cubic-bezier(.2,.8,.2,1),background .5s,box-shadow .5s}
.rail .dots li.past{background:rgba(217,181,106,.7);border-color:transparent}
.rail .dots li.here{background:var(--gold2);border-color:#fff6dc;transform:scale(1.55);box-shadow:0 0 14px 3px rgba(243,220,157,.75);animation:litnow 2.2s ease-in-out infinite}
@keyframes litnow{50%{box-shadow:0 0 0 6px rgba(243,220,157,.18),0 0 22px 6px rgba(243,220,157,.6)}}
@media (prefers-reduced-motion:reduce){.stage .photo,.now .card,.rail .dots li.here{animation:none!important}.stage .mark{transition:none}}
`;
