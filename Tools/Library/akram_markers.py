"""Ayah-end markers ﴿n﴾ in Akram-ut-Tafaseer quotations, renumbered to the mushaf.

The OCR of the printed volumes misreads the ornate marker digits: ﴿۲﴾ for 3 in
Al-Fatiha, ﴿۱۶﴾ or ﴿۱﴾ for an ayah in the hundreds. segment_akram_tafaseer's
correct_citations renumbers a marker only after it has matched the whole
quotation; this pass catches the rest, and changes nothing but marker digits.

A marker is renumbered only when one of these settles it:

* text: the Arabic just before it is the end of exactly one ayah of the row's
  range (one ayah either side allowed), the marker's own number is not one of
  the ayat that Arabic could close, and that number does not close the same
  words in any other surah (a cross-reference such as 2:178 quoted under
  5:94 keeps its number), unless the two markers before it already run
  n-2, n-1;
* text+seq: the Arabic closes several ayat of the range (a refrain such as
  "فَبِاَىِّ اٰلَاۤءِ رَبِّكُمَا تُكَذِّبٰنِ") and exactly one of them follows or
  precedes a neighbouring marker in the same line;
* fuzzy+seq: the Arabic matches no ayah exactly (an OCR misspelling) but
  reads at least 60% like one ayah of the range that a neighbouring marker
  puts next in sequence, and clearly more like it than like the printed one.

A renumbering that would give a marker the same number as the one right next
to it is left alone: that is a marker printed inside an ayah, and which of the
two is right cannot be told from the text. Translation markers (after Urdu
text) are never touched; Urdu translations number Al-Fatiha without the
basmala, and that numbering is the translation's own.
"""

from __future__ import annotations

import difflib
import re
from collections import Counter, defaultdict

EDITION = "akram-ut-tafaseer-ur"
MARKER = re.compile(r"﴿\s*([0-9٠-٩۰-۹]+)\s*﴾")
URDU_ONLY = set("ٹپچڈڑژگںےۓ")
DIGIT_VALUE = {chr(base + i): i for base in (0x30, 0x0660, 0x06F0) for i in range(10)}


def norm(text: str) -> str:
    """Letters only, with the spellings the OCR and the IndoPak text mix folded
    together (alif and hamza dropped, ya/ha/kaf folded)."""
    out = []
    for ch in text:
        o = ord(ch)
        if 0x064B <= o <= 0x065F or o in (0x0670, 0x0640) or 0x06D6 <= o <= 0x06ED or 0x0610 <= o <= 0x061A:
            continue
        if 0xE000 <= o <= 0xF8FF or o in (0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0xFEFF):
            continue
        if ch in "اأإآٱءؤئۤ":
            continue
        if ch in "ىيیۦ":
            ch = "ي"
        elif ch in "ةۃہھه":
            ch = "ه"
        elif ch in "کك":
            ch = "ك"
        if "ء" <= ch <= "ي" or ch in "ٹپچڈڑژگںےۓ":
            out.append(ch)
    return "".join(out)


class Ayat:
    def __init__(self, ayahs: list[dict]):
        self.text = {(a["surahNumber"], a["ayahNumber"]): norm(a["textArabic"]) for a in ayahs}
        self.count = Counter(a["surahNumber"] for a in ayahs)

    def closes(self, raw: str, surah: int, numbers=None) -> dict[int, str]:
        """Ayat of `surah` (or only `numbers`) that the Arabic `raw` can close:
        it is the ayah, ends with the whole ayah, or is the ayah's ending."""
        found: dict[int, str] = {}
        words = raw.split()
        candidates = numbers if numbers is not None else range(1, self.count[surah] + 1)
        for j in range(len(words)):
            seg = norm(" ".join(words[j:]))
            if len(seg) < 6:
                continue
            for k in candidates:
                a = self.text.get((surah, k))
                if a is None:
                    continue
                if a == seg:
                    found[k] = "exact"
                elif len(a) >= 10 and seg.endswith(a):
                    found.setdefault(k, "contains")
                elif len(seg) >= 12 and a.endswith(seg[-40:]):
                    found.setdefault(k, "tail")
        return found

    def closes_elsewhere(self, raw: str, number: int) -> int | None:
        for surah in sorted(self.count):
            if number <= self.count[surah] and self.closes(raw, surah, [number]):
                return surah
        return None


def _ratio(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, a, b).ratio()


def _line_markers(text: str, base: int, line: str, surah: int, ayat: Ayat):
    items, prev = [], 0
    for m in MARKER.finditer(line):
        number = int("".join(str(DIGIT_VALUE[c]) for c in m.group(1)))
        cut = line[prev:m.start()]
        prev = m.end()
        last = max((i for i, ch in enumerate(cut) if ch in URDU_ONLY), default=-1)
        arabic = cut[last + 1:]
        items.append({"n": number, "cur": number, "raw": arabic, "seg": norm(arabic),
                      "C": ayat.closes(arabic, surah), "span": (base + m.start(1), base + m.end(1)),
                      "why": None, "dup": False})
    return items


def renumber_row(row: dict, ayat: Ayat) -> tuple[str, list[dict]]:
    surah, lo, hi, text = row["surahNumber"], row["ayahStart"], row["ayahEnd"], row["text"]
    changes = []
    for line_m in re.finditer(r"[^\n]+", text):
        items = _line_markers(text, line_m.start(), line_m.group(0), surah, ayat)

        def nb(i, d):
            j = i + d
            return items[j]["cur"] if 0 <= j < len(items) else None

        def in_sequence(i, k):
            return nb(i, -1) == k - 1 or nb(i, 1) == k + 1 or nb(i, -2) == k - 2 or nb(i, 2) == k + 2

        changed = True
        while changed:
            changed = False
            for i, x in enumerate(items):
                if x["why"] or x["n"] in x["C"]:
                    continue
                own = [k for k in x["C"] if lo - 1 <= k <= hi + 1]
                fix = why = None
                if len(own) == 1 and (len(x["C"]) == 1 or in_sequence(i, own[0]) or x["C"][own[0]] != "tail"):
                    fix, why = own[0], "text"
                elif len(own) > 1:
                    q = [k for k in own if in_sequence(i, k)]
                    if len(q) == 1:
                        fix, why = q[0], "text+seq"
                if fix is None and len(x["seg"]) >= 6 and not x["C"]:
                    printed = ayat.text.get((surah, x["n"]), "")
                    floor = _ratio(x["seg"], printed) + 0.15
                    q = [k for k in range(max(1, lo - 1), min(ayat.count[surah], hi + 1) + 1)
                         if k != x["n"] and in_sequence(i, k)]
                    q = [k for k in q if _ratio(x["seg"], ayat.text[(surah, k)]) >= 0.6
                         and _ratio(x["seg"], ayat.text[(surah, k)]) > floor]
                    if len(q) == 1:
                        fix, why = q[0], "fuzzy+seq"
                if fix is None or fix == x["n"]:
                    continue
                if nb(i, -1) == fix or nb(i, 1) == fix:
                    continue  # a marker printed inside an ayah: leave both as printed
                x["cur"], x["why"] = fix, why
                changed = True
        for x in items:
            if not x["why"]:
                continue
            numbers = [y["cur"] for y in items]
            if x["why"] == "text" and ayat.closes_elsewhere(x["raw"], x["n"]):
                if not (x["cur"] - 1 in numbers and x["cur"] - 2 in numbers):
                    continue
            changes.append({"span": x["span"], "old": x["n"], "new": x["cur"], "why": x["why"]})
    for c in sorted(changes, key=lambda c: -c["span"][0]):
        a, b = c["span"]
        family = ord(text[a]) - DIGIT_VALUE[text[a]]
        text = text[:a] + "".join(chr(family + int(d)) for d in str(c["new"])) + text[b:]
    return text, changes


def renumber_markers(rows: list[dict], ayahs: list[dict]) -> tuple[list[dict], dict]:
    """Renumber the Akram rows' quotation markers in place; returns the rows
    and a report of every change by row."""
    ayat = Ayat(ayahs)
    report: dict = {"markersRenumberedToMushaf": 0, "byKind": defaultdict(int), "rows": []}
    for row in rows:
        if row.get("editionID") != EDITION:
            continue
        row["text"], changes = renumber_row(row, ayat)
        if changes:
            report["rows"].append({"row": f"{row['surahNumber']}:{row['ayahStart']}-{row['ayahEnd']}",
                                   "markers": [f"{c['old']}->{c['new']} ({c['why']})" for c in changes]})
            report["markersRenumberedToMushaf"] += len(changes)
            for c in changes:
                report["byKind"][c["why"]] += 1
    report["byKind"] = dict(report["byKind"])
    return rows, report
