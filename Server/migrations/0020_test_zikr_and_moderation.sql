-- A test Zikr: only the Halqah's admins see it and nobody is notified.
ALTER TABLE group_live ADD COLUMN is_test INTEGER NOT NULL DEFAULT 0;
ALTER TABLE group_live_history ADD COLUMN is_test INTEGER NOT NULL DEFAULT 0;
-- Admins take a stage announcement off the stage, or a dua request off the list.
ALTER TABLE group_zikr_cues ADD COLUMN hidden_at TEXT;
ALTER TABLE group_dua_requests ADD COLUMN removed_at TEXT;
