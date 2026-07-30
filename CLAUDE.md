# CLAUDE.md — Darul Irfan iOS App Build Instruction

You are the senior iOS engineer, product architect, and implementation agent for the Darul Irfan iOS app.

Build an iOS app named **Darul Irfan**. The app is an Azan/prayer-time app plus a complete Naqshbandia Owaisiah content companion. Some worktree may already exist, but assume we are starting from scratch. First inspect the repository, preserve useful configuration, then implement the app cleanly using the architecture below. Do not rely on undocumented assumptions from existing code.

Primary source/theme website:
- https://www.naqshbandiaowaisiah.org/

Core product goal:
Darul Irfan must become a best-in-class Islamic iOS app combining accurate Azan/prayer features with the official Naqshbandia Owaisiah identity, content library, multimedia, Quran tafsir/translation, zikr guidance, event updates, and offline-friendly reading/listening.

## Non-negotiable principles

1. **Respect religious content**
   - Preserve Arabic, Urdu, English, and Islamic terminology exactly.
   - Do not paraphrase Quran, tafsir, zikr instructions, bayans, or scholarly content unless a summary field is explicitly marked as a summary.
   - Any AI/Q&A feature must be source-grounded and must cite app content. It must not issue fatwas or invent religious answers.

2. **Respect content rights**
   - The source website says copyright is reserved. Assume the product owner has permission to use the content. If permission is not confirmed, do not bulk-copy copyrighted content into the app; instead build a content index, deep links, and a permission-ready ingestion pipeline.
   - Never scrape competitor app content or copy competitor UI. Competitor research is only for feature benchmarking.

3. **Privacy first**
   - Location data must stay on-device by default.
   - Prayer calculations must work locally without sending coordinates to a server.
   - No ads in the app.
   - No third-party trackers.
   - Analytics, if added, must be opt-in and privacy-preserving.

4. **iOS quality**
   - Native SwiftUI app.
   - Fast launch.
   - Works offline for prayer times and already-downloaded content.
   - Excellent accessibility.
   - Full RTL support for Urdu/Arabic.
   - Beautiful typography and calm spiritual design.

## Target platform and stack

Use:
- SwiftUI
- Swift Concurrency
- SwiftData or SQLite-backed persistence. Prefer SwiftData if project target supports it cleanly; otherwise use SQLite with a small repository layer.
- CoreLocation
- UserNotifications
- WidgetKit
- ActivityKit where appropriate for next-prayer / Ramadan countdown.
- AVFoundation for audio playback.
- MapKit for Dar-ul-Irfan location and directions.
- SafariServices / WKWebView only when native rendering is not feasible.
- Swift Package Manager.

Prayer calculation:
- Prefer `batoulapps/adhan-swift` for prayer time calculations.
- Wrap it behind our own `PrayerCalculationService` so the app is not tightly coupled to a library.
- Support multiple methods and manual overrides.

Minimum deliverables:
- Buildable Xcode project.
- App target.
- Unit tests.
- Clear folder structure.
- README.
- Data ingestion documentation.
- No placeholder screens in the final milestone.

## App identity and design direction

App name:
- Darul Irfan

Brand feel:
- Theme should be inspired by the Naqshbandia Owaisiah website and Dar-ul-Irfan identity.
- Use a calm, reverent Islamic visual style: deep green / emerald, warm cream/off-white, restrained gold accents, soft card surfaces, elegant calligraphy-friendly headings, readable body text.
- Avoid flashy gradients, noisy animations, or commercial “lifestyle app” clutter.
- The interface should feel trustworthy, scholarly, spiritual, and modern.

Typography:
- Arabic: use a high-quality Arabic-capable font available on iOS or bundled only if licensing permits.
- Urdu: ensure proper Nastaliq/Naskh fallback and RTL behavior.
- English: use SF Pro or system fonts.
- All text must scale with Dynamic Type.

Navigation:
Use a tab-based structure:

1. **Prayer**
2. **Quran**
3. **Library**
4. **Media**
5. **More**

The first-run onboarding should request:
- Location permission, with “manual city” fallback.
- Notification permission.
- Preferred calculation method.
- Asr method: Hanafi / Shafi.
- Preferred language: English / Urdu / Arabic where available.
- Content download preference.

## Core feature set

### 1. Prayer / Azan

Build a best-in-class prayer dashboard.

Required:
- Current location detection.
- Manual location search/fallback.
- Prayer times: Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha.
- Next prayer countdown.
- Date display: Gregorian + Hijri.
- Daily and monthly timetable.
- Calculation method selector:
  - Muslim World League
  - ISNA
  - Egyptian
  - Umm al-Qura
  - Karachi / University of Islamic Sciences Karachi
  - Moonsighting Committee
  - Dubai / Gulf / Qatar / Kuwait if supported or implemented
  - Manual custom angle mode
- Asr juristic method:
  - Shafi
  - Hanafi
- High-latitude adjustment options.
- Manual minute offsets per prayer.
- Timezone/DST correctness.
- Prayer notification scheduler.
- Separate notification options per prayer:
  - Off
  - Silent
  - Default sound
  - Short Azan clip
  - Vibration/haptic where allowed
- Pre-prayer reminders:
  - 5 / 10 / 15 / 30 minutes before.
- Full Azan playback in-app.
- iOS notification sound files must be short enough for system notifications; use short bundled clips for background notification and full audio only in app.
- Prayer tracker:
  - Mark prayed
  - Jamaat indicator
  - Qaza/missed indicator
  - Weekly/monthly streaks
  - No shame-based UX; use gentle encouragement.
- Lock Screen / Home Screen widgets:
  - Next prayer + countdown
  - Today’s prayer times
  - Ramadan Suhoor/Iftar where applicable
- Live Activity:
  - Optional next-prayer countdown.
  - Optional Ramadan fasting countdown.
- Qibla compass:
  - Direction to Kaaba
  - Compass calibration state
  - Manual fallback if compass unavailable.
- Apple Watch support can be planned as V2; create architecture to support it later.

Important:
- Prayer calculations must be testable. Write unit tests for known locations and dates.
- Do not call remote APIs for basic prayer times unless the user opts in to a server-backed verification mode.

### 2. Quran

Build a Quran module that can support:
- Arabic Quran text.
- Akram-ut-Tarajum Urdu translation from the website, if permission confirmed.
- Asrar-at-Tanzil English/Urdu tafsir from the website, if permission confirmed.
- Akram-ut-Tafasir Urdu tafsir from the website, if permission confirmed.

Required UI:
- Surah list.
- Ayah reader.
- Translation toggle.
- Tafsir toggle.
- Bookmark ayah.
- Last read position.
- Search across Arabic, Urdu, and English.
- Font size controls.
- Night reading mode.
- Share ayah reference, not copyrighted long text unless allowed.
- Offline downloaded Quran/translation/tafsir packs.

Data model:
- `QuranSurah`
- `QuranAyah`
- `QuranTranslation`
- `QuranTafsir`
- `Bookmark`
- `ReadingProgress`

Do not hardcode Quran content directly inside views. Use structured local database or bundled JSON imported into persistence.

### 3. Naqshbandia Owaisiah library

The website includes many content sections. Build a native Library area that supports:

Categories:
- About Silsila Naqshbandia Owaisiah
- Hazrat Ameer Abdul Qadeer Awan
- Hazrat Ameer Muhammad Akram Awan
- Chain of Transmission / Shajra
- What is Tasawwuf
- Tazkiyah-e-Nafs
- Zikr Allah
- Method of Zikr
- Bai’at
- Articles
- Books
- Booklets
- Sufi poetry
- Training courses
- Important documents
- Al-Murshid magazine archive
- Press releases
- Announcements
- Feature articles
- Aqwal-e-Sheikh

Required:
- Search across all library content.
- Filters by language, category, author, year, media type.
- Offline saving.
- Bookmarking.
- Reading progress.
- Native article reader with RTL support.
- PDF/document viewer for downloadable books/magazines.
- Download manager with storage controls.
- “Source” link back to original website item.
- Last updated date.

Data model:
- `ContentItem`
  - id
  - sourceUrl
  - type: article/book/magazine/document/announcement/event/page
  - title
  - titleUrdu
  - language
  - author
  - category
  - bodyHtml
  - bodyPlainText
  - excerpt
  - publishedAt
  - updatedAt
  - mediaUrls
  - downloadUrls
  - checksum
  - rightsStatus
- `ContentCollection`
- `DownloadedAsset`
- `Favorite`
- `ContentSearchIndex`

### 4. Multimedia

Build a Media section for:
- Audio lectures / bayans
- Video lectures
- Tafseer-e-Quran videos
- AlMurshid TV
- AlMurshid Q&A
- Short clips
- Recommended videos
- Kalam-e-Sheikh

Required:
- Browse by year, month, title, speaker, category.
- Audio streaming.
- Background audio playback for user-initiated audio.
- Lock screen controls.
- Download MP3 for offline listening where permitted.
- WMA links should not be assumed playable on iOS; either convert server-side if rights permit, ignore WMA in the app, or deep-link/download with a warning.
- YouTube content should open in YouTube app or embedded player only if terms allow.
- Playback queue.
- Speed controls: 0.75x, 1x, 1.25x, 1.5x, 2x.
- Bookmarks inside lectures.
- Recently played.
- Continue listening.
- Share source link.

Data model:
- `MediaItem`
  - id
  - title
  - language
  - speaker
  - date
  - duration
  - mediaType: audio/video/youtube
  - sourceUrl
  - streamUrl
  - downloadUrl
  - youtubeId
  - year
  - month
  - category
  - transcriptUrl
  - downloadedAssetId
- `PlaybackProgress`
- `Playlist`

### 5. Online Zikr

Build a Zikr section under More or as a prominent card on Home/Prayer.

Website references:
- Online Zikr
- Method of Zikr
- Paltalk joining instructions
- Daily timings may vary by source page; design this as remotely configurable.

Required:
- Explain Method of Zikr using official content only.
- Show online zikr schedule.
- Add reminders for online zikr.
- Join link / Paltalk instructions.
- “Room available only during session” note where relevant.
- Editable/remotely configurable schedule because website timing pages may change.
- Optional simple personal zikr counter/tasbih.
- Optional daily zikr habit tracker.
- Do not invent spiritual instructions beyond the source content.

### 6. Events and Dar-ul-Irfan

Build an Events / Dar-ul-Irfan section:
- Monthly Ijtema
- Salana Ijtema
- Ramadan Aitekaaf
- Event updates
- Announcements
- Program gallery
- Dar-ul-Irfan Munara location
- Contact information
- Inquiry categories

Required:
- Events list.
- Event detail pages.
- Add to Calendar.
- Reminders.
- Map and directions to Dar-ul-Irfan.
- Contact actions: email, phone, website.
- News/announcement feed.
- Server-configured event updates.

### 7. Daily spiritual companion features

Add differentiating features inspired by the best azan apps, but implemented with Darul Irfan identity:

- Daily ayah / tafsir excerpt from official content.
- Daily quote / Aqwal-e-Sheikh where permitted.
- Prayer habit tracker.
- Dhikr/tasbih counter.
- Ramadan mode:
  - Suhoor/Iftar countdown
  - fasting tracker
  - Ramadan duas/content
  - Aitekaaf information
- Hijri calendar with offset setting.
- Islamic important days.
- Qibla.
- 99 Names of Allah, only with verified content source.
- Duas, only from verified content source.
- No ads.
- No manipulative paywalls.
- Premium/donation support may be added later, but core prayer features must remain free.

### 8. Search

Implement a global search tab/sheet:
- Search Quran, tafsir, articles, books, lectures, events.
- Support English, Urdu, Arabic.
- Normalize Urdu/Arabic forms where reasonable.
- Search should work offline for downloaded/bundled content.
- Results grouped by type.
- Highlight matched terms.

Architecture:
- Create `SearchIndexService`.
- Use local database FTS if available.
- Index title, body, tags, author, date, source URL.

### 9. Content ingestion pipeline

Do not make the app scrape HTML pages live at runtime. Build a maintainable content pipeline.

Preferred architecture:
- A separate script/tool ingests the Naqshbandia Owaisiah site into structured JSON.
- The app consumes:
  - bundled seed JSON for essential content
  - remote manifest JSON for updates
  - downloadable media/document assets

Create a `/Tools/ContentIngest` folder or similar.

Pipeline requirements:
- Start from `https://www.naqshbandiaowaisiah.org/`.
- Crawl only allowed pages.
- Rate-limit requests.
- Preserve source URLs.
- Extract:
  - title
  - language
  - category
  - body HTML
  - plain text
  - media links
  - document links
  - dates
  - author/speaker
  - year/month where present
  - checksum
- Output:
  - `content_manifest.json`
  - `articles.json`
  - `media.json`
  - `quran_tafsir_manifest.json`
  - `events.json`
  - `documents.json`
- Add tests using saved sample HTML fixtures.
- Make ingestion idempotent.
- Store last imported timestamp.
- Never silently overwrite edited curated metadata.

Important:
- If content permission is not confirmed, ingest metadata and source links only.
- If permission is confirmed, ingest full text and assets.
- Keep the data schema stable and versioned.

### 10. App architecture

Use clean modular architecture:

Suggested folders:

- `DarulIrfanApp/`
  - `App/`
  - `Core/`
    - `DesignSystem/`
    - `Navigation/`
    - `Localization/`
    - `Persistence/`
    - `Networking/`
    - `Logging/`
    - `Permissions/`
  - `Features/`
    - `Prayer/`
    - `Quran/`
    - `Library/`
    - `Media/`
    - `Zikr/`
    - `Events/`
    - `Search/`
    - `Settings/`
    - `Onboarding/`
  - `Services/`
    - `PrayerCalculationService`
    - `LocationService`
    - `NotificationScheduler`
    - `QiblaService`
    - `ContentSyncService`
    - `DownloadManager`
    - `AudioPlayerService`
    - `HijriCalendarService`
  - `Models/`
  - `Resources/`
    - `SeedData/`
    - `Audio/`
    - `Images/`
    - `Localizations/`
- `DarulIrfanTests/`
- `DarulIrfanUITests/`
- `Widgets/`
- `Tools/ContentIngest/`
- `Docs/`

Use dependency injection:
- Create protocols for services.
- Provide live and mock implementations.
- Make view models testable.

Pattern:
- SwiftUI views should be thin.
- ViewModels own state and use services.
- Repositories handle persistence.
- Services handle system/API integration.

### 11. Persistence

Use local persistence for:
- User settings
- Prayer preferences
- Manual offsets
- Location preference
- Notification settings
- Bookmarks
- Reading progress
- Prayer tracker
- Downloaded content
- Media playback progress
- Content index

Do not store precise location history unless user explicitly enables it. Default to current location only.

### 12. Notifications

Implement:
- Permission request flow.
- Rolling schedule of prayer notifications.
- Re-schedule when:
  - location changes
  - calculation method changes
  - timezone changes
  - manual offsets change
  - notification settings change
  - app launches after long idle period
- Short bundled Azan clips only.
- Localized notification titles:
  - “Fajr time”
  - “Dhuhr time”
  - etc.
- Optional pre-prayer reminders.
- Zikr reminders.
- Event reminders.
- Ramadan Suhoor/Iftar reminders.

### 13. Localization and RTL

Required languages:
- English
- Urdu

Prepare structure for:
- Arabic
- Punjabi if content is available

Implementation:
- Use `.strings` / String Catalogs.
- Do not concatenate localized strings.
- Use semantic layout where possible.
- Test RTL screens.
- Quran and Urdu content must render correctly.
- Add language switch in Settings independent of system language if feasible.

### 14. Settings

Settings must include:
- Location
- Calculation method
- Asr method
- High-latitude rule
- Manual offsets
- Notification settings per prayer
- Azan sound choice
- Widget preferences
- Language
- Font size
- Theme: System / Light / Dark
- Content downloads
- Clear cache
- Privacy
- About Darul Irfan
- Source website
- Contact
- Acknowledgements / open-source licenses

### 15. App Store readiness

Prepare:
- Privacy nutrition/manifest notes.
- No tracking.
- Clear location permission purpose.
- Clear notification permission purpose.
- Copyright/licensing checklist.
- Open-source license acknowledgements.
- Screenshots plan.
- App description draft.

Do not include copyrighted full content in screenshots unless approved.

### 16. Testing requirements

Write tests for:
- Prayer time calculation wrapper.
- Timezone/DST behavior.
- Asr method differences.
- Manual offsets.
- Notification scheduling.
- Qibla calculation.
- Hijri date offset.
- Content parser fixtures.
- Search indexing.
- Bookmark persistence.
- Media progress persistence.

UI tests:
- Onboarding flow.
- Prayer dashboard.
- Change calculation method.
- Search content.
- Open article.
- Start audio playback.
- Download content.
- RTL layout smoke test.

### 17. Definition of done

A milestone is done only when:
- App builds in Xcode.
- Tests pass.
- No compiler warnings that can be reasonably fixed.
- No placeholder screens.
- No broken navigation.
- Prayer time feature works offline.
- Qibla works or gives graceful fallback.
- Notifications can be scheduled.
- At least sample seed content is visible in Quran/Library/Media.
- Content ingestion pipeline exists with sample fixtures.
- README explains setup, architecture, and commands.
- Privacy and licensing notes are documented.

### 18. Implementation order

Implement in this order:

1. Inspect repo and document current state.
2. Create/clean project structure.
3. Add design system and app shell.
4. Build onboarding.
5. Build prayer calculation service.
6. Build prayer dashboard.
7. Build notification scheduler.
8. Build qibla compass.
9. Build persistence/settings.
10. Build widgets.
11. Build content data models.
12. Build seed content importer.
13. Build Library reader.
14. Build Quran reader shell with sample structured content.
15. Build Media player and sample media list.
16. Build Zikr section.
17. Build Events/Contact section.
18. Build global search.
19. Add offline download manager.
20. Add tests.
21. Polish UI/accessibility/RTL.
22. Document everything.

### 19. Work style

When implementing:
- Make small commits or logical patch groups.
- Explain major architectural choices in README.
- Do not leave TODOs for core functionality.
- Prefer native implementation over webviews.
- Use webviews only as temporary fallback and mark them clearly.
- Keep code simple and maintainable.
- Do not introduce Firebase, analytics SDKs, ad SDKs, or unnecessary third-party dependencies.
- Ask for approval before adding paid APIs or external services.

### 20. Final deliverable expected from Claude

Produce:
- Working iOS project.
- Source code.
- Tests.
- `CLAUDE.md`
- `README.md`
- `Docs/CONTENT_INGESTION.md`
- `Docs/PRIVACY.md`
- `Docs/APP_STORE_CHECKLIST.md`
- Sample seed data.
- A short final summary explaining:
  - what was implemented
  - how to run it
  - what remains for production launch
  - what content permissions are still required

---

## Repository-specific notes (added during implementation)

- This machine is **Windows** — the Xcode project cannot be compiled here. The project is authored to be generated on macOS via **XcodeGen** (`xcodegen generate` against `project.yml`). See `README.md` for exact Mac-side steps.
- The sibling folder `../Darul-Irfan/` contains an earlier **Expo/React Native prototype**. It is preserved untouched as reference; its theme palette, en/ur locale strings, and service logic informed this native app. Do not modify it from this repo.
- Prayer calculation uses `batoulapps/adhan-swift` behind `PrayerCalculationService` (see `project.yml` packages section for the pinned version).
- Content rights: the owner of naqshbandiaowaisiah.org **granted content permission on 2026-07-10** (owner confirmation; keep the written record on file). The bundled seed (manifest v2) now ships **full verbatim text** for site articles and pages with `rightsStatus: permissionConfirmed`, produced by the ingest pipeline's `--full-text --rights-confirmed` mode. Books, Al-Murshid magazine issues, and Asrar-at-Tanzil tafsir booklets remain **metadata + remote PDF URLs** (PDFs are not bundled or re-hosted); lecture MP3s stream from the site's own public URLs. Per-ayah **Akram-ut-Tarajum** translation (English + Urdu, 6236 rows each) is complete and shipped. **Asrar-at-Tanzil English** (`editionID: asrar-at-tanzil-en`): integrated v1.6.9 as one 662 KB per-surah block (crashed large surahs), removed v1.6.10, then **re-integrated properly in v1.6.11 (manifest v13)** from the owner's **per-ayah index** (`OCR/ayah-index/english/*.json`, 6,236 records, 919 commentary groups). Now: **640 per-ayah/range tafsir blocks** (commentary groups merged where they collide on the `(edition,surah,ayah_start)` key; **max block ~34 KB**, mean ~4 KB) + **5,896 per-ayah translations** (Asrar's OWN English, stored as translation rows under the same edition id). The reader's **Asrar tab shows Asrar's own translation** (`translation(for:)` is mode-aware — `asrarTranslationsByAyah`, keyed `asrar-at-tanzil-<lang>`), staying **blank** for the **340 gaps** (335 missing + 5 oversized-blanked; never backfilled from Akram-ut-Tarajum). Gap list: `Asrar-at-Tanzil — English tafsir/asrar_translation_gaps.{html,txt}`. **v1.6.12 (manifest v14)** applied a verse-by-verse mapping verification against Akram-ut-Tarajum (deterministic overlap/neighbour-shift/Arabic-contamination + a 5-agent semantic sweep of all 465 low-overlap/shift verses → 0 real Asrar mismaps): fixes = blank surah **84** (whole-surah source shift, tafsir+translation), remap **33:28-30** (verified print-order 3-cycle), strip Arabic script bleed from 61 translations + 8 tafsir blocks, blank **49:5** (source merged 49:5+49:6). **v1.6.14 (manifest v16)** filled 362 of the 367 translation gaps from the **authoritative source site english-tafseer.com** (the online Asrar-at-Tanzil English): scraped all 558 surah pages, extracted per-ayah translations keyed by the printed "(N:M)" number (robust to the site's broken `<a name>` anchors, e.g. surah 96), stripped -SWT/-AS honorifics, validated every fill against Akram-ut-Tarajum (neighbour-shift) + a 6-reviewer semantic panel. Asrar-en translations now **6,231/6,236** (5 gaps left: 16:123, 23:38, 37:114, 37:127, 80:41 — website extraction artifacts/local misalignment, deliberately left blank not guessed). Scraper + pages live in scratchpad (not committed). Surah 84 translation restored; its **tafsir/commentary remains blanked** (commentary re-extraction from the site's Word-export HTML needs a proper parser — follow-up). Was 5,869 translations / 639 tafsir blocks. **Akram-ut-Tarajum errors found by that audit are now FIXED with owner-supplied text in v1.6.13 (manifest v15):** akram-ut-tarajum-en **7:56** and **7:82** (had each duplicated the previous verse) now carry the owner's correct English; akram-ut-tarajum-ur **75:18-21** were re-split to the owner's correct arrangement (the Urdu column had merged/shifted vs the correct English/canonical — verse 18 now holds full canonical 18, 19=elaboration, 20=love-world, 21=leave-hereafter, re-syncing at 22). Applied byte-exact to the seed AND the source OCR files `Tools/OCR/akram_ut_tarajum_translations.txt` + `..._ocr_training.txt` (gitignored); git diff = exactly 6 seed lines. Akram imports via plain upsert (no delete-then-insert needed — updates in place). **Crash-safety**: reader uses `LazyVStack`, blocks are small, and import does **delete-then-insert** for `asrar-at-tanzil-en` (both `deleteTafsir` + `deleteTranslations`) so no stale full-surah block can orphan under an ayah — even upgrading straight from v1.6.9. Reader is language-strict (no cross-language tafsir fallback). Still outstanding: **Asrar-at-Tanzil Urdu** and **Akram-ut-Tafaseer Urdu** tafsir (only 1 placeholder record each, surah 1). Religious content is never summarized or paraphrased; a clearly-labeled excerpt field is the only exception.
- Azan audio is **shipped** (2026-07-10): `DarulIrfanApp/Resources/Audio/` bundles `azan-short.caf` (18 s Linear PCM notification clip, under the 30 s system limit) and `azan-full.mp3`, both cut from "Beautiful adhan" (Wikimedia Commons, CC0 1.0), plus `azan-fajr-full.mp3` (Islamic Center Malmö, Wikimedia Commons, CC BY 3.0 — attribution ships in-app in Acknowledgements). Full source/license records live in `DarulIrfanApp/Resources/Audio/README.md`; `prayer-chime.wav` remains the fallback sound.
