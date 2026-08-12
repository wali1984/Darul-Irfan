#!/usr/bin/env python3
"""Stamp sourceBook on collections whose source prints no in-book reference.

The nine advanced collections (Ibn Abi Shayba, ʿAbd ar-Razzāq, Bayhaqi, Nasa'i
al-Kubra, Ibn Hibban, Hakim, Daraqutni, Darimi, Ibn Khuzayma) carry no
"In-book reference" block on sunnah.com, so every record lacked sourceBook and
the reader showed no kitab structure for them at all.

The attribution is still fully determined: build_from_scratch appended records
by iterating the cached book pages in discover_books order, so the pack IS the
concatenation of per-page runs. Re-parsing each cached page yields its run
length, and positions map to book numbers exactly. The stamping refuses to
write unless the run lengths sum to the pack's length — a mismatch means the
cache and pack disagree, and guessing would misfile narrations.

Run fix_sections_sourcebook.py afterwards to rebuild sections and counts.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ingest_sunnah import SEED_DIRS, PRIMARY_SEED, discover_books, parse_book_page  # noqa: E402

# Every from-scratch collection qualifies: their packs are the exact
# concatenation of per-page runs. Enriched core packs (fawazahmed0 base) do
# NOT - their record order predates the pages - and must never be listed here.
SLUGS = ["ibnabishayba", "abdurrazzaq", "bayhaqi", "nasaikubra", "ibnhibban",
         "hakim", "daraqutni", "darimi", "ibnkhuzayma",
         "bulugh", "adab", "mishkat", "ahmad", "riyadussalihin", "shamail"]


def main() -> int:
    cache = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".hadith_cache")
    for slug in SLUGS:
        pack_path = PRIMARY_SEED / f"hadith_{slug}.json"
        records = json.loads(pack_path.read_text(encoding="utf-8"))
        landing_path = cache / f"_{slug}.html"
        if not landing_path.exists():
            print(f"{slug:14} SKIP: no cached landing page")
            continue
        books = discover_books(slug, landing_path.read_text(encoding="utf-8"))

        runs: list[tuple[object, int]] = []
        for book in books:
            page = cache / f"_{slug}_{book}.html"
            if not page.exists():
                continue
            parsed = parse_book_page(page.read_text(encoding="utf-8"))
            if parsed:
                runs.append((book, len(parsed)))

        total = sum(count for _, count in runs)
        if total != len(records):
            print(f"{slug:14} REFUSED: runs sum to {total}, pack holds {len(records)} "
                  f"— cache and pack disagree, not guessing")
            continue

        index = 0
        stamped = 0
        for book, count in runs:
            number = 0 if not str(book).isdigit() else int(book)
            for _ in range(count):
                if records[index].get("sourceBook") is None:
                    records[index]["sourceBook"] = number
                    stamped += 1
                index += 1

        body = json.dumps(records, ensure_ascii=False, indent=1) + "\n"
        for seed in SEED_DIRS:
            (seed / f"hadith_{slug}.json").write_text(body, encoding="utf-8", newline="\n")
        print(f"{slug:14} stamped={stamped:6} across {len(runs)} books")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
