"""Restore the end of two Israr-ul-Haramain pages cut off mid-sentence.

When pages 50 and 52 of Israr-ul-Haramain were re-read from the scan, the end
of the Urdu column was written into the reading's notes instead of the page
text, so both pages stopped mid-sentence ("... تم جھوٹ بولتے ہو" and
"... تو فرمایا"). The notes hold the page's own text: each continuation is the
Urdu translation of the Arabic printed on the same page, and page 51 picks up
exactly where the page-50 continuation ends ("... اور سولی پر" / "پر چڑھا دیا
گیا"). book_page_fixes.json carries both continuations as written in the notes;
this appends each to its page, after checking the page still ends where the
re-read stopped.

    python Tools/Content/fix_book_pages.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from seed_io import dump, load

HERE = Path(__file__).resolve().parent


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    fixes = json.loads((HERE / "book_page_fixes.json").read_text(encoding="utf-8"))
    pages, layout = load("book_pages.json")
    index = {(row["bookID"], row["page"]): row for row in pages}
    changed = 0
    for fix in fixes:
        row = index.get((fix["bookID"], fix["page"]))
        if row is None:
            raise SystemExit(f"book_pages.json has no page {fix['bookID']} p{fix['page']}")
        text = row["text"].rstrip()
        if text.endswith(fix["append"]):
            continue
        if not text.endswith(fix["currentEnd"]):
            raise SystemExit(f"{fix['bookID']} p{fix['page']} no longer ends where the re-read stopped")
        row["text"] = f"{text} {fix['append']}"
        changed += 1
    if changed:
        dump("book_pages.json", pages, layout)
    print(f"book_pages.json: {changed} pages completed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
