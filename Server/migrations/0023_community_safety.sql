-- Adult community consent stores no birth date. Reading and anonymous streams
-- do not require community membership or this record.
CREATE TABLE member_community_consent (
  member_id TEXT PRIMARY KEY REFERENCES members(id) ON DELETE CASCADE,
  terms_version TEXT NOT NULL,
  accepted_at TEXT NOT NULL
);

CREATE TABLE community_reports (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  reporter_id TEXT REFERENCES members(id) ON DELETE SET NULL,
  target_kind TEXT NOT NULL CHECK(target_kind IN ('group','post','participant','chat','stage-chat','dua')),
  target_id TEXT NOT NULL,
  reason TEXT NOT NULL,
  details TEXT,
  status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','resolved','dismissed')),
  created_at TEXT NOT NULL,
  reviewer_id TEXT REFERENCES members(id) ON DELETE SET NULL,
  review_note TEXT,
  resolved_at TEXT,
  UNIQUE(reporter_id,id)
);
CREATE INDEX idx_community_reports_queue ON community_reports(status,created_at);
