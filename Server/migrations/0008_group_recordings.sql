-- Recorded zikr: an admin plays a recording to the group instead of leading
-- it live - a file uploaded to the group, or a past zikr from the official
-- YouTube channel. Added 2026-10-27.
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

-- What a live session plays when it is a recording, and when it ends by
-- itself. A recording plays to everyone from the moment it started, so the
-- group hears the same part together.
ALTER TABLE group_live ADD COLUMN recording_id TEXT;
ALTER TABLE group_live ADD COLUMN recorded INTEGER NOT NULL DEFAULT 0;
ALTER TABLE group_live ADD COLUMN ends_at TEXT;
