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

export const parseJSON = <T>(value: string | null, fallback: T): T => {
  if (!value) return fallback;
  try { return JSON.parse(value) as T; } catch { return fallback; }
};

export const actorEmail = (request: Request): string | null =>
  request.headers.get("cf-access-authenticated-user-email");

export const isUUID = (value: string): boolean =>
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);

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
