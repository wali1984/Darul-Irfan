-- Contact email is deliberately separate from verified identity email.
-- It must never be used for account linking, invitations or administrator roles.
CREATE TABLE sheikh_public_profiles (
  member_id TEXT PRIMARY KEY REFERENCES members(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  city TEXT NOT NULL,
  country_code TEXT NOT NULL,
  contact_email TEXT,
  updated_at TEXT NOT NULL
);
