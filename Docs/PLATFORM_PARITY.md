# Platform parity — hadith reader

State of the hadith feature across the four platforms after the 2026-08-11
parity pass. Before it, the 26 collections and the narrator store were bundled
byte-identical on all four platforms but **only iOS had any hadith UI**; the
data sat unread on Android, Harmony and Web.

Seed data is identical everywhere by construction (hash-verified on every
sync); this table is about the reader UI.

| Capability | iOS | Web | Android | Harmony |
|---|---|---|---|---|
| Collections list (26, honest hasUrdu) | ✔ | ✔ | ✔ | ✔ |
| Cover page (3 s auto-advance, tap to skip) | ✔ | ✔ | ✔ | ✔ |
| Cover suppressed on search jump | ✔ | ✔ | ✔ | — (jump stays in reader) |
| Paged reading | ✔ | ✔ | ✔ | ✔ |
| In-collection search | ✔ | ✔ | ✔ | ✔ |
| Search jump lands on exact narration (canonicalID) | ✔ | ✔ | ✔ | ✔ |
| Per-language text + honest missing-translation note | ✔ | ✔ | ✔ | ✔ |
| Narrator bios per language (12,643 store) | ✔ sheet | ✔ popup | ✔ dialog | ✔ overlay |
| Colored isnad/matn/verse spans inline | ✔ | ✔ | chips row | chips row |
| Verse quote opens Quran reader | ✔ | ✔ (surah) | — | — |
| Cross-collection search | ✔ | — | — | — |
| Kitab (book) section headers | ✔ | — | — | — |

Implementation notes:

* **Android** streams the packs with `JsonReader` — a page, a search pass or
  one narrator is read in a single pass, so the 45 MB Bukhari pack is never
  held in memory. Whole tree compiles clean against android-36 (verified with
  the stub-R harness; CI remains the authoritative build).
* **Harmony** parses a pack lazily on first open and caches it; the narrator
  store loads on the first bio tap. Cannot be compiled on this machine —
  written to the file's existing ArkTS idiom; validate on a DevEco build.
* **Web** loads packs on demand and renders the typed Arabic segments with
  green tappable narrator names (popup) and verse quotes (opens the Quran
  tab). Verified locally: syntax, build and content checks all pass.
* Android/Harmony render narrator names as a tappable chips row rather than
  colored inline spans — same function, simpler text layout. Inline coloring
  is the natural next step on both.

Verifier coverage: the Harmony validator now checks all 26 packs against the
catalogue's counts (no-over-claim, same rule as the iOS content gate); Android
and Web verifiers pass unchanged.
