-- The Darul Irfan desktop app (Windows and macOS, 2026-11-09): the computer
-- shows a code, the member approves it in the app on their phone, and the
-- computer gets a session of its own for the same account and role.
--
-- The reporting website already signs in this way, so its table holds both
-- kinds of link; existing rows are the website's.
ALTER TABLE reporting_links ADD COLUMN client TEXT NOT NULL DEFAULT 'reporting' CHECK(client IN ('reporting','desktop'));
ALTER TABLE reporting_links ADD COLUMN device_name TEXT;
ALTER TABLE reporting_links ADD COLUMN platform TEXT;

-- A desktop session ('desktop' in member_sessions.client) carries the computer's
-- name and platform, for the phone's list of signed-in computers.
ALTER TABLE member_sessions ADD COLUMN device_name TEXT;
ALTER TABLE member_sessions ADD COLUMN platform TEXT;
CREATE INDEX IF NOT EXISTS idx_member_sessions_client ON member_sessions(member_id, client);
