#!/usr/bin/env python3
"""Enrich the Sahih al-Bukhari pack with sunnah.com's book (kitab) structure.

Context
-------
The bundled hadith text is the public-domain (Unlicense) `fawazahmed0/hadith-api`
corpus, which mirrors sunnah.com: identical Arabic and English (Dr. M. Muhsin
Khan), sunnah.com's exact reference numbers *including* sub-numbered narrations
(402.2, 690.2, 1390.2, 1390.3, ...), and sunnah.com's in-book references. It is
already stored losslessly (textual canonical id + displayNumber; see schema v4).

What sunnah.com adds that this script folds in: the 97 **kitab** (book) division
that sunnah.com's /bukhari page presents — each with an English and an Arabic
title — so the reader can group narrations by book exactly as sunnah.com does.
The authoritative kitab list + reference ranges live in
``sunnah_bukhari_books.json`` (fetched from sunnah.com/bukhari).

This script:
  * assigns every narration to its kitab (fills ``sourceBook`` where the mirror
    left it blank — 308 records — without ever contradicting an existing value);
  * writes a ``sections`` array (number, English title, Arabic title, count
    computed from the packaged records) onto the bukhari entry of the catalogue;
  * re-writes the bukhari pack + catalogue byte-identically to all four platform
    seed directories.

It does NOT touch the hadith text, numbers, or the other six collections.

sunnah.com has **no Urdu translation for Sahih al-Bukhari** (verified: the site's
Urdu toggle loads nothing for this collection). The Urdu shipped here is the
hadith-api public-domain Urdu, kept as an honest bonus and marked missing on the
564 narrations the source itself lacks.
"""
from __future__ import annotations
import json, sys, hashlib
from pathlib import Path

IOS_ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = IOS_ROOT.parent
SEED_DIRS = [
    IOS_ROOT / "DarulIrfanApp/Resources/SeedData",
    REPO_ROOT / "DarulIrfanAndroid/app/src/main/assets/seed",
    REPO_ROOT / "DarulIrfanHarmony/entry/src/main/resources/rawfile/seed",
    REPO_ROOT / "DarulIrfanWeb/content",
]
INDEX = json.loads((IOS_ROOT / "Tools/Hadith/sunnah_bukhari_books.json").read_text(encoding="utf-8"))["books"]

# Canonical record key order (matches Tools/Hadith/build_hadith_packs.py).
KEY_ORDER = ["canonicalID", "bookID", "displayNumber", "numberMajor",
             "sourceSequence", "text_ar", "text_en", "text_ur",
             "numberMinor", "sourceBook", "sourceHadith", "grades"]


def kitab_for(rec: dict) -> int:
    """Authoritative kitab for a narration.

    1. Its in-book reference (``sourceBook``) when the mirror carries one — this
       agreed with the sunnah.com index for all 7,577 records that have it.
    2. Otherwise the sunnah.com reference-range the number falls inside.
    3. Otherwise (the six inter-book boundary numbers such as 1066/2516/6860,
       which sunnah.com lists just outside a range) the preceding book — which
       is where their in-book reference places them (e.g. 1066 = Book 16, H24).
    """
    existing = rec.get("sourceBook")
    if existing is not None:
        return existing
    major = rec["numberMajor"]
    for b in INDEX:
        if b["start"] <= major <= b["end"]:
            return b["no"]
    preceding = [b for b in INDEX if b["end"] < major]
    return preceding[-1]["no"] if preceding else INDEX[0]["no"]


def ordered(rec: dict) -> dict:
    return {k: rec[k] for k in KEY_ORDER if k in rec}


def write_records(path: Path, records: list[dict]) -> None:
    body = ",\n ".join(json.dumps(r, ensure_ascii=False) for r in records)
    path.write_text(f"[\n {body}\n]\n", encoding="utf-8", newline="\n")


def main() -> int:
    dry = "--write" not in sys.argv
    src = SEED_DIRS[0] / "hadith_bukhari.json"
    records = json.loads(src.read_text(encoding="utf-8"))

    filled = 0
    for rec in records:
        k = kitab_for(rec)
        if rec.get("sourceBook") is None:
            filled += 1
        rec["sourceBook"] = k
    records = [ordered(r) for r in records]

    # Section (kitab) counts computed from the packaged records — never copied.
    counts = {}
    for r in records:
        counts[r["sourceBook"]] = counts.get(r["sourceBook"], 0) + 1
    sections = [{"number": b["no"], "titleEnglish": b["en"],
                 "titleArabic": b["ar"], "hadithCount": counts.get(b["no"], 0)}
                for b in INDEX]

    assert sum(counts.values()) == len(records)
    assert len(sections) == 97
    assert all(s["hadithCount"] > 0 for s in sections), "a kitab has zero hadith"

    # Update the catalogue: fold sections onto bukhari only.
    #
    # The shipped catalogue must NOT name the structural reference site — nothing
    # in the app bundle attributes a third-party site to the user. The text
    # license (public-domain hadith-api) is the honest, shippable provenance; the
    # book division is standard kitab structure and the site provenance lives
    # only in Tools/ and Docs/, which are not bundled.
    cat_path = SEED_DIRS[0] / "hadith_books.json"
    catalog = json.loads(cat_path.read_text(encoding="utf-8"))
    catalog["source"] = "fawazahmed0/hadith-api"
    catalog.pop("structureSource", None)
    for book in catalog["books"]:
        if book["id"] == "bukhari":
            book["hadithCount"] = len(records)
            book["sectionCount"] = len(sections)
            book["hasUrdu"] = any(r.get("text_ur") for r in records)
            book["sections"] = sections
    catalog_text = json.dumps(catalog, ensure_ascii=False, indent=1) + "\n"

    print(f"records: {len(records)}  sourceBook filled: {filled}")
    print(f"sections: {len(sections)}  sum(section counts): {sum(counts.values())}")
    print(f"section count range: {min(counts.values())}..{max(counts.values())}")

    if dry:
        # hash of what WOULD be written, to sanity-check determinism
        import io
        buf = io.StringIO()
        body = ",\n ".join(json.dumps(r, ensure_ascii=False) for r in records)
        payload = f"[\n {body}\n]\n"
        print("pack sha256:", hashlib.sha256(payload.encode()).hexdigest()[:16])
        print("catalog sha256:", hashlib.sha256(catalog_text.encode()).hexdigest()[:16])
        print("\n--dry run (pass --write to update all four platform seeds)")
        return 0

    written = 0
    for d in SEED_DIRS:
        if not d.exists():
            print(f"! skip missing {d}")
            continue
        write_records(d / "hadith_bukhari.json", records)
        (d / "hadith_books.json").write_text(catalog_text, encoding="utf-8", newline="\n")
        written += 1
        print(f"wrote -> {d}")
    if written < len(SEED_DIRS):
        print(f"! only {written}/{len(SEED_DIRS)} seeds updated")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
