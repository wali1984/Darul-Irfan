#!/usr/bin/env python3
"""Rebuild the bundled hadith packs from the upstream `hadith-api` editions.

Why this exists
---------------
The first generation of the packs stored the hadith number as an *integer*.
Upstream numbers such as ``402.2`` therefore truncated to ``402`` and collided
with the real hadith 402, so one of the two rows was silently lost on insert.
Across the seven bundled collections that destroyed 103 narrations in 86
collision groups.

The fix is to stop treating the number as a number at all.  A hadith number is
an *identifier* printed on a page, not a quantity:

* ``3604.1`` in Jami' at-Tirmidhi means sub-number **10** — it follows
  ``3604.09`` in the source.  Read as a decimal it would sort before it.
* Muwatta Malik uses ``.25`` / ``.5`` / ``.75`` as insertion positions between
  whole numbers, so the minor part is not a sequence counter either.

So the pack keeps the number's exact printed form in ``displayNumber``, splits
it into integer ``numberMajor`` / ``numberMinor`` parts for lookup only, and
orders every reader by ``sourceSequence`` — the narration's own position in the
source edition, which is authoritative for both cases above.

Source
------
fawazahmed0/hadith-api, released into the public domain (Unlicense).
Download the editions this script reads with ``--download`` (needs network), or
point ``--source-dir`` at an existing copy.  Files are named ``<lang>-<book>.json``
with ``lang`` in ``ara`` / ``eng`` / ``urd``.

Usage
-----
    python Tools/Hadith/build_hadith_packs.py --download --source-dir /tmp/hadith-src
    python Tools/Hadith/build_hadith_packs.py --source-dir /tmp/hadith-src

Writes ``hadith_books.json`` plus ``hadith_<book>.json`` for each collection
into every platform seed directory, and prints a reconciliation report.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path
from typing import Any, Iterable, NamedTuple

# Anchored on the iOS checkout (Tools/Hadith/<this file>), whose parent is the
# workspace directory holding the other three platform checkouts. Only iOS is
# under version control, so the others may be absent; missing ones are skipped
# with a warning rather than failing the build.
IOS_ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = IOS_ROOT.parent

# Every platform ships byte-identical seed files; see PLATFORM_RELEASE_MATRIX.md.
SEED_DIRS = [
    IOS_ROOT / "DarulIrfanApp/Resources/SeedData",
    REPO_ROOT / "DarulIrfanAndroid/app/src/main/assets/seed",
    REPO_ROOT / "DarulIrfanHarmony/entry/src/main/resources/rawfile/seed",
    REPO_ROOT / "DarulIrfanWeb/content",
]

LANGUAGES = ("ara", "eng", "urd")

# Review state stamped into the generated catalogue. Kept here so regenerating
# the packs cannot silently drop it; see Docs/CONTENT_REVIEW_STATES.md.
REVIEW_STATE = "testFlightApproved"

# `urd` is used as the ordering edition: it was verified to be a superset of the
# Arabic and English editions for all seven collections (Muwatta Malik's 31
# sub-numbered narrations and one Sahih Muslim entry appear only there), so it
# alone can number every hadith in the merged corpus.
ORDERING_LANGUAGE = "urd"

CDN = "https://cdn.jsdelivr.net/gh/fawazahmed0/hadith-api@1/editions"


class BookSpec(NamedTuple):
    book_id: str
    title_english: str
    title_urdu: str


BOOKS = [
    BookSpec("bukhari", "Sahih al-Bukhari", "صحیح بخاری"),
    BookSpec("muslim", "Sahih Muslim", "صحیح مسلم"),
    BookSpec("abudawud", "Sunan Abu Dawud", "سنن ابو داؤد"),
    BookSpec("tirmidhi", "Jami' at-Tirmidhi", "جامع ترمذی"),
    BookSpec("nasai", "Sunan an-Nasa'i", "سنن نسائی"),
    BookSpec("ibnmajah", "Sunan Ibn Majah", "سنن ابن ماجہ"),
    BookSpec("malik", "Muwatta Malik", "موطأ امام مالک"),
]


def load_edition(source_dir: Path, language: str, book_id: str) -> dict[str, Any]:
    """Load one edition, keeping every number's exact printed form.

    ``parse_float``/``parse_int`` return the raw JSON literal, so ``402.2``
    stays the four characters ``402.2`` and never becomes a lossy float.
    """
    path = source_dir / f"{language}-{book_id}.json"
    with path.open(encoding="utf-8") as handle:
        return json.load(handle, parse_float=str, parse_int=str)


def download_editions(source_dir: Path) -> None:
    source_dir.mkdir(parents=True, exist_ok=True)
    for book in BOOKS:
        for language in LANGUAGES:
            target = source_dir / f"{language}-{book.book_id}.json"
            if target.exists() and target.stat().st_size > 0:
                continue
            url = f"{CDN}/{language}-{book.book_id}.json"
            print(f"  downloading {url}")
            with urllib.request.urlopen(url, timeout=300) as response:
                target.write_bytes(response.read())


def split_number(display: str) -> tuple[int, int | None]:
    """Split a printed hadith number into its integer identifier parts.

    These are lookup keys, never sort keys — see the module docstring.
    """
    major, _, minor = display.partition(".")
    return int(major), (int(minor) if minor else None)


def optional_int(raw: Any) -> int | None:
    """Source references use 0 as "no reference"; keep that as absent."""
    if raw in (None, "", "0"):
        return None
    try:
        return int(raw)
    except (TypeError, ValueError):
        return None


def format_grades(raw: Iterable[dict[str, str]] | None) -> list[str]:
    """Flatten the source's ``{name, grade}`` pairs to display strings."""
    if not raw:
        return []
    out = []
    for item in raw:
        name = (item.get("name") or "").strip()
        grade = (item.get("grade") or "").strip()
        if grade and name:
            out.append(f"{name}: {grade}")
        elif grade:
            out.append(grade)
    return out


class BookResult(NamedTuple):
    book_id: str
    records: list[dict[str, Any]]
    source_total: int
    dropped_empty: list[str]
    sub_numbered: list[str]
    collapse_groups: int
    collapse_rows_lost: int
    section_count: int


def build_book(source_dir: Path, spec: BookSpec) -> BookResult:
    editions = {lang: load_edition(source_dir, lang, spec.book_id) for lang in LANGUAGES}
    by_number = {
        lang: {h["hadithnumber"]: h for h in data["hadiths"]}
        for lang, data in editions.items()
    }

    # Source order is authoritative: it is what the printed collection uses, and
    # it is the only ordering that gets Tirmidhi's 3604.02…3604.09, 3604.1 run
    # and Malik's .25/.5/.75 insertions right.
    order = [h["hadithnumber"] for h in editions[ORDERING_LANGUAGE]["hadiths"]]

    missing = (set(by_number["ara"]) | set(by_number["eng"])) - set(order)
    if missing:
        raise SystemExit(
            f"{spec.book_id}: ordering edition '{ORDERING_LANGUAGE}' is missing "
            f"{len(missing)} numbers present in another edition, e.g. "
            f"{sorted(missing)[:5]} — pick a different ordering edition."
        )

    records: list[dict[str, Any]] = []
    dropped_empty: list[str] = []
    sub_numbered: list[str] = []

    for index, display in enumerate(order, start=1):
        texts = {}
        for lang, key in (("ara", "text_ar"), ("eng", "text_en"), ("urd", "text_ur")):
            entry = by_number[lang].get(display)
            text = (entry or {}).get("text") or ""
            texts[key] = text if text.strip() else None

        if not any(texts.values()):
            # Upstream reserves these numbers with an empty body in all three
            # languages. They carry no narration, so they are not shipped —
            # but they are counted in the report rather than vanishing quietly.
            dropped_empty.append(display)
            continue

        major, minor = split_number(display)
        if minor is not None:
            sub_numbered.append(display)

        reference: dict[str, Any] = {}
        for lang in LANGUAGES:
            candidate = (by_number[lang].get(display) or {}).get("reference") or {}
            if optional_int(candidate.get("book")) is not None:
                reference = candidate
                break

        grades: list[str] = []
        for lang in ("eng", "ara", "urd"):
            grades = format_grades((by_number[lang].get(display) or {}).get("grades"))
            if grades:
                break

        record = {
            # bookID | printed number | position in the source edition.
            "canonicalID": f"{spec.book_id}|{display}|{index}",
            "bookID": spec.book_id,
            "displayNumber": display,
            "numberMajor": major,
            "sourceSequence": index,
            "text_ar": texts["text_ar"],
            "text_en": texts["text_en"],
            "text_ur": texts["text_ur"],
        }
        if minor is not None:
            record["numberMinor"] = minor
        source_book = optional_int(reference.get("book"))
        source_hadith = optional_int(reference.get("hadith"))
        if source_book is not None:
            record["sourceBook"] = source_book
        if source_hadith is not None:
            record["sourceHadith"] = source_hadith
        if grades:
            record["grades"] = grades
        records.append(record)

    # What the old integer-keyed schema would have destroyed, for the report.
    buckets: dict[int, list[str]] = {}
    for record in records:
        buckets.setdefault(record["numberMajor"], []).append(record["displayNumber"])
    collapse = {k: v for k, v in buckets.items() if len(v) > 1}

    sections = editions[ORDERING_LANGUAGE]["metadata"]["sections"]
    section_count = sum(1 for name in sections.values() if str(name).strip())

    return BookResult(
        book_id=spec.book_id,
        records=records,
        source_total=len(order),
        dropped_empty=dropped_empty,
        sub_numbered=sub_numbered,
        collapse_groups=len(collapse),
        collapse_rows_lost=sum(len(v) - 1 for v in collapse.values()),
        section_count=section_count,
    )


def write_json(path: Path, payload: Any) -> None:
    """Small documents get pretty-printed; the catalogue is read by people."""
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(payload, ensure_ascii=False, indent=1) + "\n"
    path.write_text(text, encoding="utf-8", newline="\n")


def write_records(path: Path, records: list[dict[str, Any]]) -> None:
    """Writes a pack as one JSON object per line.

    These files run to 20 MB. On one line, every regeneration is a single
    unreadable diff; fully indented, they are half a million lines. One record
    per line keeps a changed narration to a one-line diff and stays compact.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    body = ",\n ".join(json.dumps(record, ensure_ascii=False) for record in records)
    path.write_text(f"[\n {body}\n]\n", encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--download", action="store_true", help="fetch editions first")
    parser.add_argument("--dry-run", action="store_true", help="report without writing")
    args = parser.parse_args()

    if args.download:
        print("Downloading upstream editions…")
        download_editions(args.source_dir)

    results = [build_book(args.source_dir, spec) for spec in BOOKS]
    by_id = {r.book_id: r for r in results}

    catalog = {
        "source": "fawazahmed0/hadith-api",
        "license": "Unlicense (public domain dedication)",
        "licenseUrl": "https://github.com/fawazahmed0/hadith-api/blob/1/LICENSE",
        "languages": ["ar", "en", "ur"],
        # Public-domain corpus, identifiers rebuilt and integrity-gated, but no
        # line-by-line human proofreading pass. See Docs/CONTENT_REVIEW_STATES.md.
        "reviewState": REVIEW_STATE,
        "books": [
            {
                "id": spec.book_id,
                "titleEnglish": spec.title_english,
                "titleUrdu": spec.title_urdu,
                # Counted from the packaged records, never from source metadata,
                # so the catalogue can never over-claim what actually ships.
                "hadithCount": len(by_id[spec.book_id].records),
                "hasArabic": any(r["text_ar"] for r in by_id[spec.book_id].records),
                "hasEnglish": any(r["text_en"] for r in by_id[spec.book_id].records),
                "hasUrdu": any(r["text_ur"] for r in by_id[spec.book_id].records),
                "sectionCount": by_id[spec.book_id].section_count,
            }
            for spec in BOOKS
        ],
    }

    print()
    print(f"{'collection':12} {'source':>7} {'empty':>6} {'shipped':>8} "
          f"{'sub-num':>8} {'was-lost':>9} {'groups':>7}")
    print("-" * 64)
    totals = [0, 0, 0, 0, 0, 0]
    for result in results:
        row = (result.source_total, len(result.dropped_empty), len(result.records),
               len(result.sub_numbered), result.collapse_rows_lost, result.collapse_groups)
        totals = [a + b for a, b in zip(totals, row)]
        print(f"{result.book_id:12} {row[0]:7} {row[1]:6} {row[2]:8} "
              f"{row[3]:8} {row[4]:9} {row[5]:7}")
    print("-" * 64)
    print(f"{'TOTAL':12} {totals[0]:7} {totals[1]:6} {totals[2]:8} "
          f"{totals[3]:8} {totals[4]:9} {totals[5]:7}")
    print()
    print(f"Recovered {totals[4]} narrations that the integer-keyed schema "
          f"lost across {totals[5]} collision groups.")
    print(f"{totals[1]} upstream numbers carry no text in any language and are "
          f"not shipped (reserved/placeholder numbers).")

    if args.dry_run:
        print("\n--dry-run: nothing written.")
        return 0

    for seed_dir in SEED_DIRS:
        if not seed_dir.exists():
            print(f"! skipping missing seed dir {seed_dir}")
            continue
        write_json(seed_dir / "hadith_books.json", catalog)
        for result in results:
            write_records(seed_dir / f"hadith_{result.book_id}.json", result.records)
        print(f"wrote {len(results) + 1} files -> {seed_dir.relative_to(REPO_ROOT)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
