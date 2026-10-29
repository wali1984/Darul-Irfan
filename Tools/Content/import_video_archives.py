"""Bring the official video archives into media_items.json.

Two archives on the official site were never ingested, which left the Video
Lectures tile with only the 23 TV programmes and AlMurshid Q&A empty:

* /video-lectures (Video Lectures, ویڈیو بیانات): the site's lectures that have
  a video. They are the same /lecture/<id> pages as the audio archive, so
  - a lecture the app already has as audio gets the video's youtubeId (the row
    then offers "Play video" next to the audio; no second copy of the lecture);
  - a lecture the app does not have (its only recording on the site is WMA,
    which iPhone cannot play) is added as a YouTube item under videoLectures;
  - lectures that only exist as a video are listed under Video Lectures rather
    than Audio Lectures.
* /almurshid-programs (AlMurshid Q&A TV Program): each episode is added as a
  YouTube item under alMurshidQA. Episodes whose page has no video are skipped.

Every video is matched to its item by the item's id on the listing page, and
YouTube's oEmbed must answer 200 (public and embeddable) before a video id is
written. The pairs were also checked against each video's own title (its date
or episode number) on 2026-10-28; the ones in WRONG_VIDEO name a different
bayan or episode and are left out. New rows follow the ingest conventions
(Tools/ContentIngest/schema.py): id from the page address, sorted keys,
midnight-UTC dates and a checksum.

    python Tools/Content/import_video_archives.py [--cache DIR] [--dry-run] [--preview new.json]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "ContentIngest"))
import schema  # noqa: E402

import official_site as site  # noqa: E402
from import_missing_lectures import clean_title  # noqa: E402
from seed_io import dump, load  # noqa: E402

LECTURE_ID = re.compile(r"/lectures?/(\d+)/")

# Page path -> why the video shown beside that item is not its recording.
WRONG_VIDEO = {
    "lecture/2223": "the video is 'Ramzan ul Mubarak ko Rukhsat na karain', lecture 2224 of the day before",
    "almurshid-program/433": "the video is 'Almurshed.Tv Ep 182', episode 182 (item 432); this item is episode 181",
    "lecture/1102": "the video is dated 29-05-2020; this Jumma-tul-Wida bayan is of 22-05-2020",
    "lecture/1798": "the video is the Rehmat-ul-lil-Aalameen Conference, Rawalpindi Bar, 04-11-2021, not 'Firaun se Nijat'",
    "lecture/1985": "the video is 'Sohbat-e-Sheikh, Sunnat-e-Aitkaf', not 'Be-chaini ki Wajah'",
    "lecture/1176": "the video is the concluding sermon of the Annual Training Program 2020, not titled 'Ism-e-Azam'",
    "lecture/724": "the video is 'Tarz-e-Hayat (Jumma Beyan)', not 'Bandgi'",
}
MODEL_ORDER = ["id", "title", "language", "speaker", "date", "durationSeconds", "mediaType",
               "sourceUrl", "streamUrl", "downloadUrl", "youtubeId", "year", "month", "category",
               "checksum", "transcriptUrl", "rightsStatus"]


def crawl(section: str, cache: Path | None) -> list[dict]:
    """All items of a paginated listing, following page/N until a page is empty."""
    items: dict[str, dict] = {}
    page = 1
    while True:
        url = f"{site.SITE}/{section}/page/{page}"
        status, body, _ = site.get(url, cache)
        if status != 200:
            raise SystemExit(f"{url} answered {status}")
        found = site.listing_items(body.decode("utf-8", "replace"))
        if not found or all(item["itemID"] in items for item in found):
            break
        for item in found:
            items.setdefault(item["itemID"], item)
        page += 1
    return list(items.values())


def new_item(entry: dict, category: str) -> dict:
    day = entry["date"]
    item = {
        "id": schema.slug_from_url(entry["href"]),
        "title": clean_title(entry["itemID"], entry["title"]) if category != "alMurshidQA"
        else site.clean_text(entry["title"]),
        "language": "ur",
        "speaker": entry["speaker"],
        "date": schema.iso_date_only(day.year, day.month, day.day),
        "mediaType": "youtube",
        "sourceUrl": entry["href"],
        "youtubeId": entry["youtube"][0],
        "year": day.year,
        "month": day.month,
        "category": category,
        "rightsStatus": "permissionConfirmed",
    }
    if item["speaker"] is None:
        del item["speaker"]
    item = {key: item[key] for key in sorted(item)}
    item["checksum"] = schema.checksum_for(item)
    return {key: item[key] for key in sorted(item)}


def reorder(item: dict, was_sorted: bool) -> dict:
    if was_sorted:
        return {key: item[key] for key in sorted(item)}
    rank = {key: index for index, key in enumerate(MODEL_ORDER)}
    return {key: item[key] for key in sorted(item, key=lambda k: rank.get(k, len(rank)))}


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--cache", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--preview", type=Path, help="write the rows added/changed here, for review")
    args = parser.parse_args()

    items, layout = load("media_items.json")
    sorted_rows = {item["id"] for item in items if list(item) == sorted(item)}
    by_lecture = {m.group(1): item for item in items if (m := LECTURE_ID.search(item["sourceUrl"]))}
    ids = {item["id"] for item in items}

    videos = crawl("video-lectures", args.cache)
    programs = crawl("almurshid-programs", args.cache)
    print(f"site: {len(videos)} video lectures, {len(programs)} AlMurshid Q&A programmes")

    wanted = sorted({entry["youtube"][0] for entry in videos + programs if len(entry["youtube"]) == 1})
    playable = site.youtube_playable_many(wanted)

    attach, add_videos, add_programs, skipped, mismatched = [], [], [], [], []
    def wrong_video(entry: dict) -> str | None:
        path = entry["href"].split("naqshbandiaowaisiah.org/", 1)[-1]
        return next((why for key, why in WRONG_VIDEO.items() if path.startswith(key + "/")), None)

    for entry in videos + programs:
        if wrong_video(entry):
            skipped.append((entry["href"], wrong_video(entry)))
    videos = [entry for entry in videos if not wrong_video(entry)]
    programs = [entry for entry in programs if not wrong_video(entry)]

    for entry in videos:
        if len(entry["youtube"]) != 1 or entry["date"] is None:
            skipped.append((entry["href"], f"{len(entry['youtube'])} videos, date {entry['date']}"))
            continue
        video = entry["youtube"][0]
        if not playable[video]["ok"]:
            skipped.append((entry["href"], f"YouTube {video} answered {playable[video]['status']}"))
            continue
        existing = by_lecture.get(entry["itemID"])
        if existing is None:
            add_videos.append(new_item(entry, "videoLectures"))
        elif existing.get("youtubeId") is None:
            attach.append((existing, video))
        elif existing["youtubeId"] != video:
            mismatched.append((existing["id"], existing["youtubeId"], video))
    for entry in programs:
        if len(entry["youtube"]) != 1 or entry["date"] is None:
            skipped.append((entry["href"], f"{len(entry['youtube'])} videos on the page"))
            continue
        if not playable[entry["youtube"][0]]["ok"]:
            skipped.append((entry["href"], f"YouTube answered {playable[entry['youtube'][0]]['status']}"))
            continue
        add_programs.append(new_item(entry, "alMurshidQA"))

    fresh = [item for item in add_videos + add_programs if item["id"] not in ids]
    clashes = len(add_videos) + len(add_programs) - len(fresh)
    changed = []
    for item, video in attach:
        item["youtubeId"] = video
        changed.append(item)
    # A lecture whose only playable form is a video belongs under Video Lectures.
    moved = [item for item in items if item["category"] == "audioLectures" and item["mediaType"] == "youtube"]
    for item in moved:
        item["category"] = "videoLectures"
        changed.append(item)
    for item in changed:
        if "checksum" in item:
            item["checksum"] = schema.checksum_for(item)

    print(f"videos attached to {len(attach)} audio lectures; {len(moved)} video-only lectures moved to "
          f"Video Lectures; adding {sum(i['category'] == 'videoLectures' for i in fresh)} video lectures and "
          f"{sum(i['category'] == 'alMurshidQA' for i in fresh)} AlMurshid Q&A programmes; "
          f"skipped {len(skipped)}; id clashes {clashes}")
    for href, why in skipped:
        print(f"  skipped {href}: {why}")
    for row in mismatched:
        print(f"  different video already on {row[0]}: seed {row[1]}, site {row[2]} (left as is)")

    if args.preview:
        args.preview.write_text(json.dumps({"attached": [[i["id"], v] for i, v in attach],
                                            "moved": [i["id"] for i in moved], "added": fresh},
                                           ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    if args.dry_run:
        return 0

    changed_ids = {item["id"] for item in changed}
    for index, item in enumerate(items):
        if item["id"] in changed_ids:
            items[index] = reorder(item, item["id"] in sorted_rows)
    by_date = lambda item: (item["date"], item["id"])  # noqa: E731
    last_video = max(i for i, item in enumerate(items) if item["category"] == "videoLectures")
    items[last_video + 1:last_video + 1] = sorted((i for i in fresh if i["category"] == "videoLectures"), key=by_date)
    items.extend(sorted((i for i in fresh if i["category"] == "alMurshidQA"), key=by_date))
    dump("media_items.json", items, layout)
    print(f"media_items.json: {len(items)} items")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
