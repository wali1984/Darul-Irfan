-- Live zikr pipeline: the cloud listeners that carry the Paltalk room to the
-- stream hub, the hub's inputs, and the broadcast's hub source. Added
-- 2026-10-27. Nothing here is recorded media: only who is up and streaming.
PRAGMA foreign_keys = ON;

-- One row per listener machine, updated by its heartbeat.
CREATE TABLE IF NOT EXISTS live_listeners (
  id TEXT PRIMARY KEY,
  in_room INTEGER NOT NULL DEFAULT 0,
  streaming INTEGER NOT NULL DEFAULT 0,
  input_id TEXT,
  problem TEXT,
  problem_since TEXT,
  last_seen_at TEXT NOT NULL,
  alerted_at TEXT
);

-- The hub's live inputs, as Cloudflare Stream reports them.
CREATE TABLE IF NOT EXISTS live_inputs (
  id TEXT PRIMARY KEY,
  connected INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
);

-- The hub's playback link while a listener is streaming, and whether the
-- channel's own live video is on, so neither source ends the other's broadcast.
ALTER TABLE live_broadcasts ADD COLUMN hub_stream_url TEXT;
ALTER TABLE live_broadcasts ADD COLUMN youtube_live INTEGER NOT NULL DEFAULT 0;
