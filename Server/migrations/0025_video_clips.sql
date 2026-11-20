-- Halqah video clips (2026-11-19): an admin of a Halqah marked here can play a
-- YouTube video from a start time to an end time (to skip silent parts), for
-- a session started now and for a zikr time that plays by itself. Only the
-- Halqahs marked here accept and show clip times; every other Halqah is
-- unchanged. First: "North America - Evening Zikr".
ALTER TABLE member_groups ADD COLUMN video_clips INTEGER NOT NULL DEFAULT 0;
