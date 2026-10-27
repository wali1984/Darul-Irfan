-- Rooms recorded by the meeting service. Each finished recording is copied
-- from the service into the app's own R2 bucket and added to the group's
-- recordings, so a zikr led live can be played again. Added 2026-10-27.
PRAGMA foreign_keys = ON;

-- Rooms the server opened, and whether they are recorded.
CREATE TABLE IF NOT EXISTS group_rooms (
  room_id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  session_id TEXT,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  record INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rooms_recent ON group_rooms(record, created_at);

-- Each recording the service made of a room, until it is in our storage.
CREATE TABLE IF NOT EXISTS group_room_recordings (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  room_id TEXT NOT NULL,
  session_id TEXT,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  status TEXT NOT NULL,
  started_at TEXT,
  updated_at TEXT NOT NULL,
  -- The group_recordings row once copied.
  recording_id TEXT,
  error TEXT
);

-- Whether the live session's room is being recorded, shown to everyone in it.
ALTER TABLE group_live ADD COLUMN room_recording INTEGER NOT NULL DEFAULT 0;
