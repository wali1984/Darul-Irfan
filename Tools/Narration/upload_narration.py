#!/usr/bin/env python3
"""Upload new narrations from amd to R2 and rewrite the manifest the apps read.

Runs on amd every 30 minutes while the narration is being made (and once after
it ends). Uses R2's S3 API with a bucket-scoped key kept in
~/.config/darul-irfan/r2.env (R2_ACCOUNT_ID, R2_ACCESS_KEY_ID,
R2_SECRET_ACCESS_KEY), chmod 600. Only files not yet in the bucket are sent;
a flagged file (length far from its text after three tries) is held back.

    upload_narration.py          upload what is new, then the manifest
"""

from __future__ import annotations

import json
import os
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import boto3

ROOT = Path("/mnt/sata1tb/di-tts/quran")
FLAGGED = Path("/mnt/sata1tb/di-tts/flagged.json")
BUCKET = "darul-irfan-media"
PREFIX = "audio/quran/"
VOICES = {"ur": {"name": "Shamshad Ali Khan"}, "en": {"name": "Ibrahim Walk"}}


def credentials() -> dict[str, str]:
    values = {}
    for line in (Path.home() / ".config/darul-irfan/r2.env").read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"')
    return values


def main() -> int:
    c = credentials()
    s3 = boto3.client("s3", endpoint_url=f"https://{c['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com",
                      aws_access_key_id=c["R2_ACCESS_KEY_ID"], aws_secret_access_key=c["R2_SECRET_ACCESS_KEY"],
                      region_name="auto")
    present = set()
    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Prefix=PREFIX):
        present.update(item["Key"] for item in page.get("Contents", []))
    flagged = set(json.loads(FLAGGED.read_text())) if FLAGGED.exists() else set()

    local = sorted(p for p in ROOT.rglob("*.mp3"))
    todo = [p for p in local if PREFIX + str(p.relative_to(ROOT)).replace(os.sep, "/") not in present
            and str(p.relative_to(ROOT).with_suffix("")).replace(os.sep, "/") not in flagged]

    def send(path: Path) -> None:
        key = PREFIX + str(path.relative_to(ROOT)).replace(os.sep, "/")
        s3.upload_file(str(path), BUCKET, key, ExtraArgs={"ContentType": "audio/mpeg"})

    with ThreadPoolExecutor(max_workers=16) as pool:
        list(pool.map(send, todo))

    editions: dict[str, dict[str, list[str]]] = {}
    for path in local:
        relative = path.relative_to(ROOT)
        if str(relative.with_suffix("")).replace(os.sep, "/") in flagged:
            continue
        edition, kind = relative.parts[0], relative.parts[1]
        editions.setdefault(edition, {}).setdefault(kind, []).append(path.stem)
    for kinds in editions.values():
        for names in kinds.values():
            names.sort()
    manifest = {"version": sum(len(n) for k in editions.values() for n in k.values()), "voices": VOICES, "editions": editions}
    s3.put_object(Bucket=BUCKET, Key=PREFIX + "manifest.json", Body=json.dumps(manifest, separators=(",", ":")).encode(),
                  ContentType="application/json")
    print(f"uploaded {len(todo)} new files; manifest lists {manifest['version']} narrations, {len(flagged)} held back")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
