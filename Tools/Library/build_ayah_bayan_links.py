"""Build the ayah-to-bayan index from the media catalogue.

Part of the silsila's lecture catalogue is verse-addressed: a 2017 series works
through the short surahs an ayah-group at a time, with titles like
"Surah Al-Balad Ayat 8 to 13". Those lectures can be attached to the exact
verses they expound, so a reader on 90:9 can open the sheikh's bayan on it.

The surah names are mapped BY HAND below. Regex over transliterations was tried
and is not safe here: the catalogue writes "Al-Shams" where the Quran data says
"Ash-Shams", "Ash-Shrah" for Ash-Sharh, and "Al fajr" without the hyphen, while
"Behr e Hayat" contains the letters "ayat" and is not about a verse at all.
Attaching a lecture to the wrong ayah of the Quran is not a cosmetic bug, so
nothing here is guessed.

Every range is checked against the surah's real ayah count, so a mis-keyed
number fails the build rather than pointing a reader at a verse that does not
exist.

Writes `ayah_bayan_links.json` to the four platform seeds. Read-only otherwise.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1].parent

SEED_DIRS = [
    ROOT / "DarulIrfanApp" / "Resources" / "SeedData",
    ROOT.parent / "DarulIrfanAndroid" / "app" / "src" / "main" / "assets" / "seed",
    ROOT.parent / "DarulIrfanHarmony" / "entry" / "src" / "main" / "resources" / "rawfile" / "seed",
    ROOT.parent / "DarulIrfanWeb" / "content",
]

# Exactly the spellings the catalogue uses, lowercased with non-letters removed.
# Add a row when a new verse-addressed lecture appears; never widen this into a
# fuzzy match.
SURAH_BY_NAME = {
    "almaida": 5,       # Al-Ma'idah
    "alala": 87,        # Al-A'la, whose apostrophe drops out of the key
    "alghashiyah": 88,
    "alfajr": 89,
    "albalad": 90,
    "alshams": 91,      # the data calls it Ash-Shams
    "allayl": 92,
    "adduhaa": 93,
    "ashshrah": 94,     # Ash-Sharh, spelled without the first 'a' in the catalogue
    "attin": 95,
    "alalaq": 96,
    "alqadr": 97,
    "albayyinah": 98,
    "azzalzalah": 99,
    "aladiyat": 100,
    "alqariah": 101,
    "attakathur": 102,
}

# "Ayat 8 to end" means the surah's last ayah.
TITLE = re.compile(
    r"surah\s+(?P<name>[A-Za-z'’\s\-]{2,24}?)\s+ayat\s+(?P<start>\d{1,3})"
    r"(?:\s*(?:to|-|–)\s*(?P<end>\d{1,3}|end))?",
    re.IGNORECASE,
)


def key(name: str) -> str:
    return re.sub(r"[^a-z]", "", name.lower())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write the four seeds")
    args = parser.parse_args()

    seed = SEED_DIRS[0]
    media = json.loads((seed / "media_items.json").read_text(encoding="utf-8"))
    surahs = json.loads((seed / "quran_surahs.json").read_text(encoding="utf-8"))
    ayah_count = {surah["id"]: surah["ayahCount"] for surah in surahs}

    links: list[dict] = []
    skipped: list[str] = []
    problems: list[str] = []

    for item in media:
        title = (item.get("title") or "").strip()
        match = TITLE.search(title)
        if not match:
            continue
        surah = SURAH_BY_NAME.get(key(match.group("name")))
        if surah is None:
            # Named a verse but not a surah we recognise: report it rather than
            # dropping it silently, so a new series gets a mapping row.
            skipped.append(title)
            continue
        start = int(match.group("start"))
        raw_end = match.group("end")
        if raw_end is None:
            end = start
        elif raw_end.lower() == "end":
            end = ayah_count[surah]
        else:
            end = int(raw_end)
        if start > end:
            start, end = end, start
        total = ayah_count[surah]
        if not (1 <= start <= total and 1 <= end <= total):
            problems.append(f"{title}: {surah}:{start}-{end} outside 1-{total}")
            continue
        links.append({
            "surah": surah,
            "ayahStart": start,
            "ayahEnd": end,
            "mediaID": item["id"],
            "title": title,
        })

    links.sort(key=lambda link: (link["surah"], link["ayahStart"], link["ayahEnd"]))

    if problems:
        print("problems:")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    covered = sorted({link["surah"] for link in links})
    print(f"verse-addressed bayans linked : {len(links)}")
    print(f"surahs covered                : {len(covered)} -> {covered}")
    if skipped:
        print(f"titles naming ayat but no mapped surah ({len(skipped)}):")
        for title in skipped:
            print(f"  ? {title}")
    print()
    for link in links[:8]:
        print(f"   {link['surah']}:{link['ayahStart']}-{link['ayahEnd']:<3} {link['title'][:48]}")

    payload = json.dumps({
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "links": links,
    }, ensure_ascii=False, separators=(",", ":"))

    if not args.write:
        print("\nreport only; pass --write to update the seeds")
        return 0

    for directory in SEED_DIRS:
        if not directory.exists():
            print(f"  skipped (absent): {directory}")
            continue
        (directory / "ayah_bayan_links.json").write_text(payload, encoding="utf-8", newline="")
        print(f"  wrote {directory}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
