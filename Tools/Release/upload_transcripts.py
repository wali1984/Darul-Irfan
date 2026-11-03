#!/usr/bin/env python3
"""Upload the bayan transcripts to R2, where GET /v1/transcripts/<id> serves them.

Each transcript is Darul Irfan/pw/transcript-pipeline/out/<mediaId>.json.gz,
one per bayan, named by its id in media_items.json. Only files that pass the
schema check and name a catalogue bayan are sent; a file whose bytes already
match the bucket's copy (R2's ETag is the MD5 of a single-part upload) is
skipped, so a re-run sends only what changed. Nothing is deleted.

The R2 credentials are the "S3 clients" ones in `Darul Irfan/cloudflare.md`
(outside git), read as testflight.py reads them. They
are never printed.

usage:
  upload_transcripts.py --dry-run [folder]   check every file and say what would be sent
  upload_transcripts.py [folder]             upload what is new or changed
"""

from __future__ import annotations

import gzip
import hashlib
import json
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def first_existing(*candidates: Path) -> Path:
    return next((c for c in candidates if c.exists()), candidates[0])


# The repository is Darul Irfan/DarulIrfan-iOS, or a worktree under Darul Irfan/pw.
R2_CONFIG = first_existing(REPO.parent / "cloudflare.md", REPO.parent.parent / "cloudflare.md")
DEFAULT_FOLDER = first_existing(REPO.parent / "transcript-pipeline" / "out",
                                REPO.parent / "pw" / "transcript-pipeline" / "out")
CATALOGUE = REPO / "DarulIrfanApp" / "Resources" / "SeedData" / "media_items.json"
BUCKET, PREFIX = "darul-irfan-media", "transcripts/"
ID = re.compile(r"^[a-z0-9][a-z0-9_-]{0,159}$")
KINDS = {"speech", "quran", "hadith", "dua", "arabicUnverified"}
QURAN_REF = re.compile(r"^\d{1,3}:\d{1,3}$")


def r2():
    """The media bucket, with the "credentials for S3 clients" in cloudflare.md."""
    import boto3
    lines = [line.strip() for line in R2_CONFIG.read_text(encoding="utf-8").splitlines()]

    def after(label: str) -> str:
        return next(line for line in lines[lines.index(label) + 1:] if line)

    endpoint = next(line for line in lines if line.startswith("https://") and ".r2.cloudflarestorage.com" in line)
    return boto3.client("s3", endpoint_url=endpoint, aws_access_key_id=after("Access Key ID"),
                        aws_secret_access_key=after("Secret Access Key"), region_name="auto")


def problem(path: Path, catalogue: set[str]) -> str | None:
    """Why this file must not be sent, or None when it is a valid transcript."""
    media_id = path.name[: -len(".json.gz")]
    if not ID.match(media_id):
        return "name is not a media id"
    if media_id not in catalogue:
        return "no bayan with this id in media_items.json"
    try:
        document = json.loads(gzip.decompress(path.read_bytes()))
    except (OSError, ValueError) as error:
        return f"unreadable ({error.__class__.__name__})"
    if document.get("id") != media_id:
        return "its id differs from its name"
    segments = document.get("segments")
    if not isinstance(segments, list) or not segments:
        return "no segments"
    for number, segment in enumerate(segments):
        kind = segment.get("kind")
        if kind not in KINDS:
            return f"segment {number}: unknown kind {kind!r}"
        if not isinstance(segment.get("s"), (int, float)) or not isinstance(segment.get("e"), (int, float)):
            return f"segment {number}: no timing"
        if kind != "arabicUnverified" and not isinstance(segment.get("t"), str):
            return f"segment {number}: no text"
        if kind == "quran" and not QURAN_REF.match(str(segment.get("ref", ""))):
            return f"segment {number}: Qur'an line without an S:A reference"
    return None


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    args = sys.argv[1:]
    dry_run = "--dry-run" in args
    folders = [a for a in args if a != "--dry-run"]
    # A mistyped flag (--dryrun) must never be taken for a folder and upload.
    if any(a.startswith("-") for a in folders) or len(folders) > 1:
        print("usage: upload_transcripts.py [--dry-run] [folder]")
        return 2
    folder = Path(folders[0]) if folders else DEFAULT_FOLDER
    catalogue = {item["id"] for item in json.loads(CATALOGUE.read_text(encoding="utf-8"))}
    files = sorted(folder.glob("*.json.gz"))
    good: list[Path] = []
    for path in files:
        reason = problem(path, catalogue)
        if reason:
            print(f"held back {path.name}: {reason}")
        else:
            good.append(path)
    print(f"{len(good)} of {len(files)} transcripts are valid")
    if dry_run or not good:
        return 0 if len(good) == len(files) else 1

    bucket = r2()
    present: dict[str, str] = {}
    for page in bucket.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Prefix=PREFIX):
        for item in page.get("Contents", []):
            present[item["Key"]] = item["ETag"].strip('"')
    todo = [p for p in good if present.get(PREFIX + p.name) != hashlib.md5(p.read_bytes()).hexdigest()]

    def send(path: Path) -> None:
        bucket.put_object(Bucket=BUCKET, Key=PREFIX + path.name, Body=path.read_bytes(),
                          ContentType="application/gzip", CacheControl="public, max-age=86400")

    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(send, todo))
    print(f"uploaded {len(todo)} new or changed transcripts; {len(good) - len(todo)} were already current")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
