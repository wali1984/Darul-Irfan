-- Admins forward official material to the organisation's WhatsApp Business
-- number and the webhook records it. feed_items.source is constrained by a
-- CHECK, and SQLite cannot alter one, so the table is rebuilt with the new
-- value allowed. Every column, default and constraint below is unchanged
-- except that list.

PRAGMA foreign_keys = OFF;

CREATE TABLE feed_items_rebuilt (
  id TEXT PRIMARY KEY,
  source TEXT NOT NULL CHECK(source IN ('youtube','facebook','website','announcement','event','whatsapp')),
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

INSERT INTO feed_items_rebuilt (
  id, source, kind, title, body, source_url, image_url, video_id, published_at,
  is_featured, is_hidden, publication_status, expires_at, raw_json, updated_at
)
SELECT
  id, source, kind, title, body, source_url, image_url, video_id, published_at,
  is_featured, is_hidden, publication_status, expires_at, raw_json, updated_at
FROM feed_items;

DROP TABLE feed_items;
ALTER TABLE feed_items_rebuilt RENAME TO feed_items;

CREATE INDEX IF NOT EXISTS idx_feed_published ON feed_items(publication_status, is_hidden, published_at DESC, id DESC);

PRAGMA foreign_keys = ON;
