-- The newest Daily Zikr video, played by itself from where the Zikr begins
-- (owner 2026-11-19: "auto pick most recent zikr and its start time ... play
-- 5 seconds before Ameer, Ghazi or Haleem starts the Zikr").
--
-- video_clip_marks: where the Zikr begins and ends in a channel video, found
-- by the detector on amd (or set by hand) and posted through
-- /v1/service/video-marks.
CREATE TABLE IF NOT EXISTS video_clip_marks (
  video_id TEXT PRIMARY KEY,
  start_seconds INTEGER NOT NULL,
  end_seconds INTEGER,
  method TEXT,
  detected_at TEXT NOT NULL
);
-- A zikr time that plays the newest marked Daily Zikr by itself; an admin's
-- own choice (Change video) wins for that day only.
ALTER TABLE group_zikr_sessions ADD COLUMN autoplay_latest INTEGER NOT NULL DEFAULT 0;
ALTER TABLE group_zikr_sessions ADD COLUMN autoplay_override_at TEXT;
