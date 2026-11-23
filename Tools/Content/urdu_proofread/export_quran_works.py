"""Write the Qur'an works' text out for text to speech, ahead of the rest of the library.

    akram-ut-tarajum/       the translation, Urdu and English, one ayah under each "===== s:a ====="
    akram-ut-tafaseer/      one file per volume, "===== page N =====", and the passages per ayah
    asrar-at-tanzil/        the same, Urdu; and the English passages per ayah
    STATUS.json             for each volume: pages read, corrections made, what still waits
    SHA256SUMS              to check a copy by: sha256sum -c SHA256SUMS
    README.md

    python Tools/Content/urdu_proofread/export_quran_works.py

It reads the seed in this checkout and the ledger of the build that wrote it
(`DI_PROOFREAD_REGISTER` must name the register that build read). The folder
is `outputs/darul-urdu-proofread-apply/quran-works`; copying it to amd is a
separate step.
"""

from __future__ import annotations

import hashlib
import json
import sys
from collections import Counter, defaultdict
from datetime import datetime

from apply_proofread import OUT, REGISTER, SEED, read_json

WORKS = (("akram-ut-tafaseer", "tafaseer-parah-", "", "akram-ut-tafaseer-ur"),
         ("asrar-at-tanzil", "asrar-", "-ur", "asrar-at-tanzil-ur"))
FULLY_READ = "all_nonempty_urdu_read"
READ_BUT_FOR_THE_SCAN = "all_available_urdu_read_source_gap_pending"


def seed(name: str):
    return json.loads((SEED / name).read_text(encoding="utf-8"))


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    target = OUT / "quran-works"
    written = []

    def put(name: str, lines: list[str]) -> None:
        path = target / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(lines).rstrip("\n") + "\n", encoding="utf-8", newline="\n")
        written.append(name)

    translations = defaultdict(list)
    for row in seed("quran_translations.json"):
        if row["editionID"].startswith("akram-ut-tarajum"):
            translations[row["editionID"]].append(row)
    for edition, rows in translations.items():
        lines = []
        for row in sorted(rows, key=lambda r: (r["surahNumber"], r["ayahNumber"])):
            lines += [f"===== {row['surahNumber']}:{row['ayahNumber']} =====", row["text"], ""]
        put(f"akram-ut-tarajum/per-ayah-{edition}.txt", lines)

    passages = defaultdict(list)
    for row in seed("quran_tafsir.json"):
        passages[row["editionID"]] += [f"===== {row['surahNumber']}:{row['ayahStart']}-{row['ayahEnd']} =====", row["text"], ""]
    for edition, lines in passages.items():
        folder = "akram-ut-tafaseer" if edition.startswith("akram-") else "asrar-at-tanzil"
        put(f"{folder}/per-ayah-{edition}.txt", lines)

    books = {book["id"]: book for book in read_json(REGISTER / "inventory.json")["books"]}
    ledger = json.loads((OUT / "ledger.json").read_text(encoding="utf-8"))
    outcome = defaultdict(Counter)
    for finding in read_json(REGISTER / "findings.json"):
        if finding["id"] in ledger:
            outcome[finding["bookID"]][ledger[finding["id"]]["status"]] += 1

    pages = defaultdict(list)
    for row in seed("book_pages.json"):
        pages[row["bookID"]].append(row)
    status, table = [], []
    for folder, prefix, suffix, _ in WORKS:
        ids = sorted((b for b in books if b.startswith(prefix) and b.endswith(suffix)),
                     key=lambda b: [int(p) if p.isdigit() else 0 for p in b.split("-")])
        read_count = waiting = applied = 0
        unfinished = []
        for book in ids:
            rows = sorted(pages[book], key=lambda r: r["page"])
            lines = [f"# {books[book]['title']} ({book}) - {len(rows)} pages", ""]
            for row in rows:
                lines += [f"===== page {row['page']} =====", row["text"], ""]
            put(f"{folder}/by-book/{book}.txt", lines)
            state = books[book].get("textReviewStatus")
            finished = state in (FULLY_READ, READ_BUT_FOR_THE_SCAN)
            counts = outcome[book]
            status.append({"book": book, "title": books[book]["title"], "pages": len(rows),
                           "readThrough": finished,
                           "unreadableOnTheScan": len(books[book].get("unreadablePagesInspected") or []),
                           "urduPagesRead": books[book].get("reviewedPages", 0),
                           "correctionsApplied": counts["applied"],
                           "wordingAwaitingSecondReading": counts["review"],
                           "leftAsPrinted": counts["hold"] + counts["protected"] + counts["superseded"]})
            applied += counts["applied"]
            waiting += counts["review"]
            read_count += finished
            if not finished:
                unfinished.append(book)
        table.append(f"- {folder}: {read_count} of {len(ids)} volumes read through; {applied:,} corrections made; "
                     f"{waiting:,} wording corrections still wait for a second reading."
                     + (f"\n  Not yet read through: {', '.join(unfinished)}." if unfinished else ""))
    put("STATUS.json", json.dumps(status, ensure_ascii=False, indent=1).split("\n"))

    put("README.md", f"""# Darul Irfan - Qur'an works, corrected text for text to speech
Written {datetime.now().strftime('%Y-%m-%d %H:%M')} New York time.

- akram-ut-tarajum: Urdu and English translation, every ayah, as the app carries it.
{chr(10).join(table)}
- asrar-at-tanzil, English: per ayah, as the app carries it (outside the Urdu proofreading).

Proposed changes to Arabic in the whole library left as printed (not exactly the mushaf's words):
{len(read_json(OUT / 'arabic-awaiting-approval.json'))}.
STATUS.json says where each volume stands and how many findings were left as printed.
A volume with "readThrough": false is partly uncorrected.

The text follows the printed volumes: a correction stays only where two readers, each looking at the
printed page, found that the print says so or that it mends an obvious printing mistake outside a
translation of an ayah. The mushaf itself is not here and is not changed. Arabic quoted inside the books
is as printed, except the corrections the owner approved, and those decided on 23 November under the
owner's authority where the words put in are exactly the mushaf's.
[؟] marks a word that could not be read on the scan.

Check a copy with: sha256sum -c SHA256SUMS
The other books and publications are in ../final-text-proofread.""".split("\n"))

    sums = [f"{hashlib.sha256((target / name).read_bytes()).hexdigest()}  {name}" for name in sorted(written)]
    (target / "SHA256SUMS").write_text("\n".join(sums) + "\n", encoding="utf-8", newline="\n")
    print(f"{target}: {len(written)} files")
    for line in table:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
