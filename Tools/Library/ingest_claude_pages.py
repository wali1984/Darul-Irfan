"""Replace OCR page text with Claude's re-reading of the same scanned pages.

The 43 books and Asrar-ut-Tanzil (Urdu) were first read by Surya, which handles
Nastaliq badly: about a quarter of the book pages were mostly unreadable. Each
of those printed pages has now been read again from its scan by Claude
(Tools on amd: /mnt/sata1tb/di-claude-ocr, claude_ocr_run.py), which returns
the page as typed blocks: headings, paragraphs, couplets, Arabic quotations,
footnotes, tables and captions. The running header and printed page number are
left out.

Each page keeps its text as before - the blocks in reading order with a blank
line between them, which is what search indexes - and gains a `layout`: one
letter per block, in the same order as the blank-line-separated parts of the
text, so the readers set the page out as printed instead of guessing headings,
poetry and quotations from plain text:

    h heading      p paragraph     v verse (a couplet or stanza, its lines kept)
    a Arabic quotation             f footnote
    t table (one row per line, cells split by " | ")             c caption

A blank line inside a block would split it in two, so blank lines inside a
block are closed up to a single line break, and every page is checked to split
back into exactly one part per letter. Pages that are not Claude's reading get
no layout and the readers lay them out as before.

Only pages Claude returned are replaced; every other row, including any page a
budget stop left for later, keeps its old text and its `machineProvisional`
state, so the readers still show the proofreading notice for those.

A page whose reading was later completed in place keeps that text: two
Israr-ul-Haramain pages ended mid-sentence because the reading put the end of
the page in its notes, and Tools/Content/fix_book_pages.py appended it. A text
that is the reading with words added to the end of its last block is kept as it
is, so re-importing never undoes such a completion.

A cover or blank page comes back with no blocks. Its row is kept with empty
text (an upgrade upserts by book and page, so dropping the row would leave the
old garbled text in place) and the readers skip empty pages.

    python Tools/Library/ingest_claude_pages.py --pages <dir of page JSON> --exclude <json>          report
    python Tools/Library/ingest_claude_pages.py --pages <dir> --exclude <json> --write               update all four seeds
    python Tools/Library/ingest_claude_pages.py --pages <dir> --exclude <json> --write --ios-only    the iOS seed only
    python Tools/Library/ingest_claude_pages.py --pages <dir> --add-pages --write                    also add pages the app lacks

A reading whose page has no row is a problem unless --add-pages is given: then
the row is created first (a page the first OCR skipped, or a book the app did
not have yet, such as Akram-ut-Tafaseer Parah 30 part 2) and filled like any
other.
"""

from __future__ import annotations

import argparse
import collections
import json
import re
from pathlib import Path

from ingest_tafsir_pages import MAX_PAGE_BYTES, SEED_DIRS

REVIEW_STATE = "claudeTranscribed"

# The block kinds Claude returns, and the letter each has in a page's layout.
KIND_LETTERS = {
    "heading": "h",
    "paragraph": "p",
    "verse": "v",
    "arabic": "a",
    "footnote": "f",
    "table": "t",
    "caption": "c",
}
PART_SEPARATOR = "\n\n"
# A line holding nothing but white space ends a block's line as a blank line would.
BLANK_LINES = re.compile(r"\n\s*\n")


def page_parts(page: dict) -> list[tuple[str, str]]:
    """(layout letter, text) for each block with text, in reading order.

    A couplet keeps its line breaks; a blank line inside a block is closed up
    to one line break so the page text splits back into its blocks.
    """
    parts = []
    for block in page.get("blocks") or []:
        text = (block.get("text") or "").replace("\r\n", "\n").replace("\r", "\n").strip()
        if not text:
            continue
        kind = block.get("kind")
        if kind not in KIND_LETTERS:
            raise ValueError(f"unknown block kind {kind!r}")
        parts.append((KIND_LETTERS[kind], BLANK_LINES.sub("\n", text)))
    return parts


def completed_later(current: str, reading: str) -> bool:
    """True when the page text is this reading with words added to the end of
    its last block, as Tools/Content/fix_book_pages.py restores them."""
    if len(current) <= len(reading) or not current.startswith(reading):
        return False
    added = current[len(reading):]
    return added[0] == " " and "\n" not in added


def load_claude_pages(folder: Path) -> dict[tuple[str, int], dict]:
    pages = {}
    for path in sorted(folder.glob("*.json")):
        entry = json.loads(path.read_text(encoding="utf-8"))
        if "page" not in entry:
            continue
        book_id, _, number = entry["id"].rpartition("__p")
        pages[(book_id, int(number))] = entry
    return pages


def write_if_changed(path: Path, content: str) -> bool:
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return False
    path.write_text(content, encoding="utf-8", newline="")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pages", type=Path, required=True)
    parser.add_argument("--write", action="store_true")
    # Pages a check found incomplete (half of a two-page spread, or a reading
    # that stopped early) keep their original text until they are re-read.
    parser.add_argument("--exclude", type=Path, help="JSON object whose keys are page ids to leave alone")
    # The release sync copies the iOS seed to the other platforms and bumps
    # the manifest once, so a fix can be made to the iOS seed alone.
    parser.add_argument("--ios-only", action="store_true", help="write only the iOS seed")
    parser.add_argument("--add-pages", action="store_true", help="create a row for a reading whose page has none")
    args = parser.parse_args()

    claude = load_claude_pages(args.pages)
    excluded = set(json.loads(args.exclude.read_text(encoding="utf-8"))) if args.exclude else set()
    for page_id in excluded:
        book_id, _, number = page_id.rpartition("__p")
        claude.pop((book_id, int(number)), None)
    seed = SEED_DIRS[0]
    rows = json.loads((seed / "book_pages.json").read_text(encoding="utf-8"))
    added = 0
    if args.add_pages:
        present = {(row["bookID"], row["page"]) for row in rows}
        for book_id, number in sorted(set(claude) - present):
            rows.append({"bookID": book_id, "page": number, "text": "", "blocks": 0, "unresolvedBlocks": 0,
                         "reviewState": "machineProvisional", "validator": ""})
            added += 1
        rows.sort(key=lambda row: (row["bookID"], row["page"]))
    replaced, emptied, oversize, illegible = 0, 0, [], 0
    problems: list[str] = []
    kept_completions: list[str] = []
    letters: collections.Counter[str] = collections.Counter()
    for row in rows:
        entry = claude.get((row["bookID"], row["page"]))
        if entry is None:
            continue
        name = f"{row['bookID']} p{row['page']}"
        try:
            parts = page_parts(entry["page"])
        except ValueError as error:
            problems.append(f"{name}: {error}")
            continue
        text = PART_SEPARATOR.join(part for _, part in parts)
        layout = "".join(letter for letter, _ in parts)
        if len(text.encode("utf-8")) > MAX_PAGE_BYTES:
            oversize.append(name)
            continue
        if row["reviewState"] == REVIEW_STATE and completed_later(row["text"], text):
            text = row["text"]
            kept_completions.append(name)
        # Every block must come back as exactly one part of the text, or the
        # reader would set a paragraph as a heading.
        if layout and len(text.split(PART_SEPARATOR)) != len(layout):
            problems.append(f"{name}: text splits into {len(text.split(PART_SEPARATOR))} parts, layout has {len(layout)}")
            continue
        row["text"] = text
        row["blocks"] = len(entry["page"].get("blocks") or [])
        row["unresolvedBlocks"] = 0
        row["reviewState"] = REVIEW_STATE
        row["validator"] = entry.get("model", "claude-opus-5-5")
        if layout:
            row["layout"] = layout
        else:
            row.pop("layout", None)
        letters.update(layout)
        replaced += 1
        emptied += not text
        illegible += int(entry["page"].get("illegible_words") or 0)

    unmatched = len(claude) - replaced - len(oversize) - len(problems)
    # The finished seed is checked as the readers will read it.
    for row in rows:
        layout = row.get("layout")
        if layout is None:
            continue
        if row["reviewState"] != REVIEW_STATE:
            problems.append(f"{row['bookID']} p{row['page']}: layout on a page that is not Claude's reading")
        elif len(row["text"].split(PART_SEPARATOR)) != len(layout) or set(layout) - set(KIND_LETTERS.values()):
            problems.append(f"{row['bookID']} p{row['page']}: layout does not match its text")
    index: dict[str, dict] = {}
    for row in rows:
        item = index.setdefault(row["bookID"], {"bookID": row["bookID"], "pages": 0, "unresolvedBlocks": 0})
        item["pages"] += 1
        item["unresolvedBlocks"] += row["unresolvedBlocks"]
    index_rows = sorted(index.values(), key=lambda item: item["bookID"])

    print(f"Claude pages read    : {len(claude) + len(excluded):,}  ({len(excluded):,} held back as incomplete)")
    print(f"rows added           : {added:,}")
    print(f"rows replaced        : {replaced:,}  ({emptied:,} covers or blank pages left empty)")
    print(f"pages laid out       : {sum(1 for r in rows if 'layout' in r):,}  "
          + ", ".join(f"{letter} {count:,}" for letter, count in letters.most_common()))
    print(f"completions kept     : {len(kept_completions)}  {kept_completions}")
    print(f"words marked [؟]     : {illegible:,}")
    print(f"rows still original  : {sum(1 for r in rows if r['reviewState'] != REVIEW_STATE):,}")
    if unmatched:
        print(f"PROBLEM: {unmatched} Claude pages match no existing row")
    if oversize:
        print(f"PROBLEM: {len(oversize)} pages over {MAX_PAGE_BYTES:,} bytes: {oversize[:5]}")
    for problem in problems[:20]:
        print(f"PROBLEM: {problem}")
    if unmatched or oversize or problems:
        return 1
    if not args.write:
        print("\nreport only; pass --write to update the seeds")
        return 0

    pages_json = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    index_json = json.dumps(index_rows, ensure_ascii=False, separators=(",", ":"))
    for directory in SEED_DIRS[:1] if args.ios_only else SEED_DIRS:
        if not directory.exists():
            print(f"  skipped (absent): {directory}")
            continue
        for name, content in (("book_pages.json", pages_json), ("book_pages_index.json", index_json)):
            changed = write_if_changed(directory / name, content)
            print(f"  {'wrote' if changed else 'unchanged'} {directory / name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
