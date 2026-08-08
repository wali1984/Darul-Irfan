"""Feasibility probe: can Asrar Urdu per-ayah translations be attributed reliably?

Anchors the Arabic lines in the `tafsir-final` drop against the app's canonical
mushaf. Similarity is trigram Jaccard (O(n) with sets) rather than
SequenceMatcher, which was too slow at 6,236 ayat x ~600 lines per surah.

Reports, per surah, how many ayat can be anchored above threshold — the gate
that decides whether a per-ayah build is honest or guesswork.
"""
import json
import glob
import os
import re
import statistics
import unicodedata

ROOT = r"c:/Users/WajidAli/OneDrive - Verinext/Desktop/Automation/Darul Irfan/DarulIrfan-iOS"
DOCS = os.path.join(ROOT, "Asrar u Tanzil - Eng Urdu/asrar-urdu-tafsir-final/documents/urdu")
CIRCLED = re.compile(r"[\u2460-\u2473\u3251-\u325F\u32B1-\u32BF]")


def letters(text):
    text = unicodedata.normalize("NFD", text or "")
    text = "".join(c for c in text if unicodedata.category(c) != "Mn")
    return re.sub(r"[^\u0621-\u064A]", "", text)


def grams(s, n=3):
    return {s[i:i + n] for i in range(len(s) - n + 1)}


def jaccard(a, b):
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def main():
    canon = {}
    path = os.path.join(ROOT, "DarulIrfanApp/Resources/SeedData/quran_ayahs.json")
    for a in json.load(open(path, encoding="utf-8")):
        canon.setdefault(a["surahNumber"], {})[a["ayahNumber"]] = letters(a["textArabic"])

    per_surah = {}
    sims = []
    for d in sorted(glob.glob(os.path.join(DOCS, "*"))):
        m = re.search(r"Surah-(\d+)$", d)
        if not m:
            continue
        surah = int(m.group(1))
        finals = glob.glob(os.path.join(d, "final", "*.final.txt"))
        if not finals or surah not in canon:
            continue
        lines = [l.strip() for l in open(finals[0], encoding="utf-8").read().splitlines() if l.strip()]
        # Arabic candidates: no circled ayah marker (those end Urdu lines) and
        # enough Arabic letters to be a verse rather than a heading.
        cand = [grams(letters(l)) for l in lines if not CIRCLED.search(l) and len(letters(l)) >= 10]
        matched = total = 0
        for _, av in canon[surah].items():
            if len(av) < 12:
                continue
            total += 1
            g = grams(av)
            best = max((jaccard(g, c) for c in cand), default=0.0)
            sims.append(best)
            if best >= 0.60:
                matched += 1
        if total:
            per_surah[surah] = (matched, total)

    print(f"ayat probed: {len(sims)}")
    print(f"  mean {statistics.mean(sims):.2f} | median {statistics.median(sims):.2f}")
    for th in (0.80, 0.70, 0.60, 0.50):
        hit = sum(1 for s in sims if s >= th)
        print(f"  >= {th:.2f}: {hit:5} / {len(sims)} = {100 * hit / len(sims):5.1f}%")

    full = sorted(s for s, (m, t) in per_surah.items() if m == t)
    part = sorted(s for s, (m, t) in per_surah.items() if 0 < m < t)
    none = sorted(s for s, (m, t) in per_surah.items() if m == 0)
    print()
    print(f"surahs fully anchored : {len(full)} {full[:24]}")
    print(f"surahs partial        : {len(part)}")
    print(f"surahs none anchored  : {len(none)}")
    worst = sorted(per_surah.items(), key=lambda kv: kv[1][0] / kv[1][1])[:6]
    print("worst surahs (matched/total):", [(s, f"{m}/{t}") for s, (m, t) in worst])


if __name__ == "__main__":
    main()
