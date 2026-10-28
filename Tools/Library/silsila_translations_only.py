"""Keep only the Silsila's own Qur'an translations in the seed.

The first content build (2026-07-13) bundled two public-domain translations,
Pickthall (English, `sample-en`) and Fateh Muhammad Jalandhry (Urdu,
`ur-jalandhry`), before Akram-ut-Tarajum was available. The owner's rule is
that every Qur'an translation in the app comes from the Silsila, so this
removes both editions and their 12,472 rows, and rewrites the bundled Ayah of
the Day text from Akram-ut-Tarajum (Urdu and English) for the same ayat.

Writes all four platform seeds and bumps the manifest version. Idempotent.
"""

from __future__ import annotations

import json
import re

from ingest_tafsir_pages import SEED_DIRS

REMOVED = {"sample-en", "ur-jalandhry"}
SILSILA = {"en": "akram-ut-tarajum-en", "ur": "akram-ut-tarajum-ur"}


def main() -> int:
    seed = SEED_DIRS[0]
    editions = json.loads((seed / "quran_editions.json").read_text(encoding="utf-8"))
    translations = json.loads((seed / "quran_translations.json").read_text(encoding="utf-8"))
    daily = json.loads((seed / "daily_ayat.json").read_text(encoding="utf-8"))

    kept_editions = [e for e in editions if e["id"] not in REMOVED]
    kept_rows = [r for r in translations if r["editionID"] not in REMOVED]
    text = {(r["editionID"], r["surahNumber"], r["ayahNumber"]): r["text"] for r in kept_rows}

    for entry in daily:
        for field, language in (("english", "en"), ("urdu", "ur")):
            parts = [text.get((SILSILA[language], entry["surah"], ayah), "")
                     for ayah in range(entry["ayahStart"], entry["ayahEnd"] + 1)]
            if not all(parts):
                raise SystemExit(f"{entry['id']}: Akram-ut-Tarajum {language} is missing an ayah")
            entry[field] = " ".join(part.strip() for part in parts)

    print(f"editions: {len(editions)} -> {len(kept_editions)}")
    print(f"translation rows: {len(translations):,} -> {len(kept_rows):,}")
    print(f"Ayah of the Day entries rewritten from Akram-ut-Tarajum: {len(daily)}")

    outputs = {
        # Same layout as before (indent 1, a final "\n]"), so the diff shows only content.
        "quran_editions.json": json.dumps(kept_editions, ensure_ascii=False, indent=1),
        "quran_translations.json": json.dumps(kept_rows, ensure_ascii=False, indent=1),
        "daily_ayat.json": json.dumps(daily, ensure_ascii=False, indent=1),
    }
    for directory in SEED_DIRS:
        for name, body in outputs.items():
            (directory / name).write_text(body, encoding="utf-8", newline="")
        manifest = directory / "manifest.json"
        raw = manifest.read_text(encoding="utf-8")
        version = int(re.search(r'"version":\s*(\d+)', raw).group(1))
        manifest.write_text(re.sub(r'"version":\s*\d+', f'"version": {version + 1}', raw, count=1),
                            encoding="utf-8", newline="")
        print(f"  wrote {directory} (manifest {version + 1})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
