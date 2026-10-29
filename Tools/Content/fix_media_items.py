"""Corrections to existing lectures in media_items.json (audit of 2026-10-28).

The corrections are listed in media_fixes.json beside this script, and each
was checked against the official site the same day:

* youtubeOnly - five lectures played another lecture's recording. On the site
  they are YouTube-only rows; the old ingest found no audio inside the row,
  took the first MP3 and date of the month instead, and so gave them a
  neighbour's recording and date. They become YouTube items with their own
  date (the video ids are the ones embedded on each lecture's page).
* titles - typing slips copied from the site: an ayah number typed at the
  wrong end (so the Urdu title reads "ayat 9 to 8"), Arabic presentation-form
  letters, misspelt surah names (نوع for نوح) and words (بیعت اللہ for
  بیت اللہ). Each replacement is confirmed by the page's own address, its file
  name or the neighbouring lectures of the series.
* speakers - one speaker field held the lecture title.

It also makes three corrections that need no list:

* 26 speaker lines lacked the "By " every other lecture has.
* The 23 TV programmes had no year/month, so Browse by Year never showed them.
* Media addresses with raw spaces or Urdu letters are stored percent-encoded:
  Android cannot open them otherwise.

Every changed row gets a fresh checksum (the Tools/ContentIngest/schema.py
rule). Re-running is safe: a title is replaced only while it still has the old
value.

    python Tools/Content/fix_media_items.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "ContentIngest"))
import schema  # noqa: E402  (checksum rule shared with the ingest)

from official_site import encode_url  # noqa: E402
from seed_io import dump, load  # noqa: E402

# MediaItem property order (MediaModels.swift), with the ingest's checksum where
# the older rows keep it. Rows written with sorted keys stay sorted.
MODEL_ORDER = ["id", "title", "language", "speaker", "date", "durationSeconds", "mediaType",
               "sourceUrl", "streamUrl", "downloadUrl", "youtubeId", "year", "month", "category",
               "checksum", "transcriptUrl", "rightsStatus"]


def ordered(item: dict, was_sorted: bool) -> dict:
    """The item with its keys in the order its row already uses."""
    if was_sorted:
        return {key: item[key] for key in sorted(item)}
    rank = {key: index for index, key in enumerate(MODEL_ORDER)}
    return {key: item[key] for key in sorted(item, key=lambda k: rank.get(k, len(rank)))}


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    fixes = json.loads((HERE / "media_fixes.json").read_text(encoding="utf-8"))
    items, layout = load("media_items.json")
    sorted_rows = {item["id"] for item in items if list(item) == sorted(item)}
    by_id = {item["id"]: item for item in items}
    for wanted in (*fixes["youtubeOnly"], *fixes["titles"], *fixes["speakers"]):
        if wanted not in by_id:
            raise SystemExit(f"media_items.json has no item {wanted}")

    counts = dict.fromkeys(("youtube", "title", "speaker", "by", "yearMonth", "url"), 0)
    changed: set[str] = set()

    for item_id, fix in fixes["youtubeOnly"].items():
        item = by_id[item_id]
        before = dict(item)
        day = fix["date"]
        item["mediaType"] = "youtube"
        item["youtubeId"] = fix["youtubeId"]
        item["date"] = f"{day}T00:00:00Z"
        item["year"], item["month"] = int(day[:4]), int(day[5:7])
        item.pop("streamUrl", None)
        item.pop("downloadUrl", None)
        if item != before:
            counts["youtube"] += 1
            changed.add(item_id)

    for item_id, fix in fixes["titles"].items():
        item = by_id[item_id]
        if item["title"] == fix["old"]:
            item["title"] = fix["new"]
            counts["title"] += 1
            changed.add(item_id)
        elif item["title"] != fix["new"]:
            raise SystemExit(f"{item_id}: title is neither the old nor the corrected value: {item['title']!r}")

    for item_id, speaker in fixes["speakers"].items():
        if by_id[item_id].get("speaker") != speaker:
            by_id[item_id]["speaker"] = speaker
            counts["speaker"] += 1
            changed.add(item_id)

    for item in items:
        speaker = item.get("speaker")
        if speaker and not speaker.startswith("By "):
            item["speaker"] = "By " + speaker
            counts["by"] += 1
            changed.add(item["id"])
        if item.get("date") and (item.get("year") is None or item.get("month") is None):
            item["year"], item["month"] = int(item["date"][:4]), int(item["date"][5:7])
            counts["yearMonth"] += 1
            changed.add(item["id"])
        for field in ("streamUrl", "downloadUrl"):
            if item.get(field) and encode_url(item[field]) != item[field]:
                item[field] = encode_url(item[field])
                counts["url"] += 1
                changed.add(item["id"])

    for index, item in enumerate(items):
        if item["id"] in changed:
            if "checksum" in item:
                item["checksum"] = schema.checksum_for(item)
            items[index] = ordered(item, item["id"] in sorted_rows)

    dump("media_items.json", items, layout)
    print(f"media_items.json: {len(changed)} items changed - " +
          ", ".join(f"{key} {value}" for key, value in counts.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
