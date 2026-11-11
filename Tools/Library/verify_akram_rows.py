"""Independent check of the per-ayah Akram-ut-Tafaseer rows.

`segment_akram_tafaseer.py` attributes commentary using quotations matched
within each juz. This check does not trust that: it re-matches every vowelled
quotation in every row against the *whole* mushaf, and counts a row as
misplaced when most of its confident quotations from its own surah belong
outside its range (two or more). Quotations from other surahs are citations,
which the commentary makes freely, and are not counted against a row.

A row that opens with its section's printed heading (سورۃ ... رکوع n آیات a تا b)
first recites the Arabic of every ayah of the section, a..b, up to the end
marker of ayah b. Those recitations are the book's layout, not commentary, so
they are left out of the count (reported as "section openings").

Usage: verify_akram_rows.py [--rows FILE] [--max-rate 0.05]
Reads the seed's quran_tafsir.json unless --rows names a JSON list of rows.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import segment_akram_tafaseer as seg  # noqa: E402

DIGIT = r"[0-9۰-۹٠-٩]"
OPENING = re.compile(r"\s*سور[ۃةہۂ][^\n]{0,40}?رکوع\s*" + DIGIT + r"+\s*آی(?:ات|ت)\s*(" + DIGIT + r"+)"
                     r"(?:\s*(?:تا|-)\s*(" + DIGIT + r"+))?")


def section_opening(text: str):
    """(first ayah, last ayah, where the recited Arabic ends) for a row that
    opens with its section heading; None otherwise."""
    heading = OPENING.match(text)
    if not heading:
        return None
    first = int(heading.group(1).translate(seg.ASCII_DIGITS))
    last = int((heading.group(2) or heading.group(1)).translate(seg.ASCII_DIGITS))
    # The marker closing ayah `last`, in any of the digit forms the book uses.
    digits = "".join(f"[{d}{'۰۱۲۳۴۵۶۷۸۹'[int(d)]}{'٠١٢٣٤٥٦٧٨٩'[int(d)]}]" for d in str(last))
    end_marker = re.compile(r"(?:﴿\s*|۝\s*)" + digits + r"(?!" + DIGIT + r")")
    found = end_marker.search(text, heading.end())
    return (first, last, found.end()) if found else None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rows")
    parser.add_argument("--max-rate", type=float, default=0.05)
    parser.add_argument("--show", type=int, default=8)
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")

    seed = seg.SEED_DIRS[0]
    mushaf = seg.Mushaf(seg.load(seed, "quran_ayahs"))
    if args.rows:
        rows = json.loads(Path(args.rows).read_text(encoding="utf-8"))
    else:
        rows = [r for r in seg.load(seed, "quran_tafsir") if r["editionID"] == seg.EDITION]

    first, last = (1, 1), (114, 6)
    checked = inside = openings = 0
    bad_rows = []
    for row in rows:
        own_in = own_out = 0
        opening = section_opening(row["text"])
        for match in seg.QUOTE.finditer(row["text"]):
            if len(seg.HARAKA.findall(match.group(1))) < 4:
                continue
            hit = mushaf.best(match.group(1), first, last)
            if not hit or hit[1] < 0.5:
                continue  # only confident, near-whole-ayah matches count
            surah, ayah = hit[0]
            if (opening and match.start() < opening[2] and surah == row["surahNumber"]
                    and opening[0] <= ayah <= opening[1]):
                openings += 1
                continue  # the section's own recitation, ahead of its commentary
            checked += 1
            if surah == row["surahNumber"] and row["ayahStart"] <= ayah <= row["ayahEnd"]:
                own_in += 1
                inside += 1
            elif surah == row["surahNumber"]:
                own_out += 1
            # Another surah is a citation, which the commentary makes freely.
        if own_out >= 2 and own_out > own_in:
            bad_rows.append((row["surahNumber"], row["ayahStart"], row["ayahEnd"], own_in, own_out))

    rate = len(bad_rows) / max(1, len(rows))
    print(f"rows {len(rows)} | confident quotations {checked} | inside own range {inside}"
          f" ({inside / max(1, checked):.1%}) | section openings left out {openings}")
    print(f"rows whose own-surah quotations are mostly outside their range: {len(bad_rows)} ({rate:.2%})")
    for item in bad_rows[: args.show]:
        print("  ", item)
    return 0 if rate <= args.max_rate else 1


if __name__ == "__main__":
    raise SystemExit(main())
