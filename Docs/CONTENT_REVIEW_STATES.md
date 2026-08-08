# Content review states

Two approval levels sit between text arriving in the pipeline and text reaching
a reader. They exist so that a TestFlight build is not held hostage to a task
that only matters for public release, and so that public release is not reached
by accident.

## The states

| State | Meaning | TestFlight | App Store |
| --- | --- | --- | --- |
| `draft` | Incomplete or unreviewed. A placeholder, a partial import. | no | no |
| `testFlightApproved` | Vision review, extracted-text review and the content validators all passed. No known corruption, duplicate loss or schema fault. Line-by-line human proofreading still outstanding. | **yes** | no |
| `publicApproved` | Additionally proofread by a person, or cross-verified line by line against independent authoritative sources. | yes | yes |
| `rejected` | Found faulty. Must not ship anywhere. | no | no |

The App Store gate is **defined but not enforced yet**. `ReviewState.allowedOnAppStore`
exists and is correct; nothing calls it. It turns on when the proofreading pass
is far enough along that enforcing it would not empty the reader.

## Where the state lives

Internal metadata only, in three places:

- `quran_editions.json` — `reviewState` per edition, persisted to
  `quran_editions.review_state` so the model round-trips through the store.
- `hadith_books.json` — `reviewState` for the corpus as a whole.
- `manifest.json` — `reviewState` for the seed, the single field the content
  gate checks before a build may ship.

It is **never rendered as a label on the text**. No badge saying "OCR-derived",
no asterisk, no disclaimer beside an ayah. A reader sees the work, its author
and its source. Provenance and review state belong in Acknowledgements and in
`Docs/CONTENT_INTEGRITY.md`, not in the reader.

The same rule governs missing text: a gap is shown as a gap. The reader never
substitutes English prose into an Urdu slot (Nastaliq, right-to-left, reading as
though it were the translation) and never repeats the Arabic as its own
translation. See `HadithEntry.text(languageCode:)`, which deliberately has no
fallback, and `availableText(preferring:)`, which returns the language alongside
the text so a view can style it for the script it really is.

## Current assignment

| Content | State | Why |
| --- | --- | --- |
| Quran Arabic (6,236 ayat) | `publicApproved` | Triple-verified against Tanzil, fawazahmed0 and quran.com — see `QURAN_VERIFICATION.md`. |
| `sample-en` (Pickthall) | `publicApproved` | Public domain, verified in the same pass. |
| `ur-jalandhry` | `publicApproved` | Public domain, verified in the same pass. |
| `akram-ut-tarajum-en` | `testFlightApproved` | OCR-derived, reviewed, two owner-supplied corrections applied (7:56, 7:82). Not yet proofread line by line. |
| `akram-ut-tarajum-ur` | `testFlightApproved` | OCR-derived, reviewed, owner-supplied re-split at 75:18–21. |
| `asrar-at-tanzil-en` | `testFlightApproved` | OCR-derived, gaps filled and validated against the authoritative source site. Two gaps left blank because the source itself is wrong there — never guessed. |
| `asrar-at-tanzil-ur` | `testFlightApproved` | 1,118 blocks, all 114 surahs. |
| `akram-ut-tafaseer-ur` | `draft` | One placeholder block, surah 1 only. Preserved, not offered as a complete edition. |
| Hadith corpus (36,221 narrations) | `testFlightApproved` | Public-domain corpus, identifiers rebuilt and integrity-gated. No human proofreading pass. |

The seed manifest carries `testFlightApproved`, the weakest state among content
the app actually offers.

## What does not block a TestFlight tag

Reviewed content does not fail a gate merely because a human has not read every
line of it. Specifically, none of these block a tag:

- Outstanding line-by-line proofreading of any `testFlightApproved` edition.
- The 154 replacement characters inherited from the upstream hadith corpus
  (see below).
- Missing translations, provided they are represented honestly.

## Known upstream defect: 154 lost Arabic characters

76 narrations carry a `U+FFFD` replacement character in their Arabic, 154 in
total. Each one stands where a single Arabic character was lost to a bad decode
**upstream, before the data reached this project** — the same corruption is
present in both of the upstream Arabic editions (with and without diacritics),
so it cannot be repaired from that source. It has been in every build the app
has shipped.

The exact inventory is recorded in
`Tools/ContentIntegrity/known_upstream_defects.json`, per narration and per
language. The content gate uses it to tell an inherited defect from a new one:
**any replacement character not in that inventory, or one more than recorded,
fails the build.** The inventory cannot drift, and it can only shrink.

Repairing these needs a second authoritative Arabic corpus to cross-reference
against. That is a public-release task.

## Running the gate

```sh
python3 Tools/ContentIntegrity/check_content.py --report Docs/CONTENT_INTEGRITY.md
```

Exit code 0 means shippable. It runs in both Codemagic workflows — `ios-verify`
on every push, and `ios-testflight` before a signed build is archived, so a
release cannot get past a failing gate even if the tag is pushed directly.
