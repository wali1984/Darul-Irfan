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
      If the group ID ever changes, change it in `project.yml` (all shipping
      target entitlement blocks) and `Core/Shared/PrayerWidgetSnapshot.swift`
      together — the widget reads its data through that group.
- [ ] Signing style is Automatic (`CODE_SIGN_STYLE: Automatic`); verify the
      team and provisioning profile on all four shipping targets after
      `xcodegen generate`.
- [x] Version `1.9.7` (local build `43`) — bump via `MARKETING_VERSION` /
      `CURRENT_PROJECT_VERSION` in `project.yml`, not in Xcode (the project is
      regenerated). Codemagic replaces the archive build with `BUILD_NUMBER`.
- [ ] Xcode 16+ required (adhan-swift 1.5.0 is swift-tools-version 6.0).
- [ ] `ITSAppUsesNonExemptEncryption` is already `false` in Info.plist — no
      export-compliance questionnaire on each build.
- [x] **[blocker]** `DarulIrfanApp/Resources/PrivacyInfo.xcprivacy` exists and
      declares `CA92.1` for `UserDefaults`, which the app calls in nine places.
      Without it an upload draws Apple's ITMS-91053 notice and can be refused.
      It must keep matching `Docs/PRIVACY.md`; change the two together.

## 2. Info.plist

- [x] `NSCalendarsWriteOnlyAccessUsageDescription` is present in
      `DarulIrfanApp/App/Info.plist` ("Darul Irfan adds community events such
      as the Monthly Ijtema to your calendar only when you ask it to."), so
      "Add to Calendar" in `EventDetailViewModel` is active. Verify the
      permission flow on device.
- [x] `CFBundleLocalizations` declares `en` and `ur`, and the String Catalog
      (`Resources/Localizations/Localizable.xcstrings`, ~700 keys with Urdu
      units) ships with the app. Spot-check Urdu rendering (Nastaliq, RTL) on
      device before claiming Urdu support in the store listing.

## 3. Assets

- [ ] App icon: a single 1024 px universal icon exists
      (`AppIcon.appiconset/icon-1024.png`). Confirm final artwork — the visual
      identity requires organization approval, so retain that approval
      with the release records.
- [ ] `AccentColor` and `LaunchBackground` color sets exist; verify dark-mode
      values on device.
- [ ] Screenshots — required device classes given
      `TARGETED_DEVICE_FAMILY: "1,2"` (iPhone **and** iPad):
      - iPhone 6.9" (Pro Max class) — mandatory
      - iPhone 6.5" — optional but recommended
      - iPad Pro 13" — mandatory because the app installs on iPad
      Suggested shot list: Prayer dashboard with next-prayer countdown;
      Monthly timetable; Qibla compass; Quran reader on Surah Al-Fatihah
      (Arabic + Akram-ut-Tarajum); Library article reader; Media lecture
      list; Next Prayer widget on the Home/Lock Screen; Tasbih counter;
      Settings/privacy screen.
- [ ] **Screenshots may show the app's real content**: article text, lecture
      titles and publication listings. Keep religious text verbatim (no crops
      that distort meaning).

## 4. App Review notes (paste into the Review Notes field)

- [ ] **Religious content**: the content is the Silsila's own.
- [ ] **Location**: prayer times and Qibla are calculated on the device, and
      the app is fully functional with a manually chosen city. When Weather on
      Today is on (it is by default, and has a switch), the chosen city's
      approximate location, rounded to 0.1 degree, is sent to our weather
      service. A nearby-masjid search, only when the user starts it, sends the
      chosen place's location to our service and on to Google Maps' places
      service (see `Docs/PRIVACY.md`).
- [ ] **Background audio**: the `audio` background mode is used solely to
      continue user-initiated lecture/recitation playback with Lock Screen
      controls.
- [ ] **No account** is needed for prayer times, Quran, hadith, books or
      lectures; a reviewer can exercise all of that immediately after
      onboarding with no credentials.
- [ ] **An account is optional and used only for Halqahs**: Sign in with
      Apple, an invitation code, or Our Sheikh's entry with a name, city and
      country. So: in-app account deletion is mandatory (5.1.1(v)) and lives on
      the Halqah screen; the privacy manifest declares User ID, Name and Email
      Address as linked; and the Sign in with Apple capability must be enabled
      on the App ID in the developer portal or signing fails even though the
      build compiles.
- [ ] Tell review that a reviewer who signs in will correctly see **no private
      Halqahs**: membership is granted by an administrator, so an empty list
      is the expected result and not a broken feature. Our Sheikh is open
      through "Join Daily Zikr".
- [ ] **User-generated content: Yes** (guideline 1.2 applies). Live meetings
      have voice, video and chat (text, pictures, files, to everyone or to one
      participant); the Zikr stage has members' ready-made messages and admins'
      own text; members can send du'a requests to admins; only admins publish
      group posts. The moderation that exists: private Halqahs by invitation
      or an admin's approval; admins remove members, posts, stage messages and
      du'a requests; meeting hosts mute, stop a camera and remove a
      participant; stage messages are rate limited.
- [ ] **[blocker]** Guideline 1.2 also asks for filtering, a way to report
      content and a way to block a person. The server accepts content reports,
      but the iPhone app has no report or block control and chat has no
      filter. Settle this before submission, and do not claim them until then.
- [ ] Explain the official read-only social feed, non-persistent YouTube
      embed, live Zikr sound heard inside the app, opt-in APNs alerts, 30-day
      opt-in MetricKit
      diagnostics, and Cloudflare-hosted public configuration.
- [ ] Age rating: answer Yes to user-generated content and to messaging and
      chat, and take the rating calculated from that. There is no objectionable
      content and no unrestricted embedded web browser.
      Official reading is native; the YouTube player is host-limited.

## 5. Private record of the owner's confirmations

These are private records kept with the release. None of them requires anything
on screen, and none is copied into store text, notes or screenshots. The app
has no credits or licences screen (removed 2026-11-21).

That removal does not cover two services (owner's decision, 2026-11-21): the
Apple Weather name, mark and link, and the Google Maps name and provider
buttons, stay as they are on every platform, as those services' terms ask. The
Qur'an reciter is not named in the app: the Listen bar says "Recitation".

- [ ] **adhan-swift** (Batoul Apps) — MIT License. MIT requires the copyright
      notice with substantial portions of the software: keep the license
      text, or the authors' written confirmation that it is not needed, with
      the release records.
- [x] **Akram-ut-Tarajum** — the Silsila's own Urdu and English editions,
      6,236 ayat each, covered by the owner's confirmation of 2026-07-10.
- [x] **Quran Arabic text** — all 114 surahs / 6,236 ayat, never edited. Its
      record is `Docs/QURAN_VERIFICATION.md`.
- [ ] **prayer-chime.wav** — original work created for this app (no rights
      issues).
- [x] **Azan notification clip & full azan recordings** — shipped 2026-07-10.
      `azan-short.caf` + `azan-full.mp3` from "Beautiful adhan" (Wikimedia
      Commons, CC0 1.0); `azan-fajr-full.mp3` from Islamic Center Malmö
      (Wikimedia Commons, CC BY 3.0).
      Full source/license records in `DarulIrfanApp/Resources/Audio/README.md`.
      `prayer-chime.wav` remains the fallback.
- [ ] **Fajr azan (CC BY 3.0)** — the license requires attribution and the app
      shows none: keep the author's written confirmation that no credit in
      the app is needed with the release records before submission.
- [x] **The Silsila's content** — the owner confirmed on 2026-07-10 that its
      full text and assets may ship in the app and appear in screenshots.
- [ ] **[blocker]** Obtain and keep the owner's **written confirmation on
      file** before submission (the 2026-07-10 confirmation is recorded;
      archive the written record with the submission materials).
- [ ] **Owned live audio** — if an MP3/AAC/HLS endpoint is configured, keep
      written confirmation that it is authorized for public app streaming.
- [ ] **App icon / visual identity** — check that the owner's confirmation
      of 2026-07-10 covers it, or record a separate approval.

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
- [ ] Zikr widgets on the Home and Lock Screens show upcoming/live/ended
      transitions, work from cached schedules, localize, and open the Zikr tab.
- [ ] The configurable Devotional Dashboard renders overview/prayer/Quran/zikr
      choices, reflects local progress, and deep-links to the selected area.
- [ ] Next Prayer, Zikr, and Devotional Dashboard widgets receive appropriate
      Smart Stack prominence near prayer and live-zikr boundaries.
- [ ] Countdown text updates without stale timelines across a prayer boundary.
- [ ] Opt-in next-prayer Live Activity starts, updates, and ends when disabled;
      at the prayer boundary it shows the refresh state instead of counting up;
      Dynamic Island and Lock Screen layouts do not clip.
- [ ] Watch app receives prayer and zikr snapshots, remains useful while
      disconnected, shows local prayer/Quran/zikr progress, and its azan/zikr
      timers plus both complications advance correctly across boundaries.

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
