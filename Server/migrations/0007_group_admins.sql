-- Group admins and adding people from the app. Added 2026-10-27.
--
-- An admin is now an admin of a group, not of every group they belong to:
-- the role moves from the member onto their place in each group. Existing
-- admins keep exactly the groups they had. The super admin stays a property
-- of the member, since it spans every group.
PRAGMA foreign_keys = ON;

ALTER TABLE member_group_members ADD COLUMN role TEXT NOT NULL DEFAULT 'member'
  CHECK(role IN ('member','admin'));
UPDATE member_group_members SET role='admin'
  WHERE member_id IN (SELECT id FROM members WHERE role='admin');
UPDATE members SET role='member' WHERE role='admin';

-- People an admin added by email before they have signed in. Signing in with
-- Apple under that verified email admits them, with the role given here.
-- Claimed rows stay as the record of who added whom.
CREATE TABLE IF NOT EXISTS member_group_grants (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member' CHECK(role IN ('member','admin')),
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL,
  claimed_by TEXT REFERENCES members(id) ON DELETE SET NULL,
  claimed_at TEXT,
  UNIQUE(group_id, email)
);
CREATE INDEX IF NOT EXISTS idx_member_group_grants_open
  ON member_group_grants(email) WHERE claimed_at IS NULL;
