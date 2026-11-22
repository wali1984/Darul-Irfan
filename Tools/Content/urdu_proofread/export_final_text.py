"""Write the library's text out as plain files, for text to speech on the amd machine.

The same shape as the export of 11 November 2026 (`di-claude-ocr/final-text`
on amd), made from the proofread seed in this checkout:

    by-book/<bookID>.txt    one file per book, "===== page N =====" between pages
    by-publication/<id>.txt (a long id cut short) the articles, press releases, announcements and pages
    publications.json       id, file, title, language
    books.json              bookID, title, pages
    per-ayah-<edition>.txt  the tafsir passages under the ayat, "===== s:a-b =====" between them
    seed-json/              the seed files themselves
    SHA256SUMS              to check a copy by: sha256sum -c SHA256SUMS
    README.md               what this is and how far the proofreading had got

    python Tools/Content/urdu_proofread/export_final_text.py [--titles books.json]

`--titles` is the earlier export's books.json, for the books' names. The
folder is written to `outputs/darul-urdu-proofread-apply/final-text`; copying
it to amd is a separate step (scp), so that nothing there is overwritten by
running this.
"""

from __future__ import annotations

import hashlib
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

    (target / "by-publication").mkdir(exist_ok=True)
    publications = []
    for item in json.loads((SEED / "library_items.json").read_text(encoding="utf-8")):
        body = item.get("bodyPlainText")
        if not body:
            continue
        title = item.get("title") or item["id"]
        name = item["id"]
        if len(name) > 70:  # Windows will not write a path beyond 260 characters
            name = f"{name[:60]}-{hashlib.sha256(name.encode('utf-8')).hexdigest()[:8]}"
        (target / "by-publication" / f"{name}.txt").write_text(
            f"# {title} ({item['id']})\n\n{body}\n", encoding="utf-8", newline="\n")
        publications.append({"id": item["id"], "file": f"by-publication/{name}.txt", "title": title, "language": item.get("language")})
    kept = {item["file"].split("/")[1][:-4] for item in publications}
    for stale in (target / "by-publication").glob("*.txt"):
        if stale.stem not in kept:
            stale.unlink()
    (target / "publications.json").write_text(
        json.dumps(publications, ensure_ascii=False, indent=1), encoding="utf-8", newline="\n")

    translations: dict[str, list[str]] = defaultdict(list)
    for row in json.loads((SEED / "quran_translations.json").read_text(encoding="utf-8")):
        if row["editionID"].startswith("akram-ut-tarajum"):
            translations[row["editionID"]] += [f"===== {row['surahNumber']}:{row['ayahNumber']} =====", row["text"], ""]
    for edition, lines in translations.items():
        (target / f"per-ayah-{edition}.txt").write_text("\n".join(lines), encoding="utf-8", newline="\n")

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
the books is as printed, apart from the corrections the owner approved or left to judgement (21 and 22 November 2026).

Findings not applied: {sum(n for status, n in summary['status'].items() if status != 'applied')} (doubtful, notes without replacement words, or Arabic).
Places of Arabic still waiting for the owner's answer, as printed until then: {len(read_json(OUT / 'arabic-awaiting-approval.json'))}.
This folder is replaced when they are answered.

- by-book/<bookID>.txt   one file per book, "===== page N =====" separators ({len(pages):,} pages, {len(books)} books)
- books.json             bookID, title, page count
- by-publication/<id>.txt the {len(publications)} articles, press releases, announcements and pages with text
- publications.json      id, file, title, language
- per-ayah-*.txt         Akram-ut-Tarajum (Urdu and English), and the tafsir passages under the ayat with the same corrections
- seed-json/             the app seed files themselves (manifest {manifest['version']})

What is doubtful stays as printed. Check a copy with: sha256sum -c SHA256SUMS

[؟] marks a word that could not be read on the scan. A heading printed in the margin stands
above the sentence it was printed beside.
"""
    (target / "README.md").write_text(readme, encoding="utf-8", newline="\n")
    listed = sorted(path for path in target.rglob("*") if path.is_file() and path.name != "SHA256SUMS")
    sums = [f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(target).as_posix()}" for path in listed]
    (target / "SHA256SUMS").write_text("\n".join(sums) + "\n", encoding="utf-8", newline="\n")
    size = sum(path.stat().st_size for path in target.rglob("*") if path.is_file())
    print(f"{target}: {len(books)} books, {len(pages):,} pages, {size / 1e6:.0f} MB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
