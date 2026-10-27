# Release worklist — v1.11 pass (opened 2026-10-26)

Every item from the post-v1.10.1 report and the "useful companion" plan, with
its root cause and status. Nothing is removed from this list; an item is only
ever marked done, deferred (with the reason), or blocked (with what unblocks it).

Status: `todo` · `doing` · `done` · `deferred` · `blocked`

## A. Reported issues (all must be fixed this pass)

| # | Issue | Root cause | Fix | Status |
|---|---|---|---|---|
| 1 | No Urdu tafsir anywhere | Urdu tafsir existed only as page volumes; reader never linked them; per-ayah tables had 0 Asrar-Urdu rows and 1 Akram row | **Akram-ut-Tafaseer segmented per ayah**: 2,995 rows, 5,917/6,236 ayat, 91 surahs (`Tools/Library/segment_akram_tafaseer.py`), anchored on the book's own section openings (translation numbering + mushaf-matched Arabic) with quotation fallback; independent check 0.77% rows flagged (`verify_akram_rows.py`); 1,964 whole-ayah quotations replaced with the mushaf's text. Asrar Urdu stays volume-only (its OCR corrupts Quranic Arabic - see ASRAR_URDU_TRANSLATION_STATUS.md). Every tafsir tab now offers "Read the full commentary" opened at the surah's page (`tafsir_volumes.json`) | done |
| 2 | Akram 1:1 shows "noon noon" and OCR everywhere | (a) bundled Noto Nastaliq is Google's variable OpenType build, which Core Text shapes badly - iOS ships its own correctly-shaped copy; (b) draft row with an "OCR نوٹ" disclaimer | App now prefers the system `NotoNastaliqUrdu` (bundled one only a fallback, removed from UIAppFonts); draft row replaced by segmented text; OCR notes stripped; hallucinated honorific ("رحمۃ اللہ علیہ السلام" for ﷺ) and repetition runs repaired (`repair_ocr_artifacts.py`) | done - confirm on device |
| 3 | English Asrar translation/tafsir right-aligned | English `bodyText` inherited RTL; `BookTextReaderView` forced Urdu/RTL for every book | LTR forced for Latin text; book reader decides direction/font per page from its script | done |
| 4 | EN/UR switching does nothing | `translationsByAyah`/`asrarTranslationsByAyah`/`editionsByID` were `@ObservationIgnored` | Observed; reading-language choice kept across surahs for the session | done |
| 5 | Urdu shows English and vice versa | Stale caches above + "System" resolved to English + **234 UI strings had no Urdu** (fell back to English) | `AppLanguage.contentLanguageCode`; catalog 757 -> 991 keys, audit `Tools/Localization/audit_strings.py` reports 745/745 literals translated; English plurals built in code replaced; unknown-edition tafsir no longer shown | done |
| 6 | Method of Zikr "is being prepared" | One all-or-nothing import, hadith before library, 57 MB book pages decoded up front: any failure left the library empty | Staged import, each stage stamped on its own, small content first, hadith last; bundled-seed fallback on the screen | done |
| 7 | "Live in Darul Irfan" -> "Daily Zikr" | Strings | Section, card button, default title (app + server defaults + push copy + web) renamed, Urdu "روزانہ ذکر" | done |
| 8 | Online zikr schedule in phone's local time | Fixed 21:15 Asia/Karachi; **backend publishes no schedule, so the app showed "Schedule not available" to everyone** | Official sessions ("After Isha and Tahajjud (Pakistan Time)") computed daily at Dar-ul-Irfan (Isha / last third of night) and shown as "Your time: Mon 10:05 AM EDT" with Pakistan time beside; joining steps verbatim from the site | done |
| 9 | Private groups have no instructions | Join screen had only a code field | "How private groups work" (6 steps), meeting-link hint; admin page forms to mint codes, set meeting links, publish posts | done |
| 10 | Remove Acknowledgements from About | - | Removed from About; licence notices (MIT, OFL, CC BY 3.0 azan) now Settings -> Licences, as CLAUDE.md requires | done |

## B. Whole-app review findings (added as found)

| Finding | Fix | Status |
|---|---|---|
| Asrar English 2:215 carried the OCR checker's own note ("Note: The OCR is correct... the image") inside the ayah | Leak removed, verse text intact | done |
| Akram-ut-Tafaseer parah 30 OCR ends at Ash-Shams (91); 92-114 absent from the drop ("Para-30-part1") | Reader offers Asrar for 92-114; find part 2 on amd SATA | todo |
| Shell heredocs turn `\b`/`\n` into control bytes in written files | All touched files scanned clean; scripts now written as files | done |
| Book reader opened every book RTL/Nastaliq | Per-page direction | done |
| Dua group headers, greeting, broadcast status rendered verbatim (never localized) | Looked up in the catalog | done |

## C. "Useful companion" plan — first increment (iOS)

| Item | Status |
|---|---|
| Today: one header (Gregorian + Hijri date, city, search, language) | todo |
| Today: prayer panel — next prayer, countdown, all five times, reminder status, link to timetable | todo |
| Today: quick tools row — Quran, Duas, Qibla, Tasbih, My Day, Focus | todo |
| Today: My Day — next 3 tasks, Add, View all | todo |
| Today: Continue reading / listening | todo |
| Today: "Understand something today" (approved content only) | todo |
| Today: upcoming zikr session / event | todo |
| Azan: per-prayer muadhin, pre-azan reminder, iqamah-gap reminder | todo |
| Notification status + "send a test reminder" | todo |
| Monthly timetable + manual city | todo (verify existing) |
| Hifz practice | done (v1.10.1) |
| Situational duas, morning/evening collections | todo (verify sources) |
| Tasbih | done (existing) |
| Fasting record + Ramadan timings | todo |
| My Day: tasks with date/time/repeat, prayer-relative reminders ("after Fajr") | todo |
| My Day: private notes, optionally attached to a passage | todo |
| My Day: focus timer that warns before the next prayer | todo |
| My Day: weekly view, calendar export | todo |
| Tools sheet | todo |
| Reader-language model app-wide | todo |
| Discover: topics, glossary, Roman-Urdu search | todo (verify) |
| Five destinations Today/Read/Zikr/Discover/Community | todo (assess against current tabs) |

## D. Constraints carried forward

- No generated religious answers; no review badges beside scripture.
- Private devotional data stays on the device; My Day needs no account.
- GMS-free Android, invite-based bearer sessions.
- Seed changes mirrored to all four platforms, manifest bumped, parity gate green.

## E. Operator actions (yours)

- Apply D1 migrations 0003 and 0004: `npm run db:migrate:remote` in `Server/`.
- Run `ios-verify` after this pass; tag on green; run `ios-testflight`.
