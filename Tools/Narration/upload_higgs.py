#!/usr/bin/env python3
"""Upload the Higgs Urdu narrations to R2, and publish them once approved.

Files go up as they are made, under the same keys the apps already read
(audio/quran/<edition>/<kind>/<name>.mp3), replacing the withdrawn OmniVoice
Urdu ones. The manifest - what the apps offer - is rewritten only while
/mnt/sata1tb/di-voices/PUBLISH exists, which is created after the owner has
heard a first batch. It lists the Urdu editions only (English is on hold) and
credits the voice as the Higgs licence asks ("Boson AI's Higgs Audio").

    upload_higgs.py
"""

from __future__ import annotations

import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import boto3

V = Path("/mnt/sata1tb/di-voices")
ROOT = V / "quran-higgs"
FLAGGED = V / "higgs_flagged.json"
PUBLISH = V / "PUBLISH"
SENT = V / "higgs_uploaded.json"
BUCKET, PREFIX = "darul-irfan-media", "audio/quran/"
VOICES = {"ur": {"name": "Shamshad Ali Khan, created with Boson AI's Higgs Audio"}}


def main() -> int:
    c = {}
    for line in (Path.home() / ".config/darul-irfan/r2.env").read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            c[key.strip()] = value.strip()
    s3 = boto3.client("s3", endpoint_url=f"https://{c['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com",
                      aws_access_key_id=c["R2_ACCESS_KEY_ID"], aws_secret_access_key=c["R2_SECRET_ACCESS_KEY"],
                      region_name="auto")
    flagged = set(json.loads(FLAGGED.read_text())) if FLAGGED.exists() else set()
    sent = json.loads(SENT.read_text()) if SENT.exists() else {}
    local = sorted(ROOT.rglob("*.mp3"))
    # A file is (re)sent when it is new or was remade since it was sent.
    todo = [p for p in local if str(p.relative_to(ROOT).with_suffix("")) not in flagged
            and sent.get(str(p.relative_to(ROOT))) != p.stat().st_mtime]

    def send(path: Path) -> None:
        s3.upload_file(str(path), BUCKET, PREFIX + str(path.relative_to(ROOT)),
                       ExtraArgs={"ContentType": "audio/mpeg"})

    with ThreadPoolExecutor(max_workers=16) as pool:
        list(pool.map(send, todo))
    for path in todo:
        sent[str(path.relative_to(ROOT))] = path.stat().st_mtime
    SENT.write_text(json.dumps(sent))

    if not PUBLISH.exists():
        print(f"uploaded {len(todo)} files; not published (no PUBLISH file)")
        return 0
    editions: dict[str, dict[str, list[str]]] = {}
    for path in local:
        relative = path.relative_to(ROOT)
        if str(relative.with_suffix("")) in flagged:
            continue
        editions.setdefault(relative.parts[0], {}).setdefault(relative.parts[1], []).append(path.stem)
    for kinds in editions.values():
        for names in kinds.values():
            names.sort()
    count = sum(len(n) for k in editions.values() for n in k.values())
    manifest = {"version": count, "voices": VOICES, "editions": editions}
    s3.put_object(Bucket=BUCKET, Key=PREFIX + "manifest.json", Body=json.dumps(manifest, separators=(",", ":")).encode(),
                  ContentType="application/json")
    print(f"uploaded {len(todo)} files; manifest lists {count} narrations, {len(flagged)} held back")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
