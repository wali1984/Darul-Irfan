-- Android: alerts through Firebase Cloud Messaging, and Google sign-in.
-- Added 2026-10-30.

-- The platform a registered phone receives alerts on. Every phone registered
-- before this is an iPhone, so 'ios' is the default and every existing row,
-- body and query stays as it was. An Android phone's FCM registration token is
-- kept in apns_token, the column for the phone's push token (unique either
-- way): APNs tokens stay lower-cased hex, FCM tokens are kept exactly as sent,
-- since they are case-sensitive.
ALTER TABLE devices ADD COLUMN platform TEXT NOT NULL DEFAULT 'ios'
  CHECK(platform IN ('ios','android'));

-- Google's stable subject for a member who signs in with Google, and the
-- verified email that sign-in last carried. Someone who signed in with Apple
-- and then with Google under the same verified email is one member with both.
-- A member known only through Google carries 'google:<sub>' in apple_subject,
-- which stays unique and non-null, as an invite member carries 'invite:<uuid>'.
ALTER TABLE members ADD COLUMN google_subject TEXT;
ALTER TABLE members ADD COLUMN google_email TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_members_google_subject
  ON members(google_subject) WHERE google_subject IS NOT NULL;
