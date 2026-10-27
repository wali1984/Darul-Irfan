-- The zikr room open with no in-app stream yet: members are offered the room
-- itself to join ("Join Zikr"). Set from the listener's report that it is in
-- the room. Added 2026-10-27.
ALTER TABLE live_broadcasts ADD COLUMN room_open INTEGER NOT NULL DEFAULT 0;
