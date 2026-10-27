-- Admin-issued invite codes, so a member can join a private group without any
-- platform sign-in.
--
-- Sign in with Apple needs the com.apple.developer.applesignin entitlement, and
-- under manual signing the distribution profile must already carry it, which it
-- cannot until the capability is enabled on the App ID. That blocked the whole
-- feature. An invite code needs nothing from Apple, works the same on Android,
-- HarmonyOS and the web, and keeps admission an administrator's decision rather
-- than a platform's.
--
-- The code itself is never stored, only its SHA-256. A leaked database cannot
-- be used to join a group.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS member_invites (
  code_hash TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  -- The admin's own note about who it was issued to; never shown to members.
  label TEXT,
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  -- Single use: once redeemed it can never admit anyone again.
  redeemed_by TEXT REFERENCES members(id) ON DELETE SET NULL,
  redeemed_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_member_invites_group ON member_invites(group_id);
CREATE INDEX IF NOT EXISTS idx_member_invites_open
  ON member_invites(group_id, redeemed_at, expires_at);
