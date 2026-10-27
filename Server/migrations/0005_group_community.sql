-- Community groups: roles, routed feeds, group zikr, live sessions, meetings
-- and group-scoped notifications. Added 2026-10-27.
PRAGMA foreign_keys = ON;

-- A member's role. Admins publish and run sessions in their own groups; the
-- super admin does so in every group. Granted by an admin invitation code or
-- from the admin page, never self-assigned.
ALTER TABLE members ADD COLUMN role TEXT NOT NULL DEFAULT 'member'
  CHECK(role IN ('member','admin','superadmin'));

-- An invitation can grant a role as well as a group.
ALTER TABLE member_invites ADD COLUMN grants_role TEXT
  CHECK(grants_role IS NULL OR grants_role IN ('admin','superadmin'));

-- Posts can now arrive as drafts (forwarded from WhatsApp, or sent from the
-- public feed) and be published by an admin.
ALTER TABLE member_group_posts ADD COLUMN status TEXT NOT NULL DEFAULT 'published'
  CHECK(status IN ('draft','published'));
ALTER TABLE member_group_posts ADD COLUMN source TEXT NOT NULL DEFAULT 'admin'
  CHECK(source IN ('admin','whatsapp','feed'));
-- Where a routed post came from (WhatsApp message id, feed item id), so the
-- same message is never routed twice.
ALTER TABLE member_group_posts ADD COLUMN source_ref TEXT;
-- A picture stored in R2 (forwarded from WhatsApp), served by signed link.
ALTER TABLE member_group_posts ADD COLUMN image_key TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_group_posts_source_ref
  ON member_group_posts(group_id, source_ref) WHERE source_ref IS NOT NULL;

-- Which group a forwarding WhatsApp number posts to by default. A #tag at the
-- start of the message overrides it.
CREATE TABLE IF NOT EXISTS whatsapp_sender_groups (
  sender TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  label TEXT,
  updated_at TEXT NOT NULL,
  updated_by TEXT NOT NULL
);

-- A group's own zikr times. Like the public schedule, a session may follow a
-- prayer at Dar-ul-Irfan (anchor) or keep a fixed clock time.
CREATE TABLE IF NOT EXISTS group_zikr_sessions (
  id TEXT NOT NULL,
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  weekdays_json TEXT NOT NULL DEFAULT '[1,2,3,4,5,6,7]',
  start_hour INTEGER NOT NULL CHECK(start_hour BETWEEN 0 AND 23),
  start_minute INTEGER NOT NULL CHECK(start_minute BETWEEN 0 AND 59),
  time_zone TEXT NOT NULL,
  anchor TEXT CHECK(anchor IS NULL OR anchor IN ('afterIsha','tahajjud')),
  duration_minutes INTEGER NOT NULL DEFAULT 30,
  is_active INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(group_id, id)
);

-- What is happening in a group right now: a live zikr or meeting, watched or
-- joined inside the app. One row per group.
CREATE TABLE IF NOT EXISTS group_live (
  group_id TEXT PRIMARY KEY REFERENCES member_groups(id) ON DELETE CASCADE,
  state TEXT NOT NULL DEFAULT 'offline' CHECK(state IN ('offline','live')),
  kind TEXT NOT NULL DEFAULT 'zikr' CHECK(kind IN ('zikr','meeting')),
  title TEXT,
  -- A live video stream of the zikr, when there is one.
  video_id TEXT,
  -- The in-app room members join together, when there is one.
  room_id TEXT,
  started_at TEXT,
  started_by TEXT,
  updated_at TEXT NOT NULL
);

-- Scheduled meetings, announced ahead and joined in the app.
CREATE TABLE IF NOT EXISTS group_meetings (
  id TEXT NOT NULL,
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  starts_at TEXT NOT NULL,
  duration_minutes INTEGER NOT NULL DEFAULT 60,
  room_id TEXT,
  created_by TEXT NOT NULL,
  is_cancelled INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(group_id, id)
);
CREATE INDEX IF NOT EXISTS idx_group_meetings_upcoming ON group_meetings(group_id, starts_at);

-- Which push installation belongs to which member, so a group's notice goes
-- to that group's members and nobody else.
CREATE TABLE IF NOT EXISTS member_devices (
  member_id TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  installation_id TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(member_id, installation_id)
);
