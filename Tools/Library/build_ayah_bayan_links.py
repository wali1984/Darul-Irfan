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
import unicodedata
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
    "ashshrah": 94,     # Ash-Sharh, as the catalogue first spelled it
    "ashsharh": 94,     # and as the corrected titles spell it (2026-10-29)
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

# The Tafseer-ul-Quran of Hazrat Ameer Muhammad Akram Awan (RA), 2005-2016,
# is titled in Urdu: "سورۃ البقرہ آیت نمبر 1 تا 4", sometimes two surahs in one
# lecture. Exactly the names the titles use (NFC), mapped by hand - including
# the pairs a loose match would confuse: حم السجدہ (41) / السجدہ (32),
# المومن (40) / المؤمنون (23), and الدھر, the Urdu name of Al-Insan (76).
SURAH_BY_URDU_NAME = {
    "الفاتحہ": 1, "البقرہ": 2, "آل عمران": 3, "النساء": 4, "المائدہ": 5, "الانعام": 6,
    "الاعراف": 7, "الانفال": 8, "التوبہ": 9, "یونس": 10, "ھود": 11, "یوسف": 12,
    "الرعد": 13, "ابراھیم": 14, "الحجر": 15, "النحل": 16, "بنی اسرائیل": 17, "الکہف": 18,
    "مریم": 19, "طہٰ": 20, "الانبیاء": 21, "الحج": 22, "المؤمنون": 23, "النور": 24,
    "الفرقان": 25, "الشعراء": 26, "النمل": 27, "القصص": 28, "العنکبوت": 29, "الروم": 30,
    "لقمان": 31, "السجدہ": 32, "الاحزاب": 33, "سبا": 34, "فاطر": 35, "یٰس": 36,
    "الصافات": 37, "ص": 38, "الزمر": 39, "المومن": 40, "حم السجدہ": 41, "الشورٰی": 42,
    "الزخرف": 43, "الدخان": 44, "الجاثیہ": 45, "الاحقاف": 46, "محمد": 47, "الفتح": 48,
    "الحجرات": 49, "ق": 50, "الذاریات": 51, "الطور": 52, "النجم": 53, "القمر": 54,
    "الرحمٰن": 55, "الواقعہ": 56, "الحدید": 57, "المجادلہ": 58, "الحشر": 59, "الممتحنہ": 60,
    "الصف": 61, "جمعہ": 62, "المنافقون": 63, "التغابن": 64, "الطلاق": 65, "التحریم": 66,
    "الملک": 67, "القلم": 68, "الحاقہ": 69, "المعارج": 70, "نوح": 71, "الجن": 72,
    "المزمل": 73, "المدثر": 74, "القیامۃ": 75, "الدھر": 76, "المرسلات": 77, "النبا": 78,
    "النازعات": 79, "عبس": 80, "التکویر": 81, "الانفطار": 82, "المطففین": 83,
    "الانشقاق": 84, "البروج": 85, "الطارق": 86, "الاعلیٰ": 87,
}
URDU_TITLE = re.compile(
    r"سور[ۃةہه]\s+(?P<name>.+?)\s+آیت\s*نمبر\s*(?P<start>[0-9۰-۹]{1,3})"
    r"(?:\s*(?:تا|-|–)\s*(?P<end>[0-9۰-۹]{1,3}))?"
)
DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹", "0123456789")
# Lectures on one named ayah rather than a numbered range.
NAMED_AYAT = {"آیت الکرسی": (2, 255)}


def references(title: str) -> list[tuple[int | None, int, str | None, str]]:
    """(surah or None when the name is unknown, start, end or None, the name) per verse range in a title."""
    found = []
    match = TITLE.search(title)
    if match:
        found.append((SURAH_BY_NAME.get(key(match.group("name"))), int(match.group("start")),
                      match.group("end"), match.group("name")))
    text = unicodedata.normalize("NFC", title)
    for match in URDU_TITLE.finditer(text):
        name = " ".join(match.group("name").split())
        end = match.group("end")
        found.append((SURAH_BY_URDU_NAME.get(name), int(match.group("start").translate(DIGITS)),
                      end.translate(DIGITS) if end else None, name))
    if not found:
        for prefix, (surah, ayah) in NAMED_AYAT.items():
            if text.startswith(prefix):
                found.append((surah, ayah, None, prefix))
    return found


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
        for surah, start, raw_end, name in references(title):
            if surah is None:
                # Named a verse but not a surah we recognise: report it rather than
                # dropping it silently, so a new series gets a mapping row.
                skipped.append(f"{title}  [{name}]")
                continue
            if raw_end is None:
                end = start
            elif raw_end.lower() == "end":
                end = ayah_count[surah]
            else:
                end = int(raw_end)
            total = ayah_count[surah]
            # A reversed range ("آیت نمبر 9 تا 8") is a typing error in the
            # title; it is refused, not guessed at.
            if not (1 <= start <= end <= total):
                problems.append(f"{title}: {surah}:{start}-{end} outside 1-{total} or reversed")
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
