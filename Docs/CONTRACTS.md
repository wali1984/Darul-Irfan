# Implementation contracts & conventions

Read this before writing any Swift file. The keystone files listed below are
**already written and authoritative** — code against them exactly; do not
redefine their types, do not "improve" their signatures. If something seems
missing, extend your own feature files, never the contracts.

## Keystone files (read them, never rewrite them)

| File | Contains |
|---|---|
| `DarulIrfanApp/Models/*.swift` | All domain models: `Prayer`, `PrayerDaySchedule`, `NextPrayerInfo`, `PlaceCoordinate`, `PrayerCalculationPreferences`, `PrayerNotificationPreferences`, `PrayerLogEntry`, Quran/Content/Media/Zikr/Event/Companion/Settings models, `SearchResult` |
| `DarulIrfanApp/Services/ServiceProtocols.swift` | Every service protocol: `PrayerCalculationServicing`, `QiblaServicing`, `LocationServicing`, `HeadingProviding`, `NotificationScheduling`, `HijriCalendarServicing`, `AudioPlayerServicing` + `AudioPlayableItem`, `DownloadManaging`, `ContentSyncServicing`, `SearchIndexServicing`, `SettingsStoring` |
| `DarulIrfanApp/Core/Persistence/SQLiteDatabase.swift` | `SQLiteDatabase` actor: `execute(_:_:)`, `query(_:_:) -> [SQLRow]`, `executeBatch(_:)`, `executeScript(_:)`; `SQLValue` (`.text/.integer/.real/.null/.blob` + helpers `.int/.bool/.date/.optionalText/.optionalDate/.optionalInt/.optionalReal`); `SQLRow` accessors `int/int64/double/text/bool/date/blob` |
| `DarulIrfanApp/Core/Persistence/AppDatabase.swift` | Store owner + additive schema migrations (currently v2) — column names are law; JSON-array columns end in `_json` |
| `DarulIrfanApp/Models/OfficialPlatformModels.swift` | Versioned bootstrap, normalized feed, live-source, remote schedule, push preference, and feature-flag contracts shared conceptually with `Server/src/contracts.ts` |
| `DarulIrfanApp/Services/OfficialPlatformService.swift` | ETag/last-known-good client for the official Worker; anonymous APNs registration and consented diagnostics transport |
| `DarulIrfanApp/Core/Persistence/RepositoryProtocols.swift` | All repository protocols + `DayKey` helper |
| `DarulIrfanApp/Core/DesignSystem/Theme.swift` | `DIColor`, `DISpacing`, `DIRadius`, `DIFont` tokens |
| `DarulIrfanApp/Core/DesignSystem/Components.swift` | `DICard`, `DISectionHeader`, `DIPrimaryButtonStyle`, `DISecondaryButtonStyle`, `DIEmptyState`, `DIPillBadge`, `.diScreenBackground()` |
| `DarulIrfanApp/App/AppDependencies.swift` | DI container — its `live()` names the concrete types each agent must provide (e.g. `QuranRepository(database:)`, `LocationService()`, `NotificationScheduler()`, `AudioPlayerService(mediaRepository:)`, `DownloadManager(downloadsRepository:)`, `HijriCalendarService()`, `SettingsStore(database:)`, `SearchIndexService(database:quranRepository:contentRepository:mediaRepository:eventsRepository:)`, `ContentSyncService(quranRepository:contentRepository:mediaRepository:eventsRepository:database:searchIndex:)`) |
| `DarulIrfanApp/App/AppState.swift` | `@Observable @MainActor` session state: `settings`, `activePlace`, `updateSettings{}`, `refreshScheduledNotificationsAndWidgets()`, `bootstrap()` |
| `DarulIrfanApp/Core/Shared/PrayerWidgetSnapshot.swift` | Widget data bridge (compiled into app + widget targets) |
| `DarulIrfanApp/Services/PrayerCalculationService.swift` | Live Adhan wrapper (done — do not touch) |

## Language / toolchain rules

- Swift 5.9 mode, iOS 17 deployment target. SwiftUI + Swift Concurrency. No third-party dependency other than `Adhan` (only inside `PrayerCalculationService`).
- There is **no compiler on this machine** — write conservative Swift. Prefer well-trodden APIs over the newest sugar. No force-unwraps outside tests; no `try!`.
- ViewModels: `@Observable @MainActor final class`, injected with the protocols they need via `init`. Views stay thin: no SQL, no service calls in `body`.
- Concurrency correctness: repositories are `Sendable` structs/final classes calling the `SQLiteDatabase` actor with `await`. UI-facing services (`AudioPlayerServicing`, `DownloadManaging`, `HeadingProviding`) are `@MainActor` classes.
- Domain enum `Prayer` shadows `Adhan.Prayer`; only `PrayerCalculationService` imports Adhan.

## UI conventions

- Every screen: tokens from `DIColor/DISpacing/DIRadius/DIFont`, components from `Components.swift`, `.diScreenBackground()` on tab roots.
- All user-facing strings use **natural English literals as String Catalog keys** — `Text("Prayer Times")`, `Label("Settings", systemImage: ...)` — localized via `DarulIrfanApp/Resources/Localizations/Localizable.xcstrings` (en source, ur translations). This guarantees a readable English fallback with no compiler. Never concatenate localized strings; use interpolation (`Text("Next prayer: \(name)")`).
- Enum display names: use the model's `englishName` property wrapped as `Text(LocalizedStringKey(x.englishName))` so the catalog can translate it at runtime. Do not use the `localizationKey` computed properties for display (raw keys would show if a catalog entry is missing); they remain available for future keyed migration.
- RTL: rely on SwiftUI semantic layout (leading/trailing). Urdu/Arabic text blocks: `.environment(\.layoutDirection, .rightToLeft)` where content (not chrome) is RTL, `DIFont.urduBody`/`DIFont.quranArabic`.
- Accessibility: Dynamic Type everywhere (no fixed frames on text), meaningful `accessibilityLabel` on icon-only buttons, headers marked `.isHeader`.
- Dates: display via `Text(date, style:)` / `formatted()`; compute via injected services.

## Navigation shape (integration contract)

`RootView` (written by the integration agent) owns a `TabView` with 5 tabs.
Each feature exposes exactly one entry-point view with this signature:

```swift
struct PrayerTabView: View  { init(dependencies: AppDependencies, appState: AppState) }
struct QuranTabView: View   { init(dependencies: AppDependencies, appState: AppState) }
struct ZikrHomeView: View   { init(dependencies: AppDependencies, appState: AppState) }
struct ExploreTabView: View { init(dependencies: AppDependencies, appState: AppState) }
struct MoreTabView: View    { init(dependencies: AppDependencies, appState: AppState) }
```

plus `struct OnboardingFlowView: View { init(dependencies: AppDependencies, appState: AppState, onComplete: @escaping () -> Void) }`
and `struct GlobalSearchView: View { init(dependencies: AppDependencies) }` (presented as a sheet; Prayer/Quran/Library/Media toolbars may offer it).

Each tab root wraps itself in its own `NavigationStack`. Explore hosts official
updates, Library, Media, Events, and search. More hosts Qibla, Companion,
settings, privacy, diagnostics consent, organization information, and About.

- The mini audio player bar is overlaid by RootView above the tab bar whenever
  `dependencies.audioPlayer.nowPlaying != nil`; feature code never draws its own.

## Data & rights rules

- Seed JSON lives in `DarulIrfanApp/Resources/SeedData/` (schema v1, camelCase keys matching the Codable models; dates ISO-8601). `ContentSyncService` imports it idempotently (guarded by a `seed.version` row in `key_value`).
- Content permission for naqshbandiaowaisiah.org was **granted by the owner on 2026-07-10** (keep the written confirmation on file). Content sourced from the site now ships as `rightsStatus: "permissionConfirmed"` — full verbatim body text is allowed, produced only via the ingest pipeline's `--full-text --rights-confirmed` mode. Book/magazine/tafsir PDFs and lecture MP3s stay as **remote URLs on the site** (download/stream natively; never bundle or bulk re-host). Quran Arabic text and standard factual data (surah index, 99 Names, Quranic duas) are `publicDomain`.
- UI must still degrade gracefully for any `linkOnly` item (the pre-grant status; none remain in the current seed but the status stays valid): show metadata + "Read on naqshbandiaowaisiah.org" link (SafariView), and for media play the public MP3 stream URL natively (streaming a public URL is fine; bulk re-hosting is not).
- Never invent religious content: zikr instructions, tafsir, aqwal must come verbatim from `Docs/RESEARCH_NOTES.md` verified facts or seed data marked with a source. Permission does **not** relax the verbatim rule — religious text is never summarized or paraphrased; a clearly-labeled excerpt field is the only exception.

## Testing conventions

- `DarulIrfanTests/` — XCTest, `@testable import DarulIrfan`. Use `AppDatabase.inMemory()` for repository tests; known-city fixtures (Karachi 24.8607/67.0011 Asia/Karachi, New York 40.7128/-74.0060 America/New_York, London 51.5074/-0.1278 Europe/London) for calculation tests with tolerance ±3 min against published values.
- Mocks for protocols live in `DarulIrfanTests/Mocks/` (or `Services/Mocks/` when previews need them).
