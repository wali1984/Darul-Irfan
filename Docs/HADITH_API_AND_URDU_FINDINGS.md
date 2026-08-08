# Hadith: sunnah.com API, Urdu, narrators & Quran-link findings

_Internal investigation (not shipped). Compiled 2026-08-08 from the sunnah.com developer
docs, the open-source `sunnah-com/api` repo, and live inspection of sunnah.com. **No app
code was changed and nothing was pushed** — this is report-before-build._

## TL;DR

- **I was wrong earlier: sunnah.com DOES serve authentic Urdu for Bukhari.** It is loaded at
  runtime from a **keyless same-origin endpoint** `GET /ajax/urdu/{collection}/{book}`, which
  returns clean JSON with the Urdu **isnad and matn already split**, plus grade and Urdu
  book/chapter names. Coverage is ~**100%** (6,283/6,283 non-empty across 95 of 97 Bukhari
  books; the 2 largest books error at book-level and need a finer fetch).
- The **official REST API** (`api.sunnah.com/v1`, needs a key) gives structure + English +
  Arabic + grades, with narrator and Quran-verse **links embedded in the Arabic HTML** — but
  **no Urdu and no narrator bios**.
- **Narrator bios** exist only as `/narrator/{id}` HTML pages (very rich). **Quran quotes**
  are embedded as `openquran(surahIndex,begin,end)` → our surah = surahIndex + 1.
- Everything can be ingested at **build time** into our own bundled native data, with **zero
  runtime calls** to sunnah.com / quran.com, per the architecture instruction.

## 1. Official API — capabilities & auth

- Base URL `https://api.sunnah.com/v1/`; auth header **`X-API-Key`**. **A key is required.**
  Request it by opening a GitHub issue (template: name/email, purpose, requests-per-second &
  per-day, offline-dump vs API, languages wanted, client language).
  **No key is present in this environment → user action required to obtain one.**
- Endpoints (all paginated, `limit`≤100, `page`): `/collections`, `/collections/{c}`,
  `/collections/{c}/books`, `/collections/{c}/books/{n}/chapters`,
  `/collections/{c}/books/{n}/hadiths`, `/collections/{c}/hadiths/{num}`, `/hadiths`
  (filter by collection/book/chapter/number), `/hadiths/{urn}`, `/hadiths/urns?urns=…`,
  `/hadiths/random`.
- **Hadith payload = English + Arabic only** (from the open-source `models.py`):
  `hadith: [{lang:"en", body(HTML), chapterNumber, chapterTitle, urn, grades:[{graded_by,grade}]}, {lang:"ar", …}]`.
  **No Urdu field in the documented API.** Grades are structured.
- **Book/Chapter are fully structured**: book `name` en/ar + `hadithStartNumber`/`EndNumber`/
  `numberOfHadith`; chapter `chapterNumber`, `chapterTitle`, `intro`, `ending` (en/ar), `chapterId`.
  This is cleaner than my HTML scrape and should replace `sunnah_bukhari_books.json` going forward.

## 2. Isnad vs matn + narrator IDs

- No separate "isnad array", but the **Arabic `body` HTML embeds narrator anchors**:
  `<a href="https://sunnah.com/narrator/{id}">name</a>` around each isnad narrator
  (confirmed by `text_transform.fix_hyperlinks` and the live pages). **Matn = the Arabic text
  not inside a narrator anchor.** So we can color green-isnad / black-matn and get each
  narrator's ID by parsing the body.
- **Even better for Urdu:** the `/ajax/urdu` endpoint returns Urdu **pre-split** into
  `hadithSanad` (isnad) and `hadithText` (matn).

## 3. Quran-verse references

- Quran quotes are stored as `openquran(surahIndex, begin, end)` and rendered as links.
  **`surahIndex` is 0-based → our surah number = surahIndex + 1.** Example confirmed:
  `openquran(95,1,3)` = **al-Alaq (96), ayat 1–3** (matches quran.com/al-alaq/1-3). Each quote
  is a parseable `(surah, ayahStart, ayahEnd)` we map to our own Quran reader; the green verse
  span is the `<a>` wrapping the ayah in the Arabic body.

## 4. Urdu — the keyless endpoint (correcting the earlier false negative)

- **Why I missed it before:** the single-hadith permalink pages (`bukhari:1`) and the raw book
  HTML contain **empty** Urdu containers; the site fills them at runtime via
  `GET https://sunnah.com/ajax/urdu/{collection}/{book}`. `get_page_text` skipped the hidden
  divs and my raw-HTML/container checks keyed off the wrong thing. The endpoint is same-origin
  and **needs no API key**.
- **Response**: JSON array, one object per hadith, fields:
  `urduURN, collection, volumeNumber, bookNumber, bookName(ur), babNumber, babName(ur),
  hadithNumber, hadithSanad(ur isnad), hadithText(ur matn), bookID, grade, comments,
  ourHadithNumber, matchingArabicURN, last_updated`.
  `hadithNumber` aligns to our `displayNumber`; `matchingArabicURN` aligns to the Arabic hadith.
- **Coverage (measured live):** Bukhari books 1–63 and 66–97 → **6,283 records, 100% with Urdu
  text, 0 blank.** Books **64 and 65** (the two largest) return **HTTP 500** at book level —
  workaround: fetch their Urdu per chapter or per hadith. So effectively **~100% Urdu**, versus
  our current shipped Urdu of **7,019 / 7,583** (which also has defects — e.g. hadith 1 is
  missing its leading word "ہم").
- **Other collections:** Abu Dawud confirmed (`/ajax/urdu/abudawud/1` → 200, 390 Urdu records).
  Muslim/Nasa'i/Tirmidhi/Ibn Majah/Malik returned 500 during the run — most likely load/rate
  limiting from my rapid requests (Abu Dawud + 95 Bukhari books succeeded); to be re-tested with
  heavy throttling. **The endpoint appears available across collections but is flaky under load
  and for very large books**, so a build-time fetch must throttle, cache, and retry.
- The Urdu is essentially the standard Urdu translation, but **cleaner, complete, pre-split into
  sanad/matn, and carries grade + Urdu book/bab names** — clearly better than what we ship.

## 5. Narrator bios

- **Not in the API.** Only as `/narrator/{id}` HTML pages, which are rich: names en/ar, kunya,
  generation (tabaqa), death year, gender, full lineage, cities/regions, affiliations (nisba),
  overall grade, multiple scholarly appraisals (jarḥ wa taʿdīl), **teachers** and **students**
  (each linked with a narrator ID), count of hadith narrated, and classical rijāl texts
  (Tahdhīb al-Kamāl, etc.).
- Narrator ID space is large (IDs observed up to ~65,000+; the people DB is tens of thousands).
  **We only need the narrators actually referenced by the collections we ship** (the isnad
  anchors) — a bounded subset. Bundle compact fields; optionally trim long rijāl texts for size.

## Proposed native data model (build-time ingest → bundled; no runtime calls)

- **HadithEntry (extend):**
  - `arabicSegments: [{type: isnad|matn|verse, text, narratorId?, surah?, ayahStart?, ayahEnd?}]`
    — parsed from the Arabic body anchors; drives green-isnad (→bio sheet), green-verse (→our
    Quran reader), black-matn.
  - `urduSanad`, `urduText` (from `/ajax/urdu`); rendered in the app's Urdu face, grey; keep the
    honest missing state where absent.
  - `quranRefs: [{surah, ayahStart, ayahEnd}]` (surahIndex+1) for fast linking + validation
    against our Quran (114 surahs / 6236 ayat).
  - Keep existing en/ar/ur, references, grades, kitab/section; add bab chapter number + name (en/ar/ur).
- **Narrators store (new, bundled):** `id, nameEn, nameAr, kunya, generation, deathYear,
  gradeEn/gradeAr, lineage, cities, affiliations, hadithCount, teacherIds[], studentIds[],
  appraisals[](optional)`. Reader opens a native bio sheet by `narratorId`, dismiss → same spot.
- **Chapters (bab) per collection:** number + name en/ar/ur + intro/ending.

## Build plan (collection-agnostic; Bukhari first as proof)

1. **Decide the source of record** (report для user):
   - *Official API* (needs key): cleanest en/ar/grades/structure, but **no Urdu, no bios**.
   - *Keyless page + `/ajax/urdu` + `/narrator/{id}` ingestion*: gives Urdu (split), isnad/verse
     anchors, and bios — **no key needed**. Recommended primary, with the API as a cross-check
     if/when a key is granted. (I can draft the API-access request either way.)
2. **Build-time ingest tool** (heavily throttled, cached to disk, retry on 500, report failures):
   Arabic+English bodies → parse `arabicSegments` + `quranRefs`; `/ajax/urdu/{c}/{book}` →
   `urduSanad`/`urduText`/grade/babName (per-chapter fallback for books that 500); collect all
   referenced narratorIds → fetch `/narrator/{id}` → parse → dedupe → bundle.
3. **Map Quran refs** (surahIndex+1) and validate against our Quran data.
4. **Vet** (counts, Urdu coverage, key integrity, encoding, cross-platform parity) → report.
5. **App (native, our theme/fonts, no external branding, no runtime calls):** extend
   model/schema for segments + narrators + bab chapters + quranRefs; reader renders colored
   isnad/matn/verse, tap-isnad → bio sheet, tap-verse → our Quran reader.
6. Bukhari first, then every collection.

## Blockers / decisions for the user

- **API key**: required only for `api.sunnah.com`; not in our environment → request via the
  GitHub issue if we want the official API. **The Urdu + bios + links we need are all available
  keyless** via `/ajax/urdu` and the page/narrator HTML, so a key may be optional.
- **Rate limits / 500s**: build ingestion must be slow + cached + retried; the two largest
  Bukhari books need per-chapter Urdu fetches.
- **Bundle size**: decide how much narrator-bio detail to bundle (core fields vs full rijāl texts).
- **Urdu swap**: sunnah.com Urdu is more complete/correct than our current public-domain Urdu —
  recommend adopting it (build-time) for Bukhari and all collections, keeping honest missing states.
