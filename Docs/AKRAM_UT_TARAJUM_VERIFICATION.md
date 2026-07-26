# Akram-ut-Tarajum verification

## Source and scope

- Official index: `https://www.naqshbandiaowaisiah.org/quran`
- Discovered source pages: 114 of 114
- Expected canonical ayat: 6,236
- Imported Urdu translations: 6,236
- Imported English translations: 6,236
- Missing, duplicate, empty, replacement-character, or control-character rows: 0
- Canonical paired-corpus SHA-256: `a2671697f9a38083b61f998e9186bb3c6325a3d9392067b71d108d485ce484a8`

The importer discovers individual surah URLs from the index instead of
maintaining a hard-coded slug list. Each source page must contain exactly the
ayah numbers declared by the app's verified 114-surah metadata before any
seed file is changed.

## Al-Fatihah alignment

The source page presents the basmalah as display row `0`, numbers
`Al-Hamdu...` as row `1`, and splits the app's canonical seventh ayah across
source rows `6` and `7`. The app's Arabic dataset counts the basmalah as ayah
`1` and combines the final phrase as ayah `7`.

The importer explicitly maps these eight display rows to the app's seven
canonical ayat. A regression test protects this mapping. Other surahs discard
the unnumbered display-row basmalah, except At-Tawbah, which has no such row.

## Outputs

- Native app data: `DarulIrfanApp/Resources/SeedData/quran_translations.json`
- Edition metadata: `DarulIrfanApp/Resources/SeedData/quran_editions.json`
- Urdu OCR ground-truth corpus: `Tools/OCR/akram_ut_tarajum_ocr_training.txt`
- Paired Urdu/English corpus: `Tools/OCR/akram_ut_tarajum_translations.txt`
- Reproducible importer: `Tools/Quran/import_akram_ut_tarajum.py`

The OCR corpus is UTF-8 with one Urdu record per canonical ayah:

```text
surah:ayah<TAB>Urdu
```

The paired reference corpus uses:

```text
surah:ayah<TAB>Urdu<TAB>English
```

Religious text is copied verbatim from the structured official source. The
importer performs whitespace and Unicode NFC normalization only; it does not
translate, paraphrase, spell-correct, or use OCR-generated wording.
