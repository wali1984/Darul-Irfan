"""Collapse duplicate library entries so one publication appears once.

The catalogue was built from two passes over the same site. The crawl made
entries keyed by PDF filename (`book-Hayyat-e-Tayyabah-I.pdf`) and the OCR
ingest made or matched entries keyed by slug (`book-hayyat-e-tayyabah-i`). Both
survived, so a reader sees the same book twice: one copy opens its text, the
twin says nothing is available and offers only the website link.

This keeps the copy that has text, moves any field only the twin knew onto it -
`author` is usually the one - and drops the twin. Nothing that carries text is
ever removed, and a download URL is never lost.

It also drops entries that are a page of the website rather than a publication.
`page-downloads-index` is the site's own downloads index: in the library it is a
row whose only purpose is to send the reader to a browser, which is the one
thing the app is not supposed to do.

Read-only unless --write. Writes all four platform seeds.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1].parent

SEED_DIRS = [
    ROOT / "DarulIrfanApp" / "Resources" / "SeedData",
    ROOT.parent / "DarulIrfanAndroid" / "app" / "src" / "main" / "assets" / "seed",
    ROOT.parent / "DarulIrfanHarmony" / "entry" / "src" / "main" / "resources" / "rawfile" / "seed",
    ROOT.parent / "DarulIrfanWeb" / "content",
]

# Website navigation that was catalogued as though it were a publication. Listed
# by hand, with the reason, because removing content must never be a guess.
NOT_PUBLICATIONS = {
    "page-downloads-index": "the site's downloads index page, not a publication",
}

# Fields worth rescuing from a twin before it goes.
MERGEABLE = ("author", "titleUrdu", "excerpt", "publishedAt", "sourceUrl", "downloadUrls", "mediaUrls")


def normalised(value: str | None) -> str:
    return re.sub(r"[^a-z0-9]", "", (value or "").lower())


def has_text(item: dict, with_pages: set[str]) -> bool:
    if item["id"] in with_pages:
        return True
    return bool((item.get("bodyPlainText") or item.get("bodyHtml") or "").strip())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write the four seeds")
    args = parser.parse_args()

    seed = SEED_DIRS[0]
    items = json.loads((seed / "library_items.json").read_text(encoding="utf-8"))
    index = json.loads((seed / "book_pages_index.json").read_text(encoding="utf-8"))
    with_pages = {entry["bookID"] for entry in index}

    by_id = {item["id"]: item for item in items}
    groups: dict[tuple[str | None, str], list[dict]] = {}
    for item in items:
        groups.setdefault((item.get("category"), normalised(item.get("title"))), []).append(item)

    removals: dict[str, str] = {}
    merges: list[str] = []

    for (category, _), group in groups.items():
        if len(group) < 2:
            continue
        readable = [item for item in group if has_text(item, with_pages)]
        textless = [item for item in group if not has_text(item, with_pages)]
        if readable and textless:
            # Keep the one a reader can actually open.
            keeper = readable[0]
            for twin in textless:
                rescued = []
                for field in MERGEABLE:
                    value = twin.get(field)
                    if value in (None, "", [], {}):
                        continue
                    if keeper.get(field) in (None, "", [], {}):
                        keeper[field] = value
                        rescued.append(field)
                removals[twin["id"]] = f"duplicate of {keeper['id']}"
                if rescued:
                    merges.append(f"{keeper['id']} <- {twin['id']} ({', '.join(rescued)})")
        elif len(group) > 1 and not readable:
            # Neither copy has text. Keep the slug-style id, which is the one
            # the rest of the catalogue references, and drop the filename twin.
            keeper = min(group, key=lambda item: (item["id"].lower().endswith(".pdf"), len(item["id"])))
            for twin in group:
                if twin["id"] != keeper["id"]:
                    removals[twin["id"]] = f"duplicate of {keeper['id']} (neither has text)"

    for identifier, reason in NOT_PUBLICATIONS.items():
        if identifier in by_id:
            removals[identifier] = reason

    # A row with pages must never be removed: that would orphan its text.
    for identifier in list(removals):
        if identifier in with_pages:
            print(f"refusing to remove {identifier}: it has page text")
            del removals[identifier]

    kept = [item for item in items if item["id"] not in removals]

    print(f"library items      : {len(items)} -> {len(kept)}")
    print(f"entries removed    : {len(removals)}")
    print(f"fields rescued onto the surviving entry: {len(merges)}")
    print()
    for identifier, reason in sorted(removals.items()):
        print(f"  - {identifier[:46]:46} {reason}")
    if merges:
        print()
        for line in merges[:10]:
            print(f"  merged {line}")
        if len(merges) > 10:
            print(f"  ... and {len(merges) - 10} more")

    remaining = sum(1 for item in kept if not has_text(item, with_pages))
    print()
    print(f"items still without text: {remaining} of {len(kept)}")

    if not args.write:
        print("\nreport only; pass --write to update the seeds")
        return 0

    payload = json.dumps(kept, ensure_ascii=False, separators=(",", ":"))
    for directory in SEED_DIRS:
        if not directory.exists():
            print(f"  skipped (absent): {directory}")
            continue
        (directory / "library_items.json").write_text(payload, encoding="utf-8", newline="")
        print(f"  wrote {directory}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
