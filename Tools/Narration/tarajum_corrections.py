#!/usr/bin/env python3
"""Turn the second look at the printed Akram-ut-Tarajum into text corrections.

An ayah changes only where the second look (tarajum_adjudicate.py) found a
typo, missing or extra words, or different wording - never for spelling alone
- and then takes the whole printed text of that ayah (the owner: the printed
book is authoritative). An ayah goes to review instead, for a person to look
at the page, when the second look was not certain, could not read a word, or
its printed text hardly resembles the ayah (it may have read the wrong one).

    tarajum_corrections.py <adjudicated dir> <out dir>
        writes corrections.json  {"surah:ayah": printed text}
               review.json       the ayat a person must look at
               website_errors.json  typing errors in the website text, for the Silsila
"""

from __future__ import annotations

import difflib
import json
import sys
from pathlib import Path

from tarajum_compare import words

CHANGES = {"typo_in_app", "missing_from_app", "extra_in_app", "different_wording"}


def main() -> int:
    source, out = Path(sys.argv[1]), Path(sys.argv[2])
    corrections, review, website_errors = {}, [], []
    counts = {"unchanged": 0, "corrected": 0, "review": 0}
    for path in sorted(source.glob("*.json")):
        item = json.loads(path.read_text(encoding="utf-8"))
        check = item["check"]
        key = f"{item['surah']}:{item['ayah']}"
        real = [d for d in check["differences"] if d["kind"] in CHANGES]
        if not real:
            counts["unchanged"] += 1
            continue
        printed = " ".join(check["printed"].split())
        likeness = difflib.SequenceMatcher(None, words(item["app"]), words(printed), autojunk=False).ratio()
        reason = ("not certain" if not check["certain"] else "unreadable word" if "؟]" in printed
                  else f"printed text unlike the ayah ({likeness:.2f})" if likeness < 0.6 else None)
        entry = {"ayah": key, "app": item["app"], "printed": printed, "differences": real, "pages": item["pages"],
                 "notes": check["notes"]}
        if reason:
            review.append({**entry, "reason": reason})
            counts["review"] += 1
            continue
        corrections[key] = printed
        counts["corrected"] += 1
        typos = [d for d in real if d["kind"] != "different_wording"]
        if typos:
            website_errors.append({"ayah": key, "errors": typos, "pages": item["pages"]})
    out.mkdir(parents=True, exist_ok=True)
    for name, body in (("corrections.json", corrections), ("review.json", review), ("website_errors.json", website_errors)):
        (out / name).write_text(json.dumps(body, ensure_ascii=False, indent=1), encoding="utf-8")
    print(counts, "| website typing errors in", len(website_errors), "ayat")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
