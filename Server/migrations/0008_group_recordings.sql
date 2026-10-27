-- Halqah sessions beyond leading live: recordings and past zikr played to the
-- group from one shared clock the admin controls, who is listening, dua
-- requests, a record of past sessions, and a recording that starts itself at
-- the group's zikr time. Added 2026-10-27.
PRAGMA foreign_keys = ON;

-- Recordings uploaded to a group, kept in R2 and reused from session to
-- session. Served to members by signed, expiring link only.
CREATE TABLE IF NOT EXISTS group_recordings (
  id TEXT NOT NULL,
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  media_key TEXT NOT NULL,
  content_type TEXT NOT NULL,
  byte_size INTEGER NOT NULL,
  duration_seconds INTEGER,
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY(group_id, id)
);

-- The session now live. What it plays is a queue of recordings and past
-- videos; everyone plays the same item at the same place, worked out from
-- where playback stood (position_seconds) at a moment (position_at). The
-- admin pauses, moves and changes it; the session stays open until an admin
-- ends it.
ALTER TABLE group_live ADD COLUMN session_id TEXT;
ALTER TABLE group_live ADD COLUMN queue_json TEXT NOT NULL DEFAULT '[]';
ALTER TABLE group_live ADD COLUMN queue_index INTEGER NOT NULL DEFAULT 0;
ALTER TABLE group_live ADD COLUMN position_seconds REAL NOT NULL DEFAULT 0;
ALTER TABLE group_live ADD COLUMN position_at TEXT;
ALTER TABLE group_live ADD COLUMN paused INTEGER NOT NULL DEFAULT 0;
-- A short message from the admin shown on the session ("Dua in five minutes").
ALTER TABLE group_live ADD COLUMN notice TEXT;
ALTER TABLE group_live ADD COLUMN notice_at TEXT;

-- Who has the session open, refreshed every minute by the app.
CREATE TABLE IF NOT EXISTS group_live_presence (
  session_id TEXT NOT NULL,
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  member_id TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  first_seen_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  PRIMARY KEY(session_id, member_id)
);
CREATE INDEX IF NOT EXISTS idx_presence_recent ON group_live_presence(session_id, last_seen_at);

-- Dua requests members send to the group's admins, by name or without it.
CREATE TABLE IF NOT EXISTS group_dua_requests (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  session_id TEXT,
  member_id TEXT REFERENCES members(id) ON DELETE SET NULL,
  show_name INTEGER NOT NULL DEFAULT 1,
  text TEXT NOT NULL,
  created_at TEXT NOT NULL,
  read_at TEXT,
  read_by TEXT
);
CREATE INDEX IF NOT EXISTS idx_dua_group ON group_dua_requests(group_id, created_at);

-- Sessions that have ended, with how many attended.
CREATE TABLE IF NOT EXISTS group_live_history (
  session_id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  title TEXT,
  started_at TEXT NOT NULL,
  started_by TEXT,
  ended_at TEXT NOT NULL,
  ended_by TEXT,
  attendees INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_history_group ON group_live_history(group_id, started_at);

-- What a clock-time zikr plays by itself when no admin has started one: a
-- queue in the same shape as a live session's.
ALTER TABLE group_zikr_sessions ADD COLUMN autoplay_json TEXT;
ALTER TABLE group_zikr_sessions ADD COLUMN last_autoplay_at TEXT;
