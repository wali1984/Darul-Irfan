# Privacy

Darul Irfan has no advertising, user account, community posting, or
cross-app tracking. Prayer calculations, precise location, bookmarks, prayer
history, reading/listening progress, tasbih activity, and downloads remain on
the device.

## Network and data inventory

| Purpose | Data sent | Retention and control |
|---|---|---|
| Official feed/live configuration | Normal HTTPS request metadata; no app identifier or location in the request body | Cloudflare edge access logs follow the configured account retention. Cached public content is stored locally and can be removed by deleting the app. |
| Opt-in official alerts | Random installation UUID, APNs token (iPhone) or FCM registration token (Android), locale, timezone, app version, and selected alert topics | Stored in D1 until the user disables alerts, APNs or FCM reports the token invalid, or operations removes stale registrations. `DELETE /v1/devices/{installationID}` is called when alerts are disabled. |
| Android alert delivery | For each alert, the Worker sends its title, text, in-app link and the phone's FCM token to Google's Firebase Cloud Messaging, which delivers it, as Apple's APNs does on iPhone | Google processes it only to deliver the alert. The Firebase Messaging SDK creates a Firebase installation ID on the phone. No Firebase Analytics, Crashlytics or other Firebase product is included. |
| Google sign-in (Android, private groups only) | Google ID token: Google's stable account ID for the app, the name, and the verified email | Stored as the member's Google subject, name and email. The email recognises the silsila's administrators and links the account to an Apple sign-in with the same email; nothing is sent to it. Removed by "Delete my account". |
| Opt-in diagnostics | Hash of the random installation UUID, app/OS version, and Apple MetricKit payload | Stored for 30 days, then deleted by the Worker cron. Precise location, names, email, APNs token, prayer history, bookmarks, and reading activity are rejected/removed. |
| Content catalog | GET requests to the GitHub-hosted content manifest and its JSON payloads | Public catalog data is cached in SQLite; no personal data is sent. |
| YouTube playback | The selected video ID and normal web request metadata go to YouTube through a non-persistent `WKWebView` | The app does not receive YouTube cookies or account data and does not extract/download YouTube streams. Users can instead open YouTube externally. |
| Audio/PDF use | Requested public media/document URL | Files explicitly downloaded by the user stay in the app container. Owned direct audio streams use `AVPlayer`. |
| Apple geocoding | City query or coordinates handled by `CLGeocoder` | Apple operating-system service. The app stores one city-level place, rounded to two decimal coordinates, not location history. |
| Source links and directions | User-selected URL handed to Safari, YouTube, Facebook, Paltalk, Maps, Mail, or Phone | The destination application controls its own data under its privacy policy. |

Facebook and YouTube API credentials are stored only as encrypted Cloudflare
Worker secrets. Social APIs are called by the Worker; secrets never ship in
the Swift binary. Cloudflare Access protects all `/admin*` routes.

## App Store privacy answers

The release must declare the following when the corresponding opt-in features
are enabled in the submitted binary, even though collection is optional:

- **Identifiers / Device ID — App Functionality, not linked to identity, not
  used for tracking:** random installation UUID and APNs token for official
  alert delivery.
- **Diagnostics — App Functionality, not linked to identity, not used for
  tracking:** consent-gated MetricKit diagnostic and performance payloads.
- **Precise/Coarse Location — Not collected by the developer:** used locally
  for prayer/Qibla; never sent to the Darul Irfan service.
- **Usage Data — Not collected:** no product analytics or reading/prayer event
  telemetry.
- **Identifiers / User ID, Name and Email Address — App Functionality,
  LINKED to identity, not used for tracking:** only for members of the private
  regional groups who sign in with Apple. Apple's stable subject for this app
  is the member id; the name Apple discloses on first authorisation lets an
  administrator recognise who to add; the email (which the member may replace
  with Apple's relay address) is used only to recognise the silsila's own
  administrators, and nothing is ever sent to it. Members who join with an
  invitation code give none of these. These are the app's only linked data.
  (Changed 2026-10-27: the email scope is now requested. App Store Connect's
  privacy answers must list Email Address the same way.)
- **Tracking — No:** no IDFA, ATT prompt, data broker sharing, advertising, or
  cross-company tracking.

### Accounts

Nothing outside the private groups needs an account: prayer times, the Quran,
hadith, books and lectures all work without signing in, and a reviewer can
exercise them untouched. **Private groups do create an account**, through Sign
in with Apple on iPhone or Sign in with Google on Android, and such an account
must be deletable from inside the app — "Delete my account" sits on the
groups screen on both platforms and removes the sign-in, the session and every
group membership in one call.

Signing in grants nothing by itself. A new member belongs to no group until an
administrator adds them, and a group the member does not belong to answers
exactly as a group that does not exist, so one region cannot discover another's
existence, let alone read it. Members never post: administrators publish and
members read, so no member's words are ever shown to another member.

Recheck App Store Connect terminology at submission time. Optional collection
still needs disclosure; do not select the older blanket “Data Not Collected”
answer.

## Google Play data safety answers (Android)

Draft for the first Play submission; recheck Play Console's wording then.

- **Device or other IDs — collected, optional, App functionality, not
  shared:** the random installation UUID, the FCM token and the Firebase
  installation ID, only while official alerts or Halqah notices are on.
  Deleted from the server when they are turned off.
- **Name, Email address and User IDs — collected, optional, App
  functionality and Account management, not shared:** only for members of the
  private groups who sign in with Google. Members who join with an invitation
  code give none of these. Deletable in the app with "Delete my account".
- **Audio and Video — collected, optional, App functionality:** the camera
  and microphone stream only inside a Halqah's meeting room, while the member
  is in it; an administrator can record the room into the group's recordings.
- **Photos and Videos — collected, optional:** administrators' uploads to
  their group's posts.
- **Location, App activity, App info and performance — not collected:**
  location stays on the phone; there is no analytics or crash reporting.
- Data is encrypted in transit. Users can ask for deletion in the app.

## Permissions

- Location When In Use: accurate local prayer times and Qibla. Manual city is
  a complete fallback.
- Notifications: local prayer/zikr/event reminders and, only when separately
  enabled, official live/update alerts and Halqah notices (APNs on iPhone,
  FCM on Android).
- Camera and microphone (Android: asked when a Halqah meeting room needs
  them; iPhone: the same through the room's web view): used only inside the
  meeting room.
- Calendar write-only: requested only after “Add to Calendar.” Existing events
  are never read.
- Background audio: user-initiated owned/authorized direct audio only. YouTube
  playback remains foreground and inside the official embed.
- Live Activities: opt-in next-prayer countdown; disabling it ends activities.

## On-device storage and deletion

- SQLite stores settings, city-level place, content caches, search index,
  bookmarks, tracker records, progress, favorites, and remote last-known-good
  feed/live data.
- Downloads live under `Application Support/DarulIrfan/Downloads` and can be
  removed in Content & Storage.
- The App Group stores prayer snapshots for widgets and Watch synchronization.
- Keychain stores only the random installation UUID and current APNs token.
  On Android, the installation UUID and FCM token stay in the app's private
  storage, and a member's session token is encrypted with an Android Keystore
  key in no-backup storage.
- Deleting the app removes local data. Disabling official alerts requests
  deletion of the server registration before removing the local token.

No third-party analytics/crash SDK is included. The Android app includes
Google's Firebase Messaging SDK, for alert delivery only. Any future data category,
vendor, retention change, or account feature requires updating this document,
the in-app privacy screen, server validation, and App Store disclosures first.
