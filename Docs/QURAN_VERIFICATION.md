# Quran Arabic text — verification record

The bundled Quran Arabic (`Resources/SeedData/quran_ayahs.json`, all 114 surahs
/ 6,236 ayat) is a digital Uthmani text, **never OCR**. It was verified
error-free against three independent authoritative digitizations before
release.

## Provenance
- **Source of the bundled text:** Tanzil "quran-uthmani" edition (via
  api.alquran.cloud). Tanzil is a widely-used, scholarly-reviewed digital
  Quran.

## Triple verification (2026-07-13)
Compared the full 6,236-ayah set at the **rasm (consonantal skeleton)** level —
diacritics/marks normalized away so genuine textual differences surface while
cosmetic encoding differences between digitizations do not.

| # | Source | Result |
|---|---|---|
| 1 | Tanzil `quran-uthmani` (bundled) | baseline |
| 2 | fawazahmed0 `ara-quranuthmanihaf` | all match except source's own 97:1 (stray basmala fragment — bundled text is correct) |
| 3 | quran.com v4 KFGQPC Uthmani | **0 mismatches across all 6,236 ayat** |

- Counts verified: 114 surahs, 6,236 ayat, every per-surah ayah count matches
  `quran_surahs.json`.
- No missing, extra, or misordered ayat.
- Basmala correctly separated from ayah 1 of every surah except Al-Fatihah (1)
  and At-Tawbah (9); two surahs (95, 97) whose source basmala was malformed were
  fixed and re-verified.
- `daily_ayat.json` Arabic is rebuilt directly from the verified `quran_ayahs`
  so the daily-ayah card is byte-identical to the reader.

## Re-running the check
The verification scripts live outside the repo (session scratchpad):
`clean_verify_quran.py`, `final_quran_check.py`, `third_source_check.py`.
Re-point them at `Resources/SeedData/` to re-verify after any regeneration.

## Translations (not the Arabic — separate provenance)
- English: Pickthall (public domain).
- Urdu: Fateh Muhammad Jalandhry (public domain).
Translations are human renderings and are not part of the Arabic-text guarantee
above; they are bundled verbatim from their editions, not paraphrased.
