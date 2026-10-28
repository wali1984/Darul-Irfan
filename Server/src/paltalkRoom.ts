import type { Env, PaltalkRoomStatus } from "./contracts";

// Whether the Silsila's Paltalk room is open, from Paltalk's own public room
// directory - the list paltalk.com shows of rooms open right now, with how
// many are in each. Nothing is installed or signed in anywhere: the server
// reads it every minute, and the live state, notifications and the app's
// Paltalk status follow from it.

const DIRECTORY = "https://www.paltalk.com/g2/api/group/home/searchRooms/";

interface DirectoryRoom {
  id?: number;
  groupId?: number;
  groupName?: string | null;
  online?: boolean;
  liveMemberCount?: number;
}

function roomName(env: Env): string {
  return (env.PALTALK_ROOM ?? "oursheikh").trim().toLowerCase();
}

/** The room as the directory lists it, or null when it is not open. */
async function directory(query: string): Promise<DirectoryRoom[]> {
  const response = await fetch(`${DIRECTORY}${query}`, {
    headers: { accept: "application/json", "user-agent": "DarulIrfan/1.0 (+https://naqshbandiaowaisiah.org)" },
  });
  if (!response.ok) throw new Error(`Paltalk directory ${response.status}`);
  const payload = await response.json<{ data?: { topRoomDetails?: DirectoryRoom[] } }>();
  return payload.data?.topRoomDetails ?? [];
}

export async function findOpenRoom(env: Env): Promise<DirectoryRoom | null> {
  const name = roomName(env);
  const id = Number(env.PALTALK_GROUP_ID ?? 463712);
  // The room itself - by its name, or by its group number
  // (paltalk://group/463712) - not another whose name merely contains it.
  const isOurs = (room: DirectoryRoom) => room.online === true
    && ((room.groupName ?? "").trim().toLowerCase() === name || room.id === id || room.groupId === id);
  const found = (await directory(`?keyword=${encodeURIComponent(name)}`)).find(isOurs);
  if (found) return found;
  // A name Paltalk lists differently still matches by number among the open rooms.
  return (await directory("")).find(isOurs) ?? null;
}

export async function paltalkRoomStatus(env: Env): Promise<PaltalkRoomStatus | null> {
  const row = await env.DB.prepare("SELECT value_json FROM app_config WHERE key='paltalkRoom'").first<{ value_json: string }>();
  if (!row) return null;
  try {
    return JSON.parse(row.value_json) as PaltalkRoomStatus;
  } catch {
    return null;
  }
}

/** Reads the directory and records the room's state; returns it. */
export async function refreshPaltalkRoom(env: Env, now = new Date()): Promise<PaltalkRoomStatus> {
  const room = await findOpenRoom(env);
  const prior = await paltalkRoomStatus(env);
  const status: PaltalkRoomStatus = room
    ? { online: true, listeners: room.liveMemberCount ?? 0, since: prior?.online ? prior.since : now.toISOString(),
        checkedAt: now.toISOString() }
    : { online: false, listeners: 0, since: prior?.online ? undefined : prior?.since, checkedAt: now.toISOString() };
  await env.DB.prepare(`INSERT INTO app_config(key,value_json,updated_at) VALUES('paltalkRoom',?,?)
    ON CONFLICT(key) DO UPDATE SET value_json=excluded.value_json,updated_at=excluded.updated_at`)
    .bind(JSON.stringify(status), status.checkedAt).run();
  return status;
}
