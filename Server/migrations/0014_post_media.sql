-- Pictures and videos an admin attaches to a Halqah post from the phone, up
-- to ten, kept in R2 and shown by signed link to the group only. A JSON list
-- of {key, kind, contentType}. Added 2026-10-28.
ALTER TABLE member_group_posts ADD COLUMN media_json TEXT;
