"""Corrections to the smaller companion seeds (audit of 2026-10-28).

Values are in companion_fixes.json beside this script.

* names_of_allah.json - seven Divine Names had wrong or missing vowels (a
  kasra on the wrong letter in المقيت, the accusative الضَّارَّ for الضَّارُّ, no
  shadda in التَّوَّابُ, a missing fatha, ذو joined to الجلال). The Arabic is
  replaced with the vowelling of the list in Jami' at-Tirmidhi 3507, as bundled
  in the app (canonical id tirmidhi|3507|3540). Misspelt transliterations and
  meanings are corrected (Mughi, Wudood, Maginificent, Repentence ...).
* quran_surahs.json - misspelt Urdu meanings (حود for ہود, رات کا صفر "the
  night's zero" for رات کا سفر, ...), and بادشاہ "king" for Al-Mulk, "the
  Sovereignty" (بادشاہی).
* events.json - the 31 seminar-* rows carry the exact date shown on each
  seminar's own page (checked for all 31), so they are not approximate; the
  three standing programmes no longer promise dates that "appear automatically".
* islamic_days.json - Shab-e-Mi'raj, Shab-e-Barat and the 27th night of
  Ramadan are nights: they begin at sunset the evening before the Hijri day the
  date is computed for. The notes say so, and observedOnEve marks the rows for
  the app (an unknown key, so older builds decode the file unchanged).
* zikr_sessions.json - the Tahajjud note no longer says the time "will be
  confirmed": the app computes it from Fajr at Dar-ul-Irfan.
* quran_editions.json - the Asrar-at-Tanzil source page is .../asrar-at-tanzil.html
  (the address without .html is the site's not-found page).
* aqwal_e_sheikh.json - every saying comes from an article that opens
  "Translated Speech of His Eminence Ameer Muhammad Akram Awan", so the card
  names him rather than only the Silsila. Which sayings to keep is the owner's
  choice and is not touched here.

Changed rows that carry a checksum get a fresh one. Re-running is safe.

    python Tools/Content/fix_companion_seeds.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "ContentIngest"))
import schema  # noqa: E402

from seed_io import dump, load  # noqa: E402


def replace(record: dict, field: str, old: str, new: str, where: str) -> bool:
    """Replace a value only while it still has the value the fix was made for."""
    if record.get(field) == new:
        return False
    if record.get(field) != old:
        raise SystemExit(f"{where}: {field} is {record.get(field)!r}, expected {old!r}")
    record[field] = new
    return True


def names(fixes: dict) -> int:
    rows, layout = load("names_of_allah.json")
    by_id = {str(row["id"]): row for row in rows}
    changed = 0
    for key, value in fixes["arabic"].items():
        changed += replace(by_id[key], "arabic", value["old"], value["new"], f"name {key}")
    for field in ("transliteration", "meaningEnglish"):
        for key, (old, new) in fixes[field].items():
            changed += replace(by_id[key], field, old, new, f"name {key}")
    dump("names_of_allah.json", rows, layout)
    return changed


def surahs(fixes: dict) -> int:
    rows, layout = load("quran_surahs.json")
    by_id = {str(row["id"]): row for row in rows}
    changed = sum(replace(by_id[key], "nameUrdu", old, new, f"surah {key}") for key, (old, new) in fixes.items())
    dump("quran_surahs.json", rows, layout)
    return changed


def events(fixes: dict) -> int:
    rows, layout = load("events.json")
    changed = 0
    for row in rows:
        before = dict(row)
        if row["id"].startswith(fixes["exactDatePrefix"]) and row.get("startDate"):
            row["datesAreApproximate"] = False
        if row["id"] in fixes["details"]:
            row["details"] = fixes["details"][row["id"]]
        if row != before:
            changed += 1
            if "checksum" in row:
                row["checksum"] = schema.checksum_for(row)
    dump("events.json", rows, layout)
    return changed


def islamic_days(notes: dict) -> int:
    rows, layout = load("islamic_days.json")
    changed = 0
    for row in rows:
        if row["id"] in notes:
            before = dict(row)
            row["note"] = notes[row["id"]]
            row["observedOnEve"] = True
            changed += row != before
    dump("islamic_days.json", rows, layout)
    return changed


def zikr_sessions(notes: dict) -> int:
    rows, layout = load("zikr_sessions.json")
    changed = 0
    for row in rows:
        if row["id"] in notes and row.get("availabilityNote") != notes[row["id"]]:
            row["availabilityNote"] = notes[row["id"]]
            changed += 1
    dump("zikr_sessions.json", rows, layout)
    return changed


def editions(fixes: dict) -> int:
    rows, layout = load("quran_editions.json")
    old, new = fixes["sourceUrl"]["old"], fixes["sourceUrl"]["new"]
    changed = 0
    for row in rows:
        if row.get("sourceUrl") == old:
            row["sourceUrl"] = new
            changed += 1
    dump("quran_editions.json", rows, layout)
    return changed


def aqwal(fixes: dict) -> int:
    rows, layout = load("aqwal_e_sheikh.json")
    library = {item["sourceUrl"]: item for item in load("library_items.json")[0]}
    old, new = fixes["oldPrefix"], fixes["newPrefix"]
    changed = 0
    for row in rows:
        if not row["attribution"].startswith(old):
            continue
        body = (library.get(row.get("sourceUrl")) or {}).get("bodyPlainText") or ""
        if not body.startswith(fixes["speechOpening"]):
            raise SystemExit(f"{row['id']}: the source article is not a translated speech; attribution left to the owner")
        row["attribution"] = new + row["attribution"][len(old):]
        changed += 1
    dump("aqwal_e_sheikh.json", rows, layout)
    return changed


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    fixes = json.loads((HERE / "companion_fixes.json").read_text(encoding="utf-8"))
    print(f"names_of_allah.json: {names(fixes['names_of_allah'])} values corrected")
    print(f"quran_surahs.json: {surahs(fixes['surahNameUrdu'])} Urdu meanings corrected")
    print(f"events.json: {events(fixes['events'])} events changed")
    print(f"islamic_days.json: {islamic_days(fixes['islamic_days'])} night observances marked")
    print(f"zikr_sessions.json: {zikr_sessions(fixes['zikr_sessions'])} notes changed")
    print(f"quran_editions.json: {editions(fixes['quran_editions'])} source addresses changed")
    print(f"aqwal_e_sheikh.json: {aqwal(fixes['aqwal_e_sheikh'])} attributions changed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
