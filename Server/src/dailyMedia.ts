import type { Env } from "./contracts";
import { memberRole } from "./community";
import { signedMediaURL } from "./media";
import { cleanText, json } from "./util";

// Pictures for the Today page, chosen by the Super admin.
//
// Each is for one place - the Ayah of the Day, Hadith of the Day or
// Aqwal-e-Sheikh card, a daily quote that opens over the page, or an
// announcement - and one local day (an announcement may run several). They
// arrive from the Super admin's phone, or forwarded to the WhatsApp Business
// number with a #tag, always as drafts: nothing reaches readers until the
// Super admin publishes it for a day.

export const SLOTS = ["ayah", "hadith", "aqwal", "quote", "announcement"] as const;
export type Slot = typeof SLOTS[number];
const TYPES = new Map([["image/jpeg", "jpg"], ["image/png", "png"], ["image/webp", "webp"], ["image/heic", "heic"]]);
const MAX_BYTES = 12 * 1024 * 1024;
const DAY = /^\d{4}-\d{2}-\d{2}$/;

const forbidden = () => json({ error: "Super admin only" }, { status: 403 });
const notFound = () => json({ error: "Not found" }, { status: 404 });

const slotOf = (value: unknown): Slot | null => SLOTS.includes(value as Slot) ? value as Slot : null;
const dayOf = (value: unknown): string | null =>
  typeof value === "string" && DAY.test(value) && !Number.isNaN(Date.parse(`${value}T00:00:00Z`))
    && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value ? value : null;

/** A caption's leading #tag names its place: #ayah, #hadith, #aqwal,
 *  #quote or #announcement (Urdu and common spellings too). A date in it
 *  (2026-10-28) names its day. */
export function dailyTag(text: string | null | undefined): { slot: Slot; caption: string; day: string | null } | null {
  const match = /^\s*#([\p{L}-]+)\s*/u.exec(text ?? "");
  if (!match) return null;
  const tags: Record<string, Slot> = {
    ayah: "ayah", ayat: "ayah", "آیت": "ayah", hadith: "hadith", hadees: "hadith", "حدیث": "hadith",
    aqwal: "aqwal", "aqwal-e-sheikh": "aqwal", "اقوال": "aqwal", quote: "quote", "قول": "quote",
    announcement: "announcement", elaan: "announcement", "اعلان": "announcement",
  };
  const slot = tags[match[1]!.toLowerCase()];
  if (!slot) return null;
  const rest = (text ?? "").slice(match[0].length);
  const day = dayOf(/\b(\d{4}-\d{2}-\d{2})\b/.exec(rest)?.[1]);
  return { slot, caption: rest.replace(/\b\d{4}-\d{2}-\d{2}\b/, "").trim(), day };
}

/** Records a forwarded picture as a draft for its place. */
export async function recordDailyDraft(
  env: Env, ref: string, tag: { slot: Slot; caption: string; day: string | null }, mediaKey: string | null, from: string,
): Promise<void> {
  const now = new Date().toISOString();
  // Meta retries webhooks; the message id keeps a retry from making a second.
  await env.DB.prepare(`INSERT INTO daily_media(id,slot,day,media_key,caption,status,source,source_ref,created_by,created_at,updated_at)
    VALUES(?,?,?,?,?,'draft','whatsapp',?,?,?,?) ON CONFLICT(source_ref) DO NOTHING`)
    .bind(`daily-${crypto.randomUUID().slice(0, 12)}`, tag.slot, tag.day, mediaKey, tag.caption || null, ref, `whatsapp:${from}`, now, now).run();
}

type Row = {
  id: string; slot: string; day: string | null; end_day: string | null; media_key: string | null; caption: string | null;
  popup: number; status: string; source: string; created_at: string;
};

async function present(env: Env, row: Row, seconds: number) {
  return {
    id: row.id, slot: row.slot, day: row.day ?? undefined, endDay: row.end_day ?? undefined,
    caption: row.caption ?? undefined, popup: !!row.popup,
    imageURL: row.media_key ? await signedMediaURL(env, row.media_key, seconds) : undefined,
  };
}

/** GET /v1/daily-media?day=YYYY-MM-DD - what is published for the phone's
 *  local day. Public, like the rest of the Today page. */
export async function dailyMediaFor(env: Env, url: URL): Promise<Response> {
  const day = dayOf(url.searchParams.get("day"));
  if (!day) return json({ error: "day must be YYYY-MM-DD" }, { status: 400 });
  const rows = await env.DB.prepare(`SELECT * FROM daily_media WHERE status='published' AND day IS NOT NULL
    AND day<=? AND COALESCE(end_day,day)>=? ORDER BY slot, published_at DESC LIMIT 20`).bind(day, day).all<Row>();
  const items = [];
  for (const row of rows.results ?? []) items.push(await present(env, row, 3 * 86_400));
  return json({ day, items }, { headers: { "cache-control": "public, max-age=300" } });
}

async function superAdmin(env: Env, memberID: string): Promise<boolean> {
  return await memberRole(env, memberID) === "superadmin";
}

/** The Super admin's list: drafts first, then what is published from a week
 *  ago on, with each item's status and where it came from. */
export async function manageDailyMedia(env: Env, memberID: string): Promise<Response> {
  if (!await superAdmin(env, memberID)) return forbidden();
  const since = new Date(Date.now() - 7 * 86_400_000).toISOString().slice(0, 10);
  const rows = await env.DB.prepare(`SELECT * FROM daily_media WHERE status='draft' OR COALESCE(end_day,day,'9999')>=?
    ORDER BY status='draft' DESC, day DESC, created_at DESC LIMIT 200`).bind(since).all<Row>();
  const items = [];
  for (const row of rows.results ?? []) {
    items.push({ ...await present(env, row, 86_400), status: row.status, source: row.source, createdAt: row.created_at });
  }
  return json({ items, slots: SLOTS });
}

/** A picture from the Super admin's phone. The file is the body; its place,
 *  day and caption come in the query, and `publish=1` publishes it at once. */
export async function uploadDailyMedia(request: Request, env: Env, memberID: string, url: URL): Promise<Response> {
  if (!await superAdmin(env, memberID)) return forbidden();
  if (!env.MEDIA) return json({ error: "Pictures are not available yet." }, { status: 503 });
  const contentType = (request.headers.get("content-type") ?? "").split(";")[0]!.trim().toLowerCase();
  const extension = TYPES.get(contentType);
  if (!extension) return json({ error: "Choose a JPEG, PNG, WebP or HEIC picture." }, { status: 415 });
  const size = Number(request.headers.get("content-length"));
  if (!Number.isInteger(size) || size <= 0 || size > MAX_BYTES) return json({ error: "The picture must be under 12 MB." }, { status: 413 });
  const slot = slotOf(url.searchParams.get("slot"));
  if (!slot) return json({ error: "Choose where it shows." }, { status: 400 });
  const day = dayOf(url.searchParams.get("day"));
  const publish = url.searchParams.get("publish") === "1";
  if (publish && !day) return json({ error: "Choose the day it is for." }, { status: 400 });
  const endDay = dayOf(url.searchParams.get("endDay"));
  if (url.searchParams.has("endDay") && !endDay) return json({ error: "Choose a valid last day." }, { status: 400 });
  if (endDay && day && endDay < day) return json({ error: "The last day cannot be before the first." }, { status: 400 });
  const id = `daily-${crypto.randomUUID().slice(0, 12)}`;
  const key = `daily/${id}.${extension}`;
  await env.MEDIA.put(key, request.body, { httpMetadata: { contentType } });
  const now = new Date().toISOString();
  await env.DB.prepare(`INSERT INTO daily_media(id,slot,day,end_day,media_key,caption,popup,status,source,created_by,created_at,updated_at,published_by,published_at)
    VALUES(?,?,?,?,?,?,?,?,'upload',?,?,?,?,?)`)
    .bind(id, slot, day, endDay, key, cleanText(url.searchParams.get("caption"), 600) ?? null,
      url.searchParams.get("popup") === "1" ? 1 : 0, publish ? "published" : "draft", `member:${memberID}`, now, now,
      publish ? `member:${memberID}` : null, publish ? now : null).run();
  return json({ ok: true, id }, { status: 201 });
}

/** Changes a picture's place, day, caption or pop-up, or publishes or hides it. */
export async function updateDailyMedia(env: Env, memberID: string, id: string, input: Record<string, unknown>): Promise<Response> {
  if (!await superAdmin(env, memberID)) return forbidden();
  const row = await env.DB.prepare("SELECT * FROM daily_media WHERE id=?").bind(id).first<Row>();
  if (!row) return notFound();
  const slot = input.slot === undefined ? row.slot : slotOf(input.slot);
  if (!slot) return json({ error: "Choose where it shows." }, { status: 400 });
  const day = input.day === undefined ? row.day : dayOf(input.day);
  const endDay = input.endDay === undefined ? row.end_day : dayOf(input.endDay);
  if (input.day != null && !day) return json({ error: "Choose the day it is for." }, { status: 400 });
  if (input.endDay != null && !endDay) return json({ error: "Choose a valid last day." }, { status: 400 });
  const status = input.status === "published" || input.status === "hidden" || input.status === "draft" ? input.status : row.status;
  if (status === "published" && !day) return json({ error: "Choose the day it is for." }, { status: 400 });
  if (endDay && day && endDay < day) return json({ error: "The last day cannot be before the first." }, { status: 400 });
  const caption = input.caption === undefined ? row.caption : cleanText(input.caption, 600) ?? null;
  const popup = input.popup === undefined ? row.popup : input.popup === true ? 1 : 0;
  const now = new Date().toISOString();
  const publishing = status === "published" && row.status !== "published";
  await env.DB.prepare(`UPDATE daily_media SET slot=?,day=?,end_day=?,caption=?,popup=?,status=?,updated_at=?,
    published_by=CASE WHEN ? THEN ? ELSE published_by END,published_at=CASE WHEN ? THEN ? ELSE published_at END WHERE id=?`)
    .bind(slot, day, endDay, caption, popup, status, now, publishing ? 1 : 0, `member:${memberID}`, publishing ? 1 : 0, now, id).run();
  return json({ ok: true, id, status });
}

export async function deleteDailyMedia(env: Env, memberID: string, id: string): Promise<Response> {
  if (!await superAdmin(env, memberID)) return forbidden();
  const row = await env.DB.prepare("SELECT media_key FROM daily_media WHERE id=?").bind(id).first<{ media_key: string | null }>();
  if (!row) return notFound();
  if (row.media_key) await env.MEDIA?.delete(row.media_key);
  await env.DB.prepare("DELETE FROM daily_media WHERE id=?").bind(id).run();
  return new Response(null, { status: 204 });
}
