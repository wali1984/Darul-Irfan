// The PDF relay for the Web app (PLAT-011): the site's own uploaded PDFs
// only, streamed with Range, and a readable 404 when the file is missing.
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";
import { libraryPDF } from "../src/pdfProxy";

const PDF = "https://www.naqshbandiaowaisiah.org/uploads/almurshid-magazines/almurshid_may_1983.pdf";
const env = {} as Env;

type Seen = { url: string; method: string; range: string | null; redirect: string | undefined };

function source(answer: (url: string, init: RequestInit) => Response) {
  const seen: Seen[] = [];
  vi.stubGlobal("fetch", async (input: string, init: RequestInit = {}) => {
    const headers = new Headers(init.headers);
    seen.push({ url: String(input), method: init.method ?? "GET", range: headers.get("range"), redirect: init.redirect });
    return answer(String(input), init);
  });
  return seen;
}

const relay = (src: string) => "https://api.example.com/v1/pdf?src=" + encodeURIComponent(src);
const ask = (src: string, init: RequestInit = {}) => worker.fetch(new Request(relay(src), init), env);

afterEach(() => vi.unstubAllGlobals());

describe("PDF relay: what it passes", () => {
  it.each([
    ["another host", "https://evil.example.com/uploads/a.pdf"],
    ["a look-alike host", "https://www.naqshbandiaowaisiah.org.evil.com/uploads/a.pdf"],
    ["http", "http://www.naqshbandiaowaisiah.org/uploads/a.pdf"],
    ["outside the uploads", "https://www.naqshbandiaowaisiah.org/admin/a.pdf"],
    ["not a PDF", "https://www.naqshbandiaowaisiah.org/uploads/a.mp3"],
    ["a query", "https://www.naqshbandiaowaisiah.org/uploads/a.pdf?x=1"],
    ["an empty query", "https://www.naqshbandiaowaisiah.org/uploads/a.pdf?"],
    ["a fragment", "https://www.naqshbandiaowaisiah.org/uploads/a.pdf#page=2"],
    ["a climb out", "https://www.naqshbandiaowaisiah.org/uploads/..%2F..%2Fsecret.pdf"],
    ["a dotted climb", "https://www.naqshbandiaowaisiah.org/uploads/%2e%2e/secret.pdf"],
    ["credentials", "https://user:pass@www.naqshbandiaowaisiah.org/uploads/a.pdf"],
    ["another port", "https://www.naqshbandiaowaisiah.org:8443/uploads/a.pdf"],
    ["nothing", ""],
  ])("refuses %s, without asking anyone", async (_, src) => {
    const seen = source(() => new Response("x"));
    const response = await ask(src);
    expect(response.status).toBe(400);
    expect(response.headers.get("access-control-allow-origin")).toBe("*");
    expect(await response.json()).toEqual({ error: "Unsupported document" });
    expect(seen).toEqual([]);
  });

  it("accepts the site's own PDFs, any letter case of .pdf", () => {
    expect(libraryPDF(PDF)).toBe(PDF);
    expect(libraryPDF("https://www.naqshbandiaowaisiah.org/uploads/books/Dalael-us-Salook-Urdu.PDF")).not.toBeNull();
    // A few older papers live under /docs/ (the library's "Conditions for Muraqbat").
    expect(libraryPDF("https://www.naqshbandiaowaisiah.org/docs/Conditions-for-Muraqbat-in-English.pdf")).not.toBeNull();
    expect(libraryPDF("https://www.naqshbandiaowaisiah.org/docs/..%2Fadmin%2Fa.pdf")).toBeNull();
  });

  it("answers only GET, HEAD and OPTIONS", async () => {
    source(() => new Response("x"));
    const post = await worker.fetch(new Request(relay(PDF), { method: "POST" }), env);
    expect(post.status).toBe(404);
  });
});

describe("PDF relay: what it sends back", () => {
  it("streams the whole file inline, with CORS and caching", async () => {
    const seen = source(() => new Response("%PDF-1.4 ...", {
      status: 200,
      headers: { "content-type": "application/octet-stream", "content-length": "12", "accept-ranges": "bytes",
        "content-disposition": "attachment", etag: "W/1", "set-cookie": "s=1" },
    }));
    const response = await ask(PDF);
    expect(response.status).toBe(200);
    expect(await response.text()).toBe("%PDF-1.4 ...");
    expect(response.headers.get("content-type")).toBe("application/pdf");
    expect(response.headers.get("content-disposition")).toBe("inline");
    expect(response.headers.get("access-control-allow-origin")).toBe("*");
    expect(response.headers.get("access-control-expose-headers")).toContain("Content-Range");
    expect(response.headers.get("accept-ranges")).toBe("bytes");
    expect(response.headers.get("etag")).toBe("W/1");
    expect(response.headers.get("cache-control")).toBe("public, max-age=86400");
    expect(response.headers.get("x-content-type-options")).toBe("nosniff");
    expect(response.headers.get("set-cookie")).toBeNull();
    expect(seen).toEqual([{ url: PDF, method: "GET", range: null, redirect: "manual" }]);
  });

  it("passes a Range on and returns 206 with Content-Range", async () => {
    const seen = source(() => new Response("page", {
      status: 206, headers: { "content-range": "bytes 0-3/12672700", "content-length": "4", "accept-ranges": "bytes" },
    }));
    const response = await ask(PDF, { headers: { range: "bytes=0-3" } });
    expect(response.status).toBe(206);
    expect(response.headers.get("content-range")).toBe("bytes 0-3/12672700");
    expect(await response.text()).toBe("page");
    expect(seen[0]?.range).toBe("bytes=0-3");
  });

  it("asks the source with HEAD for a HEAD, and sends no body", async () => {
    const seen = source(() => new Response(null, { status: 200, headers: { "content-length": "12672700" } }));
    const response = await ask(PDF, { method: "HEAD" });
    expect(response.status).toBe(200);
    expect(response.headers.get("content-length")).toBe("12672700");
    expect(await response.text()).toBe("");
    expect(seen[0]?.method).toBe("HEAD");
  });

  it("passes 416 and 304 through", async () => {
    source(() => new Response(null, { status: 416, headers: { "content-range": "bytes */12" } }));
    const outOfRange = await ask(PDF, { headers: { range: "bytes=99-100" } });
    expect(outOfRange.status).toBe(416);
    expect(outOfRange.headers.get("access-control-allow-origin")).toBe("*");
    source(() => new Response(null, { status: 304, headers: { etag: "W/1" } }));
    const unchanged = await ask(PDF, { headers: { "if-none-match": "W/1" } });
    expect(unchanged.status).toBe(304);
  });

  it("turns a missing file into a readable 404 with CORS", async () => {
    for (const status of [404, 410]) {
      source(() => new Response("gone", { status }));
      const response = await ask(PDF);
      expect(response.status).toBe(404);
      expect(response.headers.get("access-control-allow-origin")).toBe("*");
      expect(await response.json()).toEqual({ error: "Not found at source" });
    }
  });

  it("answers 502 when the source fails or cannot be reached", async () => {
    source(() => new Response("oops", { status: 500 }));
    expect((await ask(PDF)).status).toBe(502);
    vi.stubGlobal("fetch", async () => { throw new Error("connection reset"); });
    const unreachable = await ask(PDF);
    expect(unreachable.status).toBe(502);
    expect(unreachable.headers.get("access-control-allow-origin")).toBe("*");
  });

  it("follows one move on the site itself, and none anywhere else", async () => {
    const moved = "https://www.naqshbandiaowaisiah.org/uploads/almurshid-magazines/almurshid_may_1983_v2.pdf";
    const seen = source(url => url === PDF
      ? new Response(null, { status: 301, headers: { location: moved } })
      : new Response("%PDF", { status: 200 }));
    expect((await ask(PDF)).status).toBe(200);
    expect(seen.map(entry => entry.url)).toEqual([PDF, moved]);

    const away = source(() => new Response(null, { status: 302, headers: { location: "https://evil.example.com/a.pdf" } }));
    expect((await ask(PDF)).status).toBe(502);
    expect(away.map(entry => entry.url)).toEqual([PDF]);
  });

  it("answers the preflight a Range request may bring", async () => {
    const response = await worker.fetch(new Request(relay(PDF), { method: "OPTIONS" }), env);
    expect(response.status).toBe(204);
    expect(response.headers.get("access-control-allow-origin")).toBe("*");
    expect(response.headers.get("access-control-allow-methods")).toBe("GET, HEAD, OPTIONS");
    expect(response.headers.get("access-control-allow-headers")).toBe("Range");
    expect(response.headers.get("access-control-max-age")).toBe("86400");
  });
});
