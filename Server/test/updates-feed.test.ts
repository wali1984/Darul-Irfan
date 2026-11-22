// Updates (the official feed): a website item carries its whole text and
// says which library item it is, a programme says which event it is, and a
// Facebook post's title ends on a whole word.
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env, OfficialFeedItem } from "../src/contracts";
import { feed, feedTarget } from "../src/repository";
import { refreshFacebook, refreshWebsiteCatalog } from "../src/sources";
import { cleanBody, wholeWords } from "../src/util";
import { sqliteD1 } from "./sqlite-d1";

const count = (text: string) => Array.from(text).length;

function setup(answer: (url: string) => Response) {
  const { db, raw } = sqliteD1();
  vi.stubGlobal("fetch", async (input: string) => answer(String(input)));
  const env = {
    DB: db, PUBLIC_BASE_URL: "https://api.example.com", FACEBOOK_GRAPH_VERSION: "v25.0",
    FACEBOOK_PAGE_ID: "page", FACEBOOK_PAGE_ACCESS_TOKEN: "token",
  } as unknown as Env;
  return { env, raw };
}

const catalog = (articles: unknown[], events: unknown[] = []) => (url: string) => {
  if (url.endsWith("content_manifest.json")) return new Response(JSON.stringify({ version: 4 }));
  if (url.endsWith("articles.json")) return new Response(JSON.stringify(articles));
  if (url.endsWith("events.json")) return new Response(JSON.stringify(events));
  return new Response("{}", { status: 200 });
};

const article = (id: string, extra: Record<string, unknown> = {}) => ({
  id, title: `Title of ${id}`, sourceUrl: `https://www.naqshbandiaowaisiah.org/${id}.html`, publishedAt: "2026-03-23T00:00:00Z", ...extra,
});

const item = async (env: Env, id: string) => (await feed(env, 50)).items.find(entry => entry.id === id);

afterEach(() => vi.unstubAllGlobals());

describe("a website item in Updates carries its text", () => {
  it("sends a dated catalogue row's whole text, paragraph by paragraph", async () => {
    const text = "مرکز دارالعرفان منارہ میں سالانہ اجتماع ہوا۔\r\nخصوصی خطاب:   شیخ المکرم نے فرمایا۔\n\n\n\nA closing line\twith a tab.\u0000";
    const { env } = setup(catalog([article("press-release-1", { bodyPlainText: text, excerpt: "A teaser." })]));
    await refreshWebsiteCatalog(env);
    expect((await item(env, "website:press-release-1"))?.body)
      .toBe("مرکز دارالعرفان منارہ میں سالانہ اجتماع ہوا۔\nخصوصی خطاب: شیخ المکرم نے فرمایا۔\n\nA closing line with a tab.");
  });

  it("does not cut a long press release short", async () => {
    // The longest in the catalogue today is about 2,500 characters.
    const paragraph = "سلسلہ نقشبندیہ اویسیہ کے زیر اہتمام ماہانہ اجتماع منعقد ہوا جس میں ملک بھر سے احباب نے شرکت کی۔";
    const text = Array.from({ length: 40 }, () => paragraph).join("\n");
    expect(count(text)).toBeGreaterThan(3_000);
    const { env } = setup(catalog([article("press-release-2", { bodyPlainText: text })]));
    await refreshWebsiteCatalog(env);
    expect((await item(env, "website:press-release-2"))?.body).toBe(text);
  });

  it("falls back to the teaser, and sends no body when the catalogue has neither", async () => {
    const { env } = setup(catalog([
      article("announcement-1", { excerpt: "  Annual gathering\n at Munara. " }),
      article("announcement-2", { bodyPlainText: "   ", excerpt: "Only a teaser." }),
      article("announcement-3"),
    ]));
    await refreshWebsiteCatalog(env);
    expect((await item(env, "website:announcement-1"))?.body).toBe("Annual gathering\nat Munara.");
    expect((await item(env, "website:announcement-2"))?.body).toBe("Only a teaser.");
    const bare = await item(env, "website:announcement-3");
    expect(bare).toBeDefined();
    expect(bare?.body).toBeUndefined();
  });

  it("puts the text on an item already in the feed without one", async () => {
    let articles = [article("press-release-3")];
    const { env } = setup(url => catalog(articles)(url));
    await refreshWebsiteCatalog(env);
    expect((await item(env, "website:press-release-3"))?.body).toBeUndefined();
    articles = [article("press-release-3", { bodyPlainText: "Now with its text." })];
    await refreshWebsiteCatalog(env);
    expect((await item(env, "website:press-release-3"))?.body).toBe("Now with its text.");
  });
});

describe("a feed item says what it opens in the app", () => {
  const event = { id: "seminar-1159-2020-06-19-salana", title: "Annual Training Program", sourceUrl: "https://www.naqshbandiaowaisiah.org/seminar/1159.html", startDate: "2026-06-19T00:00:00Z" };

  it("names the library item of a website row and the event of a programme row", async () => {
    const { env, raw } = setup(catalog([article("press-release-3985-2026-03-23-x", { bodyPlainText: "Text." })], [event]));
    await refreshWebsiteCatalog(env);
    raw.prepare(`INSERT INTO feed_items(id,source,kind,title,source_url,video_id,published_at,updated_at)
      VALUES('youtube:abcdefghijk','youtube','video','A bayan','https://www.youtube.com/watch?v=abcdefghijk','abcdefghijk','2026-03-01T00:00:00Z',datetime('now'))`).run();
    raw.prepare(`INSERT INTO feed_items(id,source,kind,title,source_url,published_at,updated_at)
      VALUES('announcement:1','announcement','announcement','A notice','https://www.naqshbandiaowaisiah.org/n','2026-03-02T00:00:00Z',datetime('now'))`).run();

    const response = await worker.fetch(new Request("https://api.example.com/v1/feed?limit=50"), env);
    expect(response.status).toBe(200);
    const items = (await response.json() as { items: OfficialFeedItem[] }).items;
    const byID = Object.fromEntries(items.map(entry => [entry.id, entry]));

    expect(byID["website:press-release-3985-2026-03-23-x"]).toMatchObject({ source: "website", libraryID: "press-release-3985-2026-03-23-x" });
    expect(byID["website:press-release-3985-2026-03-23-x"]).not.toHaveProperty("eventID");
    expect(byID["event:seminar-1159-2020-06-19-salana"]).toMatchObject({ source: "event", eventID: "seminar-1159-2020-06-19-salana" });
    expect(byID["event:seminar-1159-2020-06-19-salana"]).not.toHaveProperty("libraryID");
    for (const id of ["youtube:abcdefghijk", "announcement:1"]) {
      expect(byID[id]).toBeDefined();
      expect(byID[id]).not.toHaveProperty("libraryID");
      expect(byID[id]).not.toHaveProperty("eventID");
    }
  });

  it("still sends every field the released apps read, under the same names", async () => {
    const { env } = setup(catalog([article("press-release-9", { bodyPlainText: "Text.", mediaUrls: ["https://www.naqshbandiaowaisiah.org/uploads/9/a.jpg"] })]));
    await refreshWebsiteCatalog(env);
    expect(await item(env, "website:press-release-9")).toEqual({
      id: "website:press-release-9", source: "website", kind: "post", title: "Title of press-release-9", body: "Text.",
      sourceURL: "https://www.naqshbandiaowaisiah.org/press-release-9.html", imageURL: "https://www.naqshbandiaowaisiah.org/uploads/9/a.jpg",
      videoID: undefined, libraryID: "press-release-9", publishedAt: "2026-03-23T00:00:00Z", isFeatured: false,
    });
  });

  it("reads the id only from a row of that source", () => {
    expect(feedTarget("website", "website:a:b")).toEqual({ libraryID: "a:b" });
    expect(feedTarget("event", "event:seminar-1")).toEqual({ eventID: "seminar-1" });
    expect(feedTarget("website", "website:")).toEqual({});
    expect(feedTarget("announcement", "website:a")).toEqual({});
    expect(feedTarget("youtube", "youtube:abcdefghijk")).toEqual({});
  });
});

describe("a Facebook post's title in Updates", () => {
  const posts = (messages: string[]) => (url: string) => url.startsWith("https://graph.facebook.com/")
    ? new Response(JSON.stringify({ data: messages.map((message, index) => ({
        id: `p${index}`, message, created_time: `2026-11-0${index + 1}T10:00:00Z`, permalink_url: `https://www.facebook.com/page/posts/${index}`,
      })) }))
    : new Response("{}", { status: 200 });

  it("ends on a whole word with an ellipsis when the post goes on, and is the post itself when it is short", async () => {
    const long = "Alhamdulillah, the annual Ijtema at Dar ul Irfan Munara concluded today with a special address and collective dua for the whole Ummah.";
    const short = "Jumma Mubarak to all.";
    const { env } = setup(posts([long, short]));
    await refreshFacebook(env);

    const cut = await item(env, "facebook:p0");
    expect(cut?.title).toBe("Alhamdulillah, the annual Ijtema at Dar ul Irfan Munara concluded today with a special address and…");
    expect(count(cut!.title)).toBeLessThanOrEqual(100);
    expect(cut?.body).toBe(long);

    const whole = await item(env, "facebook:p1");
    expect(whole?.title).toBe(short);
    expect(whole?.body).toBe(short);
  });

  it("cuts Urdu on a word as well", async () => {
    const urdu = Array.from({ length: 12 }, () => "دارالعرفان منارہ میں سالانہ اجتماع").join(" ");
    const { env } = setup(posts([urdu]));
    await refreshFacebook(env);
    const title = (await item(env, "facebook:p0"))!.title;
    expect(title.endsWith("…")).toBe(true);
    expect(count(title)).toBeLessThanOrEqual(100);
    const kept = title.slice(0, -1);
    expect(urdu.startsWith(`${kept} `)).toBe(true);
  });
});

describe("wholeWords", () => {
  it("leaves text of the allowed length as it is, with no ellipsis", () => {
    expect(wholeWords("Jumma Mubarak", 100)).toBe("Jumma Mubarak");
    expect(wholeWords("12345", 5)).toBe("12345");
    // Five characters as a reader counts them, ten in UTF-16.
    expect(wholeWords("🌙🌙🌙🌙🌙", 5)).toBe("🌙🌙🌙🌙🌙");
  });

  it("cuts at the last whole word that fits, dropping punctuation left before the ellipsis", () => {
    expect(wholeWords("one two three four", 10)).toBe("one two…");
    expect(wholeWords("one two, three four", 10)).toBe("one two…");
    expect(wholeWords("123456789 abc", 10)).toBe("123456789…");
    expect(wholeWords("First line. Second line goes on", 13)).toBe("First line…");
  });

  it("never cuts an emoji in half", () => {
    const text = `${"🌙".repeat(60)} ${"🕌".repeat(60)}`;
    const cut = wholeWords(text, 100);
    expect(cut).toBe(`${"🌙".repeat(60)}…`);
    expect(() => encodeURIComponent(cut)).not.toThrow();
    const solid = wholeWords("🌙".repeat(150), 100);
    expect(solid).toBe(`${"🌙".repeat(99)}…`);
    expect(() => encodeURIComponent(solid)).not.toThrow();
  });

  it("keeps a flag's two letters and an emoji's skin tone together", () => {
    // Each is two characters; the cut at 99 would fall between them.
    const flag = "\u{1F1F5}\u{1F1F0}"; const hand = "\u{1F44D}\u{1F3FD}";
    expect(wholeWords(flag.repeat(80), 100)).toBe(`${flag.repeat(49)}…`);
    expect(wholeWords(hand.repeat(80), 100)).toBe(`${hand.repeat(49)}…`);
    // A cut that already falls between two flags stays where it is.
    expect(wholeWords(`x${flag.repeat(80)}`, 100)).toBe(`x${flag.repeat(49)}…`);
  });

  it("cuts inside one very long word rather than throwing most of the text away, keeping a letter's marks with it", () => {
    expect(wholeWords(`Hi ${"x".repeat(200)}`, 100)).toBe(`Hi ${"x".repeat(96)}…`);
    // The mark after the 9th letter would be the first character cut off.
    const marked = `${"ب".repeat(9)}\u064e${"ب".repeat(20)}`;
    expect(wholeWords(marked, 10)).toBe(`${"ب".repeat(8)}…`);
  });
});

describe("cleanBody", () => {
  it("keeps paragraphs and tidies the rest", () => {
    expect(cleanBody(" One  line \r\n\r\n\r\n Two\tlines \u2028 Three ")).toBe("One line\n\nTwo lines\nThree");
    expect(cleanBody("\n \n")).toBeUndefined();
    expect(cleanBody(undefined)).toBeUndefined();
    expect(cleanBody(12)).toBeUndefined();
  });

  it("ends an over-long text on a whole word", () => {
    const cut = cleanBody("word ".repeat(100), 42)!;
    expect(cut).toBe(`${"word ".repeat(7)}word…`);
    expect(count(cut)).toBeLessThanOrEqual(42);
  });
});
