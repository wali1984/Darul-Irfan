# Hadith rebuild — build status & engineering decisions

_Updated 2026-08-08. Records what is committed, what is deferred, and the
judgment calls made under the sandbox's hard constraints. Internal (not shipped)._

## Hard constraints this environment imposes (and why they shape the plan)

1. **No scraping in the sandbox.** The agent may only fetch via restricted tools
   that route responses through its context; it cannot run a Python/curl scraper.
   Moving the full corpus (7,583 Bukhari hadith × ar-segments + en + ur, plus
   thousands of narrator bios) through context and re-writing it to disk is not
   feasible. → The bulk **data ingestion runs on a network-enabled machine/CI**
   via `Tools/Hadith/ingest_sunnah.py`, not in-session.
2. **No local Swift compiler.** App changes are verified by inspection here and
   compiled by CI (`ios-verify`). → Ship **small, auditable** Swift increments;
   avoid large blind refactors that previously broke the build.
3. **No push credential.** Everything up to the commit is done; the user runs
   `git push origin feat/official-platform`.

## Decisions (resolved per the final directive)

- Source = **keyless build-time ingestion**; all data native/bundled; zero runtime
  calls to sunnah.com/quran.com; no external branding. No API key needed (the
  official API needs a key and lacks Urdu + bios anyway).
- **Adopt sunnah.com Urdu** (≈100% coverage, pre-split isnad/matn) over the current
  public-domain Urdu (7,019/7,583, with defects).
- **Narrator bios**: ship the source's Arabic + English in full depth. Urdu bios do
  not exist at source; they are **flagged for a reviewed translation pass**, not
  machine-fabricated — auto-translating classical rijāl (jarḥ wa-taʿdīl) text as
  authoritative religious content would violate the project's content-honesty rule
  (CLAUDE.md: sacred/scholarly content is never invented). This is the one place the
  "translate it yourself" instruction is deliberately deferred to a reviewed step;
  everything else is honored.

## Shipped in this commit (build-ready, CI-verifiable)

- **Search is now tappable (Requirement E — the reported bug).** Results in
  `HadithHomeView` are `NavigationLink`s (`HadithRoute.hadith(book, number)`); the
  reader opens the exact narration via a new `readingIndex(bookID:displayNumber:)`
  repository method, base-offset paging, `ScrollViewReader` scroll-to, and a fading
  highlight. Only one protocol implementer exists (`HadithRepository`), so no mocks
  broke; the added init param is optional (safe at every call site).
- **Bukhari data**: 7,583 lossless records, 97 kitab sections, catalogue counts from
  packed data, cross-platform hash-identical, integrity gate green (from the prior
  commit `3b67680`; unchanged here).
- **Ingestion tool** `Tools/Hadith/ingest_sunnah.py` — collection-agnostic, keyless,
  throttled/cached/retrying, with Arabic→typed-segment parsing (isnad/matn/verse),
  Quran-ref extraction (`openquran` → surah+1), Urdu merge from `/ajax/urdu`, and a
  narrator-bio parser. Runs on a network machine to emit the full bundled data.
- **Docs**: `HADITH_API_AND_URDU_FINDINGS.md` (API + keyless Urdu endpoint + bios +
  verse links), `HADITH_COLLECTIONS_INVENTORY.md` (26 collections), this file.

## Native data model (target — produced by the tool, consumed by the reader)

- `HadithEntry` (extend): `arabicSegments:[{type:isnad|matn|verse, text, narratorId?,
  surah?, ayahStart?, ayahEnd?}]`, `urduSanad`, `urduText`, `quranRefs:[{surah,
  ayahStart, ayahEnd}]`, plus existing en/ar/ur + refs + grades + kitab + bab.
- `HadithNarrator` store (bundled): id, nameEn/nameAr, kunya, generation, deathYear,
  grade, lineage, cities, affiliations, hadithCount, teacherIds/studentIds,
  appraisals; `needs_ur` where Urdu bio is pending review.
- Additive schema migration (v6) to hold segments/verse-refs + a `hadith_narrators`
  table. Reader renders green isnad (tap→native bio sheet), green verse (tap→our
  Quran reader at surah:ayah), black matn, grey translation — our IndoPak + Urdu
  faces; falls back to plain text when segment data is absent.

## Next increments (in order), against real ingested data

1. Run `ingest_sunnah.py` (network machine) → full Bukhari ar-segments + en + sunnah
   Urdu + narrator bios + quran refs; pack with lossless keys; vet; sync 4 platforms.
2. Land the schema v6 + model + reader coloring/bio-sheet/verse-navigation (validated
   against the ingested data, so it's not a blind change).
3. Extend to all collections; for total bundle size, ship the core collections in-app
   and structure the rest for on-demand fetch via the existing `DownloadManager`
   (documented, not silently dropped). Arabic-only advanced collections ship with
   en/ur honestly absent.

## What still needs CI / the user

- **CI (`ios-verify`)**: compiles the search-navigation change + runs unit/UI tests.
- **User**: `git push origin feat/official-platform` (no push credential in sandbox);
  run `ingest_sunnah.py` on a networked machine (or wire it into CI) to populate the
  full trilingual + bios + verse-link data.
