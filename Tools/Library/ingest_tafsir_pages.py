"""Ingest the Urdu tafsir OCR drops as page-structured library text.

Two works, both from the owner's `ocr-repair-20260805` pipeline:

  Asrar-at-Tanzil (Urdu)  114 surah documents -> library id `asrar-{n}-ur`
  Akram-ut-Tafaseer        30 parah documents -> library id `tafaseer-parah-{n}`

Both already exist as catalogue entries in `library_items.json` with no text, so
attaching pages is all that is needed: the readers on every platform offer
"Read the text" as soon as a book has pages. No client code changes.

WHY PAGES AND NOT PER-AYAH TAFSIR
---------------------------------
These works cannot be keyed per ayah from this data. The pipeline's own
`verse_refs` are 8% populated for Asrar and 2% for Akram, and the populated
ones are wrong: the Surah-100 document's first page claims verse 88:8, Surah-102
claims 1:3, and Akram's Para 10 - which covers roughly 8:41 to 9:93 - claims
2:244. Every one of those came from `preceding_quran_arabic_block`, meaning it
was matched against OCR'd Arabic that is itself corrupted. Guessing a verse
number onto scripture commentary is worse than not offering it, so the text
ships as a readable book and `quran_tafsir.json` is left alone.

One printed page per row, as with the 43 books: a whole document's body would be
megabytes, and the library detail view builds its paragraphs eagerly, which is
the shape that crashed the Quran reader on large tafsir blocks in v1.6.9.

Read-only with respect to the OCR drop. Writes the four platform seeds.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1].parent
MAX_PAGE_BYTES = 96 * 1024
VALIDATOR = "qwen3:8b"
REVIEW_STATE = "machineProvisional"

SEED_DIRS = [
    ROOT / "DarulIrfanApp" / "Resources" / "SeedData",
    ROOT.parent / "DarulIrfanAndroid" / "app" / "src" / "main" / "assets" / "seed",
    ROOT.parent / "DarulIrfanHarmony" / "entry" / "src" / "main" / "resources" / "rawfile" / "seed",
    ROOT.parent / "DarulIrfanWeb" / "content",
]

# Explicit, not fuzzy. Fuzzy matching previously forced two unrelated books onto
# the wrong library items, so each work states how its document name becomes a
# library id and nothing is guessed.
WORKS = [
    {
        "name": "Asrar-at-Tanzil (Urdu)",
        "glob": "asrar-urdu-raw-v1/documents/urdu/*/final/*.final.json",
        "pattern": re.compile(r"^Asrar-ut-Tanzil_UrduTafseer_Surah-(\d{1,3})$"),
        "library_id": lambda n: f"asrar-{n}-ur",
        "expected": 114,
        "max_index": 114,
    },
    {
        "name": "Asrar-at-Tanzil (English)",
        # Its own tree, not the shared OCR drop.
        "root": ROOT / "Asrar-at-Tanzil — English tafsir" / "OCR",
        "glob": "*/final/*.final.json",
        "pattern": re.compile(r"^Asrar-ut-Tanzil_EnglishTafseer_Chapter-(\d{1,3})$"),
        "library_id": lambda n: f"asrar-{n}-en",
        "expected": 114,
        "max_index": 114,
    },
    {
        "name": "Akram-ut-Tafaseer",
        "glob": "akram-ut-tafaseer-raw-v1/documents/urdu/*/final/*.final.json",
        "pattern": re.compile(r"^QuranTafseer-Para-(\d{1,2})$"),
        "library_id": lambda n: f"tafaseer-parah-{n}",
        "expected": 30,
        "max_index": 30,
    },
]

DUPLICATE_SUFFIX = re.compile(r" \(\d+\)$")

# Documents whose name does not match the work's pattern, mapped by hand with
# the reason. Nothing is aliased silently.
ALIASES = {
    # The drop carries only part 1 of parah 30 - the source PDF is itself named
    # "part1" and no part 2 exists anywhere in it. Its 232 pages are genuine, so
    # they ship, but parah 30 is therefore INCOMPLETE and said to be so in
    # Docs/CONTENT_INTEGRITY notes and the tester briefing. Do not quietly treat
    # it as the whole juz.
    "QuranTafseer-Para-30-part1": ("QuranTafseer-Para-30", "part 1 only; no part 2 in the drop"),
}


def document_name(path: Path) -> str:
    """The document directory is two levels above the final/*.json file."""
    return path.parent.parent.name


def canonical_documents(drop: Path, work: dict) -> dict[int, Path]:
    """One file per work index, ignoring the pipeline's ' (1)' re-run copies.

    The drop contains directories such as `QuranTafseer-Para-10 (1)` beside
    `QuranTafseer-Para-10`. They are partial re-runs; counting both would double
    a parah's pages, so the unsuffixed directory always wins.
    """
    chosen: dict[int, tuple[bool, Path]] = {}
    base = work.get("root") or drop
    for path in sorted(base.glob(work["glob"])):
        raw = document_name(path)
        stripped = DUPLICATE_SUFFIX.sub("", raw)
        if stripped in ALIASES:
            stripped, reason = ALIASES[stripped][0], ALIASES[stripped][1]
            print(f"  note: {raw} -> {stripped} ({reason})")
        match = work["pattern"].match(stripped)
        if not match:
            continue
        index = int(match.group(1))
        if not 1 <= index <= work["max_index"]:
            continue
        is_exact = raw == stripped
        previous = chosen.get(index)
        if previous is None or (is_exact and not previous[0]):
            chosen[index] = (is_exact, path)
    return {index: path for index, (_, path) in sorted(chosen.items())}


def page_text(page: dict) -> tuple[str, int, int]:
    """Readable text for one printed page, plus block and unresolved counts.

    Blocks the pipeline did not select are its own rejects and are left out.
    Reading order is the printed order, which for these works is the only order
    that makes the prose follow itself.
    """
    blocks = page.get("blocks") or []
    ordered = sorted(blocks, key=lambda b: b.get("reading_order") or 0)
    parts = []
    unresolved = 0
    for block in ordered:
        if not block.get("selected"):
            continue
        text = (block.get("final_text") or "").strip()
        if not text:
            continue
        parts.append(text)
        # Carried per page rather than dropped, so a reader can mark a page as
        # unchecked instead of hiding it.
        if block.get("needs_human_review") or block.get("ocr_error"):
            unresolved += 1
    return "\n\n".join(parts).strip(), len(parts), unresolved


def build_rows(drop: Path, known_ids: set[str]) -> tuple[list[dict], list[str]]:
    rows: list[dict] = []
    problems: list[str] = []
    for work in WORKS:
        documents = canonical_documents(drop, work)
        if len(documents) != work["expected"]:
            problems.append(
                f"{work['name']}: found {len(documents)} documents, expected {work['expected']}"
            )
        for index, path in documents.items():
            book_id = work["library_id"](index)
            if book_id not in known_ids:
                problems.append(f"{work['name']}: no library item for {book_id}")
                continue
            payload = json.loads(path.read_text(encoding="utf-8"))
            seen_pages: set[int] = set()
            for page in payload.get("pages") or []:
                number = page.get("page")
                if not isinstance(number, int) or number < 1:
                    problems.append(f"{book_id}: invalid page number {number!r}")
                    continue
                if number in seen_pages:
                    problems.append(f"{book_id}: duplicate page {number}")
                    continue
                text, blocks, unresolved = page_text(page)
                if not text:
                    # Covers and blank leaves carry no text; a row with empty
                    # text would fail the content gate and read as a bug.
                    continue
                size = len(text.encode("utf-8"))
                if size > MAX_PAGE_BYTES:
                    problems.append(f"{book_id} page {number}: {size} bytes over the ceiling")
                    continue
                seen_pages.add(number)
                rows.append({
                    "bookID": book_id,
                    "page": number,
                    "text": text,
                    "blocks": blocks,
                    "unresolvedBlocks": unresolved,
                    "reviewState": REVIEW_STATE,
                    "validator": VALIDATOR,
                })
    return rows, problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--drop", type=Path, required=True,
                        help="the ocr-repair-20260805 directory")
    parser.add_argument("--write", action="store_true",
                        help="write the four platform seeds; otherwise report only")
    args = parser.parse_args()

    seed = SEED_DIRS[0]
    library = json.loads((seed / "library_items.json").read_text(encoding="utf-8"))
    known_ids = {item["id"] for item in library}

    rows, problems = build_rows(args.drop, known_ids)
    if problems:
        print("problems:")
        for problem in problems[:20]:
            print(f"  - {problem}")
        if len(problems) > 20:
            print(f"  ... and {len(problems) - 20} more")
        return 1

    existing = json.loads((seed / "book_pages.json").read_text(encoding="utf-8"))
    # Replace rather than append, so re-running is idempotent instead of
    # doubling every page it already added.
    new_ids = {row["bookID"] for row in rows}
    kept = [row for row in existing if row["bookID"] not in new_ids]
    merged = kept + rows
    merged.sort(key=lambda row: (row["bookID"], row["page"]))

    index: dict[str, dict] = {}
    for row in merged:
        entry = index.setdefault(row["bookID"], {"bookID": row["bookID"], "pages": 0, "unresolvedBlocks": 0})
        entry["pages"] += 1
        entry["unresolvedBlocks"] += row["unresolvedBlocks"]
    index_rows = sorted(index.values(), key=lambda entry: entry["bookID"])

    total = sum(len(row["text"].encode("utf-8")) for row in rows)
    print(f"books ingested   : {len(new_ids)}")
    print(f"pages added      : {len(rows):,}  ({total / 1048576:.1f} MB of text)")
    print(f"pages kept       : {len(kept):,}")
    print(f"book_pages total : {len(merged):,} rows across {len(index_rows)} books")
    print(f"largest page     : {max(len(r['text'].encode('utf-8')) for r in rows):,} bytes "
          f"(ceiling {MAX_PAGE_BYTES:,})")
    print(f"unresolved blocks: {sum(r['unresolvedBlocks'] for r in rows):,}")

    if not args.write:
        print("\nreport only; pass --write to update the seeds")
        return 0

    pages_json = json.dumps(merged, ensure_ascii=False, separators=(",", ":"))
    index_json = json.dumps(index_rows, ensure_ascii=False, separators=(",", ":"))
    for directory in SEED_DIRS:
        if not directory.exists():
            print(f"  skipped (absent): {directory}")
            continue
        # newline="" keeps LF, which .gitattributes pins and the integrity gate
        # compares byte for byte across the four platforms.
        (directory / "book_pages.json").write_text(pages_json, encoding="utf-8", newline="")
        (directory / "book_pages_index.json").write_text(index_json, encoding="utf-8", newline="")
        print(f"  wrote {directory}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
