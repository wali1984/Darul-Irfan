#!/usr/bin/env python3
"""Set Claude's reading of the printed Akram-ut-Tarajum beside the app's text.

Reads tarajum/pages/*.json (tarajum_check.py) and the app's Urdu translation
(tts_input.json, the same text the seed carries), joins an ayah split across
two pages, and sorts every ayah into:

  same         the printed letters and word breaks match
  spacing      the print breaks words differently - a letter moves across a
               space ("اندھیر اچھا" / "اندھیرا چھا") - so the words differ
  letters      letters differ beyond spelling variants
  spelling     only hamza/yeh spelling variants differ (دیجئیے / دیجیے)
  unread       the reading has no text for the ayah (or [؟] in it)

Vowel marks, punctuation, brackets and a space merely present or absent
between two words (جوکچھ / جو کچھ) are not differences. Everything that is not
"same" goes to adjudication, where Claude looks at the page again before any
word is changed.

    tarajum_compare.py      writes tarajum/differences.json and a summary
"""

from __future__ import annotations

import difflib
import json
import re
from collections import Counter
from pathlib import Path

WORK = Path("/mnt/sata1tb/di-claude-ocr/tarajum")
INPUT = Path("/mnt/sata1tb/di-tts/tts_input.json")

MARKS = re.compile(r"[ؐ-ًؚ-ٰٟۖ-ۭـ‌‍]")
FOLD = str.maketrans({"ي": "ی", "ى": "ی", "ك": "ک", "ه": "ہ", "ۀ": "ہ", "ة": "ہ", "ۃ": "ہ", "أ": "ا", "إ": "ا", "ٱ": "ا"})
NOT_WORD = re.compile(r"[^ء-غف-يٱ-ۓ\s]")
# Spelling variants: hamza and yeh forms, and do-chashmi he for he (انہیں / انھیں).
SPELLING = str.maketrans({"ئ": "ی", "ۓ": "ے", "ء": None, "ؤ": "و", "آ": "ا", "ۂ": "ہ", "ھ": "ہ"})


def words(text: str) -> str:
    """Letters and single spaces only: no vowel marks, punctuation or brackets."""
    return " ".join(NOT_WORD.sub(" ", MARKS.sub("", text).translate(FOLD)).split())


def breaks(text: str) -> set[int]:
    """Where the word breaks fall, counted in letters."""
    positions, count = set(), 0
    for char in text:
        if char == " ":
            positions.add(count)
        else:
            count += 1
    return positions


def spelled(letters: str) -> str:
    return re.sub(r"ی+", "ی", letters.translate(SPELLING))


def classify(app: str, printed: str) -> str:
    if not printed.strip() or "؟]" in printed or "[؟" in printed:
        return "unread"
    a, p = words(app), words(printed)
    la, lp = a.replace(" ", ""), p.replace(" ", "")
    if la != lp:
        if spelled(la) == spelled(lp):
            return "spelling"
        return "letters"
    ba, bp = breaks(a), breaks(p)
    # A break moved by a letter or two changes the words ("اندھیر اچھا" /
    # "اندھیرا چھا"): one side breaks where the other does not, and the other
    # breaks close by where the first does not. A break merely present or
    # absent ("ڈر کر" / "ڈرکر") does not change a word.
    only_a, only_p = ba - bp, bp - ba
    moved = any({position - 2, position - 1, position + 1, position + 2} & only_p for position in only_a)
    return "spacing" if moved else "same"


def main() -> int:
    app = {}
    for item in json.loads(INPUT.read_text(encoding="utf-8")):
        if item["voice"] == "ur" and item["kind"] == "translation":
            app[(item["surah"], item["ayahStart"])] = item["text"]
    printed: dict[tuple[int, int], list[str]] = {}
    pages_of: dict[tuple[int, int], list[str]] = {}
    for path in sorted(WORK.glob("pages/*.json")):
        page = json.loads(path.read_text(encoding="utf-8"))
        for ayah in page["reading"]["ayat"]:
            key = (ayah["surah"], ayah["ayah"])
            printed.setdefault(key, []).append(ayah["urdu"])
            pages_of.setdefault(key, []).append(page["id"])
    differences, counts = [], Counter()
    for key, text in sorted(app.items()):
        reading = " ".join(printed.get(key, []))
        kind = classify(text, reading)
        counts[kind] += 1
        if kind != "same":
            entry = {"surah": key[0], "ayah": key[1], "kind": kind, "app": text, "printed": reading,
                     "pages": pages_of.get(key, [])}
            if kind in ("letters", "spelling", "spacing"):
                matcher = difflib.SequenceMatcher(None, words(text).split(), words(reading).split(), autojunk=False)
                entry["changes"] = [{"app": " ".join(matcher.a[i1:i2]), "printed": " ".join(matcher.b[j1:j2])}
                                    for op, i1, i2, j1, j2 in matcher.get_opcodes() if op != "equal"]
            differences.append(entry)
    extra = sorted(set(printed) - set(app))
    (WORK / "differences.json").write_text(json.dumps({"counts": counts, "differences": differences,
                                                      "read_but_not_in_app": extra}, ensure_ascii=False, indent=1),
                                           encoding="utf-8")
    print(dict(counts), "| read but not in the app:", len(extra))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
