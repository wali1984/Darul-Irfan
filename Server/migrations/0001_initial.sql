PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS app_config (
  key TEXT PRIMARY KEY,
  value_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS feed_items (
  id TEXT PRIMARY KEY,
  source TEXT NOT NULL CHECK(source IN ('youtube','facebook','website','announcement','event')),
  kind TEXT NOT NULL CHECK(kind IN ('post','video','announcement','event')),
  title TEXT NOT NULL,
  body TEXT,
  source_url TEXT NOT NULL,
  image_url TEXT,
  video_id TEXT,
  published_at TEXT NOT NULL,
  is_featured INTEGER NOT NULL DEFAULT 0,
  is_hidden INTEGER NOT NULL DEFAULT 0,
  publication_status TEXT NOT NULL DEFAULT 'published' CHECK(publication_status IN ('draft','published')),
  expires_at TEXT,
  raw_json TEXT,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_feed_published ON feed_items(publication_status, is_hidden, published_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS live_broadcasts (
  id TEXT PRIMARY KEY,
  source_mode TEXT NOT NULL DEFAULT 'auto' CHECK(source_mode IN ('auto','manual')),
  state TEXT NOT NULL CHECK(state IN ('offline','scheduled','live','ended')),
  title TEXT NOT NULL,
  details TEXT,
  scheduled_start TEXT,
  started_at TEXT,
  ended_at TEXT,
  youtube_video_id TEXT,
  paltalk_url TEXT,
  owned_stream_url TEXT,
  updated_at TEXT NOT NULL,
  source_updated_at TEXT,
  notification_sent_at TEXT
);

CREATE TABLE IF NOT EXISTS zikr_schedules (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  weekdays_json TEXT NOT NULL,
  start_hour INTEGER NOT NULL CHECK(start_hour BETWEEN 0 AND 23),
  start_minute INTEGER NOT NULL CHECK(start_minute BETWEEN 0 AND 59),
  duration_minutes INTEGER NOT NULL CHECK(duration_minutes BETWEEN 1 AND 480),
  timezone TEXT NOT NULL DEFAULT 'Asia/Karachi',
  join_url TEXT,
  instructions TEXT,
  availability_note TEXT,
  is_active INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
  installation_id TEXT PRIMARY KEY,
  apns_token TEXT NOT NULL UNIQUE,
  locale TEXT NOT NULL,
  timezone TEXT NOT NULL,
  topics_json TEXT NOT NULL,
  environment TEXT NOT NULL CHECK(environment IN ('sandbox','production')),
  app_version TEXT NOT NULL,
  created_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS notification_deliveries (
  event_id TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  topic TEXT NOT NULL,
  status TEXT NOT NULL,
  response_code INTEGER,
  created_at TEXT NOT NULL,
  PRIMARY KEY(event_id, installation_id),
  FOREIGN KEY(installation_id) REFERENCES devices(installation_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  actor_email TEXT NOT NULL,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  before_json TEXT,
  after_json TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS diagnostics (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  installation_hash TEXT NOT NULL,
  app_version TEXT NOT NULL,
  os_version TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  received_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_diagnostics_expiry ON diagnostics(expires_at);

CREATE TABLE IF NOT EXISTS source_health (
  source TEXT PRIMARY KEY,
  status TEXT NOT NULL CHECK(status IN ('healthy','degraded')),
  last_success_at TEXT,
  last_attempt_at TEXT NOT NULL,
  consecutive_failures INTEGER NOT NULL DEFAULT 0,
  last_error TEXT
);

CREATE TABLE IF NOT EXISTS rate_limits (
  key_hash TEXT NOT NULL,
  window_start TEXT NOT NULL,
  request_count INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY(key_hash, window_start)
);

CREATE TRIGGER IF NOT EXISTS audit_log_no_update
BEFORE UPDATE ON audit_log BEGIN SELECT RAISE(ABORT, 'audit_log is immutable'); END;
CREATE TRIGGER IF NOT EXISTS audit_log_no_delete
BEFORE DELETE ON audit_log BEGIN SELECT RAISE(ABORT, 'audit_log is immutable'); END;

INSERT OR IGNORE INTO app_config(key, value_json, updated_at) VALUES
  ('featureFlags', '{"officialFeed":true,"liveHub":true,"pushRegistration":true,"diagnostics":true}', datetime('now')),
  ('officialLinks', '{"website":"https://www.naqshbandiaowaisiah.org/","youtube":"https://www.youtube.com/channel/UCefP_tP1ROXmqu2miDVCtCg","facebook":"https://www.facebook.com/oursheikh.official","paltalk":"https://www.paltalk.com"}', datetime('now')),
  ('contentVersions', '{"website":1,"officialFeed":1}', datetime('now')),
  ('minimumSupportedVersion', '"1.2.1"', datetime('now'));

INSERT OR IGNORE INTO live_broadcasts(
  id, state, title, details, paltalk_url, updated_at
) VALUES (
  'official-live', 'offline', 'Live Zikr',
  'Join the official live zikr when a broadcast is available.',
  'https://www.paltalk.com', datetime('now')
);
