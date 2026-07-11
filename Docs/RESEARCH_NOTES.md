# Research notes (verified 2026-07-09)

Facts verified against primary sources before implementation. Implementation
agents: treat these as authoritative; do not re-derive from memory.

## adhan-swift (prayer calculation engine)

- SPM: `https://github.com/batoulapps/adhan-swift.git`, pinned `from: 1.5.0`. v1.5.0 uses swift-tools-version 6.0 → **requires Xcode 16+**. `import Adhan`.
- `PrayerTimes` init is **failable**: `init?(coordinates:date:calculationParameters:)`; on success `fajr/sunrise/dhuhr/asr/maghrib/isha` are non-optional `Date`. `date` is `DateComponents` built with `[.year, .month, .day]` — build them **in the place's timezone**.
- Get parameters via `CalculationMethod.karachi.params` (cases: muslimWorldLeague, egyptian, karachi, ummAlQura, dubai, moonsightingCommittee, northAmerica, kuwait, qatar, singapore, tehran, turkey, other). No public `CalculationParameters` initializer.
- Mutable on `CalculationParameters`: `fajrAngle`, `ishaAngle`, `ishaInterval: Int`, `madhab` (`.shafi`/`.hanafi`), `highLatitudeRule` (**optional**; nil = library auto-recommends), `adjustments = PrayerAdjustments(fajr:sunrise:dhuhr:asr:maghrib:isha:)` (Ints, minutes), `rounding`, `shafaq`.
- `Coordinates(latitude:longitude:)` — stored properties are **internal**, you cannot read them back.
- `Qibla(coordinates:).direction` → degrees from true north. Kaaba: 21.4225 N, 39.8262 E.
- Adhan also declares `Prayer` — the app's own `Prayer` enum shadows it inside the app module; never reference `Adhan.Prayer`.

## iOS platform constraints

### Notification sounds
- Custom sounds must be **< 30 s**, else system plays default sound.
- Data formats: Linear PCM, IMA4, uLaw, aLaw only — **MP3/AAC are NOT supported**. Containers: `.aiff`, `.wav`, `.caf`.
- File must be in the **app main bundle** (or Library/Sounds). API: `content.sound = UNNotificationSound(named: UNNotificationSoundName("azan-short.caf"))`. Missing/invalid file silently falls back to default sound.

### Notification limit
- iOS keeps only the **soonest-firing 64 pending** local notifications. 6 prayers/day → schedule a **rolling window ≈ 7–8 days** (42–48 requests), leave headroom for pre-reminders, and add one trailing "Open Darul Irfan to keep prayer alerts fresh" reminder. Re-schedule on every app foreground; there is no guaranteed background top-up.
- Use non-repeating `UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)` with full y/m/d/h/m components per prayer.

### Widgets (iOS 17)
- Every widget view **must** apply `.containerBackground(for: .widget) { ... }` — otherwise iOS 17 shows "Please adopt containerBackground API".
- Live countdown without timeline churn: `Text(nextPrayerDate, style: .timer)` (iOS 14+) or `Text(timerInterval: now...date, countsDown: true)` (iOS 16+).
- Families: `.systemSmall/.systemMedium` + Lock Screen `.accessoryCircular/.accessoryRectangular/.accessoryInline` (iOS 16+).
- `TimelineProvider` members: `placeholder(in:)`, `getSnapshot(in:completion:)`, `getTimeline(in:completion:)`; entries need `let date: Date`; policy `.atEnd` / `.after(date)`.
- Refresh from app: `WidgetCenter.shared.reloadAllTimelines()`.
- Data sharing: app writes JSON snapshot to App Group `group.us.naqshbaniaowaisiah` (see `Core/Shared/PrayerWidgetSnapshot.swift`, compiled into both targets).

### Location / compass
- One-shot fix: `CLLocationManager.requestLocation()` + delegate (`didUpdateLocations` **and** `didFailWithError` are both mandatory). Request `requestWhenInUseAuthorization()` first; wait for `locationManagerDidChangeAuthorization`.
- Heading: `CLLocationManager.headingAvailable()` (class func), `startUpdatingHeading()`, delegate `didUpdateHeading`. `trueHeading` valid only when location updates are also running; negative `headingAccuracy` ⇒ needs calibration. Robust: `heading.trueHeading >= 0 ? trueHeading : magneticHeading`.
- Geocoding: `CLGeocoder` still fine on iOS 17 (forward `geocodeAddressString`, reverse `reverseGeocodeLocation`).

### Hijri
- `Calendar(identifier: .islamicUmmAlQura)` — astronomical Umm al-Qura table. Apply the user's ±day offset to the **Date** (`calendar.date(byAdding: .day, ...)`) before extracting Hijri components; never offset the day component directly.

## Website map (naqshbandiaowaisiah.org) — for ingest + seed data

- robots.txt: fully permissive (`Disallow:` empty). All pages are static server-rendered HTML; plain GET + HTML parsing suffices.
- Nav tree:
  - About: `/hazrat-ameer-abdul-qadeer-awan.html`, `/hazrat-ameer-muhammad-akram-awan-ra.html`, `/silsila-naqshbandia-owaisiah.html`, `/shajra-silsila-naqshbandia-owaisiah.html`
  - Publications: `/asrar-at-tanzil` (English tafsir, 114 static HTML pages `/asrar-at-tanzil/{ID}/tafseer-quran-in-english-surah-{name}.html`, IDs 1229…), `/akram-ut-tafaseer`, `/akram-ut-tarajum`, `/almurshid-magazine.html`, `/download` (books index → `/books-on-tasawwuf.html` etc.), `/articles`
  - Multimedia: `/lectures` (year archives `/lectures/{YYYY}`, 1976–2026), `/video-lectures`, `/almurshidtv`, `/almurshid-programs`
  - Zikr: `/method-of-zikr.html` (instructions are **images** — needs OCR/manual transcription), `/zikr`, `/online-zikr-joining-instructions.html`
- Lecture rows: Urdu title, speaker "Sheikh-e-Silsila Naqshbandia Owaisiah Hazrat Ameer Abdul Qadeer Awan (MZA)", date `DD-MMM-YYYY`, MP3 `https://www.naqshbandiaowaisiah.org/uploads/{LECTURE_ID}/{DD-MM-YYYY}.mp3` (**filenames irregular** — always harvest actual hrefs, e.g. `06-02-2026%20s.mp3`), WMA (ignore on iOS), detail page `/lecture/{ID}/{YYYY-MM-DD}-{slug}.html` hosts YouTube embed.
- Magazine PDFs: `uploads/almurshid-magazines/almurshid_{month(s)}_{year}.pdf` via 5-year archive pages `almurshid-magazine-{Y1}-to-{Y2}.html` (1981–2015 populated; 2016-2020 placeholder).
- Book PDFs: `uploads/books/{Title-Slug-Language}.pdf` from `/books-on-tasawwuf.html`.
- Verified sample entries (usable as seed):
  - Lecture: «دعوت و تبلیغ کے اصول», 02-Jan-2026, MP3 `/uploads/3725/02-01-2026.mp3`, page `/lecture/3725/2026-01-02-dawat-o-tabligh-ke-usool.html`
  - Lecture: «عظمت محمد الرسول اللہ», 06-Feb-2026, MP3 `/uploads/3835/06-02-2026%20s.mp3`, page `/lecture/3835/2026-02-06-azmat-mohammad-rasool-ul-allah.html`
  - Lecture: «خانقاہ کی ذمہ داری», 01-May-2026, MP3 `/uploads/4141/01-05-2026.mp3`, page `/lecture/4141/2026-05-01-khankah-ki-zimadari.html`
  - Magazine: "February - March 1981" → `/uploads/almurshid-magazines/almurshid_february_march_1981.pdf`; "May 1983" → `/uploads/almurshid-magazines/almurshid_may_1983.pdf`
  - Books: "Dalael-us-Salook in Urdu" → `/uploads/books/Dalael-us-Salook-Urdu.pdf`; "Hayyat-e-Tayyabah - I" → `/uploads/books/Hayyat-e-Tayyabah-I.pdf`
  - Tafsir page: Surah Al-Fatihah → `/asrar-at-tanzil/1229/tafseer-quran-in-english-surah-al-fatihah.html`

### Verified organizational facts (for About/Events/Zikr seed content)
- Current Sheikh: **Hazrat Ameer Abdul Qadeer Awan (MZA)**, "Sheikh-e Silsilah", born 26 March 1973, Munara, District Chakwal. Predecessor: **Hazrat Ameer Muhammad Akram Awan (RA)**; earlier reviver: Shaikh Allah Yar Khan (1904–1984). Order traces to Khawajah Owais Qarni.
- HQ: **Dar ul Irfan, Munara, Khushab Road, District Chakwal, Punjab, Pakistan**. Phone: +92 543 562200. Email: Darulirfan@gmail.com.
- Method: **Zikr-e Khafi Qalbi** with **Pas Anfas** ("guarding every breath"). Distinguishing feature: spiritual bai'at directly at the hands of the holy Prophet ﷺ (Owaisiah transmission).
- Online Zikr: **twice daily on Paltalk — after Isha and at Tahajjud (Pakistan time)**; evening session ~9:15pm PKT. Paltalk room: All Rooms → Religion & Spirituality → Islam → room "**OURSHEIKH**" (visible only while a session is in progress). Site stream page: `/zikr`.
- Tafsir attribution: "Asrar-at-Tanzil is Qur'an Tafseer written … by Our Sheikh Hazrat Ameer Muhammad Akram Awan", written during Ramadan over 10+ years.

## Expo prototype carry-overs (../Darul-Irfan)

- Palette (already encoded in `Core/DesignSystem/Theme.swift`): primary #0B6E4F, primaryDark #063D2C, accent #C9A24B, background #F6F3EC, surface #FFFFFF, text #1C1C1C, textMuted #6B6B6B, border #E2DCCD, danger #B3261E. Spacing 4/8/16/24/32; radii 8/12/20.
- App name ur: **دارالعرفان**; tagline en "Light of Sacred Knowledge" / ur "علمِ مقدس کی روشنی". Full en/ur strings for prayer names, common actions, settings are in the prototype's `src/locales/*.json` — reuse translations in the String Catalog (prayer names: فجر، طلوعِ آفتاب، ظہر، عصر، مغرب، عشاء).
- Quran recitation audio CDN used by prototype: `https://everyayah.com/data/Alafasy_128kbps/{surah:03d}{ayah:03d}.mp3`.
- AlMurshid TV live audio URL used by prototype: `https://stream.darulirfan.org/almurshid-tv.mp3` (treat as remote-config default; may be unavailable — handle failure gracefully).
- **Deliberately NOT ported**: the prototype's on-the-fly AI translation of religious content (violates the "do not paraphrase religious content" principle) and its client-side Anthropic API key usage.
