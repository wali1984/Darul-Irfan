-- Pictures for the Today page: on the Ayah of the Day, Hadith of the Day and
-- Aqwal-e-Sheikh, a daily quote that opens over the page, and announcements.
-- They come from the Super admin's phone or are forwarded to the WhatsApp
-- Business number with a #tag; nothing shows until the Super admin publishes
-- it for a day. Added 2026-10-28.
CREATE TABLE IF NOT EXISTS daily_media (
  id TEXT PRIMARY KEY,
  slot TEXT NOT NULL CHECK(slot IN ('ayah','hadith','aqwal','quote','announcement')),
  -- The local day it is for (YYYY-MM-DD), through end_day for an
  -- announcement that runs several days. NULL until chosen.
  day TEXT,
  end_day TEXT,
  media_key TEXT,
  caption TEXT,
  -- Opens over the Today page once, the first time it is seen that day.
  popup INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','hidden')),
  source TEXT NOT NULL CHECK(source IN ('upload','whatsapp')),
  source_ref TEXT UNIQUE,
  created_by TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  published_by TEXT,
  published_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_daily_media_day ON daily_media(status, day, end_day);
