#!/usr/bin/env python3
"""Hadith content gate: the defects found in the October 2026 audit fail here.

Run on the seed folder before a pack is written or shipped:

    python Tools/Hadith/hadith_gate.py                 # iOS seed folder
    python Tools/Hadith/hadith_gate.py --seed <dir>     # any copy

ingest_sunnah.py calls check_pack() on every collection before --pack writes
anything, so a bad join can no longer reach the four seed folders.

Rules (each was a shipped defect):
  display     The Arabic the reader shows (arabicSegments) must be the
              record's own narration (text_ar): identical, token similarity
              >= 0.9, or the same words. Allowed besides: the record's whole
              narration plus the compiler's remarks that no neighbour carries.
              Fails: another narration (HAD-001/002: 4,650 records joined by
              number), part of it (HAD-016), or a neighbour's text too.
  text        No markup, URL, control character, U+FFFC or placeholder in any
              displayed field (HAD-007/014/015/017); U+FFFD only where
              Tools/ContentIntegrity/known_upstream_defects.json records it.
  copies      No record may carry the same Arabic as another record while
              its own Urdu is a different text (HAD-003: 85 records were
              "filled" with a neighbour's Arabic and English).
  verses      A verse span must quote the ayah it links to (HAD-022).
  kitab       Every catalogue section exists in the pack, every kitab is one
              run of records, every record's kitab is in the catalogue
              (HAD-011/024).
  muslim      Sahih Muslim display numbers match
              Tools/Hadith/muslim_reference_numbers.json (HAD-004).
  narrators   Links to narrators missing from hadith_narrators.json are
              counted (warning: some have no page at the source).
"""
from __future__ import annotations

import argparse
import difflib
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
IOS_ROOT = HERE.parents[1]
DEFAULT_SEED = IOS_ROOT / "DarulIrfanApp/Resources/SeedData"
KNOWN_DEFECTS = IOS_ROOT / "Tools/ContentIntegrity/known_upstream_defects.json"
MUSLIM_REFERENCES = HERE / "muslim_reference_numbers.json"

# Records whose kitab differs from the run they sit in, and where sunnah.com
# places them in that same kitab (the compiler's own cross-references, kept in
# fawazahmed0's order; moving one would change its canonicalID). They are
# skipped when kitab runs are checked; any other stray label fails.
STRAY_KITAB_ALLOWED = {
    "muslim|5114|5115", "muslim|5115|5116",          # 977c/977d: Book 36, Hadith 81/82
    "ibnmajah|2435|2435",                             # Book 10 between 15 and 16
    "ibnmajah|2476|2476", "ibnmajah|2477|2477",       # Book 10 inside 16 (audit: as on sunnah.com)
    "ibnmajah|2528|2528",                             # Book 15 inside 19 (audit: as on sunnah.com)
    "tirmidhi|2735|2748",                             # Book 38 inside 40 (sunnah.com: Book 38, Hadith 13)
    # Nasa'i 3919b (Book 35b, Hadith 64): the 83rd narration of 35b has no
    # free sourceSequence between 3856 and 3939, so it follows the last record.
    "nasai|3919.2|5766",
}

# ---------------------------------------------------------------- Arabic
_TASHKEEL = re.compile("[ؐ-ًؚ-ٰٟۖ-ۭـ]")
_NONLETTER = re.compile(r"[^ء-ي٠-٩ٮ-ۓۺ-ۿ0-9 ]+")
_FOLD = str.maketrans({"أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ى": "ي", "ی": "ي", "ئ": "ي",
                       "ؤ": "و", "ة": "ه", "ۃ": "ه", "ہ": "ه", "ھ": "ه", "ک": "ك", "ڪ": "ك"})


def norm_ar(s: str | None) -> str:
    if not s:
        return ""
    s = _NONLETTER.sub(" ", _TASHKEEL.sub("", s).translate(_FOLD))
    return re.sub(r"\s+", " ", s).strip()


def toks(s):
    return norm_ar(s).split()


def sim(a, b) -> float:
    ta, tb = toks(a), toks(b)
    if not ta or not tb:
        return 0.0
    return difflib.SequenceMatcher(None, ta, tb, autojunk=False).ratio()


def coverage(own, shown):
    ta, tb = toks(own), toks(shown)
    if not ta or not tb:
        return 0.0, 0.0
    ca, cb = Counter(ta), Counter(tb)
    inter = sum(min(v, cb.get(k, 0)) for k, v in ca.items())
    return inter / len(ta), inter / len(tb)


def seg_text(segs) -> str:
    return " ".join(s.get("text", "") for s in (segs or []))


def _grams(tokens, n=4):
    return {tuple(tokens[i:i + n]) for i in range(len(tokens) - n + 1)}


def same_narration(own_ar, other_ar, threshold=0.9) -> bool:
    """True when other_ar is this record's narration: identical, similar
    (>= threshold), the same words, or all of it plus more (the compiler's
    remark that sunnah.com prints in the same block). False for a record
    without Arabic of its own: there is nothing to prove the join with."""
    if not own_ar or not other_ar:
        return False
    if norm_ar(own_ar) == norm_ar(other_ar):
        return True
    co, cs = coverage(own_ar, other_ar)
    return sim(own_ar, other_ar) >= threshold or co >= threshold


def classify_display(recs, i, threshold=0.9):
    """ok | fuller | partial | merged | other (see the module docstring)."""
    r = recs[i]
    segs, ta = r.get("arabicSegments"), r.get("text_ar")
    if not segs or not ta:
        return "ok", {}
    shown = seg_text(segs)
    if norm_ar(shown) == norm_ar(ta):
        return "ok", {}
    s = sim(ta, shown)
    co, cs = coverage(ta, shown)
    d = {"sim": round(s, 3), "covOwn": round(co, 3), "covShown": round(cs, 3)}
    if s >= threshold or (co >= threshold and cs >= threshold):
        return "ok", d
    if co < threshold:
        return ("partial" if cs >= threshold else "other"), d
    a, b = toks(ta), toks(shown)
    extra = []
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if op in ("insert", "replace"):
            extra += b[j1:j2]
    if len(extra) >= 12:
        g = _grams(extra)
        for k in range(max(0, i - 3), min(len(recs), i + 4)):
            if k != i and g:
                h = _grams(toks(recs[k].get("text_ar")))
                if len(g & h) / len(g) >= 0.8:
                    d["neighbour"] = recs[k]["canonicalID"]
                    return "merged", d
    return "fuller", d


# ------------------------------------------------------------------ text
TAG = re.compile(r"<[^<>]{0,80}>|</?(?:span|b|br|i|div|p|a)\b|>br>|[a-z]>[a-z]", re.I)
URL = re.compile(r"https?\s*:\s*//|www\.|tanzil\.net", re.I)
CTRL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]")
PLACEHOLDER = re.compile(r"Hadith Translation Not Available", re.I)
DISPLAY_FIELDS = ("text_ar", "text_en", "text_ur", "urduSanad", "urduText",
                  "chapterTitleEnglish", "chapterTitleArabic", "chapterTitleUrdu")


def text_defects(s: str) -> list[str]:
    out = []
    if TAG.search(s):
        out.append("markup")
    if URL.search(s):
        out.append("url")
    if CTRL.search(s):
        out.append("control character")
    if "\ufffc" in s:
        out.append("U+FFFC")
    if PLACEHOLDER.search(s):
        out.append("placeholder")
    return out


# ---------------------------------------------------------------- verses
class Verses:
    def __init__(self, ayahs):
        self.sk = {}
        self.count = Counter()
        for a in ayahs:
            key = (a["surahNumber"], a["ayahNumber"])
            self.sk[key] = self._tri(a["textArabic"])
            self.count[a["surahNumber"]] += 1

    @staticmethod
    def _tri(s):
        k = re.sub("[اءيوهى ]", "", norm_ar(s))
        return {k[i:i + 3] for i in range(len(k) - 2)}

    def quote_matches(self, text, surah, a1, a2) -> bool | None:
        st = self._tri(text)
        if len(st) < 6:
            return None                          # too short to judge
        cited = set().union(*[self.sk.get((surah, k), set()) for k in range(a1, a2 + 1)])
        c = len(st & cited) / len(st)
        if c >= 0.5:
            return True
        best = max((len(st & t) / len(st) for (s, _), t in self.sk.items() if s == surah), default=0)
        return False if best >= 0.8 else None    # wrong only when another ayah clearly fits


# ----------------------------------------------------------------- checks
def check_pack(slug, records, *, known=None, verses=None, catalog_book=None,
               muslim_refs=None, narrator_ids=None) -> tuple[list[str], list[str]]:
    """-> (failures, warnings) for one collection."""
    fail, warn = [], []
    recs = sorted(records, key=lambda r: r["sourceSequence"])
    known = known or {}

    bad = [(recs[i]["canonicalID"], k) for i in range(len(recs))
           for k, _ in [classify_display(recs, i)] if k in ("partial", "merged", "other")]
    if bad:
        fail.append(f"{slug}: {len(bad)} records display Arabic that is not their own narration: {bad[:5]}")

    txt, fffd = [], []
    for r in recs:
        cid = r["canonicalID"]
        for f in DISPLAY_FIELDS:
            v = r.get(f)
            if isinstance(v, str) and v:
                txt += [(cid, f, d) for d in text_defects(v)]
                n = v.count("\ufffd")
                if n and n > known.get(cid, {}).get(f[5:] if f.startswith("text_") else f, 0):
                    fffd.append((cid, f, n))
        for k, s in enumerate(r.get("arabicSegments") or []):
            txt += [(cid, f"segment {k}", d) for d in text_defects(s.get("text", ""))]
            if "\ufffd" in s.get("text", ""):
                fffd.append((cid, f"segment {k}", s["text"].count("\ufffd")))
    if txt:
        fail.append(f"{slug}: {len(txt)} markup/URL/control/placeholder defects in displayed text: {txt[:5]}")
    if fffd:
        fail.append(f"{slug}: {len(fffd)} U+FFFD not recorded in known_upstream_defects.json: {fffd[:5]}")

    by_ar = defaultdict(list)
    for r in recs:
        k = norm_ar(r.get("text_ar"))
        if len(k) >= 60:
            by_ar[k].append(r)
    copies = []
    for group in by_ar.values():
        # A hadith the compiler repeats has the same Arabic twice and two
        # Urdu renderings of the same meaning (word similarity 0.49-0.91 on
        # the current corpus). A record filled with another narration's Arabic
        # keeps its own Urdu, a different narration (0.05-0.21 on the 85
        # HAD-003 records).
        with_ur = [r for r in group if r.get("text_ur")]
        for x in range(len(with_ur)):
            for y in range(x + 1, len(with_ur)):
                if sim(with_ur[x]["text_ur"], with_ur[y]["text_ur"]) < 0.3:
                    copies.append([with_ur[x]["canonicalID"], with_ur[y]["canonicalID"]])
    if copies:
        fail.append(f"{slug}: {len(copies)} Arabic texts are copies on records whose Urdu differs (filled from another narration): {copies[:3]}")

    if verses is not None:
        wrong = []
        for r in recs:
            for s in r.get("arabicSegments") or []:
                if s.get("type") == "verse":
                    ok = verses.quote_matches(s.get("text", ""), s.get("surah"), s.get("ayahStart"), s.get("ayahEnd"))
                    if ok is False:
                        wrong.append((r["canonicalID"], f"{s.get('surah')}:{s.get('ayahStart')}-{s.get('ayahEnd')}"))
        if wrong:
            fail.append(f"{slug}: {len(wrong)} verse links quote another ayah: {wrong[:5]}")

    if catalog_book is not None and catalog_book.get("sections"):
        nums = {s["number"] for s in catalog_book["sections"]}
        present = Counter(r.get("sourceBook") for r in recs)
        absent = sorted(n for n in nums if not present.get(n))
        if absent:
            fail.append(f"{slug}: catalogue books with no narration in the pack: {absent}")
        unknown = sorted(k for k in present if k is not None and k not in nums)
        if unknown:
            fail.append(f"{slug}: narrations in books the catalogue does not list: {unknown}")
        runs = Counter()
        prev = object()
        for r in recs:
            b = r.get("sourceBook")
            if b is None or r["canonicalID"] in STRAY_KITAB_ALLOWED:
                continue
            if b != prev:
                runs[b] += 1
            prev = b
        split = sorted(b for b, n in runs.items() if n > 1)
        if split:
            fail.append(f"{slug}: kitabs split into several runs (stray kitab labels): {split[:10]}")

    if muslim_refs is not None and slug == "muslim":
        mism = [r["canonicalID"] for r in recs
                if r["canonicalID"] in muslim_refs and muslim_refs[r["canonicalID"]]["display"] != r["displayNumber"]]
        if mism:
            fail.append(f"muslim: {len(mism)} display numbers differ from muslim_reference_numbers.json: {mism[:5]}")

    if narrator_ids is not None:
        dangling = Counter(s["narratorId"] for r in recs for s in r.get("arabicSegments") or []
                           if s.get("type") == "isnad" and "narratorId" in s and s["narratorId"] not in narrator_ids)
        if dangling:
            warn.append(f"{slug}: {sum(dangling.values())} narrator links to {len(dangling)} ids without a biography")
    return fail, warn


def selftest() -> None:
    recs = [
        {"canonicalID": "x|1|1", "sourceSequence": 1, "text_ar": "حَدَّثَنَا يَحْيَى عَنْ مَالِكٍ عَنْ نَافِعٍ عَنِ ابْنِ عُمَرَ قَالَ صَلَّى رَسُولُ اللَّهِ",
         "arabicSegments": [{"type": "matn", "text": "حَدَّثَنَا قُتَيْبَةُ عَنْ لَيْثٍ عَنْ يَزِيدَ عَنْ أَبِي الْخَيْرِ عَنْ عُقْبَةَ أَنَّهُ قَالَ"}]},
        {"canonicalID": "x|2|2", "sourceSequence": 2, "text_ar": "قَالَ النَّبِيُّ إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ",
         "text_ur": "اعمال کا دارومدار نیتوں پر ہے</b>"},
    ]
    f, _ = check_pack("x", recs)
    assert any("not their own narration" in m for m in f), f
    assert any("markup" in m for m in f), f
    print("hadith_gate selftest: PASS")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seed", type=Path, default=DEFAULT_SEED)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        selftest()
        return 0
    seed = args.seed
    cat = json.loads((seed / "hadith_books.json").read_text(encoding="utf-8"))
    known = json.loads(KNOWN_DEFECTS.read_text(encoding="utf-8"))["narrations"] if KNOWN_DEFECTS.exists() else {}
    quran = seed / "quran_ayahs.json"
    verses = Verses(json.loads(quran.read_text(encoding="utf-8"))) if quran.exists() else None
    refs = json.loads(MUSLIM_REFERENCES.read_text(encoding="utf-8"))["records"] if MUSLIM_REFERENCES.exists() else None
    narr = seed / "hadith_narrators.json"
    nids = {n["id"] for n in json.loads(narr.read_text(encoding="utf-8"))} if narr.exists() else None
    failures, warnings = [], []
    for book in cat["books"]:
        records = json.loads((seed / f"hadith_{book['id']}.json").read_text(encoding="utf-8"))
        if book["hadithCount"] != len(records):
            failures.append(f"{book['id']}: catalogue says {book['hadithCount']}, pack holds {len(records)}")
        f, w = check_pack(book["id"], records, known=known, verses=verses, catalog_book=book,
                          muslim_refs=refs, narrator_ids=nids)
        failures += f
        warnings += w
    for w in warnings:
        print("warning:", w)
    if failures:
        print(f"hadith gate: FAIL ({len(failures)})")
        for f in failures:
            print("  -", f)
        return 1
    print(f"hadith gate: PASS ({len(cat['books'])} collections)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
