// The public websites. Each subdomain is a site: Our Sheikh, North America, the
// United Kingdom. Each shows the live Zikr of its Halqahs (Our Sheikh on every
// site) with the stage being followed, and lets anyone join a live Zikr with a
// name and a place, to listen with no controls (owner 2026-11-04). It also
// carries the Method of Zikr and the Shajra, word for word from the app's data.
import { broadcastPage, homePage } from "./home.js";
import { previewStage } from "./stage.js";
import { methodPage, shajraPage } from "./content.js";
import { demoFile, demoPage, SHOWCASE } from "./demo.js";
import { reportingRequest } from "./reporting/server.js";
import LOGO from "../assets/logo.webp";
// The seal uncut, as the main website serves it: the pages draw the logo's badge around it.
import SEAL from "../assets/seal.webp";

// Every site answers on both domains under the same name (oursheikh., namerica.,
// uk., app-demo., reporting.). wajidali.us is the one shared for now; the
// naqshbandiaowaisiah.us names stay unannounced until production (owner
// 2026-11-05). Links between the sites stay on the domain the visitor came in on.
export const DOMAINS = ["wajidali.us", "naqshbandiaowaisiah.us"];
export const SHARED_DOMAIN = DOMAINS[0];

/** The subdomain name and the domain a request came in on (workers.dev: no name, the shared domain). */
function place(url) {
  const [name, ...rest] = url.hostname.split(".");
  const domain = rest.join(".");
  return DOMAINS.includes(domain) ? { name, domain } : { name: null, domain: SHARED_DOMAIN };
}

export const SITES = {
  oursheikh: {
    region: "Our Sheikh",
    title: "Our Sheikh · Naqshbandia Owaisiah",
    tagline: "Live Zikr with Hazrat Ameer Abdul Qadeer Awan (MZA)",
    intro: "Sit in Zikr with Our Sheikh live from anywhere: follow each Latifa and Muraqaba as it is called.",
    halqahs: [{ id: "our-sheikh", name: "Our Sheikh", description: "Hazrat Ameer Abdul Qadeer Awan (MZA)" }],
  },
  namerica: {
    region: "North America",
    title: "North America · Naqshbandia Owaisiah",
    tagline: "The Halqahs of the United States and Canada",
    intro: "Sit in Zikr with Our Sheikh live, and join the Zikr of the Halqahs across the United States and Canada.",
    halqahs: [
      { id: "our-sheikh", name: "Our Sheikh", description: "Hazrat Ameer Abdul Qadeer Awan (MZA)" },
      { id: "north-america", name: "North America", description: "Naqshbandia Owaisiah | North America" },
      { id: "usa", name: "United States of America", description: "Naqshbandia Owaisiah | United States" },
      { id: "canada", name: "Canada", description: "Naqshbandia Owaisiah | Canada" },
      { id: "new-york-ny", name: "New York, NY", description: "Naqshbandia Owaisiah | New York" },
      { id: "worcester-ma", name: "Worcester, MA", description: "Naqshbandia Owaisiah | Worcester" },
    ],
  },
  uk: {
    region: "United Kingdom",
    title: "United Kingdom · Naqshbandia Owaisiah",
    tagline: "The Halqahs of the United Kingdom",
    intro: "Sit in Zikr with Our Sheikh live, and join the Zikr of the Halqahs in the United Kingdom.",
    halqahs: [
      { id: "our-sheikh", name: "Our Sheikh", description: "Hazrat Ameer Abdul Qadeer Awan (MZA)" },
      { id: "united-kingdom", name: "United Kingdom", description: "Naqshbandia Owaisiah | United Kingdom" },
    ],
  },
};

function siteFor(url) {
  const { name } = place(url);
  if (name && SITES[name]) return name;
  // The workers.dev address previews any site with ?site=.
  const asked = url.searchParams.get("site");
  return asked && SITES[asked] ? asked : "oursheikh";
}

async function api(env, path, init) {
  try {
    const response = await env.API.fetch(new Request(`https://platform${path}`,
      { ...init, headers: { accept: "application/json", "content-type": "application/json", ...(init?.headers ?? {}) } }));
    return { status: response.status, body: await response.json().catch(() => null) };
  } catch {
    return { status: 502, body: null };
  }
}

/** What the page refreshes every 15 seconds: each Halqah, what is live in it and its stage. */
async function data(env, key) {
  const site = SITES[key];
  const [halqahs, room, sheikh] = await Promise.all([
    api(env, `/v1/public/live?ids=${site.halqahs.map(h => h.id).join(",")}`),
    api(env, "/v1/live"),
    api(env, "/v1/public/sheikh-stage"),
  ]);
  const found = new Map((halqahs.body?.halqahs ?? []).map(h => [h.id, h]));
  return {
    halqahs: site.halqahs.map(h => {
      const live = found.get(h.id);
      return { id: h.id, name: live?.name ?? h.name, description: h.description, live: live?.live ?? null, stage: live?.stage ?? null };
    }),
    // Hazrat ji's picture, as the app shows it on Our Sheikh's stage.
    picture: sheikh.body?.pictureHDURL ?? sheikh.body?.pictureURL ?? null,
    pictureFallback: sheikh.body?.pictureURL ?? null,
    // The Tahajjud Zikr is joined in the Silsila's Paltalk room while it is open.
    tahajjud: room.body?.room ? { listeners: room.body.room.listeners ?? 0, url: room.body.room.url ?? null } : null,
  };
}

/** The keeper of the firewall's home_vpn list (see followHomeVPN). */
async function followHomeVPN(env) {
  if (!env.HOME_VPN_LIST_TOKEN) return;
  const dns = await fetch(`https://cloudflare-dns.com/dns-query?name=${env.HOME_VPN_HOST}&type=A`,
    { headers: { accept: "application/dns-json" } }).then(r => r.json());
  const ips = (dns.Answer ?? []).filter(a => a.type === 1).map(a => a.data);
  // One ordinary public IPv4 address, or nothing changes.
  const ip = ips.length === 1 && /^\d{1,3}(\.\d{1,3}){3}$/.test(ips[0]) &&
    !/^(10|127|0)\.|^192\.168\.|^172\.(1[6-9]|2\d|3[01])\.|^169\.254\./.test(ips[0]) ? ips[0] : null;
  if (!ip) return console.log("home VPN: unexpected DNS answer", JSON.stringify(ips));
  const call = (path, init = {}) => fetch(`https://api.cloudflare.com/client/v4/accounts/${env.ACCOUNT_ID}/rules/lists/${env.HOME_VPN_LIST_ID}${path}`,
    { ...init, headers: { authorization: `Bearer ${env.HOME_VPN_LIST_TOKEN}`, "content-type": "application/json" } }).then(r => r.json());
  const current = (await call("/items")).result?.map(item => item.ip) ?? [];
  if (current.length === 1 && current[0] === ip) return;
  const done = await call("/items", { method: "PUT", body: JSON.stringify([{ ip, comment: env.HOME_VPN_HOST }]) });
  console.log("home VPN list", JSON.stringify(current), "->", ip, done.success ? "ok" : JSON.stringify(done.errors));
}

// The eight-pointed star of the brand mark, gold on deep green.
const FAVICON = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40"><rect width="40" height="40" rx="9" fill="#04150f"/>
<path d="M20 4 25 15 36 20 25 25 20 36 15 25 4 20 15 15Z" fill="none" stroke="#d9b56a" stroke-width="2.2"/><circle cx="20" cy="20" r="5" fill="#d9b56a"/></svg>`;

const SECURITY = {
  "x-content-type-options": "nosniff",
  "referrer-policy": "strict-origin-when-cross-origin",
  "permissions-policy": "camera=(), microphone=(), geolocation=(), autoplay=(self)",
  "content-security-policy": [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline'",
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    "font-src https://fonts.gstatic.com data:",
    "img-src 'self' data: blob: https:",
    "media-src 'self' blob: https:",
    "frame-src https://www.youtube-nocookie.com https://www.youtube.com",
    "connect-src 'self' https://darul-irfan-live-staging.wajidmahmoodali1984-e23.workers.dev wss://darul-irfan-live-staging.wajidmahmoodali1984-e23.workers.dev https://*.cloudflare.com",
  ].join("; "),
};

const html = (body, maxAge = 60) => new Response(body, {
  headers: { "content-type": "text/html; charset=utf-8", "cache-control": `public, max-age=${maxAge}`, ...SECURITY },
});
const jsonResponse = (status, body) => new Response(JSON.stringify(body), {
  status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...SECURITY },
});

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(followHomeVPN(env));
  },

  async fetch(request, env) {
    const url = new URL(request.url);
    const { name, domain } = place(url);
    // A closed domain (CLOSED_DOMAINS) keeps its routes and data but opens nothing
    // (owner 2026-11-05: naqshbandiaowaisiah.us until production; the live relay
    // captures oursheikh.wajidali.us/broadcast).
    if (name !== null && (env.CLOSED_DOMAINS ?? "").split(",").map(d => d.trim()).includes(domain)) {
      return new Response("Not found", { status: 404, headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store", "x-robots-tag": "noindex" } });
    }
    const hostOf = key => `${key}.${domain}`;
    // reporting.: the Silsila Markaz's reports, signed in from the app (and ?site=reporting on workers.dev).
    if (name === "reporting" || url.searchParams.get("site") === "reporting") return reportingRequest(request, env, LOGO);
    // app-demo.: the app's showcase for an audience (and ?site=demo on workers.dev).
    if (name === "app-demo" || url.searchParams.get("site") === "demo") {
      const all = Object.entries(SITES).map(([k, s]) => ({ host: hostOf(k), region: s.region }));
      const file = /^\/demo\/files\/([A-Za-z0-9.-]+)$/.exec(url.pathname);
      if (file) return demoFile(env, file[1], request);
      if (url.pathname === "/demo/showcase") return demoFile(env, SHOWCASE, request);
      if (url.pathname === "/seal.webp") {
        return new Response(SEAL, { headers: { "content-type": "image/webp", "cache-control": "public, max-age=604800" } });
      }
      if (url.pathname === "/logo.webp") {
        return new Response(LOGO, { headers: { "content-type": "image/webp", "cache-control": "public, max-age=604800" } });
      }
      if (url.pathname === "/favicon.ico" || url.pathname === "/favicon.svg") {
        return new Response(FAVICON, { headers: { "content-type": "image/svg+xml", "cache-control": "public, max-age=86400" } });
      }
      if (url.pathname !== "/" && url.pathname !== "/index.html") return new Response("Not found", { status: 404 });
      return html(demoPage({ region: "App showcase" }, all, domain), 300);
    }
    const key = siteFor(url);
    const site = SITES[key];
    const others = Object.entries(SITES).filter(([k]) => k !== key).map(([k, s]) => ({ host: hostOf(k), region: s.region }));
    // Joining and staying counted: passed to the platform as they are; the visitor's
    // own IP travels with it for the platform's rate limit.
    const visit = /^\/(join|presence)\/([a-z0-9-]{1,40})$/.exec(url.pathname);
    if (visit && request.method === "POST") {
      if (!site.halqahs.some(h => h.id === visit[2])) return jsonResponse(404, { error: "Not found" });
      const body = await request.text();
      if (body.length > 4096) return jsonResponse(413, { error: "Too large" });
      const result = await api(env, `/v1/public/halqahs/${visit[2]}/${visit[1]}`, {
        method: "POST", body, headers: { "cf-connecting-ip": request.headers.get("cf-connecting-ip") ?? "" } });
      return jsonResponse(result.status, result.body ?? { error: "Please try again." });
    }
    if (request.method !== "GET" && request.method !== "HEAD") return new Response("Method not allowed", { status: 405 });
    if (url.pathname === "/data.json") return jsonResponse(200, await data(env, key));
    if (url.pathname === "/seal.webp") {
      return new Response(SEAL, { headers: { "content-type": "image/webp", "cache-control": "public, max-age=604800" } });
    }
    if (url.pathname === "/logo.webp") {
      return new Response(LOGO, { headers: { "content-type": "image/webp", "cache-control": "public, max-age=604800" } });
    }
    if (url.pathname === "/favicon.ico" || url.pathname === "/favicon.svg") {
      return new Response(FAVICON, { headers: { "content-type": "image/svg+xml", "cache-control": "public, max-age=86400" } });
    }
    if (url.pathname === "/robots.txt") return new Response("User-agent: *\nAllow: /\n", { headers: { "content-type": "text/plain" } });
    // The stage alone for the YouTube/Facebook stream's picture (?halqah=, default Our Sheikh).
    if (url.pathname === "/broadcast") {
      const halqah = url.searchParams.get("halqah") ?? "our-sheikh";
      if (!site.halqahs.some(h => h.id === halqah)) return Response.redirect(new URL("/broadcast", url).toString(), 302);
      // ?stage=<id> (&roll=0..1 for the Shajra): that stage drawn ahead of
      // time, so the relay has every picture ready and swaps it the moment
      // the stage changes (owner 2026-11-11: the stream's picture lagged).
      const want = url.searchParams.get("stage");
      if (want !== null) {
        const stage = previewStage(want);
        if (stage === undefined) return new Response("Unknown stage", { status: 404, headers: { "cache-control": "no-store" } });
        const now = await data(env, key);
        now.halqahs = now.halqahs.map(h => h.id === halqah ? { ...h, live: { kind: "zikr", title: "Preview", startedAt: "preview" }, stage } : h);
        const roll = Math.min(1, Math.max(0, Number(url.searchParams.get("roll")) || 0));
        return html(broadcastPage(site, now, halqah, { roll }), 0);
      }
      return html(broadcastPage(site, await data(env, key), halqah), 0);
    }
    if (url.pathname === "/method-of-zikr") return html(methodPage(site, others), 3600);
    if (url.pathname === "/shajra") return html(shajraPage(site, others), 3600);
    if (url.pathname !== "/" && url.pathname !== "/index.html") return Response.redirect(new URL("/", url).toString(), 302);
    const feed = env.LIVE_FEED_BASE ? { base: env.LIVE_FEED_BASE, key: env.LIVE_FEED_KEY ?? "" } : null;
    return html(homePage(site, others, await data(env, key), feed), 30);
  },
};
