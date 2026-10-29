"""Check that the seed files still decode with the app's Swift models.

The app decodes each seed file as one array with JSONDecoder (.iso8601 dates,
no fractional seconds). A single record with a missing required field, a wrong
type or an unknown enum value fails the whole file, and the screen it feeds
shows nothing. This mirrors the models in DarulIrfanApp/Models (required and
optional fields, enum values) for the files edited by hand or by the content
scripts, and checks ids are unique and links point at real items.

    python Tools/Content/check_seed_models.py      # exit 1 on any problem
"""

from __future__ import annotations

import json
import re
import sys

from seed_io import SEED

ISO = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:?\d{2})$")
RIGHTS = {"linkOnly", "permissionConfirmed", "publicDomain"}
MEDIA_CATEGORY = {"audioLectures", "videoLectures", "tafseerQuranVideos", "alMurshidTV",
                  "alMurshidQA", "shortClips", "recommended", "kalamESheikh"}
MEDIA_TYPE = {"audio", "video", "youtube"}
EVENT_KIND = {"monthlyIjtema", "salanaIjtema", "ramadanAitekaaf", "announcement", "other"}
CONTENT_TYPE = {"article", "book", "booklet", "magazine", "document", "announcement",
                "pressRelease", "poetry", "page"}
CONTENT_CATEGORY = {"aboutSilsila", "sheikhAbdulQadeerAwan", "sheikhMuhammadAkramAwan", "shajra",
                    "tasawwuf", "tazkiyahNafs", "zikrAllah", "methodOfZikr", "baiat", "articles",
                    "books", "booklets", "sufiPoetry", "trainingCourses", "importantDocuments",
                    "alMurshidMagazine", "pressReleases", "announcements", "featureArticles",
                    "aqwalESheikh", "quranTranslation", "quranTafsir"}
INSPIRATION_KIND = {"ayah", "tafsirExcerpt", "aqwalESheikh", "dua"}
REVELATION = {"makkah", "madinah"}


def t_str(v): return isinstance(v, str)
def t_int(v): return isinstance(v, int) and not isinstance(v, bool)
def t_num(v): return isinstance(v, (int, float)) and not isinstance(v, bool)
def t_bool(v): return isinstance(v, bool)
def t_date(v): return isinstance(v, str) and bool(ISO.match(v))
def t_enum(values): return lambda v: isinstance(v, str) and v in values
def t_list(check): return lambda v: isinstance(v, list) and all(check(x) for x in v)


# model: (required fields, optional fields)
MODELS = {
    "MediaItem": (
        {"id": t_str, "title": t_str, "language": t_str, "mediaType": t_enum(MEDIA_TYPE),
         "sourceUrl": t_str, "category": t_enum(MEDIA_CATEGORY), "rightsStatus": t_enum(RIGHTS)},
        {"speaker": t_str, "date": t_date, "durationSeconds": t_num, "streamUrl": t_str,
         "downloadUrl": t_str, "youtubeId": t_str, "year": t_int, "month": t_int,
         "transcriptUrl": t_str}),
    "CommunityEvent": (
        {"id": t_str, "kind": t_enum(EVENT_KIND), "title": t_str, "datesAreApproximate": t_bool},
        {"titleUrdu": t_str, "details": t_str, "startDate": t_date, "endDate": t_date,
         "venue": t_str, "sourceUrl": t_str, "updatedAt": t_date}),
    "Announcement": ({"id": t_str, "title": t_str},
                     {"body": t_str, "publishedAt": t_date, "sourceUrl": t_str}),
    "NameOfAllah": ({"id": t_int, "arabic": t_str, "transliteration": t_str, "meaningEnglish": t_str},
                    {"meaningUrdu": t_str}),
    "Dua": ({"id": t_str, "title": t_str, "arabic": t_str, "source": t_str},
            {"translationEnglish": t_str, "translationUrdu": t_str, "category": t_str,
             "rightsStatus": t_enum(RIGHTS), "titleUrdu": t_str}),
    "DailyInspiration": (
        {"id": t_str, "kind": t_enum(INSPIRATION_KIND), "text": t_str, "attribution": t_str,
         "rightsStatus": t_enum(RIGHTS)},
        {"sourceUrl": t_str}),
    "IslamicDay": ({"id": t_str, "title": t_str, "hijriMonth": t_int, "hijriDay": t_int},
                   {"note": t_str, "titleUrdu": t_str, "noteUrdu": t_str, "observedOnEve": t_bool}),
    "ZikrSession": (
        {"id": t_str, "title": t_str, "weekdays": t_list(t_int), "startHour": t_int,
         "startMinute": t_int, "durationMinutes": t_int, "timeZoneIdentifier": t_str},
        {"joinUrl": t_str, "instructions": t_str, "availabilityNote": t_str, "sourceUrl": t_str,
         "anchor": t_str, "anchorOffsetMinutes": t_int, "autoplayTitle": t_str,
         "titleUrdu": t_str, "availabilityNoteUrdu": t_str}),
    "Topic": ({"id": t_str, "nameEnglish": t_str, "systemIcon": t_str,
               "searchTerms": t_list(t_str), "ayahRefs": t_list(t_str)},
              {"nameUrdu": t_str, "hadithRefs": t_list(t_str)}),
    "ContentItem": (
        {"id": t_str, "sourceUrl": t_str, "type": t_enum(CONTENT_TYPE), "title": t_str,
         "language": t_str, "category": t_enum(CONTENT_CATEGORY), "mediaUrls": t_list(t_str),
         "downloadUrls": t_list(t_str), "rightsStatus": t_enum(RIGHTS)},
        {"titleUrdu": t_str, "author": t_str, "bodyHtml": t_str, "bodyPlainText": t_str,
         "excerpt": t_str, "publishedAt": t_date, "updatedAt": t_date, "checksum": t_str}),
    "QuranSurah": (
        {"id": t_int, "nameArabic": t_str, "nameTransliterated": t_str, "nameEnglish": t_str,
         "ayahCount": t_int, "revelationPlace": t_enum(REVELATION)},
        {"nameUrdu": t_str}),
    "AyahBayanLink": ({"surah": t_int, "ayahStart": t_int, "ayahEnd": t_int, "mediaID": t_str,
                       "title": t_str}, {}),
}

ARRAYS = [
    ("media_items.json", "MediaItem"), ("events.json", "CommunityEvent"),
    ("announcements.json", "Announcement"), ("names_of_allah.json", "NameOfAllah"),
    ("duas.json", "Dua"), ("aqwal_e_sheikh.json", "DailyInspiration"),
    ("islamic_days.json", "IslamicDay"), ("zikr_sessions.json", "ZikrSession"),
    ("topics.json", "Topic"), ("library_items.json", "ContentItem"),
    ("quran_surahs.json", "QuranSurah"),
]


def problems(record: dict, model: str) -> list[str]:
    required, optional = MODELS[model]
    found = []
    for key, check in required.items():
        if record.get(key) is None:
            found.append(f"missing {key}")
        elif not check(record[key]):
            found.append(f"bad {key}={str(record[key])[:60]!r}")
    for key, check in optional.items():
        if record.get(key) is not None and not check(record[key]):
            found.append(f"bad {key}={str(record[key])[:60]!r}")
    return found


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    failures = 0
    loaded: dict[str, list] = {}
    for name, model in ARRAYS:
        rows = json.loads((SEED / name).read_text(encoding="utf-8"))
        loaded[name] = rows
        bad = [(row.get("id"), problems(row, model)) for row in rows]
        bad = [(rid, found) for rid, found in bad if found]
        ids = [row.get("id") for row in rows]
        duplicates = len(ids) - len(set(ids))
        status = "ok" if not bad and not duplicates else "FAIL"
        print(f"{status:4} {name}: {len(rows)} records, {len(bad)} undecodable, {duplicates} duplicate ids")
        for rid, found in bad[:10]:
            print(f"       {rid}: {found}")
        failures += len(bad) + duplicates

    place = json.loads((SEED / "darul_irfan_place.json").read_text(encoding="utf-8"))
    place_ok = all(isinstance(place.get(k), str) for k in ("name", "websiteUrl")) and \
        isinstance(place.get("addressLines"), list)
    print(f"{'ok' if place_ok else 'FAIL':4} darul_irfan_place.json")
    failures += 0 if place_ok else 1

    links = json.loads((SEED / "ayah_bayan_links.json").read_text(encoding="utf-8"))
    media_ids = {row["id"] for row in loaded["media_items.json"]}
    bad_links = [link for link in links.get("links", []) if problems(link, "AyahBayanLink")]
    dangling = [link["mediaID"] for link in links.get("links", []) if link.get("mediaID") not in media_ids]
    status = "ok" if not bad_links and not dangling else "FAIL"
    print(f"{status:4} ayah_bayan_links.json: {len(links.get('links', []))} links, "
          f"{len(bad_links)} undecodable, {len(dangling)} pointing at no media item {dangling[:5]}")
    failures += len(bad_links) + len(dangling)

    print("seed models: PASS" if not failures else f"seed models: FAIL ({failures} problems)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
