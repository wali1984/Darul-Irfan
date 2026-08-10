#!/usr/bin/env python3
"""Backfill plain text_ar from typed segments in from-scratch packs.

parse_book_page emitted arabicSegments but no text_ar, so every pack built
from scratch before the fix shipped null plain Arabic (mishkat: 0 of 5,306) —
which empties the reader's Arabic display and text_ar search for those
collections. The builder is fixed; this repairs packs already on disk.

Only records with segments and no text_ar are touched, so the seven core
packs (whose text_ar is the canonical fawazahmed0 Arabic) are untouched by
construction. Idempotent; writes all four platform seed dirs.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ingest_sunnah import SEED_DIRS, PRIMARY_SEED  # noqa: E402


def main() -> int:
    changed_any = False
    for pack_path in sorted(PRIMARY_SEED.glob("hadith_*.json")):
        slug = pack_path.stem[len("hadith_"):]
        if slug in ("books", "narrators"):
            continue
        records = json.loads(pack_path.read_text(encoding="utf-8"))
        filled = 0
        for r in records:
            if r.get("text_ar") or not r.get("arabicSegments"):
                continue
            text = re.sub(r"\s+", " ", " ".join(
                s.get("text", "") for s in r["arabicSegments"])).strip()
            if text:
                r["text_ar"] = text
                filled += 1
        if not filled:
            continue
        changed_any = True
        body = json.dumps(records, ensure_ascii=False, indent=1) + "\n"
        for seed in SEED_DIRS:
            (seed / pack_path.name).write_text(body, encoding="utf-8", newline="\n")
        print(f"  {slug:16} text_ar backfilled for {filled} records")
    if not changed_any:
        print("  nothing to backfill")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
