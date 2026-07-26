# Official Quran translation importer

This tool imports the complete Akram-ut-Tarajum Urdu and English text from the
organization's structured Quran reader into the native iOS seed.

```bash
python3 -m pip install -r Tools/Quran/requirements.txt
python3 Tools/Quran/import_akram_ut_tarajum.py --check-only
python3 Tools/Quran/import_akram_ut_tarajum.py
```

`--check-only` downloads and validates every source page without changing the
repository. A normal run writes both native editions and the OCR/reference
corpora. It is idempotent: unchanged source text does not bump the seed version.

Run the offline regression tests with:

```bash
python3 -m pytest Tools/Quran/tests -q
```

Do not manually edit generated translation rows. Correct the official source
or the explicit canonical-number mapping, then regenerate and review the
verification checksum.
