#!/usr/bin/env python3
"""Give every narrator an Urdu bio, without machine-translating scholarly text.

The narrator store arrives with English names/grades and Arabic names, lineage,
affiliations and appraisals, and every record flagged `needsUrdu`. Bulk-MT of
6,641 jarh-wa-ta'dil verdicts is exactly the wrong tool: these are technical
rulings on a narrator's reliability where one shifted word changes the verdict,
and we withdrew 1,118 Asrar Urdu records this week for that class of defect.

Two observations make it unnecessary:

  1. Urdu is written in Arabic script, so the fields already in Arabic
     (nameArabic, lineageArabic, affiliations, cities, appraisals) are readable
     as-is. They are re-used verbatim, never re-rendered.
  2. The grades are not prose. Across all 6,641 narrators there are only 218
     distinct tokens drawn from the closed vocabulary of rijal criticism, and
     grade_glossary_ur.json maps every one to its settled equivalent.

So nothing here translates a sentence. It re-uses sourced Arabic and substitutes
a fixed terminology table, which is reviewable line by line.

Writes byte-identical output to all four platform seed dirs.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

IOS_ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = IOS_ROOT.parent
SEED_DIRS = [
    IOS_ROOT / "DarulIrfanApp/Resources/SeedData",
    REPO_ROOT / "DarulIrfanAndroid/app/src/main/assets/seed",
    REPO_ROOT / "DarulIrfanHarmony/entry/src/main/resources/rawfile/seed",
    REPO_ROOT / "DarulIrfanWeb/content",
]
GLOSSARY = Path(__file__).resolve().parent / "grade_glossary_ur.json"
VERIFIED = "verified "
# Kept so a grade reads in Urdu order; the source joins tokens with commas.
SEPARATOR = "، "


def grade_to_urdu(grade: str | None, terms: dict[str, str]) -> tuple[str | None, bool]:
    """Map an English grade string to Urdu. Returns (urdu, fully_covered).

    Unmapped tokens are carried through in English rather than dropped, so a
    partial grade still reads and the gap is visible instead of silent.
    """
    if not grade:
        return None, False
    tokens = [t.strip() for t in re.split(r"[,/]| and ", grade) if t.strip()]
    if not tokens:
        return None, False
    out, complete = [], True
    for token in tokens:
        # "verified X" marks a confirmed grade in the source. The prefix is a
        # display marker, not part of the verdict, so it maps as plain X.
        key = token[len(VERIFIED):] if token.startswith(VERIFIED) else token
        if key in terms:
            out.append(terms[key])
        else:
            out.append(token)
            complete = False
    return SEPARATOR.join(out), complete


def main() -> int:
    terms = json.loads(GLOSSARY.read_text(encoding="utf-8"))["terms"]
    primary = SEED_DIRS[0] / "hadith_narrators.json"
    data = json.loads(primary.read_text(encoding="utf-8"))
    records = data if isinstance(data, list) else data.get("narrators", [])

    stats = {"total": len(records), "gradeUrdu": 0, "partial": 0,
             "nameUrdu": 0, "lineageUrdu": 0, "stillNeedsUrdu": 0}

    for r in records:
        # Arabic-script fields are re-used verbatim — same script Urdu uses.
        if r.get("nameArabic"):
            r["nameUrdu"] = r["nameArabic"]
            stats["nameUrdu"] += 1
        if r.get("lineageArabic"):
            r["lineageUrdu"] = r["lineageArabic"]
            stats["lineageUrdu"] += 1

        urdu, complete = grade_to_urdu(r.get("gradeEnglish"), terms)
        if urdu:
            r["gradeUrdu"] = urdu
            stats["gradeUrdu"] += 1
            if not complete:
                r["gradeNeedsUrdu"] = True
                stats["partial"] += 1
            else:
                r.pop("gradeNeedsUrdu", None)

        # An Urdu bio exists once the name, lineage and grade all read in Urdu.
        # Appraisals stay in their sourced Arabic and are not counted as a gap.
        if r.get("nameUrdu") and r.get("gradeUrdu") and complete:
            r["needsUrdu"] = False
            r["urduSource"] = "arabicSource+glossary"
            r["urduReviewState"] = "machine_provisional"
        else:
            r["needsUrdu"] = True
            stats["stillNeedsUrdu"] += 1

    payload = data if isinstance(data, list) else data
    text = json.dumps(payload, ensure_ascii=False, indent=1) + "\n"
    for seed in SEED_DIRS:
        (seed / "hadith_narrators.json").write_text(text, encoding="utf-8", newline="\n")

    for key, value in stats.items():
        print(f"  {key:16} {value}")
    print(f"  wrote to {len(SEED_DIRS)} seed dirs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
