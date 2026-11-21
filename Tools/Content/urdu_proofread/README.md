# Urdu proofreading: from the register to the apps

The Urdu text of the library (books, Asrar-at-Tanzil, Akram-ut-Tafaseer: 17,551
pages of `book_pages.json`) is being read page by page. The reader's findings
are kept outside the repository, in
`outputs/darul-urdu-proofread-2026-11-20/findings.json`, anchored to the seed as
it stood at commit `3ae7029`. The register grows while the reading goes on.

Everything here starts again from that commit's seed each time, so it can be
run as often as the register changes.

## A round

Run from the iOS checkout (`pw/i-proof`, branch `claude/urdu-proofread`).

1. `python Tools/Content/urdu_proofread/apply_proofread.py` - report only. It
   says how many findings it would apply, hold, or leave for a reading.
2. `python Tools/Content/urdu_proofread/review_queue.py` - writes the findings
   that change wording and have no decision yet as batches, and `HELD.csv`.
3. Each batch is read by a fluent reader of Urdu, who answers `apply` or `hold`
   for every finding (the rules are in the batch brief; in short: apply a plain
   slip with one possible fix, hold anything that is the author's own usage,
   changes meaning, or that the printed book also has). The answers go beside
   the batch as `decisions-…json`.
4. `python Tools/Content/urdu_proofread/merge_decisions.py` - gathers the
   answers into `decisions.json` (kept in the repository).
5. `python Tools/Content/urdu_proofread/apply_proofread.py --write` - writes
   `book_pages.json`, `book_links.json` and `quran_tafsir.json` in the iOS seed.
6. `python Tools/Content/urdu_proofread/verify_arabic.py <commit before>` and
   `python Tools/ContentIntegrity/check_content.py` - both must pass.
7. `python Tools/Content/urdu_proofread/spread.py` - copies the three files and `manifest.json` to Android
   (`app/src/main/assets/seed`) and the desktop (`content`), byte for byte.

## What is never changed

- `quran_ayahs.json`, and the Qur'an's Arabic wherever it is quoted: a finding
  that touches it is refused (`protected` in the ledger) however sure the
  reader is. So is a mark or number that closes a line of Arabic.
- The wording of the author where the printed book reads as the app does. Such
  findings are held for the owner (`HELD.csv`).

## Files written outside the repository

`outputs/darul-urdu-proofread-apply/`: `summary.json`, `ledger.json` (every
finding and what became of it), `applied-edits.json` (before and after),
`not-applied.json`, `HELD.csv`, `review/`.
