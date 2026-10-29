"""Corrections to library_items.json from the library audit of 2026-10-28.

The values are in library_fixes.json beside this script. Each was checked
before it was written down:

* remove - website menu and placeholder pages that were ingested as articles
  (they list titles and send the reader to the website), and works listed
  twice. The app drops rows the seed no longer carries (SeedHousekeeping), and
  moves a favourite to the twin that offers the same PDF.
* authors - read from each book's cover or title page (book_pages text, and
  the cover images where the text layer has no cover).
* titleUrdu - the title as printed on the cover.
* titles - English titles cleaned of file-name residue (casing, hyphens, part
  numbers, the cover's subtitle); re-spellings proposed by the audit are left
  to the owner. Press-release titles lose stray diacritics and broken words.
* languages - Islah-e-Qalb is the Arabic translation, Dil Darwaza is Punjabi.
* category - the booklets, Sufi poetry and training courses the official site
  files under those headings, which were all shown under Books.
* downloadUrls - the official PDF of each book that had text pages but no PDF,
  and the two Al-Murshid issues whose files exist under other names. Every URL
  answered 206 with a PDF on 2026-10-28.
* excerpts / textReplacements - no text tells the reader to go to the website;
  the Shajra's year of passing of Hazrat Ameer Muhammad Akram Awan (RA), who
  passed away on 7 December 2017 (Rabi-ul-Awwal 1439), not 1438.
* mediaUrls - the official illustrations of the Method of Zikr.
* addDocuments - the two "Conditions for Muraqbat" PDFs from the official
  Important Documents page.

It also applies three rules: Al-Murshid issues are titled "Al-Murshid — <month>
<year>" (a bare month is ambiguous in search and favourites) with the Urdu
title in titleUrdu; the website's SEO keyword strings are removed from
excerpts; soft hyphens (U+00AD) are removed from text, where they break search.

Changed rows get a fresh checksum (Tools/ContentIngest/schema.py rule).
Re-running is safe.

    python Tools/Content/fix_library_items.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "ContentIngest"))
import schema  # noqa: E402

from seed_io import SEED, dump, load  # noqa: E402

# ContentItem property order (ContentModels.swift); a new key goes in its place.
MODEL_ORDER = ["id", "sourceUrl", "type", "title", "titleUrdu", "language", "author", "category",
               "bodyHtml", "bodyPlainText", "excerpt", "publishedAt", "updatedAt", "mediaUrls",
               "downloadUrls", "checksum", "rightsStatus"]
SEO_EXCERPT = re.compile(r" - Silsila Naqshbandia Owaisiah, Hazrat Ameer Muhammad Akram Awan \(RA\), Tasawwuf, Sufism\b")
MONTHS_UR = {
    "january": "جنوری", "jan": "جنوری", "february": "فروری", "march": "مارچ", "april": "اپریل",
    "may": "مئی", "june": "جون", "july": "جولائی", "august": "اگست", "september": "ستمبر",
    "sept": "ستمبر", "october": "اکتوبر", "november": "نومبر", "nov": "نومبر", "december": "دسمبر",
}
ALMURSHID_UR = "ماہنامہ المرشد"


def set_field(item: dict, key: str, value) -> bool:
    """Set a key, inserting a new one where the row's own key order puts it."""
    if item.get(key) == value and key in item:
        return False
    if key in item or list(item) == sorted(item):
        item[key] = value
    else:
        rank = {name: index for index, name in enumerate(MODEL_ORDER)}
        keys = list(item)
        position = next((i for i, existing in enumerate(keys)
                         if rank.get(existing, len(rank)) > rank.get(key, len(rank))), len(keys))
        rebuilt = dict(zip(keys[:position], (item[k] for k in keys[:position])))
        rebuilt[key] = value
        rebuilt.update((k, item[k]) for k in keys[position:])
        item.clear()
        item.update(rebuilt)
    return True


def drop_field(item: dict, key: str) -> bool:
    return item.pop(key, None) is not None


def almurshid_titles(title: str) -> tuple[str, str]:
    """('Al-Murshid — April 1981', 'ماہنامہ المرشد — اپریل 1981') from 'April 1981'."""
    issue = re.sub(r"^Al-Murshid( Magazine)?\s*[:—-]\s*", "", title).strip()
    words = re.findall(r"[A-Za-z]+|\d{4}|-", issue)
    urdu = " ".join(MONTHS_UR.get(word.lower(), word) for word in words)
    return f"Al-Murshid — {issue}", f"{ALMURSHID_UR} — {urdu}"


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    fixes = json.loads((HERE / "library_fixes.json").read_text(encoding="utf-8"))
    items, layout = load("library_items.json")
    was_sorted = {item["id"] for item in items if list(item) == sorted(item)}
    changed: set[str] = set()

    # Never leave book pages or other seeds pointing at a removed item.
    removing = set(fixes["remove"])
    pages = (SEED / "book_pages.json").read_text(encoding="utf-8")
    referenced = sorted(i for i in removing if f'"bookID":"{i}"' in pages or f'"bookID": "{i}"' in pages)
    if referenced:
        raise SystemExit(f"book_pages.json still has pages for {referenced}")
    before = len(items)
    items = [item for item in items if item["id"] not in removing]
    removed = before - len(items)
    by_id = {item["id"]: item for item in items}

    def target(item_id: str) -> dict:
        if item_id not in by_id:
            raise SystemExit(f"library_items.json has no item {item_id}")
        return by_id[item_id]

    counts: dict[str, int] = {}

    def count(name: str, did: bool, item_id: str) -> None:
        if did:
            counts[name] = counts.get(name, 0) + 1
            changed.add(item_id)

    for item_id, author in fixes["authors"].items():
        count("author", set_field(target(item_id), "author", author), item_id)
    for item_id, value in fixes["titleUrdu"].items():
        count("titleUrdu", set_field(target(item_id), "titleUrdu", value), item_id)
    for item_id, value in fixes["titles"].items():
        count("title", set_field(target(item_id), "title", value), item_id)
    for item_id, value in fixes["languages"].items():
        count("language", set_field(target(item_id), "language", value), item_id)
    for item_id, (category, content_type) in fixes["category"].items():
        item = target(item_id)
        did = set_field(item, "category", category)
        if content_type:
            did = set_field(item, "type", content_type) or did
        count("category", did, item_id)
    for item_id, url in fixes["downloadUrls"].items():
        count("downloadUrls", set_field(target(item_id), "downloadUrls", [url]), item_id)
    for item_id, value in fixes["excerpts"].items():
        count("excerpt", set_field(target(item_id), "excerpt", value), item_id)
    for item_id, urls in fixes["mediaUrls"].items():
        count("mediaUrls", set_field(target(item_id), "mediaUrls", urls), item_id)
    for change in fixes["textReplacements"]:
        item = target(change["id"])
        did = False
        for field in ("bodyHtml", "bodyPlainText"):
            if item.get(field) and change["old"] in item[field]:
                item[field] = item[field].replace(change["old"], change["new"])
                did = True
        count("text", did, change["id"])

    # The Tarajum's Urdu title must name the work correctly on every volume.
    old_name, new_name = fixes["tarajumTitleUrdu"]["old"], fixes["tarajumTitleUrdu"]["new"]
    for item in items:
        if item["category"] == "quranTranslation" and item.get("titleUrdu") == old_name:
            count("titleUrdu", set_field(item, "titleUrdu", new_name), item["id"])

    for item in items:
        if item["category"] == "alMurshidMagazine":
            title, urdu = almurshid_titles(item["title"])
            did = set_field(item, "title", title)
            did = set_field(item, "titleUrdu", urdu) or did
            count("alMurshid", did, item["id"])
        if item.get("excerpt") and SEO_EXCERPT.search(item["excerpt"]):
            count("seoExcerpt", drop_field(item, "excerpt"), item["id"])
        for field in ("title", "bodyHtml", "bodyPlainText", "excerpt"):
            if item.get(field) and ("­" in item[field] or "&shy;" in item[field]):
                item[field] = item[field].replace("­", "").replace("&shy;", "")
                count("softHyphen", True, item["id"])

    known = {item["id"] for item in items}
    for doc in fixes["addDocuments"]:
        if doc["id"] in known:
            continue
        item = {"id": doc["id"], "sourceUrl": fixes["documentsSourceUrl"], "type": "document",
                "title": doc["title"], "language": doc["language"], "category": "importantDocuments",
                "mediaUrls": [], "downloadUrls": [doc["url"]], "rightsStatus": "permissionConfirmed"}
        item["checksum"] = schema.checksum_for(item)
        item = {key: item[key] for key in MODEL_ORDER if key in item}
        items.append(item)
        counts["added"] = counts.get("added", 0) + 1

    for index, item in enumerate(items):
        if item["id"] in changed:
            if "checksum" in item:
                item["checksum"] = schema.checksum_for(item)
            if item["id"] in was_sorted:
                items[index] = {key: item[key] for key in sorted(item)}

    dump("library_items.json", items, layout)
    print(f"library_items.json: {len(items)} items; removed {removed}; changed {len(changed)} - " +
          ", ".join(f"{key} {value}" for key, value in sorted(counts.items())))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
