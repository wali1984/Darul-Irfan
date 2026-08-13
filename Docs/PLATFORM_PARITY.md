# Platform parity — hadith reader

State after the 2026-08-11 full-parity pass. Seed data is identical everywhere
by construction (hash-verified on every sync); this table is about the reader.

| Capability | iOS | Web | Android | Harmony |
|---|---|---|---|---|
| Collections list (26, honest hasUrdu) | ✔ | ✔ | ✔ | ✔ |
| Cover page (3 s auto-advance, tap to skip) | ✔ | ✔ | ✔ | ✔ |
| Cover suppressed on search jump | ✔ | ✔ | ✔ | ✔ |
| Paged reading | ✔ | ✔ | ✔ | ✔ |
| In-collection search | ✔ | ✔ | ✔ | ✔ |
| Cross-collection search | ✔ | ✔ | ✔ | ✔ |
| Search jump lands on exact narration (canonicalID) | ✔ | ✔ | ✔ | ✔ |
| Per-language text + honest missing-translation note | ✔ | ✔ | ✔ | ✔ |
| Narrator bios per language (12,643 store) | ✔ sheet | ✔ popup | ✔ dialog | ✔ overlay |
| Colored inline isnad/matn/verse spans, tappable | ✔ | ✔ | ✔ ClickableSpan | ✔ Span.onClick |
| Verse quote opens the Quran reader | ✔ | ✔ | ✔ | ✔ |
| Kitab (book) section headers | ✔ | ✔ | ✔ | ✔ |
| Searchable contents page, jumps to a kitab's first narration | ✔ sheet | ✔ overlay | ✔ dialog | ✔ overlay |

Implementation notes:

* **Android** streams the packs with `JsonReader` — a page, a search pass or
  one narrator is read in a single pass, so the 45 MB Bukhari pack is never
  held in memory. Cross-collection search scans the packs sequentially with a
  live progress line. The Arabic renders as one `SpannableStringBuilder` with
  green `ClickableSpan`s (narrator → bio dialog, verse → Quran reader) so
  letter shaping is preserved. Whole tree compiles clean against android-36
  (stub-R harness; CI remains the authoritative build).
* **Harmony** parses a pack lazily per collection and caches it; the
  cross-collection search parses each pack transiently so the pass never
  accumulates the full corpus. Arabic renders as `Text`/`Span` runs with
  `onClick` on isnad and verse spans. **Builds green** — DevEco Studio is
  installed on the build machine and `hvigor assembleHap` produces the entry
  HAP (2026-08-12).
* **Web** renders the typed segments as tappable spans, searches all 26 packs
  sequentially with progress and result caps, and shows kitab headers from
  `sourceBook` plus the catalogue's section titles where a collection has
  them (currently Bukhari). Verified end to end locally: syntax, build and
  content checks all pass; the tab bar was widened to six columns.

Known data limits shared by all platforms (not UI gaps): all 22 multi-book
collections now carry named sections — 909 in total, 906 with Arabic titles and
584 with English, each count verified against the records that carry its
`sourceBook`. The 325 sections without an English title and all 909 without an
Urdu one are reviewed-translation gaps, held behind the gate in
HADITH_TRANSLATION_GATE.md rather than machine-filled; those headers fall back
to the Arabic title, which Urdu readers read natively. `sourceBook` is now
absent only on 12 records across the enriched core packs plus the 442 entries
of the four single-page works, which have no kutub at all. Coverage figures
live in HADITH_COVERAGE_GAPS.md.

Build verification (2026-08-12, all from `C:\Dev\Automation`): Android
`gradlew assembleDebug` and Harmony `hvigor assembleHap` both succeed on this
machine; Web passes `build.mjs` + `verify.mjs`; iOS type-checking remains
Codemagic's `ios-verify`.
