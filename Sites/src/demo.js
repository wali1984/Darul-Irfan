// app-demo.naqshbandiaowaisiah.us: the app's showcase for an audience. The
// interactive showcase, PowerPoint, PDF and package were made separately
// (outputs/darul-app-showcase/deliverables, v4); the PowerPoint and the admin
// screens are site files under /demo/, the three large ones come from R2
// (demo/...). "Administration and live Zikr" walks through how Hazrat ji's admins
// and each Halqah's leaders run things; member names are blurred in its screens.
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
.phones{display:flex;gap:16px;justify-content:center;align-items:flex-start}
.phones img{width:min(46%,250px);height:auto;border-radius:22px;border:1px solid rgba(243,220,157,.35);box-shadow:0 30px 70px -25px rgba(16,185,129,.55)}
.phones img:nth-child(2){margin-top:40px}
.roles{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:16px;margin-top:30px}
.role{padding:22px;border-radius:var(--radius);border:1px solid var(--line);background:rgba(10,40,30,.55)}
.role b{display:block;font:600 22px/1.2 var(--serif);color:var(--gold2);margin-bottom:8px}
.role span{color:var(--muted);font-size:14px}
.steps{counter-reset:step;display:grid;gap:14px;margin-top:30px}
.step{display:grid;grid-template-columns:56px 1fr;gap:18px;padding:20px 22px;border-radius:var(--radius);border:1px solid var(--line);background:rgba(10,40,30,.45)}
.step::before{counter-increment:step;content:counter(step);width:48px;height:48px;border-radius:50%;display:grid;place-items:center;background:linear-gradient(135deg,var(--gold2),var(--gold));color:#1d1406;font:700 20px var(--sans)}
.step h4{margin:0 0 6px;font-size:19px}.step p{margin:0;color:var(--muted);font-size:15px}
.step dl{display:grid;grid-template-columns:max-content 1fr;gap:4px 12px;margin:10px 0 0;font-size:14px}
.step dt{color:var(--gold2)}.step dd{margin:0;color:var(--ink)}
@media (max-width:600px){.step{grid-template-columns:1fr}.step dl{grid-template-columns:1fr}}
`;

const ROLES = [
  ["Super admin", "Every Halqah and every person. Makes, renames and retires Halqahs, places anyone in any Halqah, publishes Today's pictures."],
  ["Administrator", "Runs a Halqah: its people, its Admins and everything the Admins do. Appoints other Administrators."],
  ["Admin", "Posts, Zikr, meetings and people of the Halqah. Leads the live stage, removes anything from it, ends the session."],
  ["Member", "Reads and watches, joins the Zikr, sends dua requests and the ready-made chat messages."],
  ["Website visitor", "Gives a name, city and country, then follows the live Zikr with no controls. Counted in attendance."],
];

const GUIDE = [
  {
    tag: "Super admin", title: "Halqahs and people",
    text: "The Halqah page opens on a dashboard: Halqahs, people signed in, live Zikr and live meetings.",
    points: ["New Halqah: a name and a description; it starts empty and gets its first Administrator",
      "⋯ on a Halqah: rename, describe or retire it (people and history are kept)",
      "Everyone who has signed in: search, change a role in any Halqah, remove, or add to another Halqah",
      "Nobody can change their own place or another super admin's"],
    shots: ["admin-dashboard", "admin-role-menu"],
  },
  {
    tag: "Super admin", title: "Today's pictures",
    text: "The Ayah, Hadith, Aqwal-e-Sheikh, daily quote or announcement picture for a day, in every reader's own time.",
    points: ["Choose where it shows and on which day; announcements can run several days",
      "Also open it over the Today page, with an optional caption",
      "Forward a picture to the WhatsApp Business number with #ayah, #hadith, #aqwal, #quote or #announcement: it waits as a draft",
      "Publish, save as a draft, hide or delete"],
    shots: ["admin-pictures", "admin-picture-editor"],
  },
  {
    tag: "Halqah admin", title: "Running a Halqah",
    text: "Every Halqah's Administrators and Admins have a Halqah admin section: Go live and six tiles.",
    points: ["People: add by email, or make a single-use code sent from your own phone (lasts 1 to 90 days)",
      "Make someone an Administrator, an Admin or a member; withdraw an invitation not used yet",
      "New post: paste from WhatsApp, up to 10 photos or videos; publish (members are told) or keep as a draft",
      "Meetings and Zikr times in each member's own time; a Zikr time can play a recording by itself",
      "Dua requests and past sessions with attendance"],
    shots: ["admin-tiles", "admin-people"],
  },
  {
    tag: "Live Zikr", title: "Go live, or test first",
    text: "Choose Halqah Zikr or a meeting, then how the group joins.",
    points: ["Lead live: members join together and listen; optionally record it or add a live video link",
      "YouTube: a live link, or past Zikr from the channel played to everyone at the same moment",
      "Recording: the Halqah's own recordings",
      "Test only: nobody is notified and only the Halqah's admins see it, marked TEST"],
    shots: ["admin-golive", "admin-golive-test"],
  },
  {
    tag: "Leading", title: "How Hazrat ji's admins and each leader run the stage",
    text: "The stage opens full screen. Each stage tapped appears for everyone at once, with a soft chime for members.",
    points: ["Opening recitations: Tasbihat, Istighfar, Shahadah, Ta'awwudh, Bismillah, shown in Arabic",
      "Stages: the seven Lataif, Raabta, Muraqaba Ahadiyat, Ma'iyyat, Aqrabiyyat, Sair-e-Kaaba, Rauza-e-Athar, Masjid-e-Nabawi",
      "Go Live: the leading phone listens and the stage follows the voice, hands-free; Undo puts back a wrong stage",
      "Presentation hides the controls for the stream; double-tap to bring them back",
      "Add Muraqaba on the spot; remove any stage announcement or chat message"],
    shots: ["stage-listening", "stage-controls"],
  },
  {
    tag: "Members", title: "What everyone sees",
    text: "The emblem waits until the Zikr begins; then only the current stage fills the screen, in English with Urdu.",
    points: ["Recitations in Arabic; each Latifa with its numbered medallion; each Muraqaba by name",
      "On Our Sheikh, Hazrat ji's photograph; on other Halqahs, the Silsila emblem",
      "Ready-made messages: Assalamu alaikum, Request for prayers, Ameen, JazakAllahu khairan, SubhanAllah, MashaAllah"],
    shots: ["stage-tasbihat", "stage-latifa7"],
  },
  {
    tag: "Session", title: "Session controls, attendance and duas",
    text: "From the live card, admins guide the session and close it for everyone.",
    points: ["Add to the session, record it, message the group (optionally as a notification)",
      "Who is listening, right now",
      "End the session for everyone; it stays open until then",
      "Past sessions keep who joined and when, app members and website visitors alike"],
    shots: ["session-controls", "admin-attendance"],
  },
];

const STEPS = [
  ["Before", "Members see the next Zikr in their own time, a greyed Join, Remind me and Send a dua request.",
    { Websites: "Not live; Join Live Zikr is greyed out." }],
  ["Rehearse (optional)", "Go live › Test only › Start test without notifying anyone. End the session when done.",
    { Websites: "Shown as Test Zikr." }],
  ["Start", "Go live › Halqah Zikr › Lead live, YouTube or Recording › Start now and notify the group. For Our Sheikh, Hazrat ji starting on Paltalk starts it by itself.",
    { Members: "\"Halqah zikr has started\"; the card shows Zikr live and the stage opens once.", Websites: "Live now; Join Live Zikr lights up." }],
  ["Joining", "Members join the room with the microphone off, or listen and watch together at the same moment.",
    { Websites: "Name, city, country, then the full-screen stage. Our Sheikh with live sound.", "YouTube & Facebook": "The stage picture with the live sound." }],
  ["During", "The leader taps each stage or lets Go Live follow the voice. Chat, Add Muraqaba, Message the group, removals.",
    { Everywhere: "The emblem moves to the corner; only the current stage shows, with a burst of light at each change." }],
  ["Dua", "When the Dua begins the stage shows Dua. Members' dua requests have reached the admins.",
    { Paltalk: "Started from Paltalk, the session closes by itself five minutes later." }],
  ["End", "End session › End the session for everyone?",
    { Members: "The live card and stage clear.", Websites: "The Zikr has ended. JazakAllahu khairan.", Admins: "The session is in Past sessions, with attendance." }],
];

function adminGuide() {
  const shot = id => `<img src="/demo/admin/${esc(id)}.webp" alt="" loading="lazy" width="1080" height="2400">`;
  const roles = ROLES.map(([r, t]) => `<div class="role reveal"><b>${esc(r)}</b><span>${esc(t)}</span></div>`).join("");
  const items = GUIDE.map((g, i) => `
    <article class="item reveal" style="--d:${i * 40}ms">
      <div>
        <span class="chip">${esc(g.tag)}</span>
        <h3>${esc(g.title)}</h3>
        <p>${esc(g.text)}</p>
        <ul>${g.points.map(p => `<li>${esc(p)}</li>`).join("")}</ul>
      </div>
      <div class="phones">${g.shots.map(shot).join("")}</div>
    </article>`).join("");
  const steps = STEPS.map(([h, p, seen]) => `
    <div class="step reveal"><div><h4>${esc(h)}</h4><p>${esc(p)}</p>
      <dl>${Object.entries(seen).map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`).join("")}</dl></div></div>`).join("");
  return `
  <section id="admin"><div class="wrap">
    <div class="eyebrow reveal">For admins and live leaders</div>
    <h2 class="reveal">Administration and live Zikr</h2>
    <p class="lead reveal">Who looks after what, how Hazrat ji's admins and each Halqah's leaders run a live Zikr, and what members, website visitors and the live streams see at every stage. Screens are from the Android app; iOS matches except Apple sign-in. Member names, emails and places are blurred.</p>
    <div class="roles">${roles}</div>
    <div class="new">${items}</div>
    <h2 class="reveal" style="margin-top:70px">A live Zikr, step by step</h2>
    <div class="steps">${steps}</div>
  </div></section>`;
}

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
        <a class="btn btn-gold live" href="/demo/showcase">Start the interactive showcase</a>
        <a class="btn btn-ghost" href="#admin">Administration</a>
        <a class="btn btn-ghost" href="#new">What's new</a>
      </div>
      <div class="stats reveal" style="--d:300ms">
        <div><b>51</b><span>bilingual slides</span></div><div><b>263</b><span>features</span></div><div><b>103</b><span>app screens</span></div>
      </div>
    </div>
    <div class="reveal" style="--d:200ms">${animatedLogo()}</div>
  </div>

  <section id="downloads"><div class="wrap">
    <div class="eyebrow reveal">For presenting</div>
    <h2 class="reveal">The showcase</h2>
    <p class="lead reveal">Open the interactive showcase full screen to present; arrow keys move through it. The PowerPoint and PDF carry the same 51 slides, including the Administration and Live Zikr chapter.</p>
    <div class="downloads">
      <a class="dl reveal" href="/demo/showcase"><span class="ic">▶</span><span><b>Interactive showcase</b><span>App tour, administration, 103 screens, feature tree · 34 MB</span></span></a>
      <a class="dl reveal" href="/demo/Darul-Irfan-Product-Showcase-v4.pptx" download><span class="ic">PPT</span><span><b>PowerPoint</b><span>51 slides · 19.8 MB</span></span></a>
      <a class="dl reveal" href="/demo/files/Darul-Irfan-Product-Showcase-v4.pdf"><span class="ic">PDF</span><span><b>PDF</b><span>For reading and printing · 42 MB</span></span></a>
      <a class="dl reveal" href="/demo/files/Darul-Irfan-Presentation-Package-v4.zip" download><span class="ic">ZIP</span><span><b>Complete package</b><span>Everything together · 85 MB</span></span></a>
    </div>
  </div></section>
${adminGuide()}

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

/** The large files, from R2 (demo/...): over the 25 MB site-file limit. */
export const SHOWCASE = "Darul-Irfan-Interactive-Showcase-v4.html";
export async function demoFile(env, name, request) {
  const allowed = { "Darul-Irfan-Product-Showcase-v4.pdf": "application/pdf", "Darul-Irfan-Presentation-Package-v4.zip": "application/zip",
    [SHOWCASE]: "text/html; charset=utf-8" };
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
