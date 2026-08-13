#!/usr/bin/env python3
"""Export, translate, validate, and promote Hadith translations safely.

The seed corpus is never edited by ``export`` or ``translate``. Machine output
lives in a JSONL staging file with ``machineProvisional`` review state. Only
``promote`` can modify seed JSON, and it refuses every row that is incomplete,
stale, malformed, or not explicitly marked ``humanVerified`` with reviewer and
review timestamp. Arabic source text is hash-bound and is never overwritten.

An OpenAI-compatible endpoint may be used for the first translation pass:

    DI_TRANSLATE_URL=https://.../v1/chat/completions
    DI_TRANSLATE_KEY=...
    DI_TRANSLATE_MODEL=...
    python Tools/Hadith/translation_gate.py translate --queue queue.jsonl \
        --output translations.jsonl

This is a preparation tool, not a claim that machine output is verified.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
SEED = ROOT / "DarulIrfanApp" / "Resources" / "SeedData"
HADITH_FILES = sorted(
    p for p in SEED.glob("hadith_*.json")
    if p.name not in {"hadith_books.json", "hadith_narrators.json"}
)
NARRATORS = SEED / "hadith_narrators.json"
BOOKS = SEED / "hadith_books.json"
ARABIC = re.compile(r"[\u0600-\u06ff]")
LATIN = re.compile(r"[A-Za-z]")
CONTROL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")
HTML = re.compile(r"<[^>]+>")
PLACEHOLDER = re.compile(
    r"\b(?:todo|tbd|missing|translation unavailable|no translation)\b",
    re.IGNORECASE,
)
APPROVED = "humanVerified"


def text(value: object) -> str:
    return value.strip() if isinstance(value, str) else ""


def digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def queue_rows():
    """Yield one stable work item for every missing translation."""
    for path in HADITH_FILES:
        for row in load(path):
            missing = [
                lang for lang, key in (("English", "text_en"), ("Urdu", "text_ur"))
                if not text(row.get(key))
            ]
            if not missing:
                continue
            candidates = (
                ("Arabic", text(row.get("text_ar"))),
                ("English", text(row.get("text_en"))),
                ("Urdu", text(row.get("text_ur"))),
            )
            source_language, source = next(((lang, value) for lang, value in candidates if value), (None, ""))
            # Never ask a translator to infer content from an empty source.
            if not source:
                continue
            yield {
                "kind": "hadith",
                "id": row["canonicalID"],
                "bookID": row["bookID"],
                "displayNumber": row["displayNumber"],
                "sourceBook": row.get("sourceBook"),
                "sourceHadith": row.get("sourceHadith"),
                "sourceLanguage": source_language,
                "sourceText": source,
                "sourceHash": digest(source),
                "needs": missing,
            }
    catalog = load(BOOKS)
    for book in catalog.get("books", []):
        for section in book.get("sections") or []:
            missing = []
            if not text(section.get("titleEnglish")):
                missing.append("English")
            if not text(section.get("titleUrdu")):
                missing.append("Urdu")
            if not missing:
                continue
            candidates = (
                ("Arabic", text(section.get("titleArabic"))),
                ("English", text(section.get("titleEnglish"))),
                ("Urdu", text(section.get("titleUrdu"))),
            )
            source_language, source = next(((lang, value) for lang, value in candidates if value), (None, ""))
            # Never ask a translator to infer a title from an empty source.
            if not source:
                continue
            yield {
                "kind": "section",
                "id": f"{book['id']}:{section['number']}",
                "bookID": book["id"],
                "sectionNumber": section["number"],
                "sourceLanguage": source_language,
                "sourceText": source,
                "sourceHash": digest(source),
                "needs": missing,
            }
    for narrator in load(NARRATORS):
        for index, appraisal in enumerate(narrator.get("appraisals") or []):
            missing = [
                lang for lang, key in (("English", "textEnglish"), ("Urdu", "textUrdu"))
                if not text(appraisal.get(key))
            ]
            if not missing:
                continue
            candidates = (
                ("Arabic", text(appraisal.get("textArabic"))),
                ("English", text(appraisal.get("textEnglish"))),
                ("Urdu", text(appraisal.get("textUrdu"))),
            )
            source_language, source = next(((lang, value) for lang, value in candidates if value), (None, ""))
            # A legacy parser artifact may contain a citation/label but no
            # appraisal body. Quarantine it; translating an empty source could
            # invent a scholarly judgement.
            if not source:
                continue
            yield {
                "kind": "appraisal",
                "id": f"{narrator['id']}:{index}",
                "narratorID": narrator["id"],
                "appraisalIndex": index,
                "scholarEnglish": appraisal.get("scholar"),
                "scholarArabic": appraisal.get("scholarArabic"),
                "sourceLanguage": source_language,
                "sourceText": source,
                "sourceHash": digest(source),
                "needs": missing,
            }


def source_less_appraisal_count() -> int:
    """Legacy appraisal-shaped rows that have no source body in any language."""
    return sum(
        1
        for narrator in load(NARRATORS)
        for appraisal in narrator.get("appraisals") or []
        if not any(text(appraisal.get(key)) for key in ("textArabic", "textEnglish", "textUrdu"))
    )


def write_jsonl(path: Path, rows) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
            count += 1
    return count


def read_jsonl(path: Path) -> list[dict]:
    rows = []
    with path.open(encoding="utf-8-sig") as handle:
        for number, line in enumerate(handle, 1):
            if line.strip():
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError as error:
                    raise SystemExit(f"{path}:{number}: invalid JSON: {error}")
    return rows


def response_errors(item: dict, response: dict) -> list[str]:
    prefix = f"{item['kind']} {item['id']}"
    errors = []
    if response.get("kind") != item["kind"] or str(response.get("id")) != str(item["id"]):
        return [f"{prefix}: identifier mismatch"]
    if response.get("sourceHash") != item["sourceHash"]:
        errors.append(f"{prefix}: stale or incorrect sourceHash")
    if response.get("reviewState") != APPROVED:
        errors.append(f"{prefix}: reviewState must be {APPROVED}")
    if not text(response.get("reviewer")) or not text(response.get("reviewedAt")):
        errors.append(f"{prefix}: reviewer and reviewedAt are required")
    for lang in item["needs"]:
        key = f"text{lang}"
        value = text(response.get(key))
        if not value:
            errors.append(f"{prefix}: {key} is empty")
            continue
        if value == item["sourceText"]:
            errors.append(f"{prefix}: {key} repeats the source verbatim")
        if "\ufffd" in value or CONTROL.search(value) or HTML.search(value) or PLACEHOLDER.search(value):
            errors.append(f"{prefix}: {key} contains invalid markup, controls, or placeholder text")
        if lang == "English" and not LATIN.search(value):
            errors.append(f"{prefix}: textEnglish has no Latin-script text")
        if lang == "Urdu" and not ARABIC.search(value):
            errors.append(f"{prefix}: textUrdu has no Urdu/Arabic-script text")
    return errors


def validate(response_path: Path, require_complete: bool = True):
    queue = list(queue_rows())
    responses = read_jsonl(response_path)
    by_key = {}
    duplicates = []
    for row in responses:
        key = (row.get("kind"), str(row.get("id")))
        if key in by_key:
            duplicates.append(f"duplicate response {key[0]} {key[1]}")
        by_key[key] = row
    errors = list(duplicates)
    approved = {}
    for item in queue:
        key = (item["kind"], str(item["id"]))
        response = by_key.get(key)
        if response is None:
            if require_complete:
                errors.append(f"{item['kind']} {item['id']}: response missing")
            continue
        row_errors = response_errors(item, response)
        errors.extend(row_errors)
        if not row_errors:
            approved[key] = response
    unknown = set(by_key) - {(i["kind"], str(i["id"])) for i in queue}
    errors.extend(f"unknown response {k[0]} {k[1]}" for k in sorted(unknown))
    return queue, approved, errors


def endpoint_translate(item: dict, url: str, key: str, model: str) -> dict:
    targets = " and ".join(item["needs"])
    content_kind = {
        "hadith": "a hadith narration",
        "appraisal": "a classical narrator appraisal (jarh wa ta\u02bfdi\u0304l)",
        "section": "a kitab title from a hadith collection",
    }[item["kind"]]
    prompt = f"""Translate the following {item['sourceLanguage']} Islamic source text into {targets}.
It is {content_kind}.
Preserve names, honorifics, technical grading terminology, negation, and meaning exactly.
Do not summarize, explain, add a ruling, add citations, or output the source text.
Return only a JSON object with exactly the requested keys: {', '.join('text' + x for x in item['needs'])}.

SOURCE:
{item['sourceText']}"""
    payload = json.dumps({
        "model": model,
        "temperature": 0,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": "You are a careful Islamic-text translator. Output valid JSON only."},
            {"role": "user", "content": prompt},
        ],
    }).encode("utf-8")
    request = urllib.request.Request(
        url, data=payload,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        body = json.loads(response.read().decode("utf-8"))
    translated = json.loads(body["choices"][0]["message"]["content"])
    return {
        "kind": item["kind"], "id": item["id"], "sourceHash": item["sourceHash"],
        **translated,
        "reviewState": "machineProvisional",
        "translationModel": model,
        "translatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
    }


def promote(response_path: Path):
    queue, approved, errors = validate(response_path, require_complete=True)
    if errors:
        print(f"PROMOTION REFUSED: {len(errors)} validation errors", file=sys.stderr)
        for error in errors[:100]:
            print("-", error, file=sys.stderr)
        raise SystemExit(2)

    original_arabic = {}
    for path in HADITH_FILES:
        rows = load(path)
        for row in rows:
            original_arabic[row["canonicalID"]] = row.get("text_ar")
            response = approved.get(("hadith", row["canonicalID"]))
            if not response:
                continue
            if not text(row.get("text_en")):
                row["text_en"] = response["textEnglish"]
                row["englishSource"] = "reviewedTranslation"
                row["englishReviewState"] = APPROVED
            if not text(row.get("text_ur")):
                row["text_ur"] = response["textUrdu"]
                row["urduSource"] = "reviewedTranslation"
                row["urduReviewState"] = APPROVED
        path.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    narrators = load(NARRATORS)
    for narrator in narrators:
        for index, appraisal in enumerate(narrator.get("appraisals") or []):
            response = approved.get(("appraisal", f"{narrator['id']}:{index}"))
            if not response:
                continue
            if not text(appraisal.get("textEnglish")):
                appraisal["textEnglish"] = response["textEnglish"]
            if not text(appraisal.get("textUrdu")):
                appraisal["textUrdu"] = response["textUrdu"]
            appraisal["translationSource"] = "reviewedTranslation"
            appraisal["translationReviewState"] = APPROVED
    NARRATORS.write_text(json.dumps(narrators, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    catalog = load(BOOKS)
    for book in catalog.get("books", []):
        for section in book.get("sections") or []:
            response = approved.get(("section", f"{book['id']}:{section['number']}"))
            if not response:
                continue
            if not text(section.get("titleEnglish")):
                section["titleEnglish"] = response["textEnglish"]
            if not text(section.get("titleUrdu")):
                section["titleUrdu"] = response["textUrdu"]
            section["translationSource"] = "reviewedTranslation"
            section["translationReviewState"] = APPROVED
    BOOKS.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # Sacred-source invariant: promotion may fill translations only.
    for path in HADITH_FILES:
        for row in load(path):
            if row.get("text_ar") != original_arabic[row["canonicalID"]]:
                raise SystemExit(f"Arabic mutation detected after promotion: {row['canonicalID']}")
    print(f"promoted {len(approved):,} fully reviewed translation records")


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("audit")
    export = sub.add_parser("export")
    export.add_argument("--output", type=Path, required=True)
    translate = sub.add_parser("translate")
    translate.add_argument("--queue", type=Path, required=True)
    translate.add_argument("--output", type=Path, required=True)
    translate.add_argument("--limit", type=int)
    check = sub.add_parser("validate")
    check.add_argument("--responses", type=Path, required=True)
    check.add_argument("--allow-partial", action="store_true")
    promote_parser = sub.add_parser("promote")
    promote_parser.add_argument("--responses", type=Path, required=True)
    args = parser.parse_args()

    if args.command == "audit":
        rows = list(queue_rows())
        counts = {}
        for row in rows:
            for lang in row["needs"]:
                counts[f"{row['kind']}.{lang}"] = counts.get(f"{row['kind']}.{lang}", 0) + 1
        print(json.dumps({
            "queueRecords": len(rows),
            "missing": counts,
            "quarantinedSourceLessAppraisals": source_less_appraisal_count(),
        }, indent=2))
    elif args.command == "export":
        print(f"exported {write_jsonl(args.output, queue_rows()):,} records to {args.output}")
    elif args.command == "translate":
        url = os.environ.get("DI_TRANSLATE_URL", "")
        key = os.environ.get("DI_TRANSLATE_KEY", "")
        model = os.environ.get("DI_TRANSLATE_MODEL", "")
        if not (url and key and model):
            raise SystemExit("DI_TRANSLATE_URL, DI_TRANSLATE_KEY, and DI_TRANSLATE_MODEL are required")
        existing = read_jsonl(args.output) if args.output.exists() else []
        done = {(r.get("kind"), str(r.get("id"))) for r in existing}
        pending = [r for r in read_jsonl(args.queue) if (r["kind"], str(r["id"])) not in done]
        if args.limit is not None:
            pending = pending[:args.limit]
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("a", encoding="utf-8", newline="\n") as handle:
            for number, item in enumerate(pending, 1):
                result = endpoint_translate(item, url, key, model)
                handle.write(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n")
                handle.flush()
                print(f"{number}/{len(pending)} {item['kind']} {item['id']}")
    elif args.command == "validate":
        queue, approved, errors = validate(args.responses, not args.allow_partial)
        print(json.dumps({"required": len(queue), "approved": len(approved), "errors": len(errors)}, indent=2))
        for error in errors[:100]:
            print("-", error)
        if errors:
            raise SystemExit(2)
    elif args.command == "promote":
        promote(args.responses)


if __name__ == "__main__":
    main()
