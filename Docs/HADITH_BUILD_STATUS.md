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

## Update 2026-08-08 (later) — schema v6 + reader UI landed

Built in parallel with the data, against the ingester's output shape, in three
safe commits (all additive; every call site checked; only one protocol
implementer so no mocks broke):

- `4132fd9` — tappable search results (bug fix) + ingestion tool + docs.
- `849cbc6` — **schema v6 data layer**: `HadithEntry` gains typed
  `arabicSegments` (isnad/matn/verse + narratorId + surah/ayah), `quranRefs`,
  `urduSanad`/`urduText`, and bab chapter; new `HadithSegment`/`QuranRef`/
  `HadithNarrator`/`NarratorAppraisal`; additive migration v6 (nullable columns
  + `hadith_narrators`); repository read/write + narrator store; SeedBundle +
  ContentSync import. Unit tests: enriched decode+round-trip, segment fallback,
  narrator round-trip, readingIndex.
- `9b2e406` — **reader UI**: Arabic rendered as one `AttributedString` `Text`
  (shaping/RTL intact) with isnad + verse as green links (`.tint`) and matn
  near-black; `openURL` routes narrator taps → native `NarratorBioSheet`
  (Arabic + English/Urdu) and verse taps → our own Quran reader at surah:ayah
  (`.openQuranAyah` → `ReadTabView`). Split Urdu (grey chain over the text).
  All native, our IndoPak + Urdu faces, our theme; **no external branding or
  runtime calls**. Everything degrades to plain text until the ingested data
  lands, so it is safe to ship now.

Known minor fidelity note: isnad and verse links share one green (`.tint`
colours all links the same); a two-tone green would need per-run colour that
`Text` links override — deferred as cosmetic.

Remaining (data population + rollout), unchanged: run `ingest_sunnah.py` on a
networked machine/CI to fill the enriched fields + narrator bios + verse refs
for Bukhari, then all collections; ship core collections in-app and structure
the rest for `DownloadManager` if bundle size requires.

## What still needs CI / the user

- **CI (`ios-verify`)**: compiles the search-navigation change + runs unit/UI tests.
- **User**: `git push origin feat/official-platform` (no push credential in sandbox);
  run `ingest_sunnah.py` on a networked machine (or wire it into CI) to populate the
  full trilingual + bios + verse-link data.
