#!/usr/bin/env python3
"""Re-extract the labelled bio fields for every narrator from the cached pages.

The store's records are sound where it matters most — names, grades, lineage,
appraisals, teacher/student graphs — but the labelled facts came through
wrong: kunya/generation/deathYear/cities(EN) are null for all 12,643 narrators
and `cities`/`affiliations` hold the ARABIC column with the page's own label
text baked in ("النسب والنسبة الغفاري"). That is why the bio sheet reads as
Arabic-only in an English UI.

The cached pages carry each fact twice, in separate .label/.field sibling
pairs (measured: "Cities/Regions" => "Homs" and "بلد الإقامة" => "حمص"), so
this walks every cached narrator page and overwrites exactly those fields,
each language into its own key. Unknown labels are counted and reported, not
guessed. No network: cache only. Writes all four platform seed dirs.

Run apply_urdu_glossary.py afterwards to refresh the Urdu layer.
"""
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ingest_sunnah import SEED_DIRS, PRIMARY_SEED  # noqa: E402
from bs4 import BeautifulSoup  # noqa: E402

# label text (normalised) -> record key. English labels fill the English keys,
# Arabic labels the Arabic keys; neither side ever crosses into the other.
LABELS = {
    "kunya": "kunya",
    "generation": "generation",
    "cities/regions": "cities",
    "cities": "cities",
    "affiliations": "affiliations",
    "school": "madhhab",
    "madhhab": "madhhab",
    "narrator lineage": "lineageEnglish",
    "full name": "lineageEnglish",
    "died": "deathYear",
    "death year": "deathYear",
    "الكنية": "kunyaArabic",
    "الطبقة": "generationArabic",
    "بلد الإقامة": "citiesArabic",
    "النسب والنسبة": "affiliationsArabic",
    "المذهب": "madhhabArabic",
    "الاسم الكامل": "lineageArabic",
    "الوفاة": "deathYearArabic",
    "سنة الوفاة": "deathYearArabic",
    "title / byname": "byname",
    "اللقب": "bynameArabic",
    "profession": "profession",
    "الصنعة": "professionArabic",
    "description": "descriptionEnglish",
    "الوصف": "descriptionArabic",
}
# Only these keys are overwritten; anything else in the record is untouched.
# lineage/death fill only when currently empty, so the good existing lineage
# is never replaced by a page variant.
FILL_ONLY_IF_EMPTY = {"lineageEnglish", "lineageArabic"}


def clean(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def main() -> int:
    cache = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".hadith_cache")
    store_path = PRIMARY_SEED / "hadith_narrators.json"
    records = json.loads(store_path.read_text(encoding="utf-8"))

    unknown: Counter = Counter()
    stats = Counter()
    missing_page = 0

    for r in records:
        page = cache / f"_narrator_{r['id']}.html"
        if not page.exists():
            missing_page += 1
            continue
        soup = BeautifulSoup(page.read_text(encoding="utf-8"), "lxml")

        extracted: dict[str, str] = {}
        for lab in soup.select(".label"):
            fld = lab.parent.select_one(".field")
            if fld is None:
                continue
            label = clean(lab.get_text()).lower().rstrip(":")
            value = clean(fld.get_text())
            if not value:
                continue
            key = LABELS.get(label)
            if key is None:
                unknown[label] += 1
                continue
            extracted[key] = value

        # The contaminated values are replaced outright; a page without the
        # field clears it rather than leaving stale label-noise behind.
        for key in ("kunya", "kunyaArabic", "generation", "generationArabic",
                    "cities", "citiesArabic", "affiliations",
                    "affiliationsArabic", "madhhab", "madhhabArabic",
                    "deathYear", "deathYearArabic", "byname", "bynameArabic",
                    "profession", "professionArabic",
                    "descriptionEnglish", "descriptionArabic"):
            value = extracted.get(key)
            if value:
                r[key] = value
                stats[key] += 1
            elif key in r:
                del r[key]
        for key in FILL_ONLY_IF_EMPTY:
            if extracted.get(key) and not r.get(key):
                r[key] = extracted[key]
                stats[key] += 1

    body = json.dumps(records, ensure_ascii=False, indent=1) + "\n"
    for seed in SEED_DIRS:
        (seed / "hadith_narrators.json").write_text(body, encoding="utf-8", newline="\n")

    print(f"records: {len(records)} | pages missing from cache: {missing_page}")
    for key, count in sorted(stats.items()):
        print(f"  {key:20} {count}")
    print("unknown labels (not guessed):", unknown.most_common(12) or "none")
    print(f"written to {len(SEED_DIRS)} seed dirs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
