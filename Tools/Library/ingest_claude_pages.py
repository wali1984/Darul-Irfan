"""Replace OCR page text with Claude's re-reading of the same scanned pages.

The 43 books and Asrar-ut-Tanzil (Urdu) were first read by Surya, which handles
Nastaliq badly: about a quarter of the book pages were mostly unreadable. Each
of those printed pages has now been read again from its scan by Claude
(Tools on amd: /mnt/sata1tb/di-claude-ocr, claude_ocr_run.py), which returns
the page as typed blocks: headings, paragraphs, couplets, Arabic quotations,
footnotes. The running header and printed page number are left out.

Only pages Claude returned are replaced; every other row, including any page a
budget stop left for later, keeps its old text and its `machineProvisional`
state, so the readers still show the proofreading notice for those.

A cover or blank page comes back with no blocks. Its row is kept with empty
text (an upgrade upserts by book and page, so dropping the row would leave the
old garbled text in place) and the readers skip empty pages.

    python Tools/Library/ingest_claude_pages.py --pages <dir of page JSON>          report
    python Tools/Library/ingest_claude_pages.py --pages <dir> --write               update all four seeds
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from ingest_tafsir_pages import MAX_PAGE_BYTES, SEED_DIRS

REVIEW_STATE = "claudeTranscribed"


def page_text(page: dict) -> str:
    """Blocks in reading order, a blank line between them; a couplet keeps its line breaks."""
    parts = [block["text"].strip() for block in page.get("blocks") or [] if block.get("text", "").strip()]
    return "\n\n".join(parts)


def load_claude_pages(folder: Path) -> dict[tuple[str, int], dict]:
    pages = {}
    for path in sorted(folder.glob("*.json")):
        entry = json.loads(path.read_text(encoding="utf-8"))
        if "page" not in entry:
            continue
        book_id, _, number = entry["id"].rpartition("__p")
        pages[(book_id, int(number))] = entry
    return pages


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pages", type=Path, required=True)
    parser.add_argument("--write", action="store_true")
    # Pages a check found incomplete (half of a two-page spread, or a reading
    # that stopped early) keep their original text until they are re-read.
    parser.add_argument("--exclude", type=Path, help="JSON object whose keys are page ids to leave alone")
    args = parser.parse_args()

    claude = load_claude_pages(args.pages)
    excluded = set(json.loads(args.exclude.read_text(encoding="utf-8"))) if args.exclude else set()
    for page_id in excluded:
        book_id, _, number = page_id.rpartition("__p")
        claude.pop((book_id, int(number)), None)
    seed = SEED_DIRS[0]
    rows = json.loads((seed / "book_pages.json").read_text(encoding="utf-8"))
    replaced, emptied, oversize, illegible = 0, 0, [], 0
    for row in rows:
        entry = claude.get((row["bookID"], row["page"]))
        if entry is None:
            continue
        text = page_text(entry["page"])
        if len(text.encode("utf-8")) > MAX_PAGE_BYTES:
            oversize.append(f"{row['bookID']} p{row['page']}")
            continue
        row["text"] = text
        row["blocks"] = len(entry["page"].get("blocks") or [])
        row["unresolvedBlocks"] = 0
        row["reviewState"] = REVIEW_STATE
        row["validator"] = entry.get("model", "claude-opus-5-5")
        replaced += 1
        emptied += not text
        illegible += int(entry["page"].get("illegible_words") or 0)

    unmatched = len(claude) - replaced - len(oversize)
    index: dict[str, dict] = {}
    for row in rows:
        item = index.setdefault(row["bookID"], {"bookID": row["bookID"], "pages": 0, "unresolvedBlocks": 0})
        item["pages"] += 1
        item["unresolvedBlocks"] += row["unresolvedBlocks"]
    index_rows = sorted(index.values(), key=lambda item: item["bookID"])

    print(f"Claude pages read    : {len(claude) + len(excluded):,}  ({len(excluded):,} held back as incomplete)")
    print(f"rows replaced        : {replaced:,}  ({emptied:,} covers or blank pages left empty)")
    print(f"words marked [؟]     : {illegible:,}")
    print(f"rows still original  : {sum(1 for r in rows if r['reviewState'] != REVIEW_STATE):,}")
    if unmatched:
        print(f"PROBLEM: {unmatched} Claude pages match no existing row")
    if oversize:
        print(f"PROBLEM: {len(oversize)} pages over {MAX_PAGE_BYTES:,} bytes: {oversize[:5]}")
    if unmatched or oversize:
        return 1
    if not args.write:
        print("\nreport only; pass --write to update the seeds")
        return 0

    pages_json = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    index_json = json.dumps(index_rows, ensure_ascii=False, separators=(",", ":"))
    for directory in SEED_DIRS:
        if not directory.exists():
            print(f"  skipped (absent): {directory}")
            continue
        (directory / "book_pages.json").write_text(pages_json, encoding="utf-8", newline="")
        (directory / "book_pages_index.json").write_text(index_json, encoding="utf-8", newline="")
        print(f"  wrote {directory}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
