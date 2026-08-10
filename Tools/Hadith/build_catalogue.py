#!/usr/bin/env python3
"""Rebuild hadith_books.json from the packs actually on disk.

A collection is not shippable just because its pack exists. The app's
`HadithBook` needs a title in both languages, a section list and a count, and
`Tools/ContentIntegrity/check_content.py` asserts the catalogue's ids match its
HADITH_BOOKS list exactly — so pack, catalogue and gate move together or the
build fails.

Counts are taken from the packaged records, never from upstream metadata, so
the catalogue cannot over-claim. `hasArabic`/`hasEnglish`/`hasUrdu` likewise
describe what is really in the pack: the nineteen collections built from
sunnah.com have no Urdu at source, and saying so is what makes the reader show
its "no Urdu translation" state instead of a blank.

English and Arabic titles come from each collection's own landing page
(.colindextitle) rather than being invented here. Urdu titles are the
established names of the works.
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
PRIMARY = SEED_DIRS[0]

# Single-page collections have no .colindextitle on their landing page; their
# English titles come from the page <title> observed 2026-08-09.
TITLE_EN = {
    "nawawi40": "Forty Hadith of an-Nawawi",
    "qudsi40": "Forty Hadith Qudsi",
    "hisn": "Hisn al-Muslim",
    "virtues": "Virtues of the Qur'an's Chapters and Verses",
}

# The established Urdu name of each work. Not translations — these are how the
# collections are titled in Urdu scholarship.
TITLE_UR = {
    "bukhari": "صحیح بخاری", "muslim": "صحیح مسلم", "abudawud": "سنن ابو داؤد",
    "tirmidhi": "جامع ترمذی", "nasai": "سنن نسائی", "ibnmajah": "سنن ابن ماجہ",
    "malik": "موطأ امام مالک",
    "nawawi40": "اربعین نووی", "qudsi40": "چالیس حدیث قدسی",
    "riyadussalihin": "ریاض الصالحین", "mishkat": "مشکوٰۃ المصابیح",
    "bulugh": "بلوغ المرام", "adab": "الادب المفرد",
    "shamail": "الشمائل المحمدیہ", "hisn": "حصن المسلم",
    "virtues": "فضائل سور و آیاتِ قرآن",
    "ahmad": "مسند احمد", "darimi": "سنن دارمی",
    "ibnkhuzayma": "صحیح ابن خزیمہ", "ibnhibban": "صحیح ابن حبان",
    "hakim": "مستدرک حاکم", "abdurrazzaq": "مصنف عبد الرزاق",
    "ibnabishayba": "مصنف ابن ابی شیبہ", "daraqutni": "سنن دارقطنی",
    "bayhaqi": "السنن الکبریٰ للبیہقی", "nasaikubra": "السنن الکبریٰ للنسائی",
}


def landing_titles(cache: Path, slug: str) -> tuple[str | None, str | None]:
    """(english, arabic) from the collection's cached landing page."""
    page = cache / f"_{slug}.html"
    if not page.exists():
        return None, None
    try:
        from bs4 import BeautifulSoup
    except ImportError:
        return None, None
    node = BeautifulSoup(page.read_text(encoding="utf-8"), "lxml").select_one(".colindextitle")
    if not node:
        return None, None
    raw = re.sub(r"\s+", " ", node.get_text()).strip()
    arabic = " ".join(w for w in raw.split() if re.search(r"[؀-ۿ]", w))
    english = " ".join(w for w in raw.split() if not re.search(r"[؀-ۿ]", w))
    return english.strip() or None, arabic.strip() or None


def main(cache_dir: str) -> int:
    cache = Path(cache_dir)
    existing = json.loads((PRIMARY / "hadith_books.json").read_text(encoding="utf-8"))
    by_id = {b["id"]: b for b in existing.get("books", [])}

    books = []
    for pack in sorted(PRIMARY.glob("hadith_*.json")):
        slug = pack.stem[len("hadith_"):]
        if slug in ("books", "narrators"):
            continue
        records = json.loads(pack.read_text(encoding="utf-8"))
        if not records:
            print(f"  skip {slug}: pack is empty")
            continue

        prior = by_id.get(slug, {})
        # A previous rebuild may have stored the slug itself as a title when no
        # better source existed; treat that as absent so a real title can win.
        if prior.get("titleEnglish") == slug:
            prior = {**prior, "titleEnglish": None}
        if prior.get("titleUrdu") == slug:
            prior = {**prior, "titleUrdu": None}
        english, arabic = landing_titles(cache, slug)
        sections = prior.get("sections")
        # A section per distinct sourceBook the records actually carry.
        numbers = sorted({r["sourceBook"] for r in records if r.get("sourceBook") is not None})

        books.append({
            "id": slug,
            "titleEnglish": prior.get("titleEnglish") or english or TITLE_EN.get(slug) or slug,
            "titleUrdu": TITLE_UR.get(slug) or prior.get("titleUrdu") or arabic or slug,
            # Counted from the packaged records, never copied from upstream.
            "hadithCount": len(records),
            "hasArabic": any(r.get("text_ar") or r.get("arabicSegments") for r in records),
            "hasEnglish": any(r.get("text_en") for r in records),
            "hasUrdu": any(r.get("urduText") or r.get("text_ur") for r in records),
            "sectionCount": len(sections) if sections else len(numbers),
            "sections": sections,
        })

    payload = dict(existing)
    payload["books"] = sorted(books, key=lambda b: -b["hadithCount"])
    text = json.dumps(payload, ensure_ascii=False, indent=1) + "\n"
    for seed in SEED_DIRS:
        (seed / "hadith_books.json").write_text(text, encoding="utf-8", newline="\n")

    print(f"{'collection':16}{'count':>8}  ar/en/ur   title")
    for b in payload["books"]:
        flags = f"{int(b['hasArabic'])}/{int(b['hasEnglish'])}/{int(b['hasUrdu'])}"
        print(f"  {b['id']:14}{b['hadithCount']:8}  {flags:9} {b['titleEnglish'][:30]}")
    print(f"\n{len(payload['books'])} collections, "
          f"{sum(b['hadithCount'] for b in payload['books'])} narrations, "
          f"written to {len(SEED_DIRS)} seed dirs")
    print("\nHADITH_BOOKS = " + json.dumps([b["id"] for b in payload["books"]]))
    return 0


if __name__ == "__main__":
    import sys
    raise SystemExit(main(sys.argv[1] if len(sys.argv) > 1 else ".hadith_cache"))
