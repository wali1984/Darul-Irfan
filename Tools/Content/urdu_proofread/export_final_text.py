"""Write the library's text out as plain files, for text to speech on the amd machine.

The same shape as the export of 11 November 2026 (`di-claude-ocr/final-text`
on amd), made from the proofread seed in this checkout:

    by-book/<bookID>.txt    one file per book, "===== page N =====" between pages
    books.json              bookID, title, pages
    per-ayah-<edition>.txt  the tafsir passages under the ayat, "===== s:a-b =====" between them
    seed-json/              the seed files themselves
    README.md               what this is and how far the proofreading had got

    python Tools/Content/urdu_proofread/export_final_text.py [--titles books.json]

`--titles` is the earlier export's books.json, for the books' names. The
folder is written to `outputs/darul-urdu-proofread-apply/final-text`; copying
it to amd is a separate step (scp), so that nothing there is overwritten by
running this.
"""

from __future__ import annotations

import json
import shutil
import sys
from collections import defaultdict
from datetime import date

from apply_proofread import OUT, REGISTER, SEED, read_json

SEED_FILES = ("book_pages.json", "book_pages_index.json", "library_items.json", "manifest.json",
              "quran_tafsir.json", "quran_translations.json", "tafsir_volumes.json", "book_links.json")


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    titles: dict[str, str] = {}
    if "--titles" in sys.argv:
        with open(sys.argv[sys.argv.index("--titles") + 1], encoding="utf-8") as handle:
            titles = {book["bookID"]: book["title"] for book in json.load(handle)}
    for item in json.loads((SEED / "library_items.json").read_text(encoding="utf-8")):
        titles.setdefault(item["id"], item.get("title") or item["id"])

    target = OUT / "final-text"
    # Written over what is there: Windows will not always let a folder in use be removed.
    (target / "by-book").mkdir(parents=True, exist_ok=True)
    (target / "seed-json").mkdir(exist_ok=True)

    pages = json.loads((SEED / "book_pages.json").read_text(encoding="utf-8"))
    by_book: dict[str, list[dict]] = defaultdict(list)
    for page in pages:
        by_book[page["bookID"]].append(page)
    books = []
    for book in sorted(by_book):
        rows = sorted(by_book[book], key=lambda row: row["page"])
        title = titles.get(book, book)
        lines = [f"# {title} ({book}) - {len(rows)} pages", ""]
        for row in rows:
            lines += [f"===== page {row['page']} =====", row["text"], ""]
        (target / "by-book" / f"{book}.txt").write_text("\n".join(lines), encoding="utf-8", newline="\n")
        books.append({"bookID": book, "title": title, "pages": len(rows)})
    for stale in (target / "by-book").glob("*.txt"):
        if stale.stem not in by_book:
            stale.unlink()
    (target / "books.json").write_text(json.dumps(books, ensure_ascii=False, indent=1), encoding="utf-8", newline="\n")

    passages: dict[str, list[str]] = defaultdict(list)
    for row in json.loads((SEED / "quran_tafsir.json").read_text(encoding="utf-8")):
        passages[row["editionID"]] += [f"===== {row['surahNumber']}:{row['ayahStart']}-{row['ayahEnd']} =====", row["text"], ""]
    for edition, lines in passages.items():
        (target / f"per-ayah-{edition}.txt").write_text("\n".join(lines), encoding="utf-8", newline="\n")

    for name in SEED_FILES:
        shutil.copyfile(SEED / name, target / "seed-json" / name)

    progress = read_json(REGISTER / "progress.json")
    summary = json.loads((OUT / "summary.json").read_text(encoding="utf-8"))
    manifest = json.loads((SEED / "manifest.json").read_text(encoding="utf-8"))
    done = progress.get("pageEntriesInspected", 0) >= progress.get("totalUrduPages", 1)
    readme = f"""# Darul Irfan - library text, proofread (seeds {manifest['version']}), written {date.today().isoformat()}

The text of every printed page as the apps carry it, after the Urdu proofreading.
For text to speech. The export of 11 November 2026 (../final-text) is the text before it.

Proofreading had reached {progress.get('pageEntriesInspected')} of {progress.get('totalUrduPages')} Urdu pages when this was written{'' if done else ' - NOT yet the whole library; this folder is replaced as the reading goes on'}.
Findings applied: {summary['status'].get('applied')}. Every Urdu page also has its spacing tidied
(a space after a sentence mark, none before it). The mushaf itself is untouched. Arabic quoted inside
the books is as printed, apart from 45 corrections the owner approved (21 November 2026).

- by-book/<bookID>.txt   one file per book, "===== page N =====" separators ({len(pages):,} pages, {len(books)} books)
- books.json             bookID, title, page count
- per-ayah-*.txt         the tafsir passages under the ayat, cut from those pages, with the same corrections
- seed-json/             the app seed files themselves (manifest {manifest['version']})

[؟] marks a word that could not be read on the scan. A heading printed in the margin stands
above the sentence it was printed beside.
"""
    (target / "README.md").write_text(readme, encoding="utf-8", newline="\n")
    size = sum(path.stat().st_size for path in target.rglob("*") if path.is_file())
    print(f"{target}: {len(books)} books, {len(pages):,} pages, {size / 1e6:.0f} MB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
