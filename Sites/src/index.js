// The public websites. Each hostname is a site: Our Sheikh, North America, the
// United Kingdom. All three carry Our Sheikh's live Zikr (the Daily Zikr on
// YouTube, the stage being followed, the Tahajjud room on Paltalk) and the
// region's Halqahs. Halqahs are invitation only: the page names them and
// sends people to the app; it never shows who is in them.
import { page } from "./page.js";

export const SITES = {
  oursheikh: {
    host: "oursheikh.naqshbandiaowaisiah.us",
    region: "Our Sheikh",
    title: "Our Sheikh · Naqshbandia Owaisiah",
    tagline: "Live Zikr with Hazrat Ameer Abdul Qadeer Awan (MZA)",
    intro: "Join the Daily Zikr live, follow each Latifa as it is called, and keep company with the Silsila wherever you are.",
    halqahs: [
      { id: "our-sheikh", name: "Our Sheikh", description: "Hazrat Ameer Abdul Qadeer Awan (MZA)", open: true },
    ],
  },
  namerica: {
    host: "namerica.naqshbandiaowaisiah.us",
    region: "North America",
    title: "North America · Naqshbandia Owaisiah",
    tagline: "The Halqahs of the United States and Canada",
    intro: "Sit in Zikr with Our Sheikh live, and find your Halqah across the United States and Canada.",
    halqahs: [
      { id: "our-sheikh", name: "Our Sheikh", description: "Hazrat Ameer Abdul Qadeer Awan (MZA)", open: true },
      { id: "north-america", name: "North America", description: "Naqshbandia Owaisiah | North America" },
      { id: "usa", name: "United States of America", description: "Naqshbandia Owaisiah | United States" },
      { id: "canada", name: "Canada", description: "Naqshbandia Owaisiah | Canada" },
      { id: "new-york-ny", name: "New York, NY", description: "Naqshbandia Owaisiah | New York" },
      { id: "worcester-ma", name: "Worcester, MA", description: "Naqshbandia Owaisiah | Worcester" },
    ],
  },
  uk: {
    host: "uk.naqshbandiaowaisiah.us",
    region: "United Kingdom",
    title: "United Kingdom · Naqshbandia Owaisiah",
    tagline: "The Halqahs of the United Kingdom",
    intro: "Sit in Zikr with Our Sheikh live, and find your Halqah in the United Kingdom.",
    halqahs: [
      { id: "our-sheikh", name: "Our Sheikh", description: "Hazrat Ameer Abdul Qadeer Awan (MZA)", open: true },
      { id: "united-kingdom", name: "United Kingdom", description: "Naqshbandia Owaisiah | United Kingdom" },
    ],
  },
};

function siteFor(url) {
  const byHost = Object.entries(SITES).find(([, site]) => site.host === url.hostname);
  if (byHost) return byHost[0];
  // The workers.dev address previews any site with ?site=.
  const asked = url.searchParams.get("site");
  return asked && SITES[asked] ? asked : "oursheikh";
}

async function api(env, path) {
  try {
    const response = await env.API.fetch(new Request(`https://platform${path}`, { headers: { accept: "application/json" } }));
    return response.ok ? await response.json() : null;
  } catch {
    return null;
  }
}

/** What the page refreshes every 20 seconds. */
async function data(env, key) {
  const site = SITES[key];
  const [live, stage, halqahs] = await Promise.all([
    api(env, "/v1/live"),
    api(env, "/v1/public/sheikh-stage"),
    api(env, `/v1/public/halqahs?ids=${site.halqahs.map(h => h.id).join(",")}`),
  ]);
  const youtube = live?.state === "live" ? live.sources?.find(s => s.kind === "youtube" && s.videoID) : undefined;
  const names = new Map((halqahs?.halqahs ?? []).map(h => [h.id, h]));
  return {
    live: {
      onAir: !!youtube,
      title: live?.title ?? "Daily Zikr",
      videoID: youtube?.videoID ?? null,
      startedAt: live?.startedAt ?? null,
      scheduledStart: live?.scheduledStart ?? null,
      cue: live?.cue?.text ?? null,
      room: live?.room ? { listeners: live.room.listeners ?? 0, url: live.room.url ?? null } : null,
    },
    stage: stage?.live ? stage.stage ?? null : null,
    halqahLive: !!stage?.live,
    // A test Zikr shows on the websites too, marked as a test.
    halqahTest: !!stage?.live?.isTest,
    latestVideoID: stage?.latestVideoID ?? null,
    picture: stage?.pictureHDURL ?? stage?.pictureURL ?? null,
    pictureFallback: stage?.pictureURL ?? null,
    halqahs: site.halqahs.map(h => ({ ...h, ...(names.get(h.id) ? { name: names.get(h.id).name } : {}) })),
  };
}

// The eight-pointed star of the page's brand mark, gold on deep green.
const FAVICON = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40"><rect width="40" height="40" rx="9" fill="#04150f"/>
<path d="M20 4 25 15 36 20 25 25 20 36 15 25 4 20 15 15Z" fill="none" stroke="#d9b56a" stroke-width="2.2"/><circle cx="20" cy="20" r="5" fill="#d9b56a"/></svg>`;

const SECURITY = {
  "x-content-type-options": "nosniff",
  "referrer-policy": "strict-origin-when-cross-origin",
  "permissions-policy": "camera=(), microphone=(), geolocation=()",
  "content-security-policy": [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline'",
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    "font-src https://fonts.gstatic.com",
    "img-src 'self' data: https://i.ytimg.com https://img.youtube.com",
    "frame-src https://www.youtube-nocookie.com https://www.youtube.com",
    "connect-src 'self'",
  ].join("; "),
};

/** The zone's firewall lets in only the home_vpn IP list (besides these sites).
 * Every 5 minutes: look up vpn.wajidali.us and, when its address changed, make it
 * the list's only entry. Needs HOME_VPN_LIST_TOKEN (Account Filter Lists: Edit). */
async function followHomeVPN(env) {
  if (!env.HOME_VPN_LIST_TOKEN) return;
  const dns = await fetch(`https://cloudflare-dns.com/dns-query?name=${env.HOME_VPN_HOST}&type=A`,
    { headers: { accept: "application/dns-json" } }).then(r => r.json());
  const ips = (dns.Answer ?? []).filter(a => a.type === 1).map(a => a.data);
  // One ordinary public IPv4 address, or nothing changes.
  const ip = ips.length === 1 && /^\d{1,3}(\.\d{1,3}){3}$/.test(ips[0]) &&
    !/^(10|127|0)\.|^192\.168\.|^172\.(1[6-9]|2\d|3[01])\.|^169\.254\./.test(ips[0]) ? ips[0] : null;
  if (!ip) return console.log("home VPN: unexpected DNS answer", JSON.stringify(ips));
  const api = (path, init = {}) => fetch(`https://api.cloudflare.com/client/v4/accounts/${env.ACCOUNT_ID}/rules/lists/${env.HOME_VPN_LIST_ID}${path}`,
    { ...init, headers: { authorization: `Bearer ${env.HOME_VPN_LIST_TOKEN}`, "content-type": "application/json" } }).then(r => r.json());
  const current = (await api("/items")).result?.map(item => item.ip) ?? [];
  if (current.length === 1 && current[0] === ip) return;
  const done = await api("/items", { method: "PUT", body: JSON.stringify([{ ip, comment: env.HOME_VPN_HOST }]) });
  console.log("home VPN list", JSON.stringify(current), "->", ip, done.success ? "ok" : JSON.stringify(done.errors));
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(followHomeVPN(env));
  },

  async fetch(request, env) {
    const url = new URL(request.url);
    const key = siteFor(url);
    if (request.method !== "GET" && request.method !== "HEAD") return new Response("Method not allowed", { status: 405 });
    if (url.pathname === "/data.json") {
      return new Response(JSON.stringify(await data(env, key)), {
        headers: { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=15", ...SECURITY },
      });
    }
    if (url.pathname === "/robots.txt") return new Response("User-agent: *\nAllow: /\n", { headers: { "content-type": "text/plain" } });
    if (url.pathname === "/favicon.ico" || url.pathname === "/favicon.svg") {
      return new Response(FAVICON, { headers: { "content-type": "image/svg+xml", "cache-control": "public, max-age=86400" } });
    }
    if (url.pathname !== "/" && url.pathname !== "/index.html") return Response.redirect(new URL("/", url).toString(), 302);
    const others = Object.entries(SITES).filter(([k]) => k !== key).map(([, s]) => ({ host: s.host, region: s.region }));
    return new Response(page(SITES[key], others, await data(env, key)), {
      headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=60", ...SECURITY },
    });
  },
};
