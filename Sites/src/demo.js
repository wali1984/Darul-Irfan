// app-demo.: the app's showcase for an audience. The interactive showcase was
// made separately (outputs/darul-app-showcase/deliverables, v5) and comes from
// R2 (demo/...); the page no longer lists the slides or downloads (owner
// 2026-11-06). The admin screens are site files under /demo/. "Administration
// and live Zikr" walks through how Hazrat ji's admins and each Halqah's leaders
// run things; member names are blurred in its screens.
import { animatedLogo, esc, shell } from "./layout.js";

const STYLE = `
.hero{display:grid;grid-template-columns:1.1fr .9fr;gap:clamp(24px,5vw,64px);align-items:center;min-height:min(calc(100svh - 74px),820px);padding-top:30px}
.hero>*{min-width:0}
@media (max-width:900px){.hero{grid-template-columns:1fr;text-align:center}.hero .lead{margin-inline:auto}.cta{justify-content:center}}
.hero h1{font-size:clamp(44px,6.4vw,86px);line-height:1.02;margin:18px 0 18px}
.cta{display:flex;gap:14px;flex-wrap:wrap;margin-top:28px}
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

const VISION = [
  ["Every teaching, one living app", "The Qur'an with the Silsila's own translation and tafsir, hadith, the library, Al-Murshid, bayans and Zikr, joined up: from an ayah to its tafsir to the Sheikh's bayan in two taps."],
  ["A better experience for everyone", "Calm, clear and bilingual, with Urdu in Nastaliq, large text and offline reading: easy for those with the Silsila for decades and for someone opening it today."],
  ["Reaching a new generation", "Young people live on their phones, YouTube and social media. The Silsila now meets them there: a daily ayah, hadith and saying to share, gentle reminders, and a live stage that looks beautiful on any screen."],
  ["Across phones and the web", "Native iPhone and Android apps and regional websites share one visual identity. Paltalk relay and social streaming are being validated as part of the live-service preview."],
];

const REACH = [
  "Open doors: anyone can follow a live Zikr from a website link with just a name and a city, no account or download needed.",
  "A planned route to YouTube and Facebook with the live stage; availability depends on broadcast verification.",
  "Daily cards (ayah, hadith, Aqwal-e-Sheikh) made to forward on WhatsApp and social media, each one an invitation.",
  "Invitations in seconds: a WhatsApp link or a code from any Ijtema or gathering.",
  "English and Urdu throughout, so second-generation members abroad feel at home.",
  "The Markaz's reports show new members, website visitors and countries each month, so outreach can be measured and improved.",
];

const AUTOMATION = [
  {
    tag: "Automation preview", title: "Connecting Paltalk with the app and websites",
    text: "The relay is being tested with an admin supervising the source, stage and session state.",
    points: ["Automatic start and member notifications require a confirmed session", "The websites open Join when the platform reports a live Zikr",
      "Voice cues can assist stage changes; admins confirm and correct them during testing",
      "YouTube and Facebook broadcasts require a separate availability check", "Admins verify the end of each session; unattended start, recovery and closure remain under validation"],
    shots: ["live-card", "stage-tasbihat"],
  },
  {
    tag: "Voice assistance preview", title: "Voice cues with an admin in control",
    text: "Go Live can listen on the leading phone to assist stage selection. Recognition and recovery are being tested across devices.",
    points: ["An admin supervises the stage while voice assistance is enabled", "If the sound is unclear, the admin can select a stage", "Undo lets an admin correct a stage"],
    shots: ["stage-listening", "stage-controls"],
  },
  {
    tag: "Streaming", title: "Better than a chat-window stream",
    text: "Viewers no longer watch a Paltalk chat window. They see the stage: the emblem or Hazrat ji's photograph, the current Latifa in light, the Arabic recitations.",
    points: ["One full-screen picture made for YouTube and Facebook", "Each Latifa numbered, each Muraqaba named, English with Urdu", "The same stage in the app and on the websites"],
    shots: ["stage-latifa7", "stage-tasbihat"],
  },
  {
    tag: "Monitoring", title: "Admins supervise the live service",
    text: "Admins check the source and audience experience, follow attendance and use the session controls when attention is needed.",
    points: ["Who is listening, live, in every session", "Every Halqah on air at a glance in the Silsila Markaz", "A morning summary of yesterday's Zikr on officers' phones"],
    shots: ["session-controls", "admin-attendance"],
  },
];

const MARKAZ = [
  {
    tag: "Silsila Markaz", title: "One organisation, run centrally",
    text: "A new group, the Silsila Markaz, sees every region and Halqah: its people, its admins, its Zikr times, and whether it is live now.",
    points: ["Regions, countries and cities for every Halqah", "Notices to every Halqah, a region, or chosen Halqahs, with a notification",
      "Every Halqah's admins brought into the Markaz for global notices and meetings", "Only super admins and the Markaz's officers see the reports"],
    shots: ["markaz-org", "markaz-announce"],
  },
  {
    tag: "Analytics", title: "Analytics for every Halqah",
    text: "Attendance, different people, app and website visitors, against the period before, for any Halqah, region or time.",
    points: ["Trends day by day, and the busiest weekdays and hours", "Regulars, and those not seen for three weeks so their Halqah can call",
      "Insights worked out from the figures: growth, quiet Halqahs, sessions that ran by themselves", "Test sessions are never counted"],
    shots: ["markaz-analytics", "markaz-analytics-2"],
  },
  {
    tag: "Reports", title: "Daily and monthly reports",
    text: "Every Zikr, who attended and for how long, the Halqahs that held none, and the month's growth with new members.",
    points: ["Daily Zikr report, with a morning summary on officers' phones", "Monthly report on the 1st", "Spreadsheets of sessions, attendance, Halqahs and people; any report printed or saved as a PDF"],
    shots: ["markaz-daily", "markaz-monthly"],
  },
  {
    tag: "On the computer", title: "reporting.%DOMAIN%%NOTE%",
    text: "The full dashboard for a computer: overview, daily and monthly reports, Halqahs, people, sessions, the organisation, notices and signed-in computers.",
    points: ["The website shows a code; an officer approves it in the app. No passwords to share or lose",
      "Each sign-in lasts 12 hours; every computer is listed and can be signed out", "Private, never indexed, with strict security headers"],
    shots: ["markaz-signin", "markaz-daily"],
  },
];

function guideItems(list, base) {
  return list.map((g, i) => `
    <article class="item reveal" style="--d:${i * 40}ms">
      <div>
        <span class="chip">${esc(g.tag)}</span>
        <h3>${esc(g.title)}</h3>
        <p>${esc(g.text)}</p>
        <ul>${g.points.map(p => `<li>${esc(p)}</li>`).join("")}</ul>
      </div>
      <div class="phones">${g.shots.map(id => `<img src="/demo/${base(id)}/${esc(id)}.webp" alt="" loading="lazy" width="1080" height="2400">`).join("")}</div>
    </article>`).join("");
}
const shotFolder = id => id.startsWith("markaz-") ? "markaz" : "admin";

function visionSection() {
  return `
  <section id="vision"><div class="wrap">
    <div class="eyebrow reveal">Why this matters</div>
    <h2 class="reveal">One Silsila, made for today</h2>
    <p class="lead reveal">How the app brings all the teachings together, gives existing and new members a better experience, reaches a new generation, and puts the Silsila on every major platform.</p>
    <div class="roles">${VISION.map(([t, d]) => `<div class="role reveal"><b>${esc(t)}</b><span>${esc(d)}</span></div>`).join("")}</div>
    <h2 class="reveal" style="margin-top:56px">Bringing in younger people and new audiences</h2>
    <div class="steps">${REACH.map(r => `<div class="step reveal"><div><p style="color:var(--ink)">${esc(r)}</p></div></div>`).join("")}</div>
  </div></section>`;
}

function automationSection() {
  return `
  <section id="automation"><div class="wrap">
    <div class="eyebrow reveal">For Hazrat ji and the admins</div>
    <h2 class="reveal">Live-service automation preview</h2>
    <p class="lead reveal">The app, websites and broadcast stage are designed to follow one session. Automatic start, voice cues, recovery and social streaming still require end-to-end validation. An admin supervises live trials; response time and audience capacity have not yet been certified.</p>
    <div class="new">${guideItems(AUTOMATION, shotFolder)}</div>
  </div></section>`;
}

function markazSection() {
  return `
  <section id="markaz"><div class="wrap">
    <div class="eyebrow reveal">For super admins and the Silsila Markaz</div>
    <h2 class="reveal">The Silsila Markaz: organisation, analytics and reports</h2>
    <p class="lead reveal">The whole organisation managed centrally, with full analytics and reporting for every Halqah, in the app and on reporting.%DOMAIN%%NOTE%. Member names are blurred in these screens.</p>
    <div class="new">${guideItems(MARKAZ, shotFolder)}</div>
  </div></section>`;
}

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
      "Test only: no member notification; the websites also show it, clearly marked Test Zikr"],
    shots: ["admin-golive", "admin-golive-test"],
  },
  {
    tag: "Leading", title: "How Hazrat ji's admins and each leader run the stage",
    text: "The stage opens full screen. Each stage tapped appears for everyone at once, with a soft chime for members.",
    points: ["Opening recitations: Tasbihat, Istighfar, Shahadah, Ta'awwudh, Bismillah, shown in Arabic",
      "Stages: the seven Lataif, Raabta, Muraqaba Ahadiyat, Ma'iyyat, Aqrabiyyat, Sair-e-Kaaba, Rauza-e-Athar, Masjid-e-Nabawi, then the Shajra Sharif and the Dua",
      "Go Live: the leading phone listens and the stage follows the voice, hands-free; Undo puts back a wrong stage",
      "Presentation hides the controls for the stream; double-tap to bring them back",
      "Add Muraqaba on the spot; remove any stage announcement or chat message"],
    shots: ["stage-listening", "stage-controls"],
  },
  {
    tag: "Members", title: "What everyone sees",
    text: "The emblem waits until the Zikr begins; then only the current stage fills the screen, in English with Urdu.",
    points: ["Recitations in Arabic; each Latifa with its numbered medallion; each Muraqaba by name",
      "On Our Sheikh, Hazrat ji's photograph and the live sound; on other Halqahs, the Silsila emblem",
      "The Shajra Sharif rolls in line by line in under a minute, then the Dua",
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
  ["Start", "Go live › Halqah Zikr › Lead live, YouTube or Recording › Start now and notify the group. Automatic Paltalk start is under validation and must be supervised.",
    { Members: "\"Halqah zikr has started\"; the card shows Zikr live and the stage opens once.", Websites: "Live now; Join Live Zikr lights up." }],
  ["Joining", "Members tap Join: for Our Sheikh, Daily or Tahajjud, the stage opens in the app with the live sound. Other Halqahs join the room with the microphone off, or listen and watch together at the same moment.",
    { Websites: "Name, city, country, then the full-screen stage. Our Sheikh has live sound when the source is connected.", "YouTube & Facebook": "Available only after that broadcast is verified live." }],
  ["During", "The leader selects each stage or supervises voice assistance. Paltalk recognition and stage timing are under validation. Chat, Add Muraqaba, Message the group, removals.",
    { Everywhere: "The emblem moves to the corner; only the current stage shows, with a burst of light at each change." }],
  ["Shajra and Dua", "After Masjid-e-Nabawi the Shajra Sharif rolls in line by line, then the stage shows Dua. Members' dua requests have reached the admins.",
    { Paltalk: "Automatic closure is under validation; the admin checks when the session ends." }],
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
    tag: "New · Live sound", title: "Join opens Hazrat ji's live Zikr in the app",
    text: "Daily Zikr and Tahajjud alike: every Join, notice and notification now opens Our Sheikh's live stage inside the app, with the live sound. No YouTube or Paltalk needed to take part.",
    points: [
      "Listen live: the Silsila's own live feed, straight from the Zikr as it happens",
      "The Tahajjud notification says \"Join it live in Darul Irfan\"",
      "Hazrat ji's admins can broadcast the sound from the stage themselves",
      "On iPhone and Android together",
    ],
    shot: null,
  },
  {
    tag: "New · Websites", title: "Live Zikr on the web, for every region",
    text: "Three public websites, open to everyone, in the app's emerald and gold with the living emblem.",
    points: [
      "oursheikh., namerica. (USA and Canada) and uk.%DOMAIN%%NOTE%",
      "Each Halqah's Zikr appears the moment it is live; anyone joins with a name and a place",
      "Our Sheikh's live sound is available when the source is connected; other Halqahs show their stage and use the app for sound",
      "Hazrat ji's admins see every web visitor in the session's attendance",
    ],
    shot: "/demo/new/home.webp", alt: "North America website",
    links: [["https://oursheikh.%DOMAIN%", "Our Sheikh"], ["https://namerica.%DOMAIN%", "North America"], ["https://uk.%DOMAIN%", "United Kingdom"]],
  },
  {
    tag: "New · Live stage", title: "The stage, on every screen",
    text: "Once a Zikr starts, the emblem steps aside and only the stage being done fills the screen: the opening Tasbihat in Arabic, each Latifa, Raabta and every Muraqaba up to Masjid-e-Nabawi, then the Shajra Sharif and the Dua. On Our Sheikh's stage, Hazrat ji's picture stands beside each stage announcement.",
    points: [
      "The same stage in the app, on the websites and in the YouTube and Facebook picture",
      "The Shajra Sharif rolls in line by line in under a minute; each Latifa carries its star medal",
      "A 1920×1080 broadcast stage for the live streams, with Hazrat ji's picture",
      "Every stage announced is listed with its time for the Halqah's admins",
      "Every Halqah now has its stage, led by its own Ameer or admins",
    ],
    shot: "/demo/new/broadcast.webp", alt: "Broadcast stage: Hazrat ji's picture beside Muraqaba Ma'iyyat",
  },
  {
    tag: "Preview · Voice assistance", title: "Go Live: assisted stage selection",
    text: "The leading phone can listen for stage cues. Recognition has been developed with session material and still needs supervised validation on the devices and networks people use.",
    points: [
      "The screen stays awake while listening; interruption and recovery behavior require device testing",
      "Undo puts back a wrong stage; admins can add a Muraqaba from the stage",
      "The Paltalk relay's voice-assisted stage changes remain under validation",
    ],
    shot: null,
  },
  {
    tag: "Preview · Automation", title: "Automatic session handling is being tested",
    text: "The intended flow connects Paltalk audio, the app session and the websites, with assisted stage changes and a confirmed end. Unattended operation and stage-response time are not yet verified.",
    points: ["Voice and typed host cues are checked against the active session",
      "Opening recitations followed in order: Tasbih, Istighfar, Shahadah, Ta'awwudh, Bismillah",
      "Test Zikr: admins try everything without notifying anyone", "Admins remove any stage announcement, message or dua request"],
    shot: null,
  },
  {
    tag: "New · Teaching", title: "Method of Zikr and the Shajra, online",
    text: "Word for word from the app, in Urdu and English. The Lataif picture now shows the seventh as a circle around the whole body, in the app and on the web.",
    points: ["Opening recitations in Arabic, each Latifa's instruction, Raabta", "The full chain of transmission, from the Holy Prophet ﷺ to the present Sheikh"],
    shot: "/demo/new/method.webp", alt: "Method of Zikr page",
    links: [["https://oursheikh.%DOMAIN%/method-of-zikr", "Method of Zikr"], ["https://oursheikh.%DOMAIN%/shajra", "Shajra"]],
  },
];

// The site names above say %DOMAIN%: the domain the visitor came in on. Where they are shown on
// wajidali.us, %NOTE% says they will be transferred to the Silsila's official domain
// (owner 2026-11-06: never name that domain).
const MOVING = " (this will be transferred to the Silsila's official domain)";
export function demoPage(site, others, domain) {
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
      <p class="quiet reveal">Product preview. Screens may show features awaiting tester release. Live relay automation and social broadcasts are under validation.</p>
      <div class="cta reveal" style="--d:240ms">
        <a class="btn btn-gold live" href="/demo/showcase">Start the interactive showcase</a>
        <a class="btn btn-ghost" href="#get-started">Get started</a>
        <a class="btn btn-ghost" href="#vision">The vision</a>
        <a class="btn btn-ghost" href="#automation">Automation</a>
        <a class="btn btn-ghost" href="#admin">Administration</a>
        <a class="btn btn-ghost" href="#markaz">Silsila Markaz</a>
        <a class="btn btn-ghost" href="#new">What's new</a>
      </div>
    </div>
    <div class="reveal" style="--d:200ms">${animatedLogo()}</div>
  </div>
  <section id="get-started"><div class="wrap">
    <div class="eyebrow">Start here</div><h2>Choose how to take part</h2>
    <div class="roles">
      <article class="role"><b>Listen on the web</b><p>Open Our Sheikh's page. When the Zikr is live, join with your name, city and country.</p><a class="btn btn-gold" href="https://oursheikh.%DOMAIN%">Open live Zikr</a></article>
      <article class="role"><b>Explore before joining</b><p>Read the Method of Zikr or the Shajra in the website's original source text.</p><a class="btn btn-ghost" href="https://oursheikh.%DOMAIN%/method-of-zikr">Method of Zikr</a></article>
      <article class="role"><b>iPhone and iPad testers</b><p>Join the available iOS beta through TestFlight. This is a testing version, and features may change.</p><a class="btn btn-gold" href="https://testflight.apple.com/join/keXtV7jF" target="_blank" rel="noopener">Join TestFlight</a></article>
      <article class="role"><b>Android testers</b><p>Use your existing Google Play internal testing invitation. If you need access, contact your Halqah's admin.</p><a class="btn btn-ghost" href="/demo/showcase">Explore the app preview</a></article>
      <article class="role"><b>Markaz officers</b><p>Open the private reports website and approve its sign-in code from the app.</p><a class="btn btn-ghost" href="https://reporting.%DOMAIN%">Open admin reports</a></article>
    </div>
  </div></section>
${visionSection()}
${automationSection()}
${adminGuide()}
${markazSection()}

  <section id="new"><div class="wrap">
    <div class="eyebrow reveal">Since the showcase</div>
    <h2 class="reveal">What's new</h2>
    <p class="lead reveal">Recent work includes live sound, public Zikr pages and a shared stage. Automated relay behavior remains a supervised preview until its end-to-end checks pass.</p>
    <div class="new">${items}</div>
  </div></section>`;
  // The shared navigation points into the Our Sheikh site; this host only has the showcase.
  const home = "https://oursheikh.%DOMAIN%";
  return shell({ site, others, title: "Darul Irfan · App showcase", description: "The Darul Irfan app: the vision, automation, administration, the Silsila Markaz and what's new.",
    active: "", extraStyle: STYLE, body })
    .replace(/href="\/(#live|#halqahs|method-of-zikr|shajra)"/g, (_, path) => `href="${home}/${path}"`)
    .replace('<a class="brand" href="/">', '<a class="brand" href="/">')
    .replaceAll("%NOTE%", domain === "wajidali.us" ? MOVING : "").replaceAll("%DOMAIN%", domain);
}

/** The large files, from R2 (demo/...): over the 25 MB site-file limit. */
export const SHOWCASE = "Darul-Irfan-Interactive-Showcase-v5.html";
export async function demoFile(env, name, request) {
  const allowed = { "Darul-Irfan-Product-Showcase-v5.pdf": "application/pdf", "Darul-Irfan-Presentation-Package-v5.zip": "application/zip",
    "Darul-Irfan-Product-Showcase-v5.pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    [SHOWCASE]: "text/html; charset=utf-8" };
  if (!allowed[name] || !env.MEDIA) return new Response("Not found", { status: 404 });
  const hasRange = request.headers.has("range");
  const object = request.method === "HEAD" && !hasRange
    ? await env.MEDIA.head(`demo/${name}`)
    : await env.MEDIA.get(`demo/${name}`, hasRange ? { range: request.headers } : undefined);
  if (!object) return new Response("Not found", { status: 404 });
  const headers = new Headers({ "content-type": allowed[name], "cache-control": "public, max-age=86400", "accept-ranges": "bytes",
    "x-content-type-options": "nosniff", "referrer-policy": "strict-origin-when-cross-origin",
    "content-disposition": `${name.endsWith(".zip") || name.endsWith(".pptx") ? "attachment" : "inline"}; filename="${name}"` });
  if (hasRange && object.range) {
    const { offset = 0, length = object.size - offset } = object.range;
    headers.set("content-range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
    headers.set("content-length", String(length));
    return new Response(request.method === "HEAD" ? null : object.body, { status: 206, headers });
  }
  headers.set("content-length", String(object.size));
  return new Response(request.method === "HEAD" ? null : object.body, { headers });
}
