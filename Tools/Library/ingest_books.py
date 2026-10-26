#!/usr/bin/env python3
"""Build book_pages.json from the books-raw-layout-v1 OCR drop.

Reads review/text-pages-v1/page-*.json per document, concatenates each page's
blocks in index order, and emits one record per page keyed by the library item
id. Mapping is explicit (book_mapping.json) — fuzzy title matching is not used,
because a wrong match silently overwrites a different book.

Text is OCR output that has been through arbitration and visual cross-check but
NO human proofreading: every record carries reviewState "machineProvisional"
and the validator model that produced it. Arabic quotations embedded in the
Urdu prose are kept verbatim as book text; they are NOT canonical scripture and
must never be rendered as Quran or hadith.

Read-only with respect to the OCR drop. Writes only into SeedData.
"""
from __future__ import annotations
import json, os, glob, argparse, unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SEED = os.path.join(REPO, "DarulIrfanApp", "Resources", "SeedData")
MAX_PAGE_BYTES = 96 * 1024          # same ceiling check_content.py uses for tafsir
INDENT = 1                          # seed convention

def load_mapping(path: str) -> tuple[dict, dict]:
    d = json.load(open(path, encoding="utf-8"))
    return d["matched"], d["new"]

def slug(title: str) -> str:
    s = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode()
    s = "".join(c.lower() if c.isalnum() else "-" for c in s)
    while "--" in s:
        s = s.replace("--", "-")
    return "book-ocr-" + s.strip("-")

def page_text(result: dict) -> tuple[str, int, int]:
    """Page text, block count, unresolved-block count."""
    blocks = sorted((result.get("blocks") or []), key=lambda b: b.get("index", 0))
    parts, unresolved = [], 0
    for b in blocks:
        t = (b.get("final_text") or "").strip()
        if not t:
            continue
        if b.get("decision") == "unresolved":
            unresolved += 1
        parts.append(t)
    return "\n\n".join(parts), len(blocks), unresolved

def build(docs_dir: str, mapping_path: str) -> tuple[list, list, list]:
    matched, new = load_mapping(mapping_path)
    pages, new_items, problems = [], [], []
    for folder in sorted(os.listdir(docs_dir)):
        pdir = os.path.join(docs_dir, folder, "review", "text-pages-v1")
        if not os.path.isdir(pdir):
            problems.append(f"{folder}: no review/text-pages-v1")
            continue
        if folder in matched:
            book_id, title = matched[folder], None
        elif folder in new:
            title = new[folder]
            book_id = slug(title)
            new_items.append({"id": book_id, "title": title, "folder": folder})
        else:
            problems.append(f"{folder}: not in book_mapping.json — refusing to guess")
            continue
        for f in sorted(glob.glob(os.path.join(pdir, "page-*.json"))):
            try:
                j = json.load(open(f, encoding="utf-8"))
            except Exception as e:
                problems.append(f"{folder} {os.path.basename(f)}: {e}")
                continue
            text, nblocks, unresolved = page_text(j.get("result") or {})
            if not text:
                continue
            size = len(text.encode("utf-8"))
            if size > MAX_PAGE_BYTES:
                problems.append(f"{book_id} p{j.get('pdf_page')}: {size} bytes over ceiling")
                continue
            pages.append({
                "bookID": book_id,
                "page": int(j.get("pdf_page") or 0),
                "text": text,
                "blocks": nblocks,
                "unresolvedBlocks": unresolved,
                "reviewState": "machineProvisional",
                "validator": j.get("validator_model") or "unknown",
            })
    pages.sort(key=lambda r: (r["bookID"], r["page"]))
    return pages, new_items, problems

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--docs", required=True, help="books-raw-layout-v1/documents")
    ap.add_argument("--mapping", default=os.path.join(HERE, "book_mapping.json"))
    ap.add_argument("--out", default=os.path.join(SEED, "book_pages.json"))
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    pages, new_items, problems = build(a.docs, a.mapping)

    seen = set()
    for r in pages:
        k = (r["bookID"], r["page"])
        if k in seen:
            problems.append(f"duplicate key {k}")
        seen.add(k)

    books = {}
    for r in pages:
        b = books.setdefault(r["bookID"], {"pages": 0, "chars": 0, "unresolved": 0, "blocks": 0})
        b["pages"] += 1; b["chars"] += len(r["text"])
        b["unresolved"] += r["unresolvedBlocks"]; b["blocks"] += r["blocks"]

    print(f"books        : {len(books)}")
    print(f"page records : {len(pages):,}")
    print(f"total chars  : {sum(b['chars'] for b in books.values()):,}")
    print(f"largest page : {max((len(r['text'].encode('utf-8')) for r in pages), default=0):,} bytes "
          f"(ceiling {MAX_PAGE_BYTES:,})")
    print(f"new items    : {len(new_items)}")
    print(f"problems     : {len(problems)}")
    for p in problems[:12]:
        print(f"   - {p}")
    if a.dry_run:
        print("\n(dry run — nothing written)")
        return 1 if problems else 0

    with open(a.out, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(pages, fh, ensure_ascii=False, indent=INDENT)
        fh.write("\n")
    print(f"\nwrote {a.out}")
    side = os.path.join(HERE, "new_library_items.json")
    with open(side, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(new_items, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    print(f"wrote {side}")
    return 1 if problems else 0

if __name__ == "__main__":
    raise SystemExit(main())
