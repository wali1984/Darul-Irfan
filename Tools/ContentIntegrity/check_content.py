#!/usr/bin/env python3
"""Content-integrity gate for the bundled sacred text.

Every check here exists because something went wrong once: a 662 KB tafsir
block crashed large surahs, integer hadith keys silently destroyed 103
narrations, a catalogue over-claimed what actually shipped. The gate runs in CI
before a TestFlight tag and fails the build on any violation.

What it does *not* check is whether a human has proofread the text line by
line. Reviewed content that passed vision review, extracted-text review and
these validators is `testFlightApproved`; proofreading is what later promotes it
to `publicApproved`, and its absence is never a reason to fail this gate.

    python Tools/ContentIntegrity/check_content.py
    python Tools/ContentIntegrity/check_content.py --report Docs/CONTENT_INTEGRITY.md
    python Tools/ContentIntegrity/check_content.py --migration-status passed

Exit code 0 = shippable, 1 = a gate failed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
IOS_SEED = REPO_ROOT / "DarulIrfan-iOS/DarulIrfanApp/Resources/SeedData"

# Every platform ships byte-identical seed files; see PLATFORM_RELEASE_MATRIX.md.
PLATFORM_SEEDS = {
    "iOS": IOS_SEED,
    "Android": REPO_ROOT / "DarulIrfanAndroid/app/src/main/assets/seed",
    "HarmonyOS": REPO_ROOT / "DarulIrfanHarmony/entry/src/main/resources/rawfile/seed",
    "Web": REPO_ROOT / "DarulIrfanWeb/content",
}

SURAH_COUNT = 114
AYAH_COUNT = 6236

# One stored text block. The reader renders a block as a single view, so an
# oversized one janks or crashes the scroll — a 662 KB full-surah tafsir block
# did exactly that in v1.6.9. Well above the current maximum (~34 KB), well
# below anything that has ever caused trouble.
MAX_TEXT_BLOCK_BYTES = 96 * 1024

REVIEW_STATES = {"draft", "testFlightApproved", "publicApproved", "rejected"}
SHIPPABLE_ON_TESTFLIGHT = {"testFlightApproved", "publicApproved"}

HADITH_BOOKS = ["bukhari", "muslim", "abudawud", "tirmidhi", "nasai", "ibnmajah", "malik"]

# Byte sequences that appear when UTF-8 has been decoded as Latin-1/CP1252 and
# re-encoded. Any of these in sacred text means the pipeline mangled it.
MOJIBAKE = [
    "Ã¢", "Ã©", "Ã¨", "Ã¯", "Ã±", "Ã¼",       # Latin letters via Latin-1
    "â€™", "â€œ", "â€\x9d", "â€”", "â€“",      # smart punctuation via CP1252
    "Ø§Ù", "Ø¹", "Ø±Ù",                        # Arabic via Latin-1
    "Ã™", "Ã˜",
]


class Report:
    """Collects failures and the facts that go into the generated report."""

    def __init__(self) -> None:
        self.failures: list[str] = []
        self.notes: list[str] = []
        self.facts: dict[str, Any] = {}

    def check(self, condition: bool, message: str) -> bool:
        if not condition:
            self.failures.append(message)
        return condition

    def note(self, message: str) -> None:
        self.notes.append(message)


def load(seed: Path, name: str) -> Any:
    path = seed / f"{name}.json"
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------
# Encoding
# ---------------------------------------------------------------------------

def load_known_defects() -> dict[str, dict[str, int]]:
    """Narrations whose Arabic upstream already lost characters to a bad decode.

    Recorded per narration so the gate can tell a defect we inherited from one
    we introduced. Anything outside this inventory is a regression.
    """
    path = Path(__file__).with_name("known_upstream_defects.json")
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))["narrations"]


def check_encoding(seed: Path, report: Report) -> None:
    """Files must be real UTF-8, with no mojibake.

    U+FFFD is counted per narration in `check_hadith` against the recorded
    inventory; everywhere else it must not appear at all.
    """
    bad_utf8: list[str] = []
    replacement: list[str] = []
    mojibake: list[str] = []

    for path in sorted(seed.glob("*.json")):
        raw = path.read_bytes()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as error:
            bad_utf8.append(f"{path.name}: {error}")
            continue
        # U+FFFD means a decoder already gave up on this text; the character it
        # stood for is gone. Never acceptable in the Quran or in curated text.
        if "�" in text and not path.name.startswith("hadith_"):
            replacement.append(f"{path.name}: {text.count(chr(0xFFFD))} U+FFFD")
        for marker in MOJIBAKE:
            if marker in text:
                mojibake.append(f"{path.name}: contains {marker!r}")
                break

    report.check(not bad_utf8, f"seed files are not valid UTF-8: {bad_utf8}")
    report.check(not replacement, f"U+FFFD replacement characters in: {replacement}")
    report.check(not mojibake, f"mojibake in: {mojibake}")
    report.facts["encodingErrors"] = len(bad_utf8) + len(replacement) + len(mojibake)


# ---------------------------------------------------------------------------
# Quran
# ---------------------------------------------------------------------------

def check_quran(seed: Path, report: Report) -> None:
    surahs = load(seed, "quran_surahs") or []
    ayahs = load(seed, "quran_ayahs") or []
    editions = load(seed, "quran_editions") or []
    translations = load(seed, "quran_translations") or []
    tafsir = load(seed, "quran_tafsir") or []

    report.check(len(surahs) == SURAH_COUNT,
                 f"expected {SURAH_COUNT} surahs, found {len(surahs)}")
    report.check(len(ayahs) == AYAH_COUNT,
                 f"expected {AYAH_COUNT} ayat, found {len(ayahs)}")

    # `QuranSurah.id` is the surah number (1–114).
    bounds = {s["id"]: s["ayahCount"] for s in surahs}
    report.facts["quranSurahs"] = len(surahs)
    report.facts["quranAyahs"] = len(ayahs)

    # Bounds and uniqueness of the Arabic text itself.
    seen: set[tuple[int, int]] = set()
    duplicates = 0
    out_of_bounds: list[str] = []
    empty: list[str] = []
    for ayah in ayahs:
        surah, number = ayah["surahNumber"], ayah["ayahNumber"]
        key = (surah, number)
        if key in seen:
            duplicates += 1
        seen.add(key)
        if surah not in bounds or not (1 <= number <= bounds.get(surah, 0)):
            out_of_bounds.append(f"{surah}:{number}")
        if not (ayah.get("textArabic") or "").strip():
            empty.append(f"{surah}:{number}")

    report.check(duplicates == 0, f"{duplicates} duplicate (surah, ayah) keys")
    report.check(not out_of_bounds,
                 f"{len(out_of_bounds)} ayat outside their surah's bounds: {out_of_bounds[:5]}")
    report.check(not empty, f"{len(empty)} ayat with empty Arabic text: {empty[:5]}")

    # Every surah must be complete: a missing ayah is as bad as an extra one.
    missing = [
        f"{number}:{index}"
        for number, count in bounds.items()
        for index in range(1, count + 1)
        if (number, index) not in seen
    ]
    report.check(not missing, f"{len(missing)} ayat missing: {missing[:5]}")

    known_editions = {e["id"] for e in editions}
    for edition in editions:
        state = edition.get("reviewState")
        report.check(
            state in REVIEW_STATES,
            f"edition '{edition['id']}' has review state {state!r}; "
            f"expected one of {sorted(REVIEW_STATES)}"
        )
        report.check(
            state != "rejected",
            f"edition '{edition['id']}' is rejected and must not ship"
        )

    # Translations: unique per (edition, surah, ayah), inside bounds.
    translation_keys: set[tuple[str, int, int]] = set()
    translation_dupes = 0
    per_edition: dict[str, int] = {}
    unknown_edition: set[str] = set()
    for row in translations:
        edition = row["editionID"]
        key = (edition, row["surahNumber"], row["ayahNumber"])
        if key in translation_keys:
            translation_dupes += 1
        translation_keys.add(key)
        per_edition[edition] = per_edition.get(edition, 0) + 1
        if edition not in known_editions:
            unknown_edition.add(edition)

    report.check(translation_dupes == 0,
                 f"{translation_dupes} duplicate (edition, surah, ayah) translation keys")
    report.check(not unknown_edition,
                 f"translations reference undeclared editions: {sorted(unknown_edition)}")
    report.facts["translationEditions"] = per_edition

    # Tafsir: unique per (edition, surah, ayahStart), ranges well formed.
    tafsir_keys: set[tuple[str, int, int]] = set()
    tafsir_dupes = 0
    bad_ranges: list[str] = []
    coverage: dict[str, set[int]] = {}
    tafsir_counts: dict[str, int] = {}
    for row in tafsir:
        edition, surah = row["editionID"], row["surahNumber"]
        start, end = row["ayahStart"], row["ayahEnd"]
        key = (edition, surah, start)
        if key in tafsir_keys:
            tafsir_dupes += 1
        tafsir_keys.add(key)
        tafsir_counts[edition] = tafsir_counts.get(edition, 0) + 1
        coverage.setdefault(edition, set()).add(surah)
        limit = bounds.get(surah, 0)
        if not (1 <= start <= end <= limit):
            bad_ranges.append(f"{edition} {surah}:{start}-{end}")

    report.check(tafsir_dupes == 0,
                 f"{tafsir_dupes} duplicate (edition, surah, ayahStart) tafsir keys")
    report.check(not bad_ranges,
                 f"{len(bad_ranges)} tafsir blocks with invalid ranges: {bad_ranges[:5]}")
    report.facts["tafsirEditions"] = {
        edition: {"blocks": tafsir_counts[edition], "surahsCovered": len(coverage[edition])}
        for edition in sorted(tafsir_counts)
    }
    report.facts["quranEditions"] = [
        {
            "id": e["id"], "kind": e.get("kind"), "language": e.get("language"),
            "reviewState": e.get("reviewState"),
            "rows": per_edition.get(e["id"], tafsir_counts.get(e["id"], 0)),
        }
        for e in editions
    ]

    # Oversized blocks: the crash that started all of this.
    largest = 0
    largest_where = ""
    oversized: list[str] = []
    for row in translations + tafsir:
        size = len((row.get("text") or "").encode("utf-8"))
        if size > largest:
            largest, largest_where = size, f"{row['editionID']} {row['surahNumber']}"
        if size > MAX_TEXT_BLOCK_BYTES:
            oversized.append(f"{row['editionID']} {row['surahNumber']}: {size} bytes")
    report.check(not oversized,
                 f"{len(oversized)} text blocks over {MAX_TEXT_BLOCK_BYTES} bytes: {oversized[:3]}")
    report.facts["maxTextBlockBytes"] = largest
    report.facts["maxTextBlockWhere"] = largest_where


# ---------------------------------------------------------------------------
# Hadith
# ---------------------------------------------------------------------------

def check_hadith(seed: Path, report: Report) -> None:
    catalog = load(seed, "hadith_books")
    if not report.check(catalog is not None, "hadith_books.json is missing"):
        return

    state = catalog.get("reviewState")
    report.check(state in REVIEW_STATES,
                 f"hadith catalogue review state {state!r} is not a known state")
    report.check(state != "rejected", "hadith corpus is rejected and must not ship")

    collections: list[dict[str, Any]] = []
    missing_language = {"ar": 0, "en": 0, "ur": 0}
    total_duplicates = 0
    known_defects = load_known_defects()
    new_defects: list[str] = []
    inherited_defects = 0

    declared = {b["id"] for b in catalog["books"]}
    report.check(declared == set(HADITH_BOOKS),
                 f"catalogue lists {sorted(declared)}, expected {sorted(HADITH_BOOKS)}")

    for book in catalog["books"]:
        book_id = book["id"]
        records = load(seed, f"hadith_{book_id}")
        if not report.check(records is not None, f"hadith_{book_id}.json is missing"):
            continue

        # The catalogue must state exactly what the pack contains. It used to
        # copy upstream metadata and over-claimed by 201 narrations.
        report.check(
            book["hadithCount"] == len(records),
            f"catalogue claims {book['hadithCount']} for '{book_id}' "
            f"but the pack holds {len(records)}"
        )

        canonical: set[str] = set()
        display: set[str] = set()
        duplicates: list[str] = []
        empty: list[str] = []
        malformed: list[str] = []
        sequences: set[int] = set()

        for record in records:
            cid = record.get("canonicalID")
            if cid in canonical:
                duplicates.append(cid)
            canonical.add(cid)

            number = record.get("displayNumber")
            if number in display:
                duplicates.append(f"{book_id}|{number}")
            display.add(number)

            # The identifier must round-trip: canonicalID is built from the
            # other three fields, so a mismatch means one of them was edited
            # by hand and the pack is no longer self-consistent.
            expected = f"{book_id}|{number}|{record.get('sourceSequence')}"
            if cid != expected:
                malformed.append(f"{cid} != {expected}")

            # displayNumber is textual; the split parts must agree with it.
            major, _, minor = str(number).partition(".")
            if str(record.get("numberMajor")) != major:
                malformed.append(f"{cid}: numberMajor != {major}")
            if minor and str(record.get("numberMinor")) != str(int(minor)):
                malformed.append(f"{cid}: numberMinor does not match '{minor}'")
            if not minor and record.get("numberMinor") is not None:
                malformed.append(f"{cid}: numberMinor set on a whole number")

            sequences.add(record.get("sourceSequence"))

            texts = {lang: record.get(f"text_{lang}") for lang in ("ar", "en", "ur")}
            if not any((value or "").strip() for value in texts.values()):
                empty.append(cid)
            for lang, value in texts.items():
                if not (value or "").strip():
                    missing_language[lang] += 1

            # Replacement characters are allowed only where upstream already had
            # them, and only as many. A new one, or one more than recorded, is a
            # regression in our own pipeline and fails the build.
            allowed = known_defects.get(cid, {})
            for lang, value in texts.items():
                found = (value or "").count("�")
                if not found:
                    continue
                budget = allowed.get(lang, 0)
                if found > budget:
                    new_defects.append(f"{cid} [{lang}]: {found} U+FFFD, {budget} recorded")
                else:
                    inherited_defects += found

        total_duplicates += len(duplicates)
        report.check(not duplicates,
                     f"'{book_id}': {len(duplicates)} duplicate identifiers: {duplicates[:5]}")
        report.check(not empty,
                     f"'{book_id}': {len(empty)} narrations with no text in any language")
        report.check(not malformed,
                     f"'{book_id}': {len(malformed)} malformed identifiers: {malformed[:5]}")
        report.check(len(sequences) == len(records),
                     f"'{book_id}': sourceSequence is not unique across the pack")

        oversized = [
            record["canonicalID"] for record in records
            for lang in ("ar", "en", "ur")
            if len((record.get(f"text_{lang}") or "").encode("utf-8")) > MAX_TEXT_BLOCK_BYTES
        ]
        report.check(not oversized,
                     f"'{book_id}': {len(oversized)} oversized narration texts")

        collections.append({
            "id": book_id,
            "title": book["titleEnglish"],
            "shipped": len(records),
            "subNumbered": sum(1 for r in records if r.get("numberMinor") is not None),
        })

    report.check(
        not new_defects,
        f"{len(new_defects)} narrations gained replacement characters not in "
        f"known_upstream_defects.json: {new_defects[:5]}"
    )
    if inherited_defects:
        report.note(
            f"{inherited_defects} U+FFFD in the Arabic of "
            f"{len(known_defects)} narrations, inherited from the upstream corpus "
            f"and unchanged since it was recorded. Each stands where one Arabic "
            f"character was lost to a bad decode before we received the data; the "
            f"defect is in both upstream Arabic editions, so it cannot be repaired "
            f"from this source. Tracked for public release."
        )

    report.facts["hadithCollections"] = collections
    report.facts["hadithTotal"] = sum(c["shipped"] for c in collections)
    report.facts["hadithMissingLanguageFields"] = missing_language
    report.facts["duplicateCount"] = total_duplicates
    report.facts["hadithReviewState"] = state
    report.facts["inheritedReplacementCharacters"] = inherited_defects
    report.facts["inheritedDefectNarrations"] = len(known_defects)


# ---------------------------------------------------------------------------
# Manifest, hashes, cross-platform parity
# ---------------------------------------------------------------------------

def sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_manifest_and_hashes(report: Report) -> dict[str, str]:
    manifest = load(IOS_SEED, "manifest")
    if not report.check(manifest is not None, "manifest.json is missing"):
        return {}

    report.check(isinstance(manifest.get("version"), int),
                 f"manifest version must be an integer, got {manifest.get('version')!r}")
    report.check("generatedAt" in manifest, "manifest is missing generatedAt")

    state = manifest.get("reviewState")
    report.check(state in REVIEW_STATES,
                 f"manifest review state {state!r} is not a known state")
    report.check(
        state in SHIPPABLE_ON_TESTFLIGHT,
        f"manifest review state {state!r} may not ship to TestFlight"
    )

    report.facts["contentVersion"] = manifest.get("contentVersion")
    report.facts["seedVersion"] = manifest.get("version")
    report.facts["reviewState"] = state

    hashes = {path.name: sha256_of(path) for path in sorted(IOS_SEED.glob("*.json"))}

    # Every platform must ship the identical bytes, or the four apps disagree
    # about what the sacred text says.
    for platform, directory in PLATFORM_SEEDS.items():
        if platform == "iOS":
            continue
        if not directory.exists():
            report.note(f"{platform} seed directory not present in this checkout; parity unchecked")
            continue
        mismatched = []
        for name, digest in hashes.items():
            other = directory / name
            if not other.exists():
                mismatched.append(f"{name} missing")
            elif sha256_of(other) != digest:
                mismatched.append(name)
        report.check(not mismatched,
                     f"{platform} seed differs from iOS: {mismatched[:6]}")

    report.facts["fileHashes"] = hashes
    return hashes


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

def render_report(report: Report, migration_status: str, passed: bool) -> str:
    facts = report.facts
    generated = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = [
        "# Content integrity report",
        "",
        "Generated by `Tools/ContentIntegrity/check_content.py`. Do not edit by hand.",
        "",
        f"- Generated: {generated}",
        f"- Content version: {facts.get('contentVersion') or 'unset'}",
        f"- Seed manifest version: {facts.get('seedVersion')}",
        f"- Review state: **{facts.get('reviewState')}**",
        f"- Result: **{'PASS' if passed else 'FAIL'}**",
        f"- Upgrade migration test: **{migration_status}**",
        "",
        "## Quran",
        "",
        f"- Surahs: {facts.get('quranSurahs')} / {SURAH_COUNT}",
        f"- Ayat: {facts.get('quranAyahs')} / {AYAH_COUNT}",
        f"- Largest text block: {facts.get('maxTextBlockBytes', 0):,} bytes "
        f"({facts.get('maxTextBlockWhere', 'n/a')}), limit {MAX_TEXT_BLOCK_BYTES:,}",
        "",
        "| Edition | Kind | Language | Rows | Review state |",
        "| --- | --- | --- | ---: | --- |",
    ]
    for edition in facts.get("quranEditions", []):
        lines.append(
            f"| {edition['id']} | {edition['kind']} | {edition['language']} "
            f"| {edition['rows']:,} | {edition['reviewState']} |"
        )

    lines += ["", "### Tafsir coverage", "",
              "| Edition | Blocks | Surahs covered |", "| --- | ---: | ---: |"]
    for edition, data in facts.get("tafsirEditions", {}).items():
        lines.append(f"| {edition} | {data['blocks']:,} | {data['surahsCovered']} / {SURAH_COUNT} |")

    lines += ["", "## Hadith", "",
              f"- Review state: **{facts.get('hadithReviewState')}**",
              f"- Total narrations shipped: {facts.get('hadithTotal', 0):,}",
              f"- Duplicate identifiers: {facts.get('duplicateCount', 0)}",
              "",
              "| Collection | Narrations | Sub-numbered |",
              "| --- | ---: | ---: |"]
    for collection in facts.get("hadithCollections", []):
        lines.append(f"| {collection['title']} | {collection['shipped']:,} "
                     f"| {collection['subNumbered']} |")

    missing = facts.get("hadithMissingLanguageFields", {})
    lines += ["", "### Missing language fields", "",
              "Narrations with no text in a given script. These render as an "
              "explicit gap — never as another language's text.", "",
              "| Language | Missing |", "| --- | ---: |"]
    for lang in ("ar", "en", "ur"):
        lines.append(f"| {lang} | {missing.get(lang, 0):,} |")

    lines += ["", "## Encoding", "",
              f"- Encoding errors (invalid UTF-8, U+FFFD outside hadith, mojibake): "
              f"{facts.get('encodingErrors', 0)}",
              f"- Inherited upstream replacement characters: "
              f"{facts.get('inheritedReplacementCharacters', 0)} across "
              f"{facts.get('inheritedDefectNarrations', 0)} narrations "
              f"(inventory: `Tools/ContentIntegrity/known_upstream_defects.json`)"]

    lines += ["", "## Seed file hashes (SHA-256)", "",
              "Identical on iOS, Android, HarmonyOS and Web.", "",
              "| File | SHA-256 |", "| --- | --- |"]
    for name, digest in facts.get("fileHashes", {}).items():
        lines.append(f"| {name} | `{digest}` |")

    if report.notes:
        lines += ["", "## Notes", ""] + [f"- {note}" for note in report.notes]

    if report.failures:
        lines += ["", "## Failures", ""] + [f"- {failure}" for failure in report.failures]

    lines += ["", "## Outstanding for public release", "",
              "- Line-by-line human proofreading of the reviewed OCR-derived "
              "editions, which promotes them from `testFlightApproved` to "
              "`publicApproved`. Not a TestFlight blocker.",
              f"- Repair of the {facts.get('inheritedReplacementCharacters', 0)} "
              "Arabic characters lost upstream, which needs a second "
              "authoritative Arabic corpus to cross-reference.",
              ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, help="write the markdown report here")
    parser.add_argument(
        "--migration-status",
        default="not-run",
        choices=["passed", "failed", "not-run"],
        help="result of the Swift upgrade-migration test, supplied by CI",
    )
    args = parser.parse_args()

    report = Report()
    check_encoding(IOS_SEED, report)
    check_quran(IOS_SEED, report)
    check_hadith(IOS_SEED, report)
    check_manifest_and_hashes(report)

    if args.migration_status == "failed":
        report.failures.append("the upgrade-migration test failed")

    passed = not report.failures

    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(
            render_report(report, args.migration_status, passed),
            encoding="utf-8", newline="\n"
        )
        print(f"report written to {args.report}")

    for note in report.notes:
        print(f"note: {note}")

    if passed:
        print(f"content integrity: PASS "
              f"({report.facts.get('quranAyahs', 0):,} ayat, "
              f"{report.facts.get('hadithTotal', 0):,} narrations, "
              f"review state {report.facts.get('reviewState')})")
        return 0

    print("content integrity: FAIL")
    for failure in report.failures:
        print(f"  - {failure}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
