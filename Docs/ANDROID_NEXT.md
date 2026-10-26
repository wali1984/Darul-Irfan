# Android: what is left to reach iOS parity

Written 2026-10-26, while iOS is being finalised for TestFlight. iOS is the
reference implementation; this is the gap to close on Android, measured rather
than estimated.

Seed content is already identical on both platforms by construction — the
content gate enforces byte parity, so **none of the work below is data work.**
It is all reader and service code.

## Measured gap

Counted as source files referencing each capability (iOS `.swift` under
`DarulIrfanApp`, Android `.java` under `app/src/main`), so the numbers show
presence, not quality.

| Capability | iOS | Android | State on Android |
|---|---|---|---|
| Word-by-word recitation | 4 | 0 | **missing entirely** |
| Tafsir reader | 12 | 0 | **missing entirely** |
| Official feed / live broadcast | 10 | 0 | **missing entirely** |
| Bookmarks | 17 | 1 | barely present |
| Azan at prayer time | 8 | 5 | **done 2026-10-26** |
| Qibla | 11 | 1 | minimal |
| Notifications | 33 | 5 | prayer reminders only |
| Hadith reader | — | — | at parity already |
| Book text (43 OCR works) | — | — | at parity already |

## Already at parity — do not rebuild

- **Hadith reader.** Full parity as of the 2026-08-11 pass: 28 collections,
  paged reading, in-collection and cross-collection search, exact
  `canonicalID` jumps, narrator bios from the 12,643-record store, coloured
  tappable isnad/matn/verse spans, kitab headers, searchable contents.
  Android streams the packs with `JsonReader`, so the 45 MB Bukhari pack is
  never held in memory — keep that property.
- **Book text.** `BookTextActivity`, batched rendering, one printed page per
  record.
- **Prayer times and reminders**, including the azan work below.

## Done on 2026-10-26

**Full azan playback.** Both recordings had been bundled in `res/raw` since the
app was written with nothing referencing them, so prayer reminders rang the
system default sound. `media/AzanPlaybackService` now plays the complete azan
as a foreground service.

Decisions worth preserving:
- It is **not** a notification sound. Android fixes a channel's sound when the
  channel is first created and ignores every later change, so existing installs
  could never be migrated onto it, and the recitation runs past two minutes.
- Declared as `USAGE_ALARM` so it follows the alarm volume and Do Not Disturb
  treats it as an alarm instead of silencing it as a notification.
- Holds transient audio focus, so the listener's music pauses rather than being
  talked over, and its own notification is silent for the same reason.
- `MediaPlayer` is built by hand, not via `MediaPlayer.create`, because the
  alarm attributes must be applied before `prepare()`.
- Fajr uses `azan_fajr_full`, which carries the call belonging only to the dawn
  azan. The two files are never interchangeable.
- Off by default, next to the reminders switch.
- The allowance to start a foreground service from the background comes from
  the **exact** alarm. If the user revokes exact alarms the scheduler falls
  back to an inexact one and the start is refused, so it is caught and the
  prayer notification alone announces the time.

## Suggested order

1. **Quran recitation.** Highest value and the data is already shipped:
   `quran_word_timings.json` holds word-level timings for all 114 surahs
   (Mishari al-Afasy) with a streaming audio URL per surah. Mirror iOS's
   `QuranRecitation.swift`: one continuous file per surah, highlight the word
   whose `[startMs, endMs)` contains the playhead. The `reciterId` field is
   there so a second reciter can be added later without a schema change.
2. **Tafsir reader.** `quran_tafsir.json` carries 640 Asrar blocks keyed by
   `(edition, surah, ayahStart)`. Two invariants from iOS, both learned from a
   crash and a data loss:
   - Render lazily. A whole-surah tafsir block crashed the iOS reader in
     v1.6.9; blocks are per-ayah and must stay that way.
   - Be language-strict. Never fall back to another language's tafsir, and
     never show English prose styled as Urdu.
3. **Official feed and live broadcast.** The backend already serves
   `/v1/bootstrap`, `/v1/feed` and `/v1/live`; Android has no client. Keep the
   last good catalogue when a refresh fails, as the other clients do.
4. **Bookmarks**, to match the iOS set.

## Building Android on this machine

Discovered 2026-10-26; these cost real time to find.

- `JAVA_HOME` must be set — `java` is not on `PATH`. Use Android Studio's
  bundled runtime: `C:\Program Files\Android\Android Studio\jbr` (JDK 25).
- Use the **default** Gradle home. A fresh `--gradle-user-home` has no cached
  plugins and fails offline on `foojay-resolver-convention`. The OneDrive lock
  problem that once forced an isolated home no longer applies.
- **`app/build` has an ACL that makes `clean` and `--rerun-tasks` fail**
  (`AccessDeniedException`, `Unable to delete directory`). An ordinary
  incremental `assembleDebug` works. For a genuine from-scratch check, copy the
  project (excluding `build`, `.git`, `.gradle`) to a scratch directory and
  build there; that path produces the APK and runs the unit tests.
- Current state: `assembleDebug` and `testDebugUnitTest` green, 5 unit tests,
  APK ~115 MB (the offline corpus is bundled, so that size is expected).

## HarmonyOS

Paused deliberately on 2026-10-26. Its seed was two manifest revisions behind
and is now caught up, and the bundled azan is wired, but **DevEco Studio is not
installed on this machine** so none of its ArkTS is compile-verified.
`Build-Debug.ps1` still points at a `C:\Users\WajidAli\...` path that no longer
exists. Treat Harmony as needing a build environment before anything else.
