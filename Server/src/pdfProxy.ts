import { json } from "./util";

// The library's PDFs, passed through for the Web app (PLAT-011).
//
// The site serves every book and magazine without CORS and as an attachment,
// so a browser can neither read one nor show it in a frame; the Web app
// renders them itself with pdf.js and asks here instead. Only the site's own
// uploaded PDFs are passed - this is not an open proxy - and the body is
// streamed, never held, with Range answered so pdf.js loads only the pages
// being read (the complete Akram-ut-Tarajum is 165 MB).

const SOURCE_HOST = "www.naqshbandiaowaisiah.org";
/** Kept at Cloudflare's edge for 30 days; it then answers ranges itself. */
const EDGE_TTL_SECONDS = 30 * 86_400;
/** How long the source has to start answering. The body itself may take longer. */
const SOURCE_TIMEOUT_MS = 30_000;
const PASSED_HEADERS = ["content-length", "content-range", "accept-ranges", "etag", "last-modified"];

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-expose-headers": "Accept-Ranges, Content-Range, Content-Length, Content-Encoding",
};

/** The source URL when it is one of the site's own uploaded PDFs, else null. */
export function libraryPDF(src: string | null): string | null {
  // A query or fragment is refused outright, even an empty one.
  if (!src || /[?#]/.test(src)) return null;
  let url: URL;
  try {
    url = new URL(src);
  } catch {
    return null;
  }
  if (url.protocol !== "https:" || url.hostname !== SOURCE_HOST || url.port !== "" || url.username || url.password) return null;
  const path = url.pathname;
  if (!path.startsWith("/uploads/") || !path.toLowerCase().endsWith(".pdf")) return null;
  let decoded: string;
  try {
    decoded = decodeURIComponent(path);
  } catch {
    return null;
  }
  // An encoded slash or backslash could still climb out of /uploads/.
  if (decoded.includes("\\") || decoded.split("/").some(segment => segment === ".." || segment === ".")) return null;
  return url.toString();
}

/** GET, HEAD or OPTIONS /v1/pdf?src=<the PDF's https URL>. */
export async function libraryPDFRoute(request: Request, url: URL): Promise<Response> {
  if (request.method === "OPTIONS") {
    // Older Safari asks before a Range request.
    return new Response(null, {
      status: 204,
      headers: {
        "access-control-allow-origin": "*",
        "access-control-allow-methods": "GET, HEAD, OPTIONS",
        "access-control-allow-headers": "Range",
        "access-control-max-age": "86400",
      },
    });
  }
  const source = libraryPDF(url.searchParams.get("src"));
  if (!source) return json({ error: "Unsupported document" }, { status: 400, headers: CORS });

  const headers: Record<string, string> = { "user-agent": "DarulIrfan/1.0 (+https://naqshbandiaowaisiah.org)" };
  for (const name of ["range", "if-none-match", "if-modified-since", "if-range"]) {
    const value = request.headers.get(name);
    if (value) headers[name] = value;
  }
  const method = request.method === "HEAD" ? "HEAD" : "GET";

  let upstream: Response | null;
  try {
    upstream = await fromSource(source, method, headers);
    // One move on the site itself is followed; anywhere else is refused.
    if (upstream && upstream.status >= 300 && upstream.status < 400 && upstream.status !== 304) {
      const moved = libraryPDF(new URL(upstream.headers.get("location") ?? "", source).toString());
      upstream = moved ? await fromSource(moved, method, headers) : null;
    }
  } catch {
    upstream = null;
  }
  if (!upstream) return json({ error: "Source unavailable" }, { status: 502, headers: CORS });
  // The Web app says the file is not available from its source only for this.
  if (upstream.status === 404 || upstream.status === 410) {
    return json({ error: "Not found at source" }, { status: 404, headers: CORS });
  }
  if (![200, 206, 304, 416].includes(upstream.status)) {
    return json({ error: "Source unavailable" }, { status: 502, headers: CORS });
  }

  const out = new Headers(CORS);
  for (const name of PASSED_HEADERS) {
    const value = upstream.headers.get(name);
    if (value) out.set(name, value);
  }
  if (upstream.status === 200 || upstream.status === 206) out.set("content-type", "application/pdf");
  // The source says "attachment"; the app shows the document.
  out.set("content-disposition", "inline");
  out.set("cache-control", "public, max-age=86400");
  out.set("x-content-type-options", "nosniff");
  const body = method === "HEAD" || upstream.status === 304 ? null : upstream.body;
  return new Response(body, { status: upstream.status, headers: out });
}

/** The source's answer, or null when it does not start answering in time.
 *  Redirects are not followed here: each step is checked first. */
async function fromSource(source: string, method: "GET" | "HEAD", headers: Record<string, string>): Promise<Response | null> {
  const answer = fetch(source, {
    method,
    headers,
    redirect: "manual",
    cf: { cacheEverything: true, cacheTtl: EDGE_TTL_SECONDS },
  } as RequestInit);
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<null>(resolve => { timer = setTimeout(() => resolve(null), SOURCE_TIMEOUT_MS); });
  try {
    return await Promise.race([answer, late]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}
