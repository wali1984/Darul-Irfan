// The Method of Zikr and the Shajra, word for word from the app's own data
// (DarulIrfanApp/Resources/SeedData/method_of_zikr.json and
// parity-spec/redesign/shajra.json): never retyped or corrected here.
import { esc, shell } from "./layout.js";
import METHOD from "./content/method_of_zikr.json";
import SHAJRA from "./content/shajra.json";

const STYLE = `
.page{padding:clamp(40px,7vw,80px) 0}
.page h1{font-size:clamp(40px,5.6vw,70px);line-height:1.05;margin:14px 0 10px}
.tabs{display:flex;gap:10px;margin:26px 0}
.tabs button{font:600 14px var(--sans);padding:10px 18px;border-radius:999px;border:1px solid var(--line);background:transparent;color:var(--muted);cursor:pointer}
.tabs button[aria-selected=true]{background:linear-gradient(135deg,var(--gold2),var(--gold));color:#1d1406;border-color:transparent}
.cols{display:grid;grid-template-columns:1fr 340px;gap:30px;align-items:start}
.cols>*{min-width:0}
@media (max-width:900px){.cols{grid-template-columns:1fr}}
.entry{padding:22px 24px;margin-bottom:16px;border-radius:18px;border:1px solid var(--line);background:rgba(10,40,30,.5)}
.entry h3{font-size:26px;color:var(--gold2);margin-bottom:6px}
.entry p{margin:0}
.entry.arabic-line{text-align:center;font-size:clamp(24px,2.6vw,32px);line-height:2;color:#fff8e6;text-shadow:0 0 20px rgba(243,220,157,.35)}
.entry.quote{font-style:italic;border-color:rgba(243,220,157,.45)}
.entry .by{display:block;margin-top:10px;color:var(--gold);font-style:normal;font-size:.9em}
[data-lang=ur] .entry{font-size:20px}
.diagram{position:sticky;top:90px;padding:20px;text-align:center}
.diagram svg{width:100%;max-width:300px}
.diagram .cap{font-size:14px;color:var(--muted);margin-top:8px}
.chain{list-style:none;margin:30px 0;padding:0;position:relative}
.chain::before{content:"";position:absolute;left:50%;top:0;bottom:0;width:2px;translate:-1px 0;background:linear-gradient(var(--gold),var(--emerald),var(--gold))}
.link{position:relative;width:min(760px,100%);margin:0 auto 22px;padding:22px 26px;border-radius:20px;border:1px solid var(--line);background:rgba(6,34,26,.85);text-align:center}
.link .ur{font-size:clamp(20px,2.4vw,26px);color:var(--gold2)}
.link .en{color:var(--muted);margin-top:4px}
.link.prophet{border-color:rgba(243,220,157,.7);box-shadow:0 0 40px -12px rgba(243,220,157,.6)}
.link.present{border-color:rgba(52,211,153,.6);box-shadow:0 0 40px -12px rgba(52,211,153,.5)}
.link .n{position:absolute;left:50%;top:-13px;translate:-50% 0;width:26px;height:26px;border-radius:50%;background:var(--gold);color:#1d1406;font:700 12px/26px var(--sans)}
.closing{text-align:center;font-size:clamp(24px,2.8vw,32px);line-height:2;color:#fff8e6;margin-top:20px}
`;

const TAB_SCRIPT = `<script>
document.querySelectorAll(".tabs button").forEach(b => b.addEventListener("click", () => {
  document.querySelectorAll(".tabs button").forEach(x => x.setAttribute("aria-selected", x === b));
  document.querySelectorAll("[data-lang]").forEach(p => p.hidden = p.dataset.lang !== b.dataset.show);
}));
</script>`;

function entries(list, urdu) {
  return list.map(e => {
    if (e.kind === "arabic") return `<div class="entry arabic-line" lang="ar">${esc(e.text)}</div>`;
    if (e.kind === "quote") return `<blockquote class="entry quote"${urdu ? ' lang="ur"' : ""}>${esc(e.text)}${e.attribution ? `<span class="by">${esc(e.attribution)}</span>` : ""}</blockquote>`;
    return `<div class="entry"${urdu ? ' lang="ur"' : ""}>${e.title ? `<h3>${esc(e.title)}</h3>` : ""}<p>${esc(e.text)}</p></div>`;
  }).join("");
}

/** The Lataif on the body, numbered as the Method's own diagram, with the 7th a circle round the whole body. */
function diagram() {
  // The app's positions (MethodLatifaDiagram), the body drawn at 78% inside the circle of the 7th.
  const at = (x, y) => [50 + (x - .5) * 78, 53 + (y - .53) * 78];
  const points = [[.70, .77], [.30, .77], [.70, .53], [.30, .53], [.50, .65], [.50, .24]].map(([x, y]) => at(x, y));
  const p = (x, y) => at(x, y).map(v => v.toFixed(1)).join(" ");
  const body = `M${p(.12, .94)} L${p(.12, .48)} Q${p(.12, .36)} ${p(.30, .36)} C${p(.30, .10)} ${p(.70, .10)} ${p(.70, .36)} Q${p(.88, .36)} ${p(.88, .48)} L${p(.88, .94)}`;
  return `<svg viewBox="0 0 100 100" role="img" aria-label="Numbered diagram, viewed from the front: 1 lower right, 2 lower left, 3 middle right, 4 middle left, 5 centre, 6 upper centre, 7 a circle around the whole body.">
    <circle cx="50" cy="53" r="45" fill="none" stroke="#d9b56a" stroke-width="1.4" stroke-dasharray="3 2"><animate attributeName="stroke-opacity" values=".5;1;.5" dur="4s" repeatCount="indefinite"/></circle>
    <circle cx="50" cy="8" r="5" fill="#d9b56a"/><text x="50" y="10.2" text-anchor="middle" font-size="6" font-weight="700" fill="#1d1406">7</text>
    <path d="${body}" fill="none" stroke="rgba(238,246,241,.5)" stroke-width="1.2"/>
    ${points.map(([x, y], i) => `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="4.2" fill="rgba(243,220,157,.18)" stroke="#d9b56a" stroke-width=".6"/><text x="${x.toFixed(1)}" y="${(y + 1.7).toFixed(1)}" text-anchor="middle" font-size="4.6" font-weight="700" fill="#f3dc9d">${i + 1}</text>`).join("")}
  </svg>`;
}

export function methodPage(site, others) {
  const body = `<div class="wrap page">
    <div class="eyebrow">Silsila Naqshbandia Owaisiah</div>
    <h1 class="shine">Method of Zikr</h1>
    <div class="tabs" role="tablist"><button data-show="ur" aria-selected="true">اردو</button><button data-show="en" aria-selected="false">English</button></div>
    <div class="cols">
      <div><div data-lang="ur">${entries(METHOD.ur, true)}</div><div data-lang="en" hidden>${entries(METHOD.en, false)}</div></div>
      <aside class="panel diagram">${diagram()}
        <div class="cap" data-lang="ur" lang="ur">${esc(METHOD.diagramCaptionUr)}</div>
        <div class="cap" data-lang="en" hidden>${esc(METHOD.diagramCaptionEn)}</div></aside>
    </div>
  </div>`;
  return shell({ site, others, title: `Method of Zikr · ${site.title}`, description: "The Method of Zikr of Silsila Naqshbandia Owaisiah.",
    active: "method", extraStyle: STYLE, body, script: TAB_SCRIPT });
}

export function shajraPage(site, others) {
  const links = SHAJRA.entries.map(e => `<li class="link ${e.kind === "prophet" ? "prophet" : e.kind === "presentSheikh" ? "present" : ""}">
      ${e.kind === "sheikh" ? `<span class="n">${e.index}</span>` : ""}
      <div class="ur" lang="ur">${esc(e.urdu)}</div><div class="en">${esc(e.english)}</div></li>`).join("");
  const body = `<div class="wrap page">
    <div class="eyebrow">The chain of transmission</div>
    <h1 class="shine" lang="ur" style="font-family:'Noto Nastaliq Urdu',serif;line-height:1.8">${esc(SHAJRA.title.ur)}</h1>
    <p class="lead">${esc(SHAJRA.title.en)}</p>
    <ol class="chain">${links}</ol>
    <div class="closing arabic" lang="ar">${esc(SHAJRA.closingArabic)}</div>
  </div>`;
  return shell({ site, others, title: `Shajra · ${site.title}`, description: SHAJRA.title.en, active: "shajra", extraStyle: STYLE, body });
}
