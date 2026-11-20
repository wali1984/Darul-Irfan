-- A simple Halqah page (owner 2026-11-19, for "North America - Evening
-- Zikr"): the page shows only its zikr times and, while a session plays, its
-- video on the page (no stage); admins get only People and Add a zikr time.
-- Every other Halqah keeps the full page.
ALTER TABLE member_groups ADD COLUMN simple_page INTEGER NOT NULL DEFAULT 0;
