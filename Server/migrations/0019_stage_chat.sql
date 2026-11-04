-- The live Zikr stage's chat for Our Sheikh (2026-11-03). Members send only the
-- ready-made messages (preset_id); admins may also type (body). Rows are kept;
-- an admin removing one sets hidden_at.
CREATE TABLE group_stage_messages (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id TEXT NOT NULL REFERENCES member_groups(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  author_id TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  preset_id TEXT,
  body TEXT,
  created_at TEXT NOT NULL,
  hidden_at TEXT,
  CHECK ((preset_id IS NULL) <> (body IS NULL)),
  UNIQUE(group_id,id)
);
CREATE INDEX idx_group_stage_messages_timeline ON group_stage_messages(group_id,sequence);
