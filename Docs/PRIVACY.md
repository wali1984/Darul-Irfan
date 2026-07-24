# Privacy

Darul Irfan has no advertising, user account, community posting, or
cross-app tracking. Prayer calculations, precise location, bookmarks, prayer
history, reading/listening progress, tasbih activity, and downloads remain on
the device.

## Network and data inventory

| Purpose | Data sent | Retention and control |
|---|---|---|
| Official feed/live configuration | Normal HTTPS request metadata; no app identifier or location in the request body | Cloudflare edge access logs follow the configured account retention. Cached public content is stored locally and can be removed by deleting the app. |
| Opt-in official alerts | Random installation UUID, APNs token, locale, timezone, app version, and selected alert topics | Stored in D1 until the user disables alerts, APNs reports the token invalid, or operations removes stale registrations. `DELETE /v1/devices/{installationID}` is called when alerts are disabled. |
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
- **Tracking — No:** no IDFA, ATT prompt, data broker sharing, advertising, or
  cross-company tracking.

Recheck App Store Connect terminology at submission time. Optional collection
still needs disclosure; do not select the older blanket “Data Not Collected”
answer.

## Permissions

- Location When In Use: accurate local prayer times and Qibla. Manual city is
  a complete fallback.
- Notifications: local prayer/zikr/event reminders and, only when separately
  enabled, official APNs live/update alerts.
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
- Deleting the app removes local data. Disabling official alerts requests
  deletion of the server registration before removing the local token.

No third-party analytics/crash SDK is included. Any future data category,
vendor, retention change, or account feature requires updating this document,
the in-app privacy screen, server validation, and App Store disclosures first.
