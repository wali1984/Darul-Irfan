# Privacy

Darul Irfan is built privacy-first. This document states the commitments,
verifies them against the code, and records the exact answers for the App
Store's App Privacy ("nutrition label") questionnaire.

## Stance

- **Location stays on-device.** Prayer times and Qibla bearing are computed
  locally by adhan-swift; coordinates are never sent to any app server
  (there is no app server).
- **No ads. No trackers. No analytics. No accounts.** The only third-party
  code is the adhan-swift calculation library, which performs math and makes
  no network calls. There are no analytics/ad/crash SDKs and no sign-in.
- **Local notifications only.** No push, no APNs registration, no tokens.
- **Data is local and user-deletable.** Everything lives in the app's own
  container and is removed when the app is deleted.

`Features/Settings/PrivacySettingsView.swift` shows this summary to users
inside the app; keep it in sync with this document.

## Complete network surface (verified against code)

The app makes network requests in exactly these cases. None of them carry
user identifiers, device identifiers, location, or any analytics payload.

| # | What | Where in code | Details |
|---|---|---|---|
| 1 | Content manifest poll | `Services/ContentSyncService.swift` | Plain GET of `https://www.naqshbandiaowaisiah.org/app/content_manifest.json` (plus the JSON files it lists) on launch, off the critical path. Uses an **ephemeral** `URLSession` (no persisted cookies/cache), 20 s timeout. The endpoint is not deployed yet; failures resolve silently to "nothing new." Nothing is sent beyond the standard HTTP request. |
| 2 | Streaming public audio | `Services/AudioPlayerService.swift` | `AVPlayer` streams the public lecture MP3 URLs on naqshbandiaowaisiah.org and the AlMurshid TV stream (`stream.darulirfan.org`) when the user presses play. |
| 3 | User-initiated downloads | `Services/DownloadManager.swift` | `URLSession.shared.download(from:)` for PDFs/MP3s the user explicitly downloads; files are stored in the app container. |
| 4 | Apple geocoding | `Services/LocationService.swift` | `CLGeocoder` forward geocoding (manual city search) and reverse geocoding (naming the detected city). This is an **operating-system service operated by Apple**; the query/coordinates are handled under Apple's privacy policy. The app keeps only the resulting city name, coordinates, and timezone. |
| 5 | In-app Safari | `Features/Library/SafariView.swift` | `SFSafariViewController` for "Read on naqshbandiaowaisiah.org" source pages. Runs in Safari's own sandboxed process with Safari's storage — the app cannot see the browsing. |
| 6 | Hand-offs to other apps | `MediaViewModel`, `DarulIrfanCardView`, `AboutView`, `AcknowledgementsView`, `SurahReaderView` | External links opened by explicit user taps: YouTube watch URLs, Apple Maps directions, quran.com, github.com, `mailto:`/`tel:` contact actions. |

There is no other networking. Notably absent: no telemetry endpoint, no
remote logging, no A/B config service, no web views other than the isolated
`SFSafariViewController`.

## App Privacy questionnaire answers

**Answer: Data Not Collected** — for every category.

Justification, per App Store Connect's definitions ("collected" = transmitted
off the device to the developer or partners):

| Category | Answer | Why |
|---|---|---|
| Contact info, Health, Financial, Sensitive info | Not collected | Never requested or stored. |
| **Location** | **Not collected** | Used on-device only (When-In-Use). Never transmitted to the developer or any partner. The Apple geocoding call is an OS service, not developer collection. |
| Contacts, Messages, Photos, Audio (user content) | Not collected | The app records nothing and reads no user content. |
| Browsing / search history | Not collected | In-app search runs against the local SQLite FTS index. |
| Identifiers (user ID, device ID) | Not collected | No accounts, no IDFA/IDFV use, no fingerprinting. |
| Usage data / diagnostics | Not collected | No analytics or crash SDKs. |
| Tracking (ATT) | **No tracking** | Nothing is shared with data brokers or used for cross-app tracking; no App Tracking Transparency prompt is needed. |

If a server-side content manifest is later deployed, standard web server
access logs (IP addresses) on naqshbandiaowaisiah.org would be the only
byproduct; the requests still carry no identifying payload, and "Data Not
Collected" remains accurate under Apple's definitions provided the logs are
not used to identify users.

## Permission purpose strings

| Permission | Info.plist key | Current string / status |
|---|---|---|
| Location (When In Use) | `NSLocationWhenInUseUsageDescription` | Present: *"Darul Irfan uses your location to calculate accurate prayer times and Qibla direction for your area. Your location never leaves your device."* |
| Notifications | — (runtime authorization, no plist key) | Requested during onboarding and from Notification Settings with `.alert/.sound/.badge`; used only for local prayer/zikr/event reminders. |
| Calendar (write-only) | `NSCalendarsWriteOnlyAccessUsageDescription` | Present: *"Darul Irfan adds community events such as the Monthly Ijtema to your calendar only when you ask it to."* Write-only access; the app never reads existing calendar entries. |
| Background audio | `UIBackgroundModes: audio` | Lets user-initiated lecture audio continue with the screen off / app backgrounded; nothing runs in the background otherwise. |

The compass (Qibla) uses `CLLocationManager` heading APIs under the same
When-In-Use location permission; no motion permission is involved.

## Data retention — what is stored, where, and how to delete it

All data is on-device. There is no cloud copy and no account to delete.

| Data | Where | Deletion |
|---|---|---|
| Settings, prayer preferences, manual offsets, notification choices, Hijri offset | `key_value` table in `Application Support/DarulIrfan/darul-irfan.sqlite` | Delete the app |
| Last-known place (city name, coordinates, timezone) — kept so prayer times work offline at launch; **not a location history** (a single value, city-level) | Same settings row | Switch to manual mode or delete the app |
| Quran bookmarks, reading positions, prayer/fasting logs, tasbih counters, zikr habit, favorites, playback progress, playlists | SQLite tables | Individual items are removable in the UI; delete the app for everything |
| Content catalogs + FTS search index (seeded/synced, not personal) | SQLite tables | Delete the app |
| Downloaded PDFs/MP3s | `Application Support/DarulIrfan/Downloads/` | **Settings → Content & Storage → clear all downloads**, per-file removal in item screens, or delete the app |
| Event-reminder toggle flags | `UserDefaults` | Toggle off, or delete the app |
| Prayer widget snapshot (today's times + place name as JSON) | App Group container `group.us.naqshbaniaowaisiah` | Delete the app |

The SQLite store lives in Application Support and is therefore included in
the user's own device/iCloud backup, as users expect; that is the user's
backup, not developer collection.

## Commitments for future changes

- Any analytics, if ever proposed, must be **opt-in**, privacy-preserving,
  and reflected here and in the App Privacy answers first.
- No third-party SDK may be added without re-auditing this document.
- Precise location history must never be stored; the single last-known
  city-level place is the maximum.
