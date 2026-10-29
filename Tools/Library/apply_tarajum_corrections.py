"""Put the printed Akram-ut-Tarajum's wording into the app's Urdu translation.

The Urdu translation was typed from naqshbandiaowaisiah.org, which has typing
errors (113:3 "اندھیر اچھا" for "اندھیرا چھا", 2:225 "بردباد" for "بردبار")
and, in places, wording that differs from the printed book. The owner ruled
(2026-10-28) that the printed book is authoritative. Every differing ayah was
read from the page twice (Narration/tarajum_check.py, tarajum_adjudicate.py);
corrections.json holds the printed text of each ayah that changes.

Writes quran_translations.json and the Ayah of the Day text built from it on
all four platforms, and bumps the manifest. Idempotent.

    apply_tarajum_corrections.py <corrections.json>
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from ingest_tafsir_pages import SEED_DIRS

EDITION = "akram-ut-tarajum-ur"


def main() -> int:
    corrections = {tuple(map(int, key.split(":"))): text
                   for key, text in json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")).items()}
    seed = SEED_DIRS[0]
    translations = json.loads((seed / "quran_translations.json").read_text(encoding="utf-8"))
    daily = json.loads((seed / "daily_ayat.json").read_text(encoding="utf-8"))

    changed = 0
    for row in translations:
        key = (row["surahNumber"], row["ayahNumber"])
        if row["editionID"] == EDITION and key in corrections and row["text"] != corrections[key]:
            row["text"] = corrections[key]
            changed += 1
    text = {(r["surahNumber"], r["ayahNumber"]): r["text"] for r in translations if r["editionID"] == EDITION}
    daily_changed = 0
    for entry in daily:
        urdu = " ".join(text[(entry["surah"], ayah)].strip() for ayah in range(entry["ayahStart"], entry["ayahEnd"] + 1))
        if entry.get("urdu") != urdu:
            entry["urdu"] = urdu
            daily_changed += 1
    print(f"ayat corrected: {changed} of {len(corrections)} listed; Ayah of the Day entries updated: {daily_changed}")
    if not changed and not daily_changed:
        return 0

    outputs = {
        "quran_translations.json": json.dumps(translations, ensure_ascii=False, indent=1),
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
