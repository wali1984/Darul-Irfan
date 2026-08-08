# Hadith collections — sunnah.com inventory & build-out plan

_Internal planning document (not shipped in any app bundle). Compiled 2026-08-08 by
enumerating https://sunnah.com and probing each collection live (book counts, hadith
totals, and the languages the site actually serves per collection)._

## How this was measured

- Master list from the sunnah.com homepage ("The Nine Books", "Other Primary
  Collections", "Selections") — 26 collections.
- **Languages actually served**: the collection HTML ships English + Arabic inline.
  **CORRECTION (superseded):** an earlier version of this doc said "no Urdu" — that was
  wrong. sunnah.com **does** serve Urdu, loaded at runtime from the keyless endpoint
  `GET /ajax/urdu/{collection}/{book}`. Bukhari Urdu coverage is ~100% (6,283/6,283 across
  95 of 97 books; books 64/65 need per-chapter fetch). Abu Dawud confirmed too. See
  `Docs/HADITH_API_AND_URDU_FINDINGS.md` for the authoritative language + endpoint details.
- **Counts**: book count = book links on the landing page; hadith total = the
  collection's top reference number where the landing page exposes it. Advanced
  Arabic-only collections don't expose per-hadith ranges the same way, so their totals
  are marked _large / TBD at build_.

## Inventory

### The Nine Books (الكتب التسعة)

| # | Collection | slug | Books | Hadith (sunnah.com ref) | Languages served | We ship it? | Text source |
|---|------------|------|------:|------------------------:|------------------|-------------|-------------|
| 1 | Sahih al-Bukhari | `bukhari` | 97 | 7,563 | Arabic, English | **Yes — done** | fawazahmed0 (verified mirror) |
| 2 | Sahih Muslim | `muslim` | 56 | ~3,033 | Arabic, English | Yes (text) | fawazahmed0 |
| 3 | Sunan an-Nasa'i | `nasai` | 51 | ~5,758 | Arabic, English | Yes (text) | fawazahmed0 |
| 4 | Sunan Abi Dawud | `abudawud` | 43 | 5,274 | Arabic, English | Yes (text) | fawazahmed0 |
| 5 | Jami' at-Tirmidhi | `tirmidhi` | 49 | ~3,956 | Arabic, English | Yes (text) | fawazahmed0 |
| 6 | Sunan Ibn Majah | `ibnmajah` | 37 | ~4,341 | Arabic, English | Yes (text) | fawazahmed0 |
| 7 | Muwatta Malik | `malik` | 61 | ~1,985 | Arabic, English | Yes (text) | fawazahmed0 |
| 8 | Musnad Ahmad | `ahmad` | partial | partial (~1,400 on site) | Arabic, English | No | sunnah.com scrape (partial upstream) |
| 9 | Sunan ad-Darimi | `darimi` | 23 | large / TBD | **Arabic only** | No | sunnah.com scrape |

### Other Primary Collections (المصادر الأصلية الأخرى)

| Collection | slug | Books | Languages served | Text source |
|------------|------|------:|------------------|-------------|
| Sahih Ibn Khuzayma | `ibnkhuzayma` | 7 | **Arabic only** | sunnah.com scrape |
| Sahih Ibn Hibban | `ibnhibban` | 64 | **Arabic only** | sunnah.com scrape |
| Mustadrak al-Hakim | `hakim` | 49 | **Arabic only** | sunnah.com scrape |
| Musannaf `Abd ar-Razzaq | `abdurrazzaq` | 31 | **Arabic only** | sunnah.com scrape |
| Musannaf Ibn Abi Shayba | `ibnabishayba` | 39 | **Arabic only** | sunnah.com scrape |
| Sunan ad-Daraqutni | `daraqutni` | 28 | **Arabic only** | sunnah.com scrape |
| As-Sunan al-Kubra (Bayhaqi) | `bayhaqi` | 19 | **Arabic only** | sunnah.com scrape |
| Sunan an-Nasa'i al-Kubra | `nasaikubra` | 69 | **Arabic only** | sunnah.com scrape |
| Al-Adab Al-Mufrad | `adab` | 57 | Arabic, English | sunnah.com scrape (~1,322) |
| Ash-Shama'il Al-Muhammadiyah | `shamail` | 56 | Arabic, English | sunnah.com scrape (~417) |

### Selections (المصادر الثانوية)

| Collection | slug | Books | Hadith | Languages served | Text source |
|------------|------|------:|-------:|------------------|-------------|
| An-Nawawi's 40 Hadith | `nawawi40` | 1 | 42 | Arabic, English | fawazahmed0 (`nawawi`) / sunnah.com |
| Riyad as-Salihin | `riyadussalihin` | 19 | ~1,896 | Arabic, English | sunnah.com scrape |
| Mishkat al-Masabih | `mishkat` | ~29 | ~5,978 | Arabic, English | sunnah.com scrape |
| Bulugh al-Maram | `bulugh` | 16 | ~1,432 | Arabic, English | sunnah.com scrape |
| Collections of Forty | `forty` | — | ~42 | Arabic, English | sunnah.com scrape |
| Hisn al-Muslim | `hisn` | — | ~268 | Arabic, English | sunnah.com scrape |
| Special Virtues of the Qur'an | `virtues` | — | ~93 | Arabic, English | sunnah.com scrape |

_(40 Hadith Qudsi and Shah Waliullah Dehlawi's 40 are in fawazahmed0 as `qudsi` /
`dehlawi` and sit under sunnah.com's "Collections of Forty".)_

## Key facts that shape the plan

1. **Urdu**: sunnah.com does not serve Urdu text for any of these collections (verified).
   So every collection ships with Arabic + English from the source, plus our existing
   public-domain Urdu **only where we already have it** (the six books + Malik). New
   sunnah.com-only collections will have **no Urdu** and must show it honestly as missing.
2. **Two text tiers**:
   - **Tier A — text already vendored** (fawazahmed0 mirror, en+ar+ur): the six books +
     Malik + the 40-hadith sets. These need only the same kitab-structure enrichment +
     vetting that Bukhari got. No scraping.
   - **Tier B — sunnah.com-only** (Ahmad, Darimi, Adab, Shama'il, Riyad, Mishkat, Bulugh,
     Hisn, Forty, Virtues, and the Arabic-only advanced collections): text must be
     fetched from sunnah.com. Many are **Arabic-only**; Musnad Ahmad is only partially on
     the site.
3. **The app is already collection-agnostic**: `HadithBook.sections`, the `sections_json`
   schema column, and the reader's book grouping + reference block work for any
   collection. Adding a collection is data-only (a pack + catalogue entry); no per-book
   Swift code.

## Build-out plan

**Phase 0 — Bukhari (DONE).** Finished proof: 7,583 narrations, 97 books, vetted, committed.

**Phase 1 — the rest of Tier A (Muslim, Nasa'i, Abu Dawud, Tirmidhi, Ibn Majah, Malik).**
For each: fetch its sunnah.com book index (the `sunnah_<slug>_books.json` file, exactly like
`sunnah_bukhari_books.json`), run the same `enrich_*_sections.py` to assign every narration
to its book + write the `sections` catalogue, then `vet_*` to produce a per-collection
integrity report. Generalise the two Bukhari scripts to take a `--collection` argument so
one script covers all seven. Sync all four platforms, hash-verify, bump the manifest once at
the end. This is the natural next commit and needs no scraping.

**Phase 2 — 40-hadith selections (Nawawi 40, Qudsi 40, Dehlawi 40).** Small, already
vendored; add catalogue entries + trivial single-book sections. Confirm each against
sunnah.com's `nawawi40` / `forty` pages.

**Phase 3 — Tier B English+Arabic collections (Adab al-Mufrad, Shama'il, Riyad as-Salihin,
Bulugh al-Maram, Mishkat, Hisn, Virtues).** These require fetching text from sunnah.com.
Build a collection-agnostic sunnah.com fetch+cache tool (book page → per-narration
ar/en + references + chapters), throttled and cached, reporting any page it cannot fetch.
Ship with Urdu marked missing. Sequence smallest first (Shama'il ~417, Virtues ~93, Hisn
~268, Bulugh ~1,432, Riyad ~1,896, Adab ~1,322, Mishkat ~5,978).

**Phase 4 — Arabic-only advanced collections + Musnad Ahmad + Darimi.** Largest and
Arabic-only (Ibn Hibban, Ibn Khuzayma, Hakim, the two Musannafs, Daraqutni, Bayhaqi,
Nasa'i al-Kubra, Darimi; Ahmad is only partially on the site). Ship Arabic-only with
English/Urdu honestly absent. Lowest priority; confirm the product wants isnad-heavy
Arabic-only collections in a general-audience reader before investing the scrape.

**Cross-cutting**: one generalized `Tools/Hadith/build_collection.py --collection <slug>`
(index → enrich → vet) replaces the Bukhari-specific pair; one manifest bump per batch;
every collection's catalogue count computed from its packed records; four-platform
hash parity enforced by the existing content-integrity gate.
