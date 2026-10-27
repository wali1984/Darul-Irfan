-- Three roles in a Halqah, and the Super admin over all of them. Added 2026-10-27.
--
--   Super admin    only the addresses in SUPER_ADMIN_EMAILS; everything,
--                  in every Halqah, including making Halqahs
--   Administrator  a Halqah's senior role: everything in that Halqah, and the
--                  only role (with the Super admin) that appoints Administrators
--   Admin          everything in their own Halqah except Administrators
--   Member
--
-- SQLite cannot change a CHECK in place, so the three tables holding a Halqah
-- role are rebuilt with 'administrator' allowed, keeping every row (and the
-- invitation rowids the app uses as ids).
PRAGMA defer_foreign_keys = true;

CREATE TABLE member_group_members_new (
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  member_id TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  added_at TEXT NOT NULL,
  added_by TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member' CHECK(role IN ('member','admin','administrator')),
  PRIMARY KEY(group_id, member_id)
);
INSERT INTO member_group_members_new(group_id,member_id,added_at,added_by,role)
  SELECT group_id,member_id,added_at,added_by,role FROM member_group_members;
DROP TABLE member_group_members;
ALTER TABLE member_group_members_new RENAME TO member_group_members;
CREATE INDEX IF NOT EXISTS idx_group_members_member ON member_group_members(member_id);

CREATE TABLE member_group_grants_new (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member' CHECK(role IN ('member','admin','administrator')),
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL,
  claimed_by TEXT REFERENCES members(id) ON DELETE SET NULL,
  claimed_at TEXT,
  UNIQUE(group_id, email)
);
INSERT INTO member_group_grants_new SELECT id,group_id,email,role,created_by,created_at,claimed_by,claimed_at FROM member_group_grants;
DROP TABLE member_group_grants;
ALTER TABLE member_group_grants_new RENAME TO member_group_grants;
CREATE INDEX IF NOT EXISTS idx_member_group_grants_open ON member_group_grants(email) WHERE claimed_at IS NULL;

CREATE TABLE member_invites_new (
  code_hash TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  label TEXT,
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  redeemed_by TEXT REFERENCES members(id) ON DELETE SET NULL,
  redeemed_at TEXT,
  -- A code no longer makes a Super admin: that comes only from the address list.
  grants_role TEXT CHECK(grants_role IS NULL OR grants_role IN ('admin','administrator'))
);
INSERT INTO member_invites_new(rowid,code_hash,group_id,label,created_by,created_at,expires_at,redeemed_by,redeemed_at,grants_role)
  SELECT rowid,code_hash,group_id,label,created_by,created_at,expires_at,redeemed_by,redeemed_at,
    CASE WHEN grants_role='admin' THEN 'admin' ELSE NULL END FROM member_invites;
DROP TABLE member_invites;
ALTER TABLE member_invites_new RENAME TO member_invites;
CREATE INDEX IF NOT EXISTS idx_member_invites_group ON member_invites(group_id);
CREATE INDEX IF NOT EXISTS idx_member_invites_open ON member_invites(group_id, redeemed_at, expires_at);

-- Super admin is the address list alone, never a stored role.
UPDATE members SET role='member' WHERE role<>'member';

-- Who made a Halqah, for the record.
ALTER TABLE member_groups ADD COLUMN created_by TEXT;
