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
| Akram-ut-Tafaseer parah 30 OCR ends at Ash-Shams (91); 92-114 absent from the drop ("Para-30-part1") | Part 2 found on the site (250 pages) and downloaded to amd; OCR with the urdu-ocr pipeline once the GPU is free (appraisal translation running), then re-run segment_akram_tafaseer.py and drop VOLUME_END[30] | blocked: GPU busy |
| Shell heredocs turn `\b`/`\n` into control bytes in written files | All touched files scanned clean; scripts now written as files | done |
| Book reader opened every book RTL/Nastaliq | Per-page direction | done |
| Dua group headers, greeting, broadcast status rendered verbatim (never localized) | Looked up in the catalog | done |

## A2. Added 2026-10-27: prayer-time accuracy, no exceptions

| Item | Status |
|---|---|
| Reproduce the app's exact calculation (adhan engine, same parameters) for a city/date grid across every continent, both hemispheres, DST transitions, high latitudes, equator, date line | done: 16 cities x 6 dates; engine within 0.5 min of a VSOP87 ephemeris for Fajr/sunrise/Maghrib/Isha, ~1 min Asr |
| Compare against an independent implementation (Aladhan) and a high-precision ephemeris | done; found Umm al-Qura Ramadan Isha 30 min early (fixed) and the high-latitude clamp moving real twilight by up to 84 min (fixed: astronomy wherever the angle is reached) |
| Time zone of the computed place | done: geocoder zone; manual cities without a zone no longer offered |
| Default method by region (not Karachi for everyone) | done: chosen from the place's country at onboarding; Today suggests it to existing users; method/Asr/place shown under the times |
| Stale location; show which place and method the times are for | done: refresh on activation (existing) + method/Asr/place line under the times |
| Widget, Watch, notifications and Today all use the same computed times | done: all call PrayerCalculationService.schedule |
| Regression tests pinning verified times per region | done: PrayerAccuracyTests |

## A3. Added 2026-10-27: Ayah of the Day

| Item | Status |
|---|---|
| Translation from the Silsila's own Akram-ut-Tarajum, in the reader's language | done (from the Quran database, mushaf Arabic) |
| Full reference (surah name, number, ayah) and open-in-reader | done |
| Tafsir excerpt / bayan link where the ayah has one; share with reference | done (verbatim opening of Akram-ut-Tafaseer / Asrar-at-Tanzil, labelled) |

## A4. Added 2026-10-27: community groups, phase 1

| Item | Status |
|---|---|
| Group feeds: WhatsApp forwards routed by sender number or #tag, as drafts approved in the app or admin page; feed items shareable into a group | done in code + tests; live once deployed (E) and the Meta webhook is set |
| WhatsApp Business number +1 929 240 5561: pictures (with caption) as well as text | done in code + tests; pictures need R2 enabled (E) |
| Super admin wajidali1984@hotmail.com and wajidmahmood@hotmail.com: admin page, and in the app by Apple sign-in email (no code needed); admin/superadmin roles also granted by code | done; Sign in with Apple enabled on the App ID via API 2026-10-27, entitlement restored, email declared in the privacy manifest |
| In-app meetings (Cloudflare RealtimeKit; scheduled, room opens 10 min before) | done in code + tests; needs REALTIME_* secrets (E) |
| Community zikr per group: own times in local time, live in the app, join together | done in code + tests |
| Group-only notifications | done in code + tests |
| Live zikr pipeline: one source (Paltalk session) -> app + YouTube + Facebook automatically, auto-start, failover | doing: listener agent (capture, encode, self-restart, room search + join, heartbeat) and server (heartbeats, Stream events, hub source in the app, failover A->B, admin alerts by push + WhatsApp; 6 tests) built; first live rehearsal at the 2026-10-27 session on the Windows PC; hub needs Stream keys (E) |
| Share-sheet entry from WhatsApp into the app | todo (after phase 1) |

## C. "Useful companion" plan — first increment (iOS)

| Item | Status |
|---|---|
| Today: one header (Gregorian + Hijri date, city, search, language) | done |
| Today: prayer panel — next prayer, countdown, all five times, reminder status, link to timetable | done |
| Today: quick tools row — Quran, Duas, Qibla, Tasbih, My Day, Focus | done |
| Today: My Day — next 3 tasks, Add, View all | done |
| Today: Continue reading / listening | done |
| Today: "Understand something today" (approved content only) | done (topic of the day) |
| Today: upcoming zikr session / event | done |
| Azan: per-prayer muadhin, pre-azan reminder, iqamah-gap reminder | iqamah done; pre-azan existed; muadhin choice deferred - only two licensed recordings (general + Fajr), both playable |
| Notification status + "send a test reminder" | done |
| Monthly timetable + manual city | done (existed; manual cities now require a time zone) |
| Hifz practice | done (v1.10.1) |
| Situational duas, morning/evening collections | existing: morning/evening adhkar, masnoon, rabbana; situational set not added (needs a verified source) |
| Tasbih | done (existing) |
| Fasting record + Ramadan timings | done |
| My Day: tasks with date/time/repeat, prayer-relative reminders ("after Fajr") | done |
| My Day: private notes, optionally attached to a passage | done (ayah notes) |
| My Day: focus timer that warns before the next prayer | done |
| My Day: weekly view, calendar export | done |
| Tools sheet | done |
| Reader-language model app-wide | done for Quran, topics, Ayah of the Day; hadith keeps its own language tabs |
| Discover: topics, glossary, Roman-Urdu search | topics done; glossary and Roman-Urdu search not built |
| Five destinations Today/Read/Zikr/Discover/Community | done |

## D. Constraints carried forward

- No generated religious answers; no review badges beside scripture.
- Private devotional data stays on the device; My Day needs no account.
- **Sign-in exists only in Community -> Private groups** (owner, 2026-10-27).
  Everything else - Today, Read, Zikr and the live Daily Zikr, Discover,
  Events, Official Updates - is free to use with no account, and the public
  API routes (`/v1/bootstrap`, `/v1/live`, `/v1/feed`) never ask for one.
- GMS-free Android, invite-based bearer sessions.
- Seed changes mirrored to all four platforms, manifest bumped, parity gate green.

## E. Operator actions (yours)

- **Private groups do not work yet: the backend with the group routes is not
  deployed.** On 2026-10-27 the live D1 had only migration 0001 (0002-0006
  pending) and `/v1/groups` answered 404. wrangler is logged in on this PC and
  a full backup was exported first (`d1-backup-2026-10-27.sql`, 371 rows). In
  `Server/`, in this order:
  1. Enable R2 in the Cloudflare dashboard (R2 -> enable; free tier), then
     `npx wrangler r2 bucket create darul-irfan-media`. Deploy fails while
     wrangler.toml binds a bucket that does not exist.
  2. `npm run db:migrate:remote` (applies 0002-0006).
  3. Secrets (`npx wrangler secret put NAME`): `MEDIA_URL_SECRET` (any long
     random string), `LISTENER_TOKEN` (long random; the listener agent's
     `--heartbeat-token`), and when ready `WHATSAPP_APP_SECRET`,
     `WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`,
     `WHATSAPP_ALLOWED_SENDERS`, `REALTIME_ACCOUNT_ID`, `REALTIME_APP_ID`,
     `REALTIME_API_TOKEN`, `STREAM_WEBHOOK_SECRET`, `ALERT_WHATSAPP_NUMBERS`.
  4. `npm run deploy`.
- The two Cloudflare API tokens in `cloudflare.md` have an IP filter that
  refuses this PC (108.27.186.148); add the IP or use `wrangler login`.
- Cloudflare Stream: enable it, create two live inputs (recording off), set
  `STREAM_INPUTS` = "<input A id>,<input B id>" and `STREAM_CUSTOMER_HOST` in
  wrangler.toml, add YouTube and Facebook (primary on A, backup on B) as
  simulcast outputs, and point a "Stream Live Input" notification webhook at
  `https://api.naqshbandiaowaisiah.us/v1/live/stream-events` with the secret.
- App Store Connect privacy answers: add **Email Address** (linked, App
  Functionality), matching PrivacyInfo.xcprivacy.
- On the iPhone: in Darul Irfan -> More -> Private groups, Sign in with Apple
  and choose **Share My Email** (wajidmahmood@hotmail.com) to be super admin.
- Run `ios-verify`; tag on green; run `ios-testflight` (owner runs these).
