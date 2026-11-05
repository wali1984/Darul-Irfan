// app-demo.naqshbandiaowaisiah.us: the app's showcase for an audience. The
// interactive showcase, PowerPoint, PDF and package were made separately
// (outputs/darul-app-showcase/deliverables, v3); the first two are served as
// site files under /demo/, the two large ones from R2 (demo/...). "What's new"
// covers what was added after the showcase was made.
import { animatedLogo, esc, shell } from "./layout.js";

const STYLE = `
.hero{display:grid;grid-template-columns:1.1fr .9fr;gap:clamp(24px,5vw,64px);align-items:center;min-height:min(calc(100svh - 74px),820px);padding-top:30px}
.hero>*{min-width:0}
@media (max-width:900px){.hero{grid-template-columns:1fr;text-align:center}.hero .lead{margin-inline:auto}.cta,.stats{justify-content:center}}
.hero h1{font-size:clamp(44px,6.4vw,86px);line-height:1.02;margin:18px 0 18px}
.cta{display:flex;gap:14px;flex-wrap:wrap;margin-top:28px}
.stats{display:flex;gap:28px;flex-wrap:wrap;margin-top:34px}
.stats b{display:block;font:600 clamp(34px,4vw,48px)/1 var(--serif);color:var(--gold2)}
.stats span{color:var(--muted);font-size:14px}
.downloads{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:18px;margin-top:30px}
.dl{display:flex;gap:16px;align-items:center;padding:22px;border-radius:var(--radius);border:1px solid var(--line);background:rgba(10,40,30,.55);text-decoration:none;
  transition:transform .3s,border-color .3s}
.dl:hover{transform:translateY(-3px);border-color:rgba(243,220,157,.6)}
.dl .ic{flex:none;width:52px;height:52px;border-radius:14px;display:grid;place-items:center;background:linear-gradient(135deg,var(--gold2),var(--gold));color:#1d1406;font:700 13px var(--sans)}
.dl b{display:block;font-size:17px}.dl span{color:var(--muted);font-size:13px}
.new{display:grid;gap:28px;margin-top:36px}
.item{display:grid;grid-template-columns:1fr 1fr;gap:clamp(20px,4vw,48px);align-items:center;padding:clamp(20px,3vw,32px);border-radius:26px;border:1px solid var(--line);
  background:linear-gradient(160deg,rgba(16,64,48,.5),rgba(4,21,15,.6))}
.item:nth-child(even) .shot{order:-1}
@media (max-width:900px){.item{grid-template-columns:1fr}.item:nth-child(even) .shot{order:0}}
.item h3{font-size:clamp(28px,3vw,38px);margin:10px 0 10px}
.item p{color:var(--muted);margin:0 0 12px}
.item ul{margin:0;padding-left:20px;color:var(--ink)}.item li{margin:6px 0}
.item .links{display:flex;gap:10px;flex-wrap:wrap;margin-top:16px}
.item .links a{font-size:14px;padding:9px 16px}
.shot{border-radius:18px;overflow:hidden;border:1px solid rgba(243,220,157,.35);box-shadow:0 30px 70px -25px rgba(16,185,129,.55);position:relative}
.shot img{display:block;width:100%;height:auto}
.shot::after{content:"";position:absolute;inset:0;background:linear-gradient(105deg,transparent 40%,rgba(255,246,220,.14) 50%,transparent 60%);background-size:250% 100%;animation:sweep 7s ease-in-out infinite}
@keyframes sweep{0%{background-position:150% 0}60%,100%{background-position:-60% 0}}
.pillrow{display:flex;gap:10px;flex-wrap:wrap;margin-top:6px}
`;

const NEW = [
  {
    tag: "New · Websites", title: "Live Zikr on the web, for every region",
    text: "Three public websites, open to everyone, in the app's emerald and gold with the living emblem.",
    points: [
      "oursheikh., namerica. (USA and Canada) and uk.naqshbandiaowaisiah.us",
      "Each Halqah's Zikr appears the moment it is live; anyone joins with a name and a place",
      "Listen only, live: the sound comes straight from the Zikr as it happens, never a recording",
      "Hazrat ji's admins see every web visitor in the session's attendance",
    ],
    shot: "/demo/new/home.webp", alt: "North America website",
    links: [["https://oursheikh.naqshbandiaowaisiah.us", "Our Sheikh"], ["https://namerica.naqshbandiaowaisiah.us", "North America"], ["https://uk.naqshbandiaowaisiah.us", "United Kingdom"]],
  },
  {
    tag: "New · Live stage", title: "The stage, on every screen",
    text: "Once a Zikr starts, the emblem steps aside and only the stage being done fills the screen: the opening Tasbihat in Arabic, each Latifa, Raabta and every Muraqaba up to Masjid-e-Nabawi.",
    points: [
      "The same stage in the app, on the websites and in the YouTube and Facebook picture",
      "A 1920×1080 broadcast stage for the live streams",
      "Every Halqah now has its stage, led by its own Ameer or admins",
    ],
    shot: "/demo/new/broadcast.webp", alt: "Broadcast stage showing 3rd Latifa",
  },
  {
    tag: "New · Hands-free", title: "Go Live: the stage follows Hazrat ji's voice",
    text: "One tap, and the leading phone listens: each recitation, Latifa and Muraqaba Hazrat ji names shows by itself. It was tuned on real Daily Zikr sessions, so it understands the stages the way they are actually called, in Urdu and Hindi script.",
    points: [
      "Keeps listening the whole session; the screen stays awake and it recovers by itself",
      "Undo puts back a wrong stage; admins can add a Muraqaba from the stage",
      "Paltalk's hosts' cues reach the same stage through the live relay",
    ],
    shot: null,
  },
  {
    tag: "New · Automation", title: "The Zikr starts and ends by itself",
    text: "When Hazrat ji is live on Paltalk, the live relay starts Our Sheikh's Zikr in the app and on the websites, and members are told. When the dua begins, the stage shows it, and the session closes five minutes later.",
    points: ["Test Zikr: admins try everything without notifying anyone", "Admins remove any stage announcement, message or dua request"],
    shot: null,
  },
  {
    tag: "New · Teaching", title: "Method of Zikr and the Shajra, online",
    text: "Word for word from the app, in Urdu and English. The Lataif picture now shows the seventh as a circle around the whole body, in the app and on the web.",
    points: ["Opening recitations in Arabic, each Latifa's instruction, Raabta", "The full chain of transmission, from the Holy Prophet ﷺ to the present Sheikh"],
    shot: "/demo/new/method.webp", alt: "Method of Zikr page",
    links: [["https://oursheikh.naqshbandiaowaisiah.us/method-of-zikr", "Method of Zikr"], ["https://oursheikh.naqshbandiaowaisiah.us/shajra", "Shajra"]],
  },
];

export function demoPage(site, others) {
  const items = NEW.map((n, i) => `
    <article class="item reveal" style="--d:${i * 40}ms">
      <div>
        <span class="chip">${esc(n.tag)}</span>
        <h3>${esc(n.title)}</h3>
        <p>${esc(n.text)}</p>
        <ul>${n.points.map(p => `<li>${esc(p)}</li>`).join("")}</ul>
        ${n.links ? `<div class="links">${n.links.map(([href, label]) => `<a class="btn btn-ghost" href="${esc(href)}" target="_blank" rel="noopener">${esc(label)} ↗</a>`).join("")}</div>` : ""}
      </div>
      ${n.shot ? `<div class="shot"><img src="${esc(n.shot)}" alt="${esc(n.alt)}" loading="lazy"></div>` : `<div>${animatedLogo("min(300px,70vw)")}</div>`}
    </article>`).join("");
  const body = `
  <div class="wrap hero">
    <div>
      <div class="eyebrow reveal">Darul Irfan · Product showcase</div>
      <h1 class="reveal shine" style="--d:80ms">The Silsila's app, in your hands</h1>
      <p class="lead reveal" style="--d:160ms">The Qur'an with the Silsila's translation and tafsir, hadith, the library, Zikr with the Sheikh and every Halqah, in English and Urdu, on iPhone and Android.</p>
      <div class="cta reveal" style="--d:240ms">
        <a class="btn btn-gold live" href="/demo/showcase.html">Start the interactive showcase</a>
        <a class="btn btn-ghost" href="#new">What's new</a>
      </div>
      <div class="stats reveal" style="--d:300ms">
        <div><b>35</b><span>bilingual slides</span></div><div><b>243</b><span>features</span></div><div><b>62</b><span>app screens</span></div>
      </div>
    </div>
    <div class="reveal" style="--d:200ms">${animatedLogo()}</div>
  </div>

  <section id="downloads"><div class="wrap">
    <div class="eyebrow reveal">For presenting</div>
    <h2 class="reveal">The showcase</h2>
    <p class="lead reveal">Open the interactive showcase full screen to present; arrow keys move through it. The PowerPoint and PDF carry the same 35 slides.</p>
    <div class="downloads">
      <a class="dl reveal" href="/demo/showcase.html"><span class="ic">▶</span><span><b>Interactive showcase</b><span>Introduction, app tour, 62 screens, feature tree</span></span></a>
      <a class="dl reveal" href="/demo/Darul-Irfan-Product-Showcase-v3.pptx" download><span class="ic">PPT</span><span><b>PowerPoint</b><span>35 slides · 12.5 MB</span></span></a>
      <a class="dl reveal" href="/demo/files/Darul-Irfan-Product-Showcase-v3.pdf"><span class="ic">PDF</span><span><b>PDF</b><span>For reading and printing · 27.6 MB</span></span></a>
      <a class="dl reveal" href="/demo/files/Darul-Irfan-Presentation-Package-v3.zip" download><span class="ic">ZIP</span><span><b>Complete package</b><span>Everything together · 55 MB</span></span></a>
    </div>
  </div></section>

  <section id="new"><div class="wrap">
    <div class="eyebrow reveal">Since the showcase</div>
    <h2 class="reveal">What's new</h2>
    <p class="lead reveal">Added after the showcase was made: live Zikr on the web, one stage everywhere, and a Zikr that runs itself.</p>
    <div class="new">${items}</div>
  </div></section>`;
  // The shared navigation points into the Our Sheikh site; this host only has the showcase.
  const home = "https://oursheikh.naqshbandiaowaisiah.us";
  return shell({ site, others, title: "Darul Irfan · App showcase", description: "The Darul Irfan app: interactive showcase, slides and what's new.",
    active: "", extraStyle: STYLE, body })
    .replace(/href="\/(#live|#halqahs|method-of-zikr|shajra)"/g, (_, path) => `href="${home}/${path}"`)
    .replace('<a class="brand" href="/">', '<a class="brand" href="/">');
}

/** The two large files, from R2 (demo/...). */
export async function demoFile(env, name, request) {
  const allowed = { "Darul-Irfan-Product-Showcase-v3.pdf": "application/pdf", "Darul-Irfan-Presentation-Package-v3.zip": "application/zip" };
  if (!allowed[name] || !env.MEDIA) return new Response("Not found", { status: 404 });
  const object = await env.MEDIA.get(`demo/${name}`, { range: request.headers });
  if (!object) return new Response("Not found", { status: 404 });
  const headers = new Headers({ "content-type": allowed[name], "cache-control": "public, max-age=86400", "accept-ranges": "bytes",
    "content-disposition": `${name.endsWith(".zip") ? "attachment" : "inline"}; filename="${name}"` });
  if (object.range) {
    const { offset = 0, length = object.size - offset } = object.range;
    headers.set("content-range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
    headers.set("content-length", String(length));
    return new Response(object.body, { status: 206, headers });
  }
  headers.set("content-length", String(object.size));
  return new Response(object.body, { headers });
}
