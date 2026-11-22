# Privacy

Darul Irfan has no advertising or cross-app tracking. An account is optional
and used only for Halqahs, where members can chat in live meetings. Prayer
calculations, bookmarks, prayer history, reading/listening progress, tasbih
activity, and downloads remain on the device. Location leaves the device only
as the table below says: for weather, a nearby-masjid search and Apple's
geocoding.

## Network and data inventory

| Purpose | Data sent | Retention and control |
|---|---|---|
| Official feed/live configuration | Normal HTTPS request metadata; no app identifier or location in the request body | Cloudflare edge access logs follow the configured account retention. Cached public content is stored locally and can be removed by deleting the app. |
| Opt-in official alerts | Random installation UUID, APNs token (iPhone) or FCM registration token (Android), locale, timezone, app version, and selected alert topics | Stored in D1 until the user disables alerts, APNs or FCM reports the token invalid, or operations removes stale registrations. `DELETE /v1/devices/{installationID}` is called when alerts are disabled. |
| Android alert delivery | For each alert, the Worker sends its title, text, in-app link and the phone's FCM token to Google's Firebase Cloud Messaging, which delivers it, as Apple's APNs does on iPhone | Google processes it only to deliver the alert. The Firebase Messaging SDK creates a Firebase installation ID on the phone. No Firebase Analytics, Crashlytics or other Firebase product is included. |
| Google sign-in (Android, private groups only) | Google ID token: Google's stable account ID for the app, the name, and the verified email | Stored as the member's Google subject, name and email. The email recognises the silsila's administrators and links the account to an Apple sign-in with the same email; nothing is sent to it. Removed by "Delete my account". |
| Opt-in diagnostics | Hash of the random installation UUID, app/OS version, and Apple MetricKit payload | Stored for 30 days, then deleted by the Worker cron. Precise location, names, email, APNs token, prayer history, bookmarks, and reading activity are rejected/removed. |
| Local weather (when Weather on Today is on; on by default) | The chosen city's approximate coordinates, rounded to a 0.1-degree grid, go to the Worker, which asks Apple Weather | The reading is cached by grid square for 10 minutes; no member or device identifier is sent with it. Switch it off in the location settings. |
| Nearby-masjid search (only when the user starts it) | The chosen place's coordinates go to the Worker, which asks Google Maps' places service. A place found by the phone is first rounded to two decimals; a searched place keeps the coordinates the search returned for it | No content cache is kept and no member identifier is sent. Nothing is searched in the background. |
| Halqahs (optional) | The name, city, country and optional email given to join; membership and attendance; what is said, shown or sent in a live meeting, on the Zikr stage or as a du'a request | A message is shared with the people it is sent to; du'a requests with the admins, and attendance with the admins and the Silsila Markaz's officers; an administrator can record a meeting. An administrator who broadcasts from the Zikr stage sends their voice to Paltalk and YouTube too. Meeting media and chat travel through Cloudflare RealtimeKit. |
| Content catalog | GET requests to the GitHub-hosted content manifest and its JSON payloads | Public catalog data is cached in SQLite; no personal data is sent. |
| YouTube playback | The selected video ID and normal web request metadata go to YouTube through a non-persistent `WKWebView` | The app does not receive YouTube cookies or account data and does not extract/download YouTube streams. Users can instead open YouTube externally. |
| Audio/PDF use | Requested public media/document URL | Files explicitly downloaded by the user stay in the app container. Owned direct audio streams use `AVPlayer`. |
| Bayan transcripts | `GET /v1/transcripts/<mediaId>` for the bayan open in the player, with normal request metadata; no app identifier | Public text; each fetched transcript is kept in the app's cache and removed by Content & Storage › Clear Downloaded Content. |
| Apple geocoding | City query or coordinates handled by `CLGeocoder` | Apple operating-system service. The app stores the place in use, not location history: a place found by the phone is rounded to two decimals; a searched place is stored as Apple returned it. |
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
- **Precise/Coarse Location — recheck before submission:** prayer times and
  Qibla use it on the device, but the weather and nearby-masjid requests above
  send a rounded location to the Darul Irfan service. "Not collected" holds
  only while neither the service nor its logs keep those coordinates longer
  than the request needs.
- **User Content — recheck before submission:** Halqah chat, pictures, files,
  du'a requests and recorded meetings exist. So do the city and country given
  to join Our Sheikh, and attendance: choose their data types then too.
- **Usage Data — Not collected:** no product analytics or reading/prayer event
  telemetry.
- **Identifiers / User ID, Name and Email Address — App Functionality,
  LINKED to identity, not used for tracking:** only for Halqah members,
  Our Sheikh's visitors included. For a member who signs in with Apple,
  Apple's stable subject for this app is the member id; the name
  Apple discloses on first authorisation lets an administrator recognise who
  to add; the email (which the member may replace with Apple's relay address)
  is used only to recognise the silsila's own administrators, and nothing is
  ever sent to it. Members who join with an
  invitation code may give a name but no email; Our Sheikh's visitors give a
  name, city, country and, optionally, an email.
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
existence, let alone read it. Our Sheikh is the exception: anyone may join it.
Only administrators publish group posts. In a live meeting the other
participants see a member's name, the voice and video the member turns on, and
the chat the member sends them; on the Zikr stage they see a member's name,
city and ready-made messages.

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
  functionality and Account management, not shared:** only for Halqah
  members. Google sign-in gives all three; members who join with an invitation
  code may give a name but no email; Our Sheikh's visitors give a name and,
  optionally, an email. Deletable in the app with "Delete my account".
- **Audio and Video — collected, optional, App functionality:** the camera
  and microphone stream only inside a Halqah's meeting room, while the member
  is in it; an administrator can record the room into the group's recordings.
- **Photos and Videos — collected, optional:** administrators' uploads to
  their group's posts.
- **Location — recheck before submission:** the weather and nearby-masjid
  requests send the chosen place's location to the Darul Irfan service, as on
  iPhone.
- **App activity, App info and performance — not collected:** there is no
  analytics or crash reporting.
- Data is encrypted in transit. Users can ask for deletion in the app.

## Permissions

- Location When In Use: accurate local prayer times and Qibla, and local
  weather as the table above says. Manual city is a complete fallback.
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
