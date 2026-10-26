-- Private regional groups: members sign in with Apple, admins publish, members
-- read. There is deliberately no member-to-member messaging, so nothing a
-- member writes is ever shown to another member.
--
-- Isolation is the security property of this schema: a post belongs to exactly
-- one group, and reading it requires a row in group_members for that group.
-- Nothing here is reachable from the public /v1/feed.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS members (
  id TEXT PRIMARY KEY,
  -- Apple's stable subject for this user and this app. Unique so a second
  -- sign-in is recognised as the same person rather than creating a twin.
  apple_subject TEXT NOT NULL UNIQUE,
  -- Apple only discloses a name on the very first authorisation, and the email
  -- may be a private relay address. Both are optional on purpose.
  display_name TEXT,
  email TEXT,
  created_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);

-- Opaque bearer tokens. Only the hash is stored, so the table is useless to
-- anyone who reads it.
CREATE TABLE IF NOT EXISTS member_sessions (
  token_hash TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_member_sessions_member ON member_sessions(member_id);
CREATE INDEX IF NOT EXISTS idx_member_sessions_expiry ON member_sessions(expires_at);

CREATE TABLE IF NOT EXISTS member_groups (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  -- Meetings are hosted elsewhere (Paltalk, Zoom, Jitsi); the app surfaces the
  -- link to that group's members rather than running conferencing itself.
  meeting_url TEXT,
  meeting_note TEXT,
  is_active INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS member_group_members (
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  member_id TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  added_at TEXT NOT NULL,
  added_by TEXT NOT NULL,
  PRIMARY KEY(group_id, member_id)
);
CREATE INDEX IF NOT EXISTS idx_group_members_member ON member_group_members(member_id);

CREATE TABLE IF NOT EXISTS member_group_posts (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  -- 'zikr' carries a recorded YouTube zikr chosen by an admin; 'announcement'
  -- is text, optionally with a link.
  kind TEXT NOT NULL CHECK(kind IN ('announcement','zikr')),
  title TEXT NOT NULL,
  body TEXT,
  youtube_video_id TEXT,
  link_url TEXT,
  published_at TEXT NOT NULL,
  -- The staff member who published it, for the audit trail.
  author_email TEXT NOT NULL,
  is_hidden INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_group_posts_reading
  ON member_group_posts(group_id, is_hidden, published_at DESC, id DESC);

INSERT OR IGNORE INTO member_groups(id, name, description, updated_at) VALUES
  ('darul-irfan', 'Darul Irfan', 'Naqshbandia Owaisiah — Darul Irfan', datetime('now')),
  ('usa', 'United States', 'Naqshbandia Owaisiah — United States', datetime('now')),
  ('canada', 'Canada', 'Naqshbandia Owaisiah — Canada', datetime('now'));
