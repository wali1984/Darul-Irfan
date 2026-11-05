-- The live relay starts a Zikr by itself; when the dua begins it sets this, and
-- the session ends on its own five minutes later (owner 2026-11-05).
ALTER TABLE group_live ADD COLUMN auto_end_at TEXT;
