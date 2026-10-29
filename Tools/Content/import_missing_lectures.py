"""Add the official lectures that media_items.json does not have yet.

The ingest only ever read the years 2015-2017 and 2020-2026, so a decade of
Tafseer-ul-Quran lectures by Hazrat Ameer Muhammad Akram Awan (RA) (2005-2014)
and the newest bayans were missing. This reads every /lectures/<year> page of
the official site, finds the rows whose lecture id is not in the seed, and adds:

* rows with an MP3 as audio lectures, after a ranged GET has shown the file
  answers with audio (the MP3 in the lecture's own uploads/<id>/ folder);
* YouTube-only rows as YouTube items, with the video id embedded on the
  lecture's own page.

Rows that only have a WMA recording are not added (iPhone cannot play WMA);
they are written to --wma-report for the owner, since they need converting
and hosting first.

New rows follow the ingest's conventions (Tools/ContentIngest/schema.py): the
id is the slug of the lecture page address, keys are sorted, dates are
midnight UTC, and each carries its checksum. Titles are stored in canonical
form (NFC, single spaces) with the typing slips listed in TITLE_FIXES and
TITLE_WORDS corrected; everything else is the site's own text.

    python Tools/Content/import_missing_lectures.py --wma-report wma.json [--cache DIR] [--dry-run] [--preview new.json]
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
from seed_io import dump, load  # noqa: E402

# Lecture id -> corrected title. The site typed the last ayah number before the
# surah name (or split it), so the Urdu title read "ayat 86 to" or "ayat 2 6 to 64".
# The range is the one in the page's own address (e.g. ...-surah-al-baqarah-86-90).
TITLE_FIXES = {
    "2451": "سورۃ البقرہ آیت نمبر 62 تا 64",
    "2462": "سورۃ البقرہ آیت نمبر 86 تا 90",
    "2726": "سورۃ المائدہ آیت نمبر 61 تا 64",
    "2968": "سورہ ابراھیم آیت نمبر 1 تا 6",
    "2969": "سورہ ابراھیم آیت نمبر 7 تا 12",
    "2970": "سورہ ابراھیم آیت نمبر 13 تا 21",
    "2971": "سورہ ابراھیم آیت نمبر 22 تا 27",
    "2972": "سورہ ابراھیم آیت نمبر 28 تا 34",
    "2973": "سورہ ابراھیم آیت نمبر 35 تا 41",
    "2974": "سورہ ابراھیم آیت نمبر 42 تا 52",
}

# Misspellings that recur across a series: Surah 3 is Aal-e-Imran (آل with madda),
# and "سورۃالاعراف" lost the space after سورۃ.
TITLE_WORDS = [
    ("سورۃ ال عمران", "سورۃ آل عمران"),
    ("سورۃالاعراف", "سورۃ الاعراف"),
]


def clean_title(lecture_id: str, raw: str) -> str:
    if lecture_id in TITLE_FIXES:
        return TITLE_FIXES[lecture_id]
    title = site.clean_text(raw)
    for old, new in TITLE_WORDS:
        title = title.replace(old, new)
    # "آیت نمبر103" / "15تا" -> spaced like the rest of the series.
    title = re.sub(r"(نمبر)(\d)", r"\1 \2", title)
    title = re.sub(r"(\d)(تا)", r"\1 \2", title)
    return title


def year_pages(cache: Path | None) -> dict[str, str]:
    status, body, _ = site.get(f"{site.SITE}/lectures", cache)
    if status != 200:
        raise SystemExit(f"/lectures answered {status}")
    years = sorted(set(re.findall(r"naqshbandiaowaisiah\.org/lectures/(\d{4})", body.decode("utf-8", "replace"))))
    pages = site.get_many([f"{site.SITE}/lectures/{year}" for year in years], cache)
    failed = [url for url, (code, _, _) in pages.items() if code != 200]
    if failed:
        raise SystemExit(f"year pages that did not answer: {failed}")
    return {url.rsplit("/", 1)[1]: body.decode("utf-8", "replace") for url, (_, body, _) in pages.items()}


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--wma-report", type=Path, required=True)
    parser.add_argument("--cache", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--preview", type=Path, help="also write the rows to be added here, for review")
    args = parser.parse_args()

    items, layout = load("media_items.json")
    # Two lectures live at /lectures/<id>/ on the site; the rest at /lecture/<id>/.
    known = {m.group(1) for item in items if (m := re.search(r"/lectures?/(\d+)/", item["sourceUrl"]))}
    ids = {item["id"] for item in items}

    rows = {}
    for year, html in year_pages(args.cache).items():
        for row in site.lecture_rows(html):
            rows.setdefault(row["lectureID"], row)
    missing = [row for lid, row in rows.items() if lid not in known]
    audio = [row for row in missing if row["mp3"]]
    video = [row for row in missing if not row["mp3"] and not row["wma"] and row["youtube"]]
    wma_only = [row for row in missing if not row["mp3"] and row["wma"]]
    print(f"{len(rows)} lectures on the site, {len(missing)} not in the app: "
          f"{len(audio)} with MP3, {len(video)} YouTube-only, {len(wma_only)} WMA-only")

    def own_mp3(row: dict) -> str:
        own = [url for url in row["mp3"] if f"/uploads/{row['lectureID']}/" in url]
        return site.encode_url((own or row["mp3"])[0])

    sniffed = site.sniff_many([own_mp3(row) for row in audio])
    pages = site.get_many([row["href"] for row in video], args.cache)

    added, skipped = [], []
    for row in sorted(audio + video, key=lambda r: (r["date"].isoformat() if r["date"] else "", int(r["lectureID"]))):
        if row["date"] is None:
            skipped.append((row["lectureID"], "no date on the year page"))
            continue
        item = {
            "id": schema.slug_from_url(row["href"]),
            "title": clean_title(row["lectureID"], row["title"]),
            "language": "ur",
            "speaker": row["speaker"],
            "date": schema.iso_date_only(row["date"].year, row["date"].month, row["date"].day),
            "sourceUrl": row["href"],
            "year": row["date"].year,
            "month": row["date"].month,
            "category": "audioLectures",
            "rightsStatus": "permissionConfirmed",
        }
        if row["mp3"]:
            url = own_mp3(row)
            check = sniffed[url]
            if not check["ok"]:
                skipped.append((row["lectureID"], f"MP3 did not answer with audio: {check}"))
                continue
            item.update(mediaType="audio", streamUrl=url, downloadUrl=url)
        else:
            status, body, _ = pages[row["href"]]
            videos = site.youtube_ids(body.decode("utf-8", "replace")) if status == 200 else []
            if len(videos) != 1:
                skipped.append((row["lectureID"], f"lecture page has {len(videos)} YouTube ids"))
                continue
            item.update(mediaType="youtube", youtubeId=videos[0])
        if item["speaker"] is None:
            del item["speaker"]
        if not item["title"] or item["id"] in ids:
            skipped.append((row["lectureID"], "empty title or id already used"))
            continue
        item = {key: item[key] for key in sorted(item)}
        item["checksum"] = schema.checksum_for(item)
        added.append({key: item[key] for key in sorted(item)})
        ids.add(item["id"])

    mp4 = [row["lectureID"] for row in audio if sniffed[own_mp3(row)]["kind"] == "mp4"]
    print(f"adding {len(added)} ({sum(i['mediaType'] == 'audio' for i in added)} audio, "
          f"{sum(i['mediaType'] == 'youtube' for i in added)} YouTube); skipped {len(skipped)}")
    for lecture_id, why in skipped:
        print(f"  skipped {lecture_id}: {why}")
    if mp4:
        print(f"  note: {len(mp4)} '.mp3' files are MP4 audio inside: {mp4}")

    report = [{
        "lectureID": row["lectureID"], "date": row["date"].isoformat() if row["date"] else None,
        "title": site.clean_text(row["title"]), "speaker": row["speaker"], "page": row["href"],
        "wma": [site.encode_url(url) for url in row["wma"]],
    } for row in sorted(wma_only, key=lambda r: (r["date"].isoformat() if r["date"] else "", int(r["lectureID"])))]
    args.wma_report.write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"WMA-only lectures listed in {args.wma_report}: {len(report)}")

    if args.preview:
        args.preview.write_text(json.dumps(added, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    if args.dry_run or not added:
        return 0
    # Keep the file's grouping: the new lectures go after the last audio lecture.
    last_audio = max(i for i, item in enumerate(items) if item["category"] == "audioLectures")
    items[last_audio + 1:last_audio + 1] = added
    dump("media_items.json", items, layout)
    print(f"media_items.json: {len(items)} items")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
