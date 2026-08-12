#!/usr/bin/env python3
"""Give every collection kitab sections, and every attributable record a book.

Two data facts this closes, measured before writing:

* `sourceBook` was absent on whole NAMED books — Riyad as-Salihin's
  introduction is all 679 of its missing records, sitting before book 1 —
  because the source prints no in-book number there. The leading unnumbered
  run of a pack is that collection's named opening book: it becomes book 0,
  titled from its own cached page. Interior gaps sandwiched by the same book
  number are filled with it; anything else stays honestly absent.
* Only Bukhari's catalogue entry carried named sections. Every cached book
  page carries the kitab's names (.book_page_english_name /
  .book_page_arabic_name), so sections are built for all 26 collections:
  number, both titles, and a hadithCount counted from the pack itself — the
  same no-over-claim rule as the catalogue.

Writes packs and catalogue to all four platform seed dirs.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ingest_sunnah import SEED_DIRS, PRIMARY_SEED  # noqa: E402
from bs4 import BeautifulSoup  # noqa: E402


def clean(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def page_titles(cache: Path, slug: str, book: object) -> tuple[str, str]:
    """(english, arabic) kitab titles from a cached book page, or ('','')."""
    page = cache / f"_{slug}_{book}.html"
    if not page.exists():
        return "", ""
    soup = BeautifulSoup(page.read_text(encoding="utf-8"), "lxml")
    english = soup.select_one(".book_page_english_name")
    arabic = soup.select_one(".book_page_arabic_name")
    return (clean(english.get_text()) if english else "",
            clean(arabic.get_text()) if arabic else "")


def fix_pack(records: list[dict]) -> tuple[int, int]:
    """Returns (leading_assigned, interior_filled)."""
    first_numbered = next((i for i, r in enumerate(records)
                           if r.get("sourceBook") is not None), None)
    leading = 0
    if first_numbered is not None and first_numbered > 0:
        # The unnumbered opening run is the named first book (introduction).
        for r in records[:first_numbered]:
            if r.get("sourceBook") is None:
                r["sourceBook"] = 0
                leading += 1
    interior = 0
    for i, r in enumerate(records):
        if r.get("sourceBook") is not None:
            continue
        before = next((records[j].get("sourceBook") for j in range(i - 1, -1, -1)
                       if records[j].get("sourceBook") is not None), None)
        after = next((records[j].get("sourceBook") for j in range(i + 1, len(records))
                      if records[j].get("sourceBook") is not None), None)
        if before is not None and before == after:
            r["sourceBook"] = before
            interior += 1
    return leading, interior


def main() -> int:
    cache = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".hadith_cache")
    catalogue_path = PRIMARY_SEED / "hadith_books.json"
    catalogue = json.loads(catalogue_path.read_text(encoding="utf-8"))

    for book in catalogue["books"]:
        slug = book["id"]
        pack_path = PRIMARY_SEED / f"hadith_{slug}.json"
        records = json.loads(pack_path.read_text(encoding="utf-8"))

        leading, interior = fix_pack(records)
        still_missing = sum(1 for r in records if r.get("sourceBook") is None)

        # Sections for every kitab the pack actually contains.
        counts: dict[int, int] = {}
        for r in records:
            kitab = r.get("sourceBook")
            if kitab is not None:
                counts[kitab] = counts.get(kitab, 0) + 1
        sections = []
        for number in sorted(counts):
            source = "introduction" if number == 0 else number
            english, arabic = page_titles(cache, slug, source)
            if number == 0 and not english:
                english = "Introduction"
            sections.append({
                "number": number,
                "titleEnglish": english,
                "titleArabic": arabic,
                "hadithCount": counts[number],
            })
        book["sections"] = sections or None
        book["sectionCount"] = len(sections)

        titled = sum(1 for s in sections if s["titleEnglish"])
        print(f"{slug:16} book0={leading:5} interior={interior:3} "
              f"unattributed={still_missing:4} sections={len(sections):3} titled={titled}")

        if leading or interior:
            body = json.dumps(records, ensure_ascii=False, indent=1) + "\n"
            for seed in SEED_DIRS:
                (seed / f"hadith_{slug}.json").write_text(body, encoding="utf-8", newline="\n")

    body = json.dumps(catalogue, ensure_ascii=False, indent=1) + "\n"
    for seed in SEED_DIRS:
        (seed / "hadith_books.json").write_text(body, encoding="utf-8", newline="\n")
    print(f"catalogue with sections written to {len(SEED_DIRS)} seed dirs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
