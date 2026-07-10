# App Store submission checklist

Maintainer checklist for taking Darul Irfan from "builds on a Mac" to
"submitted." Work top to bottom; items marked **[blocker]** must be done
before archiving.

## 1. Identifiers & signing (source: `project.yml`)

| Target | Bundle ID |
|---|---|
| App | `org.naqshbandiaowaisiah.darulirfan` |
| Widget extension | `org.naqshbandiaowaisiah.darulirfan.widgets` |
| Unit tests | `org.naqshbandiaowaisiah.darulirfan.tests` |
| UI tests | `org.naqshbandiaowaisiah.darulirfan.uitests` |
| **App Group** (app + widget entitlements) | `group.org.naqshbandiaowaisiah.darulirfan` |

- [ ] **[blocker]** Register both app IDs and the App Group in the developer
      portal; the App Group must be enabled on the app **and** the widget ID.
      If the group ID ever changes, change it in `project.yml` (both
      entitlements blocks) and `Core/Shared/PrayerWidgetSnapshot.swift`
      together — the widget reads its data through that group.
- [ ] Signing style is Automatic (`CODE_SIGN_STYLE: Automatic`); set the team
      on the `DarulIrfan` and `DarulIrfanWidgets` targets after `xcodegen generate`.
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
      Suggested shot list (all safe on rights): Prayer dashboard with
      next-prayer countdown; Monthly timetable; Qibla compass; Quran reader on
      Surah Al-Fatihah (public-domain Arabic + Pickthall); Next Prayer widget
      on the Home/Lock Screen; Tasbih counter; Settings/privacy screen.
- [ ] **What may NOT appear in screenshots** until content permission is
      confirmed: article/tafsir/book body text, magazine or book page images,
      and any screen presenting copyrighted site content as if it ships in
      the app. Library/Media screens show only metadata (titles, dates,
      links) — legally these are link-only references, but to stay
      conservative get the owner's written OK before featuring
      lecture/publication titles in marketing imagery.

## 4. App Review notes (paste into the Review Notes field)

- [ ] **Religious content sourcing**: explain that organizational and
      spiritual content comes from naqshbandiaowaisiah.org (the order's
      official site); that copyrighted items ship as *metadata + link to the
      original page* pending the owner's written permission; that Quran
      Arabic text and the Pickthall translation are public domain; and that
      audio lectures stream from the site's own public URLs (no re-hosting).
- [ ] **Location**: used only on-device for prayer-time calculation and Qibla
      direction; the app is fully functional with a manually chosen city and
      never transmits location (see `Docs/PRIVACY.md`).
- [ ] **Background audio**: the `audio` background mode is used solely to
      continue user-initiated lecture/recitation playback with Lock Screen
      controls.
- [ ] **No account** is needed; reviewers can exercise every feature
      immediately after onboarding (no demo credentials).
- [ ] Age rating: no objectionable content; unrestricted web access is *not*
      embedded (SFSafariViewController opens specific source pages only).

## 5. Licensing & rights checklist

- [ ] **adhan-swift** (Batoul Apps) — MIT License. Attribution ships in-app
      (More → About → Acknowledgements) with a link to the repository. Keep
      the license text available; MIT requires the copyright notice with
      substantial portions of the software.
- [ ] **Pickthall translation** — *The Meaning of the Glorious Koran* (1930),
      public domain; noted in Acknowledgements. No action needed.
- [ ] **Quran Arabic text** — public domain; bundled for 6 surahs. When
      expanding to the full text, record the exact source edition here.
- [ ] **prayer-chime.wav** — original work created for this app (no rights
      issues); noted in Acknowledgements.
- [ ] **Azan notification clip** — not yet shipped. Requires a licensed or
      permitted recording; conversion instructions in
      `DarulIrfanApp/Resources/Audio/README.md` (`azan-short.caf`, IMA4,
      under 30 s). Until then the "Azan Clip" alert style plays the chime.
- [ ] **Site content permission status** — **not yet confirmed.** All site
      content is `rightsStatus: linkOnly`. After written permission: re-run
      the ingest pipeline with `--full-text --rights-confirmed`, refresh the
      seed data (see `Docs/CONTENT_INGESTION.md`), and update this line with
      the permission date and scope.
- [ ] **AlMurshid TV stream** (`stream.darulirfan.org`) — confirm with the
      owner that the URL is correct and intended for public app use.
- [ ] **App icon / visual identity** — attributed to naqshbandiaowaisiah.org;
      obtain approval alongside the content permission.

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
- [ ] Link-only items show metadata and a clearly disabled/erroring web path.
- [ ] Launch is clean offline (manifest poll fails silently).

**Notification limit sanity** (device):
- [ ] After onboarding with alerts on, pending requests stay **at or under
      64** (`NotificationScheduler.pendingCount()` is available for a debug
      readout; the plan caps at 63 + 1 trailing refresh reminder).
- [ ] Per-prayer styles behave: off/silent/default/azan-clip (chime), and the
      chime is under 30 s so it actually plays.
- [ ] Pre-reminders fire N minutes early; timezone change triggers a
      reschedule (toggle timezone in Settings → General → Date & Time).
- [ ] The trailing "Open Darul Irfan to keep prayer alerts fresh" reminder
      exists after the window.

**Widgets** (device):
- [ ] After first launch + onboarding, Next Prayer (small + Lock Screen
      circular/rectangular/inline) and Today's Times (medium) show real data
      (App Group wired correctly); placeholder shows before first snapshot.
- [ ] Countdown text updates without stale timelines across a prayer boundary.

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
- [ ] Re-read `Docs/PRIVACY.md` against any last-minute changes and fill the
      App Privacy questionnaire with **Data Not Collected**.
