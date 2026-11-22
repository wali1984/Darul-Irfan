export const json = (value: unknown, init: ResponseInit = {}): Response => {
  const headers = new Headers(init.headers);
  headers.set("content-type", "application/json; charset=utf-8");
  headers.set("cache-control", headers.get("cache-control") ?? "no-store");
  headers.set("x-content-type-options", "nosniff");
  return new Response(JSON.stringify(value), { ...init, headers });
};

export const cleanText = (value: unknown, max = 2_000): string | undefined => {
  if (typeof value !== "string") return undefined;
  const normalized = value.replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim();
  return normalized ? normalized.slice(0, max) : undefined;
};

/** The start of `text`, at most `max` characters, ending on a whole word
 *  and an ellipsis; `text` itself when it is no longer than that. Characters
 *  are counted with Array.from, so an emoji or a letter outside the basic
 *  plane is one character and is never cut in half. */
export const wholeWords = (text: string, max: number): string => {
  const characters = Array.from(text);
  if (characters.length <= max) return text;
  // One place is kept for the ellipsis.
  let end = Math.max(1, max - 1);
  if (!/\s/.test(characters[end] ?? "")) {
    let space = end - 1;
    while (space > 0 && !/\s/.test(characters[space] ?? "")) space -= 1;
    // A word boundary in the first half would throw most of the text away
    // (one very long word, a link): then the cut falls inside the word, but
    // never between a letter and the marks that belong to it.
    if (space >= Math.floor(end / 2)) end = space;
    else {
      // A mark, a joiner or an emoji's skin tone stays with what it follows.
      while (end > 1 && (/^[\p{M}\u200d\ufe0f\u{1F3FB}-\u{1F3FF}]$/u.test(characters[end] ?? "") || characters[end - 1] === "\u200d")) end -= 1;
      // A flag is two letters: an odd count before the cut is half a flag.
      let flagLetters = 0;
      while (flagLetters < end && /^[\u{1F1E6}-\u{1F1FF}]$/u.test(characters[end - 1 - flagLetters] ?? "")) flagLetters += 1;
      if (flagLetters % 2 === 1 && end > 1) end -= 1;
    }
  }
  const kept = characters.slice(0, end).join("");
  // Punctuation left hanging before the ellipsis goes with the cut.
  return `${kept.replace(/[\s.,;:،؛۔\-–—…]+$/u, "") || kept}…`;
};

/** Longer text, an article's, with its paragraphs kept: control characters
 *  go, the spaces inside a line become one, a line break stays a line break
 *  and more than one empty line becomes one. Text longer than `max`
 *  characters ends on a whole word and an ellipsis. */
export const cleanBody = (value: unknown, max = 20_000): string | undefined => {
  if (typeof value !== "string") return undefined;
  const text = value.replace(/\r\n?|[\u2028\u2029]/g, "\n")
    .replace(/[\u0000-\u0009\u000b-\u001f\u007f]/g, " ")
    .split("\n").map(line => line.replace(/\s+/g, " ").trim()).join("\n")
    .replace(/\n{3,}/g, "\n\n").trim();
  return text ? wholeWords(text, max) : undefined;
};

export const validHTTPURL = (value: unknown): string | undefined => {
  if (typeof value !== "string") return undefined;
  try {
    const url = new URL(value);
    return url.protocol === "https:" ? url.toString() : undefined;
  } catch {
    return undefined;
  }
};

export const validISODate = (value: unknown): string | undefined => {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) return undefined;
  return Number.isFinite(Date.parse(value)) ? new Date(value).toISOString() : undefined;
};

/** An instant in whole seconds, "2026-10-28T16:17:18Z". toISOString() always
 *  adds milliseconds, and the stock ISO-8601 decoder in the iOS builds already
 *  installed rejects them, so every date the public API sends goes through
 *  here. */
export const wholeSeconds = (date: Date): string => date.toISOString().replace(/\.\d{3}Z$/, "Z");

/** A stored timestamp in whole seconds, or undefined when it is not a date.
 *  SQLite's own datetime() text ("2026-10-28 16:17:18") carries no zone and
 *  is UTC. */
export const isoSeconds = (value: unknown): string | undefined => {
  if (typeof value !== "string" || !value.trim()) return undefined;
  const text = value.trim();
  const parsed = Date.parse(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?$/.test(text) ? `${text.replace(" ", "T")}Z` : text);
  return Number.isFinite(parsed) ? wholeSeconds(new Date(parsed)) : undefined;
};

export const parseJSON = <T>(value: string | null, fallback: T): T => {
  if (!value) return fallback;
  try { return JSON.parse(value) as T; } catch { return fallback; }
};

export const isUUID = (value: string): boolean =>
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);

/** Base64url without padding, as a JWT's three parts are written. */
export const base64url = (input: ArrayBuffer | Uint8Array | string): string => {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input instanceof Uint8Array ? input : new Uint8Array(input);
  let binary = ""; bytes.forEach(value => binary += String.fromCharCode(value));
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
};

/** Runs `work` over `items`, at most `limit` at a time, keeping their order. */
export async function inParallel<T, R>(items: T[], limit: number, work: (item: T) => Promise<R>): Promise<R[]> {
  const results = new Array<R>(items.length);
  let next = 0;
  const runners = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const index = next++;
      results[index] = await work(items[index]!);
    }
  });
  await Promise.all(runners);
  return results;
}

export async function sha256(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

const sensitiveDiagnosticKey = /(^|_)(name|email|phone|address|location|latitude|longitude|coordinate|bookmark|prayerHistory|readingHistory|apnsToken)($|_)/i;
const emailLike = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi;

/** Defense-in-depth redaction before consented diagnostics reach D1. */
export function redactDiagnostics(value: unknown, key = "", depth = 0): unknown {
  if (sensitiveDiagnosticKey.test(key)) return "[redacted]";
  if (depth > 10) return "[truncated]";
  if (Array.isArray(value)) return value.slice(0, 1_000).map(item => redactDiagnostics(item, key, depth + 1));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value as Record<string, unknown>)
      .map(([childKey, child]) => [childKey, redactDiagnostics(child, childKey, depth + 1)]));
  }
  if (typeof value === "string") {
    if (key === "metricKitPayload") {
      try { return redactDiagnostics(JSON.parse(value), key, depth + 1); } catch { return "[invalid MetricKit JSON]"; }
    }
    return value.replace(emailLike, "[redacted-email]").slice(0, 200_000);
  }
  return value;
}
