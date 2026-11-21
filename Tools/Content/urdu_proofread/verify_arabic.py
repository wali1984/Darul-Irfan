"""Check, by a different road, that a proofreading build left the Arabic alone.

`apply_proofread.py` refuses any change to the Qur'an's Arabic. This does not
reuse its rules. It compares the seed in the working tree with the seed at
HEAD (or a commit given as the first argument) and insists that, in every row
whose text changed:

  * no fully vowelled word (three or more harakat: Arabic) has gone, other
    than the approved slips recorded in `arabic_typos.json`; every vowelled
    word that changed at all is listed, to be read;
  * a page still has one layout letter per blank-line-separated part;
  * nothing but the text, the layout and the count of parts changed.

It also insists that `quran_ayahs.json` and `quran_translations.json` are
byte for byte what they were.

    python Tools/Content/urdu_proofread/verify_arabic.py [commit]
"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from collections import Counter
from pathlib import Path

IOS = Path(__file__).resolve().parents[3]
SEED = IOS / "DarulIrfanApp" / "Resources" / "SeedData"
HARAKAT = set("ًٌٍَُِّْٰٖٗ")
BREAKS = set(" \t\n\r()[]{}«»\"'“”‘’،۔؟!:؛.,|/-–—﴿﴾*0123456789۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩")


def vowelled(text: str) -> list[str]:
    words, word = [], []
    for ch in text + " ":
        if ch in BREAKS:
            if sum(c in HARAKAT for c in word) >= 2:
                words.append("".join(word))
            word = []
        else:
            word.append(ch)
    return words


def at(commit: str, name: str) -> bytes:
    return subprocess.run(["git", "-C", str(IOS), "show", f"{commit}:DarulIrfanApp/Resources/SeedData/{name}"],
                          capture_output=True, check=True).stdout


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    commit = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
    problems = 0
    # The slips in Arabic quotations that were approved and put right
    # (arabic_typos.json): these words, and only these, may have gone.
    approved: set[str] = set()
    record = Path(__file__).with_name("arabic_typos.json")
    if record.exists():
        mushaf: set[str] = set()
        for ayah in json.loads((SEED / "quran_ayahs.json").read_text(encoding="utf-8")):
            for word in ayah["textArabic"].split():
                word = "".join(ch for ch in word if ord(ch) not in (0x200B, 0x200C, 0x200F, 0xFEFF) and not 0xE000 <= ord(ch) <= 0xF8FF)
                mushaf.update((word, word.rstrip("ؕۖۗۘۙۚۛۜ")))
        for entry in json.loads(record.read_text(encoding="utf-8")):
            approved.update(vowelled(entry["was"]))
            if entry["how"].startswith("mushaf"):
                # What was put in must be the mushaf's own words, letter for letter.
                before = set(entry["was"].split())
                for word in entry["now"].split():
                    bare = word.strip("۔،؟!:؛()«»\"'")
                    if word not in before and sum(c in HARAKAT for c in bare) >= 1 and bare not in mushaf:
                        problems += 1
                        print(f"{entry['id']}: {bare} is not a word of the mushaf")
    keys = {
        "book_pages.json": lambda r: (r["bookID"], r["page"]),
        "quran_tafsir.json": lambda r: (r["editionID"], r["surahNumber"], r["ayahStart"], r["ayahEnd"]),
    }
    for name, key in keys.items():
        old = json.loads(at(commit, name))
        new = json.loads((SEED / name).read_text(encoding="utf-8"))
        if len(old) != len(new):
            print(f"{name}: {len(old)} rows before, {len(new)} now")
            return 1
        changed = compared = listed = 0
        for a, b in zip(old, new):
            if key(a) != key(b):
                print(f"{name}: rows are no longer in the same order at {key(a)}")
                return 1
            other = {k for k in set(a) | set(b) if k not in ("text", "layout", "blocks") and a.get(k) != b.get(k)}
            if other:
                problems += 1
                print(f"{name} {key(a)}: {sorted(other)} changed")
            if a["text"] == b["text"]:
                continue
            changed += 1
            before, after = Counter(vowelled(a["text"])), Counter(vowelled(b["text"]))
            compared += sum(before.values())
            gone, came = before - after, after - before
            if gone or came:
                # Urdu is vowelled here and there too ("اُمّت", "حُسنِ"), and a
                # correction may add or move such a mark: listed, to be read.
                # A fully vowelled word that is no longer there is Arabic lost.
                lost = [word for word in gone if sum(c in HARAKAT for c in word) >= 3 and word not in approved]
                print(f"{name} {key(a)}: was {dict(gone)} now {dict(came)}" + ("  <-- ARABIC LOST" if lost else ""))
                problems += bool(lost)
                listed += 1
            if "layout" in b and b["layout"] is not None and len(b["layout"]) != b["text"].count("\n\n") + 1:
                problems += 1
                print(f"{name} {key(a)}: {len(b['layout'])} layout letters for {b['text'].count(chr(10) * 2) + 1} parts")
        print(f"{name}: {changed} rows changed; {compared} vowelled words compared; {listed} rows listed above")
    for name in ("quran_ayahs.json", "quran_translations.json"):
        same = hashlib.sha256(at(commit, name)).digest() == hashlib.sha256((SEED / name).read_bytes()).digest()
        print(f"{name}: {'unchanged' if same else 'CHANGED'}")
        problems += not same
    print(f"problems: {problems}")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
