# Darul Irfan — iOS

A native SwiftUI iOS app that combines an accurate, fully offline Azan/prayer-times
experience with a complete companion to **Silsila Naqshbandia Owaisiah** — the
content, publications, lectures, zikr guidance, and Dar-ul-Irfan community
information of [naqshbandiaowaisiah.org](https://www.naqshbandiaowaisiah.org/).

This is not a generic prayer-app clone. The prayer engine is best-in-class
(calculation methods, Hanafi/Shafi Asr, high-latitude rules, manual offsets,
rolling notifications, widgets, Qibla, tracker), and everything around it is
built specifically for the Naqshbandia Owaisiah identity: Asrar-at-Tanzil and
Akram-ut-Tarajum editions in the Quran tab, the Al-Murshid archive and audio
lectures in Media, the verified Method of Zikr and online zikr schedule, and
Dar-ul-Irfan Munara events and contact information. Religious content is never
paraphrased or invented; everything organizational is traced to
`Docs/RESEARCH_NOTES.md`, which was verified against the official website.

## Architecture

### Contracts-first layout

The codebase was written by multiple agents against a fixed set of **keystone
contract files** (see `Docs/CONTRACTS.md` for the authoritative table):

- `DarulIrfanApp/Models/*.swift` — all domain models (Codable, `Sendable`).
- `DarulIrfanApp/Services/ServiceProtocols.swift` — one protocol per service.
- `DarulIrfanApp/Core/Persistence/RepositoryProtocols.swift` — one protocol per repository.
- `DarulIrfanApp/Core/Persistence/AppDatabase.swift` — the schema v1 DDL.
- `DarulIrfanApp/Core/DesignSystem/Theme.swift` + `Components.swift` — the design tokens (`DIColor`, `DISpacing`, `DIRadius`, `DIFont`) and shared components (`DICard`, `DIEmptyState`, button styles).

Feature code depends only on the protocols; concrete types are assembled once
in `DarulIrfanApp/App/AppDependencies.swift` (a plain constructor-injection
container, no framework) and handed to each tab. ViewModels are
`@Observable @MainActor final class`es that receive exactly the protocols they
need, which keeps them unit-testable with mocks.

### Persistence: SQLite + FTS5, not SwiftData

Storage is a single SQLite database wrapped by a small actor
(`Core/Persistence/SQLiteDatabase.swift`) with a thin repository layer on top.
SwiftData was deliberately not used because:

- **FTS5** powers global search across Quran, Library, Media, and Events with
  `unicode61 remove_diacritics 2` tokenization for Arabic/Urdu/English —
  SwiftData has no full-text story.
- The content tables are a **wire contract** with the ingest pipeline
  (`Tools/ContentIngest`) and the seed JSON; explicit column names and
  hand-written migrations keep that contract stable.
- Repositories are `Sendable` values calling one actor — simple to reason
  about under Swift Concurrency, and `AppDatabase.inMemory()` gives free
  hermetic tests.

The store lives in `Application Support/DarulIrfan/darul-irfan.sqlite`
(backed up, not user-visible). Downloads live next to it under `Downloads/`.

### Offline-first

Prayer times are computed entirely on-device by
[adhan-swift](https://github.com/batoulapps/adhan-swift) behind
`PrayerCalculationService` (the only file that imports `Adhan`). Bundled seed
JSON (`DarulIrfanApp/Resources/SeedData/`) is imported idempotently on first
launch by `ContentSyncService`, guarded by a `seed.version` row, so the Quran
index, library catalog, sample lectures, events, 99 Names, duas, and zikr
schedule all work with no network. A remote content manifest endpoint is
documented and polled (`/app/content_manifest.json`), but it is **future
work** — until it exists every fetch quietly resolves to "nothing new."

### Rights model

Content from naqshbandiaowaisiah.org is copyright reserved and permission is
**not yet confirmed**. Every item therefore carries a `rightsStatus`:

- `linkOnly` — metadata + source URL only, no body text. The UI shows the
  metadata with a "Read on naqshbandiaowaisiah.org" link (in-app Safari) and
  streams public MP3 URLs natively (streaming is fine; bulk re-hosting is not).
- `publicDomain` — Quran Arabic text, the Pickthall English translation,
  surah index, 99 Names, Quranic duas.
- `permissionConfirmed` — reserved for after written permission; produced by
  the ingest tool's `--full-text --rights-confirmed` mode.

## Repository layout

```
DarulIrfan-iOS/
├── project.yml                  # XcodeGen project definition (source of truth)
├── CLAUDE.md                    # Build mandate + repo-specific notes
├── Docs/
│   ├── CONTRACTS.md             # Keystone files, conventions, UI rules
│   ├── RESEARCH_NOTES.md        # Verified platform + website facts
│   ├── CONTENT_INGESTION.md     # Pipeline + seed data workflow
│   ├── PRIVACY.md               # Privacy stance + App Privacy answers
│   └── APP_STORE_CHECKLIST.md   # Submission checklist
├── DarulIrfanApp/               # The single app module
│   ├── App/                     # Entry point, RootView (5 tabs), DI container,
│   │                            #   AppState, Info.plist
│   ├── Core/
│   │   ├── DesignSystem/        # Theme tokens + shared components
│   │   ├── Persistence/         # SQLiteDatabase actor, AppDatabase schema,
│   │   │   └── Repositories/    #   SeedBundle loader, repositories
│   │   └── Shared/              # PrayerWidgetSnapshot (compiled into app + widget)
│   ├── Models/                  # Domain models (Prayer, Quran, Content, Media,
│   │                            #   Zikr, Events, Companion, Settings, Search)
│   ├── Services/                # Protocols + live services (calculation, location,
│   │                            #   notifications, audio, downloads, hijri, sync,
│   │                            #   search index, compass heading)
│   ├── Features/                # Prayer, Quran, Library, Media, Zikr, Events,
│   │                            #   Companion, Qibla, Search, Settings, Onboarding, More
│   └── Resources/
│       ├── Audio/               # prayer-chime.wav + azan-clip instructions
│       ├── Images/              # Asset catalog (AppIcon, AccentColor, launch color)
│       └── SeedData/            # 15 JSON files, schema v1
├── Widgets/                     # Widget extension (Next Prayer, Today's Times)
└── Tools/ContentIngest/         # Python ingest pipeline + offline pytest suite
```

## Building with Codemagic (no Mac required)

CI/CD runs on [Codemagic](https://codemagic.io) macOS machines —
`codemagic.yaml` at the repo root defines two workflows:

- **`ios-verify`** — zero configuration: XcodeGen-generates the project,
  builds app + widgets for the simulator (unsigned), runs the unit test suite
  and the ingest pipeline's pytest suite. Triggers on every push/PR. Use this
  as the compile/test loop from a Windows dev machine.
- **`ios-testflight`** — signed App Store archive published to TestFlight on
  `v*` tags. One-time setup required first (documented in comments inside
  `codemagic.yaml`): register both bundle IDs + the App Group in the Apple
  Developer portal, and add an App Store Connect API key in the Codemagic UI.

To connect: push this repo to GitHub/GitLab/Bitbucket, add the app in
Codemagic, and it picks up `codemagic.yaml` automatically.

## Building locally on macOS

This project was **authored on Windows and first compiled in CI** — there is
no Xcode here. The project file is generated from `project.yml` with XcodeGen
on a Mac.

Requirements:

- macOS with **Xcode 16 or newer** (adhan-swift 1.5.0 uses
  swift-tools-version 6.0, which older Xcodes cannot resolve).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.

Steps:

```sh
cd DarulIrfan-iOS
xcodegen generate
open DarulIrfan.xcodeproj
```

Then in Xcode:

1. Select the **DarulIrfan** scheme and an **iOS 17** simulator (e.g. iPhone 15).
2. Set your signing team on the `DarulIrfan` and `DarulIrfanWidgets` targets
   (signing style is Automatic). For device builds, the App Group
   `group.org.naqshbandiaowaisiah.darulirfan` must exist in your developer
   account, or temporarily change the group ID in `project.yml` **and**
   `Core/Shared/PrayerWidgetSnapshot.swift` together.
3. Run.

### First-build triage

The Swift was written conservatively (Swift 5.9, iOS 17 APIs, no force
unwraps, no experimental features) but **blind** — expect the possibility of
minor compiler fix-ups on the first build. A sanity checklist:

- **Scheme**: `DarulIrfan` builds the app + widget extension; tests are wired
  to the same scheme.
- **String Catalog**: `Resources/Localizations/Localizable.xcstrings` ships
  ~650 keys with en + ur units. All UI strings are natural-English literals,
  so any key missing from the catalog still renders readable English.
- **Widget Info.plist**: generated by XcodeGen from the `info:` block in
  `project.yml` — do not look for a checked-in file.
- **Typical blind-authoring issues** to watch for: `@Observable` observation
  scoping, `Sendable` warnings on delegate bridges, and asset catalog
  references (`AppIcon`, `AccentColor`, `LaunchBackground` all exist).

## Testing

Run tests with **Cmd+U** on the `DarulIrfan` scheme.

Current reality, honestly stated:

- **Swift unit tests exist but have never been executed** (authored on
  Windows, no compiler). `DarulIrfanTests/` covers prayer calculations against
  independently derived Karachi/New York values (±4 min), DST boundaries, Asr
  methods, manual offsets, Qibla bearings, Hijri offsets, `DayKey`, all
  repositories on `AppDatabase.inMemory()`, the pure notification plan
  builder (64-cap, styles, pre-reminders), FTS search, and seed-import
  idempotency. `DarulIrfanUITests/SmokeUITests.swift` drives onboarding
  defensively and asserts the tab bar. Treat the first Cmd+U run as part of
  first-build triage.
- **The ingest pipeline is tested.** `Tools/ContentIngest/tests/` is an
  offline pytest suite against saved HTML fixtures covering parser outputs,
  WMA exclusion, idempotent re-runs, curated-merge conflicts, and output
  validation:

  ```sh
  cd Tools/ContentIngest
  pip install -r requirements.txt pytest
  python -m pytest tests -q
  ```

## Legacy Expo prototype

The sibling folder `../Darul-Irfan/` contains an earlier **Expo/React Native
prototype**. It is preserved untouched as reference — its palette, en/ur
locale strings, and service logic informed this native app. Its on-the-fly AI
translation of religious content was deliberately **not** ported (it violates
the "never paraphrase religious content" principle). Do not modify that folder
from this repo.

## Feature status

| Feature | Status |
|---|---|
| Prayer dashboard (next-prayer hero, live countdown, per-prayer alert bells, Ramadan Suhoor/Iftar card, gentle tracker) | Implemented |
| Prayer calculation: methods incl. custom angles, Hanafi/Shafi Asr, high-latitude rules, per-prayer manual offsets, timezone-correct | Implemented (offline, adhan-swift) |
| Monthly timetable with month navigation + share as text | Implemented |
| Notifications: rolling ≤64 window, per-prayer styles (off/silent/default/azan clip), pre-reminders, trailing refresh reminder | Implemented |
| Prayer tracker history (7/30 days, streaks, no shame-based UX) | Implemented |
| Qibla compass with calibration banner + absolute-bearing fallback | Implemented |
| Hijri date (Umm al-Qura) with ±2 day offset + live preview | Implemented |
| Widgets: Next Prayer (small + Lock Screen circular/rectangular/inline), Today's Times (medium), App Group snapshot bridge | Implemented |
| Quran: 114-surah index, ayah reader, translation toggle (Pickthall), tafsir section, bookmarks, continue reading, reader font scale | Implemented — Arabic text bundled for 6 surahs (1, 103, 108, 112, 113, 114); full text pack is a content task |
| Library: category browser, filters, favorites, rights-aware reader, PDF download + native viewer, reading progress | Implemented — bodies are link-only pending permission |
| Media: AlMurshid TV live card, categories, year/month archive, background audio, Lock Screen controls, 0.75–2× speed, queue, lecture bookmarks, continue listening, MP3 downloads | Implemented — catalog is a curated seed sample; YouTube items open externally |
| Zikr: verified Method of Zikr summary, online zikr schedule (Paltalk) with reminders, tasbih counters, daily habit strip | Implemented |
| Events & Dar-ul-Irfan: programs, detail + reminders, add-to-calendar, map/directions, contact actions, announcements | Implemented — add-to-calendar needs an Info.plist key (see APP_STORE_CHECKLIST) |
| Companion: 99 Names of Allah, sourced duas, Islamic days | Implemented |
| Global search (FTS5) across Quran/Library/Media/Events, Urdu/Arabic diacritic-insensitive | Implemented |
| Onboarding (language → location → calculation → notifications) | Implemented |
| Settings (location, calculation, offsets, notifications, appearance, Hijri, storage, privacy) | Implemented |
| Content sync: idempotent seed import + remote manifest polling | Implemented — server endpoint not yet deployed |
| Urdu localization | Structure ready; String Catalog not yet created |
| Swift unit/UI test suites | Not yet written (targets declared) |
| Live Activities (next prayer, Ramadan) | Future |
| Apple Watch app | Future (architecture allows it) |
| Server-hosted content manifest endpoint | Future |

## Content permissions still required

Before these ship, written permission from the content owner
(naqshbandiaowaisiah.org / Dar-ul-Irfan) is required:

1. **Full-text articles, books, and pages** — currently metadata + link only.
2. **Akram-ut-Tarajum translation and Asrar-at-Tanzil / Akram-ut-Tafaseer
   tafsir text** — currently listed as editions with per-surah website links.
3. **A licensed short azan recording** for notification sounds — the app ships
   an original 6-second chime; see `DarulIrfanApp/Resources/Audio/README.md`
   for the drop-in instructions (`azan-short.caf`).
4. **AlMurshid TV stream URL confirmation** — the prototype's
   `stream.darulirfan.org` URL is treated as a default that may be
   unavailable; playback failure is handled gracefully.

Once permission is confirmed, re-run the ingest pipeline with
`--full-text --rights-confirmed` (see `Docs/CONTENT_INGESTION.md`) and refresh
the seed data.
