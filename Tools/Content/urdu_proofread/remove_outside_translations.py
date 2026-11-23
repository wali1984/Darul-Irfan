"""Take the Pickthall and Jalandhry translations out of the Asrar-at-Tanzil Urdu books (the owner, 23 November 2026).

    python Tools/Content/urdu_proofread/remove_outside_translations.py            report only
    python Tools/Content/urdu_proofread/remove_outside_translations.py --write    write book_pages.json and book_links.json

The printed Asrar Urdu volumes carry, beside the ayat, Pickthall's English and Jalandhry's Urdu
translation. The Silsila's rule is that only its own translations are shown, so those blocks leave the
app's text (the printed pages, the PDF, keep them). `outside_translations.json` names each block by
its book, page and the SHA-256 of its exact text, found by comparing every block with the two
editions ayah by ayah (Tools/Content/urdu_proofread/README.md). A block is removed only where that
exact text is a block of its page; the page's layout letters lose the same places, and a link whose
words were only in a removed block goes with it. Run after apply_layout_fixes.py.
"""

from __future__ import annotations

import hashlib
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
SEED = HERE.parents[2] / "DarulIrfanApp" / "Resources" / "SeedData"
sys.path.insert(0, str(HERE))
from apply_proofread import seed_layout  # noqa: E402


def digest(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    wanted: dict[tuple[str, int], dict[str, str]] = defaultdict(dict)
    for entry in json.loads((HERE / "outside_translations.json").read_text(encoding="utf-8")):
        wanted[(entry["book"], entry["page"])][entry["sha256"]] = entry["edition"]
    pages, pages_layout = seed_layout((SEED / "book_pages.json").read_bytes())
    links, links_layout = seed_layout((SEED / "book_links.json").read_bytes())
    removed, missing, dropped_links = Counter(), [], 0
    for row in pages:
        targets = wanted.get((row["bookID"], row["page"]))
        if not targets:
            continue
        blocks = row["text"].split("\n\n")
        keep = [digest(block) not in targets for block in blocks]
        found = {digest(block) for block in blocks} & set(targets)
        missing += [(row["bookID"], row["page"], sha[:12]) for sha in set(targets) - found]
        if all(keep):
            continue
        for block, kept in zip(blocks, keep):
            if not kept:
                removed[targets[digest(block)]] += 1
        layout = row.get("layout")
        if layout is not None:
            if len(layout) != len(blocks):
                raise SystemExit(f"{row['bookID']} p{row['page']}: layout letters do not fit; nothing written")
            row["layout"] = "".join(letter for letter, kept in zip(layout, keep) if kept) or None
        row["text"] = "\n\n".join(block for block, kept in zip(blocks, keep) if kept)
        if "blocks" in row:
            row["blocks"] = sum(keep)
        entries = links["books"].get(row["bookID"], {}).get(str(row["page"]))
        if entries:
            still = [entry for entry in entries if entry["m"] in row["text"]]
            dropped_links += len(entries) - len(still)
            links["books"][row["bookID"]][str(row["page"])] = still
    print(dict(removed), "links that went with them:", dropped_links, "not found:", len(missing))
    for item in missing[:20]:
        print("  not found:", item)
    if missing:
        raise SystemExit("some listed blocks are not on their pages; nothing written")
    if "--write" in sys.argv:
        (SEED / "book_pages.json").write_text(pages_layout.render(pages), encoding="utf-8", newline="")
        (SEED / "book_links.json").write_text(links_layout.render(links), encoding="utf-8", newline="")
        print(f"wrote book_pages.json and book_links.json in {SEED}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
