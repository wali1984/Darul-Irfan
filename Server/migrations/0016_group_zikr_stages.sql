-- Custom stages belong to the existing Halqa, not to a device or global live relay.
CREATE TABLE group_zikr_stages (
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  title TEXT NOT NULL,
  title_ur TEXT,
  created_by TEXT NOT NULL REFERENCES members(id),
  created_at TEXT NOT NULL,
  PRIMARY KEY(group_id, id)
);

-- The ordered chat timeline and pending delivery survive app and worker restarts.
CREATE TABLE group_zikr_cues (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  event_id TEXT NOT NULL,
  stage_id TEXT NOT NULL,
  title TEXT NOT NULL,
  title_ur TEXT,
  author_id TEXT NOT NULL REFERENCES members(id),
  created_at TEXT NOT NULL,
  notification_lease_until TEXT,
  notification_state TEXT NOT NULL DEFAULT 'pending' CHECK(notification_state IN ('pending','complete','expired')),
  UNIQUE(group_id,event_id)
);
CREATE INDEX idx_group_zikr_cues_timeline ON group_zikr_cues(group_id,sequence);
