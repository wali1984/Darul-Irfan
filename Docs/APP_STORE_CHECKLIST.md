# App Store submission checklist

Maintainer checklist for taking Darul Irfan from "builds on a Mac" to
"submitted." Work top to bottom; items marked **[blocker]** must be done
before archiving.

## 1. Identifiers & signing (source: `project.yml`)

| Target | Bundle ID |
|---|---|
| App | `us.naqshbaniaowaisiah` |
| Widget extension | `us.naqshbaniaowaisiah.widgets` |
| Watch app | `us.naqshbaniaowaisiah.watchkitapp` |
| Watch complication extension | `us.naqshbaniaowaisiah.watchkitapp.widgets` |
| Unit tests | `us.naqshbaniaowaisiah.tests` |
| UI tests | `us.naqshbaniaowaisiah.uitests` |
| **App Group** (app + widget entitlements) | `group.us.naqshbaniaowaisiah` |

- [ ] **[blocker]** Register the app, widget, Watch app, Watch complication,
      APNs capability, and App Group in the developer portal; enable the App
      Group on every target that declares it.
      If the group ID ever changes, change it in `project.yml` (both
      entitlements blocks) and `Core/Shared/PrayerWidgetSnapshot.swift`
      together — the widget reads its data through that group.
- [ ] Signing style is Automatic (`CODE_SIGN_STYLE: Automatic`); verify the
      team and provisioning profile on all four shipping targets after
      `xcodegen generate`.
- [ ] Version `1.0.0` (build `1`) — bump via `MARKETING_VERSION` /
      `CURRENT_PROJECT_VERSION` in `project.yml`, not in Xcode (the project is
      regenerated).
- [ ] Xcode 16+ required (adhan-swift 1.5.0 is swift-tools-version 6.0).
- [ ] `ITSAppUsesNonExemptEncryption` is already `false` in Info.plist — no
      export-compliance questionnaire on each build.

## 2. Info.plist

- [x] `NSCalendarsWriteOnlyAccessUsageDescription` is present in
      `DarulIrfanApp/App/Info.plist` ("Darul Irfan adds community events such
      as the Monthly Ijtema to your calendar only when you ask it to."), so
      "Add to Calendar" in `EventDetailViewModel` is active. Verify the
      permission flow on device.
- [x] `CFBundleLocalizations` declares `en` and `ur`, and the String Catalog
      (`Resources/Localizations/Localizable.xcstrings`, ~650 keys with Urdu
      units) ships with the app. Spot-check Urdu rendering (Nastaliq, RTL) on
      device before claiming Urdu support in the store listing.

## 3. Assets

- [ ] App icon: a single 1024 px universal icon exists
      (`AppIcon.appiconset/icon-1024.png`). Confirm final artwork — the visual
      identity is *inspired by/attributed to naqshbandiaowaisiah.org*
      (see AcknowledgementsView), so have the owner approve the icon.
- [ ] `AccentColor` and `LaunchBackground` color sets exist; verify dark-mode
      values on device.
- [ ] Screenshots — required device classes given
      `TARGETED_DEVICE_FAMILY: "1,2"` (iPhone **and** iPad):
      - iPhone 6.9" (Pro Max class) — mandatory
      - iPhone 6.5" — optional but recommended
      - iPad Pro 13" — mandatory because the app installs on iPad
      Suggested shot list: Prayer dashboard with next-prayer countdown;
      Monthly timetable; Qibla compass; Quran reader on Surah Al-Fatihah
      (public-domain Arabic + Pickthall); Library article reader (real
      content — permitted, see below); Media lecture list; Next Prayer widget
      on the Home/Lock Screen; Tasbih counter; Settings/privacy screen.
- [ ] **Screenshots may show real site content** — the owner of
      naqshbandiaowaisiah.org granted content permission on 2026-07-10, so
      article/page body text, lecture titles, and publication listings that
      ship in the app may appear in screenshots and marketing imagery. Keep
      the written confirmation on file before submission, and keep religious
      text in screenshots verbatim (no crops that distort meaning).

## 4. App Review notes (paste into the Review Notes field)

- [ ] **Religious content sourcing**: explain that organizational and
      spiritual content comes from naqshbandiaowaisiah.org (the order's
      official site) and is included **with the content owner's permission
      (granted 2026-07-10)**; that Quran Arabic text and the Pickthall
      translation are public domain; that book/magazine/tafsir PDFs download
      from the site's own URLs and audio lectures stream from the site's own
      public URLs (no re-hosting); and that religious text is preserved
      verbatim.
- [ ] **Location**: used only on-device for prayer-time calculation and Qibla
      direction; the app is fully functional with a manually chosen city and
      never transmits location (see `Docs/PRIVACY.md`).
- [ ] **Background audio**: the `audio` background mode is used solely to
      continue user-initiated lecture/recitation playback with Lock Screen
      controls.
- [ ] **No account** is needed; reviewers can exercise every feature
      immediately after onboarding (no demo credentials).
- [ ] Explain the official read-only social feed, non-persistent YouTube
      embed, Paltalk handoff, opt-in APNs alerts, 30-day opt-in MetricKit
      diagnostics, and Cloudflare-hosted public configuration.
- [ ] Age rating: no objectionable content; unrestricted web access is *not*
      embedded (SFSafariViewController opens specific source pages only).

## 5. Licensing & rights checklist

- [ ] **adhan-swift** (Batoul Apps) — MIT License. Attribution ships in-app
      (More → About → Acknowledgements) with a link to the repository. Keep
      the license text available; MIT requires the copyright notice with
      substantial portions of the software.
- [ ] **Pickthall translation** — *The Meaning of the Glorious Koran* (1930),
      public domain; noted in Acknowledgements. No action needed.
- [x] **Quran Arabic text** — complete Quran (all 114 surahs / 6,236 ayat)
      bundled, triple-verified error-free (Docs/QURAN_VERIFICATION.md). Tanzil
      Uthmani, public domain. When
      expanding to the full text, record the exact source edition here.
- [ ] **prayer-chime.wav** — original work created for this app (no rights
      issues); noted in Acknowledgements.
- [x] **Azan notification clip & full azan recordings** — shipped 2026-07-10.
      `azan-short.caf` + `azan-full.mp3` from "Beautiful adhan" (Wikimedia
      Commons, CC0 1.0); `azan-fajr-full.mp3` from Islamic Center Malmö
      (Wikimedia Commons, CC BY 3.0 — attribution shown in Acknowledgements).
      Full source/license records in `DarulIrfanApp/Resources/Audio/README.md`.
      `prayer-chime.wav` remains the fallback.
- [x] **Site content permission status** — **GRANTED 2026-07-10** by the
      owner of naqshbandiaowaisiah.org. Scope: full text and assets from the
      site may ship in the app; the 2026-07-10 ingest
      (`--full-text --rights-confirmed`, seed manifest v2) shipped full
      verbatim text for About pages, Method of Zikr, zikr-joining
      instructions, and articles as `rightsStatus: permissionConfirmed`;
      books/magazines/tafsir PDFs and lecture MP3s remain remote URLs on the
      site (no re-hosting).
- [ ] **[blocker]** Obtain and keep the owner's **written confirmation on
      file** before submission (the 2026-07-10 grant is recorded; archive the
      written record with the submission materials).
- [ ] **Owned live audio** — if an MP3/AAC/HLS endpoint is configured, keep
      written confirmation that it is authorized for public app streaming.
- [ ] **App icon / visual identity** — attributed to naqshbandiaowaisiah.org.
      Content permission was granted 2026-07-10; confirm the icon/visual
      identity is covered by that grant or obtain separate approval.

## 6. Pre-submission QA pass (on a physical device where noted)

**RTL pass** (Settings → Appearance → اردو, and a system-RTL device):
- [ ] Tab bar, navigation, and back gestures mirror correctly.
- [ ] Quran reader: Arabic renders right-aligned; translation block LTR.
- [ ] Urdu lecture titles render in the Nastaliq face inside RTL context
      (Media lists, search results).
- [ ] Global search field, snippets, and domain filters behave in RTL.

**Dynamic Type pass** (largest accessibility sizes):
- [ ] Prayer dashboard hero and time rows wrap without truncation.
- [ ] Settings rows, event cards, and the mini player stay usable.
- [ ] No fixed-height text containers clip (reader, tracker grid, widgets at
      default sizes).

**Offline pass** (Airplane Mode):
- [ ] Prayer times, countdown, monthly timetable, Qibla, Hijri date all work.
- [ ] Seeded Quran surahs, 99 Names, duas, Islamic days, zikr schedule open.
- [ ] Downloaded PDFs/MP3s open and play; non-downloaded media fails with the
      gentle message, not a spinner.
- [ ] Items without stored text (book/magazine entries, any remaining
      link-only item) show metadata and a clearly disabled/erroring web path;
      seeded article/page bodies read fully offline.
- [ ] Launch is clean offline (manifest poll fails silently).

**Notification limit sanity** (device):
- [ ] After onboarding with alerts on, pending requests stay **at or under
      64** (`NotificationScheduler.pendingCount()` is available for a debug
      readout; the plan caps at 63 + 1 trailing refresh reminder).
- [ ] Per-prayer styles behave: off/silent/default/azan-clip (azan-short.caf,
      18 s Linear PCM — under 30 s so it actually plays).
- [ ] Pre-reminders fire N minutes early; timezone change triggers a
      reschedule (toggle timezone in Settings → General → Date & Time).
- [ ] The trailing "Open Darul Irfan to keep prayer alerts fresh" reminder
      exists after the window.

**Widgets** (device):
- [ ] After first launch + onboarding, Next Prayer (small + Lock Screen
      circular/rectangular/inline) and Today's Times (medium) show real data
      (App Group wired correctly); placeholder shows before first snapshot.
- [ ] Countdown text updates without stale timelines across a prayer boundary.
- [ ] Opt-in next-prayer Live Activity starts, updates, and ends when disabled;
      Dynamic Island and Lock Screen layouts do not clip.
- [ ] Watch app receives a phone snapshot, remains useful while disconnected,
      and the next-prayer complication advances across a prayer boundary.

**Official platform**:
- [ ] `/v1/bootstrap`, `/v1/feed`, and `/v1/live` return valid production data;
      the app visibly falls back to cached data during an outage.
- [ ] Facebook token expiry and YouTube quota errors alert operators without
      deleting cached content; manual live override is respected.
- [ ] Official alert opt-in registers an APNs token, topic changes update it,
      opt-out deletes it, and duplicate event IDs do not redeliver.
- [ ] YouTube stays foreground-only; owned HTTPS audio uses native background
      playback; Paltalk opens externally.

**Permissions & flows**:
- [ ] Onboarding: deny location → manual city path works end-to-end.
- [ ] Deny notifications → Settings screen shows status and a path to
      system settings; no repeated prompts.
- [ ] Add to Calendar works after the Info.plist key is added (§2).
- [ ] Audio: interruption (phone call) pauses and resumes correctly;
      Lock Screen controls (play/pause/skip/speed) work; backgrounding saves
      progress ("continue listening" survives relaunch).

**Final**:
- [ ] Archive a Release build; run once from TestFlight before submitting.
- [ ] Re-read `Docs/PRIVACY.md` and disclose optional Device ID/APNs app
      functionality plus optional diagnostics. Do **not** use the obsolete
      blanket “Data Not Collected” answer for this build.
