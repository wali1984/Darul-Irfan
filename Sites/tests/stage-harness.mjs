// Shared by the stage tests: bundles the Sites Worker from source (esbuild from
// the Server package, or DARUL_ESBUILD) and gives it a mock platform whose live
// state and stage the test can change. Never contacts the platform or the feed.
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const esbuildPath = process.env.DARUL_ESBUILD
  ? resolve(process.env.DARUL_ESBUILD)
  : fileURLToPath(new URL("../../Server/node_modules/esbuild/lib/main.js", import.meta.url));

export async function loadSites() {
  const { build } = await import(pathToFileURL(esbuildPath).href);
  const directory = await mkdtemp(join(tmpdir(), "darul-sites-stage-"));
  const output = join(directory, "worker.mjs");
  await build({ entryPoints: [fileURLToPath(new URL("../src/index.js", import.meta.url))], outfile: output,
    bundle: true, format: "esm", platform: "neutral", target: "es2022", loader: { ".txt": "text", ".webp": "binary", ".json": "json" }, logLevel: "error" });
  const worker = (await import(pathToFileURL(output).href)).default;
  return { worker, close: () => rm(directory, { recursive: true, force: true }) };
}

export const PICTURE = "https://i.ytimg.com/vi/OIMsVhzqQ-g/maxresdefault.jpg";

// The stage titles as the platform sends them (Server DEFAULT_ZIKR_STAGES).
// The platform's own Arabic for the opening recitations (Server/src/groupZikrStages.ts RECITATIONS).
export const ARABIC = { tasbih: "سُبْحَانَ اللّٰهِ وَالْحَمْدُ لِلّٰهِ وَلَا إِلٰهَ إِلَّا اللّٰهُ وَاللّٰهُ أَكْبَرُ وَلَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللّٰهِ الْعَلِيِّ الْعَظِيمِ" };
export const TITLES = {
  tasbih: ["Tasbihat", "تسبیحات"], "latifa-1": ["1st Latifa", "پہلا لطیفہ"], "latifa-3": ["3rd Latifa", "تیسرا لطیفہ"],
  "latifa-7": ["7th Latifa", "ساتواں لطیفہ"], raabta: ["Raabta", "رابطہ"], ahadiyat: ["Muraqaba Ahadiyat", "مراقبہ احدیت"],
  maiyyat: ["Muraqaba Ma'iyyat", "مراقبہ معیت"], "sair-kaaba": ["Sair-e-Kaaba", "سیرِ کعبہ"], "masjid-nabawi": ["Masjid-e-Nabawi", "مسجدِ نبوی"],
  shajra: ["Shajra Sharif", "شجرہ شریف"], dua: ["Dua", "دعا"],
  waiting: ["Zikr will start soon", "ذکر جلد شروع ہوگا"], bayan: ["Playing Bayan", "بیان جاری ہے"], "bayan-after": ["Playing Bayan", "بیان جاری ہے"],
};

/** A platform whose state the test sets: live or not, and the stage now. */
export function mockPlatform() {
  const state = { live: true, stageID: "maiyyat", isTest: false, picture: PICTURE, startedAt: "2026-11-09T23:23:19.305Z", calls: 0 };
  let at = 0;
  const stage = () => state.stageID
    ? { stageID: state.stageID, title: TITLES[state.stageID]?.[0] ?? state.stageID, titleUr: TITLES[state.stageID]?.[1] ?? "", ...(ARABIC[state.stageID] ? { arabic: ARABIC[state.stageID] } : {}), at: new Date(Date.UTC(2026, 10, 10, 0, 0, at)).toISOString() }
    : null;
  const env = {
    CLOSED_DOMAINS: "naqshbandiaowaisiah.us",
    LIVE_FEED_BASE: "https://feed.invalid", LIVE_FEED_KEY: "fixture-only",
    API: { fetch: async request => {
      state.calls += 1;
      const url = new URL(request.url);
      if (url.pathname === "/v1/public/live") {
        const ids = (url.searchParams.get("ids") ?? "our-sheikh").split(",");
        return Response.json({ halqahs: ids.map(id => ({ id, name: id === "our-sheikh" ? "Our Sheikh" : id,
          live: state.live && (id === "our-sheikh" || id === state.otherLive) ? { kind: "zikr", title: "Daily Zikr", startedAt: state.startedAt, sessionID: "session-fixture", ...(state.isTest ? { isTest: true } : {}) } : null,
          stage: state.live && (id === "our-sheikh" || id === state.otherLive) ? stage() : null })) });
      }
      if (url.pathname === "/v1/public/sheikh-stage") return Response.json(state.picture ? { pictureHDURL: state.picture, pictureURL: state.picture } : {});
      if (url.pathname === "/v1/live") return Response.json({ room: null });
      if (/\/v1\/public\/halqahs\/[a-z0-9-]+\/(join|presence)$/.test(url.pathname)) {
        return Response.json({ id: url.pathname.split("/")[4], live: state.live ? { kind: "zikr", startedAt: state.startedAt } : null, stage: state.live ? stage() : null });
      }
      return Response.json({});
    } },
  };
  /** Moves the Zikr to a stage (each call is a new calling of it, as the platform's `at`). */
  const go = stageID => { state.stageID = stageID; at += 7; };
  return { state, env, go };
}
