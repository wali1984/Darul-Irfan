"""Put in the layout fixes that were checked against the printed page, after `apply_proofread.py --write`.

    python Tools/Content/urdu_proofread/apply_layout_fixes.py            report only
    python Tools/Content/urdu_proofread/apply_layout_fixes.py --write    write book_pages.json

`layout_fixes.json` lists them: a page's layout letters (h heading, p paragraph, v verse, c caption ...)
put right, or printed words the text had left out (a heading such as "اسرار و معارف", a row of stars) or
a paragraph break the print does not have. Each was found by one reader and confirmed by a second, both
looking at the print, and none touches Arabic. A fix is put in only where its "was" is on its page exactly
once (or the layout letters are still those it was read against); anything else is reported and left.
A block that a fix adds takes the letter the same words have elsewhere in the books; two blocks joined
keep the first one's letter.
"""

from __future__ import annotations

import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
SEED = HERE.parents[2] / "DarulIrfanApp" / "Resources" / "SeedData"
sys.path.insert(0, str(HERE))
from apply_proofread import seed_layout  # noqa: E402


def block_at(text: str, at: int) -> int:
    return text.count("\n\n", 0, at)


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    fixes = json.loads((HERE / "layout_fixes.json").read_text(encoding="utf-8"))
    raw = (SEED / "book_pages.json").read_bytes()
    pages, layout_file = seed_layout(raw)
    index = {(row["bookID"], row["page"]): row for row in pages}
    letters: dict[str, Counter] = defaultdict(Counter)
    for row in pages:
        if row.get("layout") and len(row["layout"]) == row["text"].count("\n\n") + 1:
            for block, letter in zip(row["text"].split("\n\n"), row["layout"]):
                letters[block.strip()][letter] += 1
    done, left = Counter(), []
    for fix in fixes:
        row = index.get((fix["book"], fix["page"]))
        if row is None:
            left.append((fix["id"], "no such page"))
            continue
        layout = row.get("layout")
        if fix["kind"] == "layout":
            if layout != fix["was"] or len(fix["now"]) != len(fix["was"]):
                left.append((fix["id"], f"layout is now {layout}"))
                continue
            row["layout"] = fix["now"]
            done["layout letters"] += 1
            continue
        text = row["text"]
        if text.count(fix["was"]) != 1:
            left.append((fix["id"], f"its words are on the page {text.count(fix['was'])} times"))
            continue
        at = text.index(fix["was"])
        first = block_at(text, at)
        new_text = text[:at] + fix["now"] + text[at + len(fix["was"]):]
        if layout is not None:
            before = fix["was"].count("\n\n")
            after = fix["now"].count("\n\n")
            if fix.get("layoutNow"):
                new_layout = fix["layoutNow"] if layout == fix.get("layoutWas") else None
            else:
                parts = new_text.split("\n\n")
                span = list(layout[first:first + before + 1])
                if after > before:
                    added = parts[first:first + after + 1]
                    kept = fix["was"].split("\n\n")
                    span = []
                    for block in added:
                        mine = [k for k in kept if k.strip() and k.strip() in block]
                        if mine:
                            span.append(layout[first + kept.index(mine[0])])
                        else:
                            known = letters.get(block.strip())
                            if not known:
                                span = None
                                break
                            span.append(known.most_common(1)[0][0])
                else:
                    span = span[:after + 1]
                new_layout = None if span is None else layout[:first] + "".join(span) + layout[first + before + 1:]
            if new_layout is None or len(new_layout) != new_text.count("\n\n") + 1:
                left.append((fix["id"], "the layout letters cannot be set for it"))
                continue
            row["layout"] = new_layout
        if "blocks" in row:
            row["blocks"] += new_text.count("\n\n") - text.count("\n\n")
        row["text"] = new_text
        done["printed words or breaks"] += 1
    print(dict(done), "left:", len(left))
    for fid, why in left:
        print(f"  left {fid}: {why}")
    if "--write" in sys.argv:
        (SEED / "book_pages.json").write_text(layout_file.render(pages), encoding="utf-8", newline="")
        print(f"wrote book_pages.json in {SEED}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
