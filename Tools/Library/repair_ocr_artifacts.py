"""Repair the OCR and validator artifacts found in the v1.11 content review.

Each repair is narrow and named; nothing here rewrites text by guesswork.

1. Validator commentary leaked into scripture. The Asrar-at-Tanzil English
   translation of 2:215 ends with the checking model's own note
   (`"}]} <b>Note</b>: The OCR is correct...`). Everything from the leaked
   JSON tail onward is removed; the translation before it is complete.

2. A wrong honorific invented by the OCR. In the Urdu Asrar-at-Tanzil scans
   the ﷺ ligature after the Prophet's name was read as
   "رَحْمَةُ اللہِ عَلَیْہِ السَّلَامِ" - an honorific for the deceased
   righteous, not for the Prophet - sometimes twice in a row. Each run after
   "رسول"/"حضور اکرم" becomes ﷺ. One page of Rah-Nawerd-e-Shauq uses the same
   garble after a prophet's name, where it becomes "علیہ السلام".

Idempotent. Writes the four platform seeds.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from segment_akram_tafaseer import SEED_DIRS  # noqa: E402

LEAK = re.compile(r'\}\]\}\s*<b>Note</b>[\s\S]*$')
GARBLE = r"(?:رَحْمَةُ اللہِ عَلَیْہِ السَّلَامِ|رحمۃ اللہ علیہ السلام)"
AFTER_PROPHET = re.compile(r"(رُمول|رسول|حضور اکرم)\s*(?:" + GARBLE + r"\s*)+")
AFTER_PROPHET_AS = re.compile(r"(اسماعیل)\s+" + GARBLE)


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    for seed in SEED_DIRS:
        changed = []

        path = seed / "quran_translations.json"
        rows = json.loads(path.read_text(encoding="utf-8"))
        fixed = 0
        for row in rows:
            new = LEAK.sub("", row["text"]).rstrip()
            # The leak began right after the verse's closing quotation mark;
            # an earlier run of this repair took that mark with it.
            if (row["editionID"], row["surahNumber"], row["ayahNumber"]) == ("asrar-at-tanzil-en", 2, 215) and new.count('"') % 2 == 1:
                new += '"'
            if new != row["text"]:
                row["text"] = new
                fixed += 1
        if fixed:
            path.write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8", newline="\n")
            changed.append(f"translations: {fixed}")

        path = seed / "book_pages.json"
        pages = json.loads(path.read_text(encoding="utf-8"))
        fixed = 0
        for page in pages:
            new = AFTER_PROPHET.sub(lambda m: m.group(1) + " ﷺ ", page["text"])
            new = AFTER_PROPHET_AS.sub(lambda m: m.group(1) + " علیہ السلام", new)
            if new != page["text"]:
                page["text"] = new
                fixed += 1
        if fixed:
            # Compact and without a final newline, exactly as the ingest writes it.
            path.write_text(json.dumps(pages, ensure_ascii=False, separators=(",", ":")), encoding="utf-8", newline="\n")
            changed.append(f"book pages: {fixed}")
        print(seed, changed or "nothing to repair")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
