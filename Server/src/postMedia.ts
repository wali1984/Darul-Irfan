import type { Env } from "./contracts";
import { canManage, canSee, memberRole } from "./community";
import { signedMediaURL } from "./media";
import { json } from "./util";

// Pictures and videos attached to Halqah posts. The admin's phone sends each
// file first and gets back its key; the post then names its keys. Files are
// private to the group, served by signed link only.

const TYPES = new Map<string, [string, "image" | "video"]>([
  ["image/jpeg", ["jpg", "image"]], ["image/png", ["png", "image"]], ["image/webp", ["webp", "image"]],
  ["image/heic", ["heic", "image"]], ["image/gif", ["gif", "image"]],
  ["video/mp4", ["mp4", "video"]], ["video/quicktime", ["mov", "video"]],
]);
const MAX_BYTES = 95 * 1024 * 1024;
export const MAX_ATTACHMENTS = 10;

export type Attachment = { key: string; kind: "image" | "video"; contentType: string };

/** POST /v1/groups/{group}/media - one picture or video for a post. */
export async function uploadPostMedia(request: Request, env: Env, memberID: string, groupID: string): Promise<Response> {
  const role = await memberRole(env, memberID);
  if (!await canSee(env, memberID, role, groupID)) return json({ error: "Not found" }, { status: 404 });
  if (!await canManage(env, memberID, role, groupID)) return json({ error: "Group admin role required" }, { status: 403 });
  if (!env.MEDIA) return json({ error: "Pictures are not available yet." }, { status: 503 });
  const contentType = (request.headers.get("content-type") ?? "").split(";")[0]!.trim().toLowerCase();
  const type = TYPES.get(contentType);
  if (!type) return json({ error: "Choose a picture (JPEG, PNG, HEIC, GIF) or a video (MP4, MOV)." }, { status: 415 });
  const size = Number(request.headers.get("content-length"));
  if (!Number.isInteger(size) || size <= 0) return json({ error: "The file is empty." }, { status: 411 });
  if (size > MAX_BYTES) return json({ error: "The file is larger than 95 MB. Choose a shorter video." }, { status: 413 });
  const key = `posts/${groupID}/${crypto.randomUUID()}.${type[0]}`;
  await env.MEDIA.put(key, request.body, { httpMetadata: { contentType } });
  return json({ key, kind: type[1], contentType }, { status: 201 });
}

/** The attachments a post may carry: this group's own uploads, in order. */
export async function validAttachments(env: Env, groupID: string, raw: unknown): Promise<Attachment[] | Response> {
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw) || raw.length > MAX_ATTACHMENTS) {
    return json({ error: `A post carries up to ${MAX_ATTACHMENTS} pictures and videos.` }, { status: 400 });
  }
  const pattern = new RegExp(`^posts/${groupID}/[0-9a-f-]{36}\\.(jpg|png|webp|heic|gif|mp4|mov)$`);
  const attachments: Attachment[] = [];
  for (const entry of raw) {
    const key = typeof entry === "string" ? entry : (entry as { key?: unknown })?.key;
    if (typeof key !== "string" || !pattern.test(key)) return json({ error: "Unknown attachment" }, { status: 400 });
    const stored = await env.MEDIA?.head(key);
    if (!stored) return json({ error: "An attachment did not finish sending. Add it again." }, { status: 400 });
    const contentType = stored.httpMetadata?.contentType ?? "application/octet-stream";
    attachments.push({ key, kind: contentType.startsWith("video/") ? "video" : "image", contentType });
  }
  return attachments;
}

/** A post's attachments as members get them: signed for a day. */
export async function presentAttachments(env: Env, mediaJSON: unknown) {
  let list: Attachment[] = [];
  try { list = JSON.parse(String(mediaJSON ?? "[]")) as Attachment[]; } catch { list = []; }
  const media = [];
  for (const item of Array.isArray(list) ? list : []) {
    const url = await signedMediaURL(env, item.key);
    if (url) media.push({ url, kind: item.kind, contentType: item.contentType });
  }
  return media;
}
