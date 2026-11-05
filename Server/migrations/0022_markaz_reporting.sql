-- The Silsila Markaz (owner 2026-11-05): the organisation run centrally, with
-- reports and analytics for super admins and the Markaz's officers.

-- Halqahs placed in the organisation: a region, a country and a city. The
-- Markaz itself is a group of its own kind.
ALTER TABLE member_groups ADD COLUMN kind TEXT NOT NULL DEFAULT 'halqah' CHECK(kind IN ('halqah','markaz'));
ALTER TABLE member_groups ADD COLUMN region TEXT;
ALTER TABLE member_groups ADD COLUMN country_code TEXT;
ALTER TABLE member_groups ADD COLUMN city TEXT;

INSERT OR IGNORE INTO member_groups(id, name, description, updated_at, kind)
  VALUES('silsila-markaz', 'Silsila Markaz', 'Naqshbandia Owaisiah · the Markaz: reports, organisation and coordination', datetime('now'), 'markaz');

-- A session made for the reporting website ('reporting'); the apps' own are NULL.
ALTER TABLE member_sessions ADD COLUMN client TEXT;

-- The website's sign-in: it shows a code, an officer approves it in the app.
CREATE TABLE reporting_links (
  code_hash TEXT PRIMARY KEY,
  poll_hash TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  approved_by TEXT REFERENCES members(id) ON DELETE CASCADE,
  approved_at TEXT,
  consumed_at TEXT
);

-- Notices the Markaz sent to many Halqahs at once.
CREATE TABLE markaz_announcements (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  body TEXT,
  audience TEXT NOT NULL CHECK(audience IN ('members','admins')),
  targets_json TEXT NOT NULL,
  sent_by TEXT NOT NULL,
  sent_at TEXT NOT NULL,
  posted INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_history_started ON group_live_history(started_at);
CREATE INDEX IF NOT EXISTS idx_presence_group ON group_live_presence(group_id, first_seen_at);
CREATE INDEX IF NOT EXISTS idx_cues_created ON group_zikr_cues(created_at);
