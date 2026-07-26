#!/usr/bin/env python3
"""Import the official Akram-ut-Tarajum Quran pages into the iOS seed.

The official Quran reader exposes one structured HTML row per ayah with Urdu
and English translations. This importer discovers all 114 source URLs from
the Quran index, validates every ayah against the bundled Quran metadata, and
then updates the two Akram translation editions atomically.

It also emits a UTF-8 Urdu OCR corpus plus a paired Urdu/English reference
corpus. Network text is never silently accepted when a surah or ayah is
missing, duplicated, or empty.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import hashlib
import json
import re
import sys
import time
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup


BASE_URL = "https://www.naqshbandiaowaisiah.org"
INDEX_URL = f"{BASE_URL}/quran"
USER_AGENT = "DarulIrfanContentImporter/1.0 (+official iOS content verification)"
AKRAM_UR = "akram-ut-tarajum-ur"
AKRAM_EN = "akram-ut-tarajum-en"


@dataclass(frozen=True)
class AyahTranslation:
    surah: int
    ayah: int
    urdu: str
    english: str
    source_url: str


def clean_text(value: str) -> str:
    value = unicodedata.normalize("NFC", value.replace("\u00a0", " "))
    return " ".join(value.split()).strip()


def fetch(url: str, attempts: int = 4) -> str:
    last_error: Exception | None = None
    for attempt in range(attempts):
        try:
            response = requests.get(
                url,
                headers={"User-Agent": USER_AGENT, "Accept": "text/html"},
                timeout=(15, 45),
            )
            response.raise_for_status()
            if not response.encoding or response.encoding.lower() == "iso-8859-1":
                response.encoding = response.apparent_encoding or "utf-8"
            return response.text
        except (requests.RequestException, UnicodeError) as error:
            last_error = error
            if attempt + 1 < attempts:
                time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"Could not fetch {url}: {last_error}")


def discover_surah_urls(index_html: str) -> dict[int, str]:
    soup = BeautifulSoup(index_html, "html.parser")
    urls: dict[int, str] = {}
    for link in soup.select("a[href]"):
        href = link.get("href", "")
        match = re.search(r"/quran/(\d+)-[^/?#]+", href)
        if not match:
            continue
        number = int(match.group(1))
        urls[number] = urljoin(BASE_URL, href)
    expected = set(range(1, 115))
    if set(urls) != expected:
        missing = sorted(expected - set(urls))
        extra = sorted(set(urls) - expected)
        raise ValueError(f"Quran index mismatch; missing={missing}, extra={extra}")
    return urls


def parse_surah(number: int, url: str, expected_ayahs: int) -> list[AyahTranslation]:
    soup = BeautifulSoup(fetch(url), "html.parser")
    display_rows: dict[int, AyahTranslation] = {}
    for row in soup.select(".ayat-row"):
        anchor = row.select_one('a[id^="ayat-"]')
        if anchor is None:
            continue
        match = re.fullmatch(r"ayat-(\d+)", anchor.get("id", ""))
        if not match:
            continue
        ayah = int(match.group(1))
        urdu_node = row.select_one(".ayat-urdu-title")
        english_node = row.select_one(".ayat-english-title")
        if urdu_node is None or english_node is None:
            raise ValueError(f"{number}:{ayah} is missing a translation node at {url}")
        urdu = clean_text(urdu_node.get_text(" ", strip=True))
        english = clean_text(english_node.get_text(" ", strip=True))
        if not urdu or not english:
            raise ValueError(f"{number}:{ayah} has empty translation text at {url}")
        if ayah in display_rows:
            raise ValueError(f"Duplicate ayah {number}:{ayah} at {url}")
        display_rows[ayah] = AyahTranslation(number, ayah, urdu, english, url)

    if number == 1:
        # The website presents Al-Fatihah as basmalah row 0, verses 1...5,
        # then splits the app's canonical verse 7 across display rows 6 and 7.
        # The bundled Quran follows the common 7-ayah numbering in which the
        # basmalah is ayah 1 and the final two source rows form ayah 7.
        if set(display_rows) != set(range(0, 8)):
            raise ValueError(f"Al-Fatihah display-row mismatch at {url}: {sorted(display_rows)}")
        parsed = {
            1: AyahTranslation(number, 1, display_rows[0].urdu, display_rows[0].english, url),
            2: AyahTranslation(number, 2, display_rows[1].urdu, display_rows[1].english, url),
            3: AyahTranslation(number, 3, display_rows[2].urdu, display_rows[2].english, url),
            4: AyahTranslation(number, 4, display_rows[3].urdu, display_rows[3].english, url),
            5: AyahTranslation(number, 5, display_rows[4].urdu, display_rows[4].english, url),
            6: AyahTranslation(number, 6, display_rows[5].urdu, display_rows[5].english, url),
            7: AyahTranslation(
                number,
                7,
                clean_text(f"{display_rows[6].urdu} {display_rows[7].urdu}"),
                clean_text(f"{display_rows[6].english} {display_rows[7].english}"),
                url,
            ),
        }
    else:
        # Other surahs expose the basmalah as display row zero when present;
        # it is not a numbered ayah in the canonical 6,236-row dataset.
        parsed = {ayah: row for ayah, row in display_rows.items() if ayah != 0}

    expected_numbers = set(range(1, expected_ayahs + 1))
    if set(parsed) != expected_numbers:
        missing = sorted(expected_numbers - set(parsed))
        extra = sorted(set(parsed) - expected_numbers)
        raise ValueError(f"Surah {number} ayah mismatch; missing={missing}, extra={extra}")
    return [parsed[ayah] for ayah in range(1, expected_ayahs + 1)]


def translation_row(edition: str, row: AyahTranslation, text: str) -> dict[str, object]:
    return {
        "editionID": edition,
        "surahNumber": row.surah,
        "ayahNumber": row.ayah,
        "text": text,
    }


def write_json(path: Path, value: object, indent: int | None = None) -> None:
    # Preserve the compact translation seed and explicitly formatted metadata
    # files so generated diffs stay limited to real content changes.
    path.write_text(json.dumps(value, ensure_ascii=False, indent=indent) + "\n", encoding="utf-8")


def update_editions(path: Path) -> bool:
    original = json.loads(path.read_text(encoding="utf-8"))
    editions = list(original)
    editions = [edition for edition in editions if edition.get("id") not in {AKRAM_UR, AKRAM_EN}]
    common = {
        "kind": "translation",
        "author": "Hazrat Ameer Muhammad Akram Awan (RA)",
        "sourceUrl": INDEX_URL,
        "rightsStatus": "permissionConfirmed",
        "isAvailableOffline": True,
    }
    editions.extend([
        {"id": AKRAM_UR, "title": "اکرم التراجم — اردو", "language": "ur", **common},
        {"id": AKRAM_EN, "title": "Akram-ut-Tarajum — English", "language": "en", **common},
    ])
    changed = editions != original
    if changed:
        write_json(path, editions, indent=1)
    return changed


def update_translations(path: Path, rows: Iterable[AyahTranslation]) -> tuple[int, str, bool]:
    original = json.loads(path.read_text(encoding="utf-8"))
    existing = list(original)
    existing = [row for row in existing if row.get("editionID") not in {AKRAM_UR, AKRAM_EN}]
    imported: list[dict[str, object]] = []
    digest = hashlib.sha256()
    count = 0
    for row in rows:
        imported.append(translation_row(AKRAM_UR, row, row.urdu))
        imported.append(translation_row(AKRAM_EN, row, row.english))
        digest.update(f"{row.surah}:{row.ayah}\t{row.urdu}\t{row.english}\n".encode("utf-8"))
        count += 1
    combined = existing + imported
    changed = combined != original
    if changed:
        write_json(path, combined)
    return count, digest.hexdigest(), changed


def write_corpus(path: Path, rows: Iterable[AyahTranslation]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Akram-ut-Tarajum — complete official Quran translation corpus",
        f"# Source: {INDEX_URL}",
        "# Format: surah:ayah<TAB>Urdu<TAB>English",
    ]
    lines.extend(f"{row.surah:03d}:{row.ayah:03d}\t{row.urdu}\t{row.english}" for row in rows)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def write_ocr_corpus(path: Path, rows: Iterable[AyahTranslation]) -> None:
    """Write one Urdu ground-truth record per ayah for OCR training."""
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Akram-ut-Tarajum — Urdu OCR ground-truth corpus",
        f"# Source: {INDEX_URL}",
        "# Format: surah:ayah<TAB>Urdu",
    ]
    lines.extend(f"{row.surah:03d}:{row.ayah:03d}\t{row.urdu}" for row in rows)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def update_seed_manifest(path: Path) -> int:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    manifest["version"] = int(manifest.get("version", 0)) + 1
    manifest["generatedAt"] = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    write_json(path, manifest, indent=2)
    return manifest["version"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workers", type=int, default=6, help="Concurrent source requests (default: 6)")
    parser.add_argument("--check-only", action="store_true", help="Validate all pages without writing files")
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[2]
    seed = repo / "DarulIrfanApp" / "Resources" / "SeedData"
    metadata = json.loads((seed / "quran_surahs.json").read_text(encoding="utf-8"))
    counts = {int(surah["id"]): int(surah["ayahCount"]) for surah in metadata}
    if set(counts) != set(range(1, 115)) or sum(counts.values()) != 6236:
        raise ValueError("Bundled Quran metadata is not the expected 114 surahs / 6,236 ayat")

    urls = discover_surah_urls(fetch(INDEX_URL))
    results: dict[int, list[AyahTranslation]] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, min(args.workers, 10))) as executor:
        futures = {
            executor.submit(parse_surah, number, urls[number], counts[number]): number
            for number in range(1, 115)
        }
        for future in concurrent.futures.as_completed(futures):
            number = futures[future]
            results[number] = future.result()
            print(f"validated {number:03d}: {len(results[number])} ayat", flush=True)

    rows = [row for number in range(1, 115) for row in results[number]]
    if len(rows) != 6236:
        raise ValueError(f"Expected 6,236 translations per language, got {len(rows)}")
    if args.check_only:
        print("All 114 surahs and 6,236 ayat validated; no files changed.")
        return 0

    editions_changed = update_editions(seed / "quran_editions.json")
    count, checksum, translations_changed = update_translations(seed / "quran_translations.json", rows)
    corpus = repo / "Tools" / "OCR" / "akram_ut_tarajum_translations.txt"
    write_corpus(corpus, rows)
    ocr_corpus = repo / "Tools" / "OCR" / "akram_ut_tarajum_ocr_training.txt"
    write_ocr_corpus(ocr_corpus, rows)
    manifest_path = seed / "manifest.json"
    if editions_changed or translations_changed:
        version = update_seed_manifest(manifest_path)
    else:
        version = int(json.loads(manifest_path.read_text(encoding="utf-8"))["version"])
    print(f"Imported {count} Urdu + {count} English translations")
    print(f"Corpus: {corpus}")
    print(f"Urdu OCR corpus: {ocr_corpus}")
    print(f"SHA-256 (canonical paired corpus): {checksum}")
    print(f"Seed version: {version} ({'updated' if editions_changed or translations_changed else 'unchanged'})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise
