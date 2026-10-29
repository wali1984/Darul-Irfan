#!/usr/bin/env python3
"""Upload the Higgs Urdu narrations to R2, and publish them once approved.

Files go up under the same keys the apps already read
(audio/quran/<edition>/<kind>/<name>.mp3) - but only once Whisper has heard
the file say exactly its text (verify_narration.py, for that very file). The
owner found an ayah with words the voice made up (112:4); nothing goes out
unchecked since. What was already live stays live until its checked
replacement is ready (owner, 2026-10-28). The manifest - what the apps offer - is rewritten only while
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
PUBLISH = V / "PUBLISH"
SENT = V / "higgs_uploaded.json"
BUCKET, PREFIX = "darul-irfan-media", "audio/quran/"
# The apps keep played files under a folder named from this; a new revision
# mark makes every phone fetch the corrected files instead of its copies.
VOICES = {"ur": {"name": "Shamshad Ali Khan, created with Boson AI's Higgs Audio · rev 2"}}
LISTED = V / "higgs_listed.json"


def passed(relative: Path, path: Path) -> bool:
    """Whisper heard this exact file read its text."""
    results = VERIFIED.get(relative.parts[1], {})
    result = results.get(str(relative.with_suffix("")))
    return bool(result) and not result["flag"] and result.get("mtime") == path.stat().st_mtime


VERIFIED = {kind: json.loads((V / f"verify_{kind}.json").read_text(encoding="utf-8"))
            for kind in ("translation", "tafsir") if (V / f"verify_{kind}.json").exists()}


def main() -> int:
    # 2026-10-29: held while the Urdu translation is set to the 2020 print, so the
    # first rev-2 publish carries the re-made ayat (phones cache by voice tag).
    if (V / "HOLD_UPLOAD").exists():
        print("upload held: HOLD_UPLOAD present")
        return 0
    c = {}
    for line in (Path.home() / ".config/darul-irfan/r2.env").read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            c[key.strip()] = value.strip()
    s3 = boto3.client("s3", endpoint_url=f"https://{c['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com",
                      aws_access_key_id=c["R2_ACCESS_KEY_ID"], aws_secret_access_key=c["R2_SECRET_ACCESS_KEY"],
                      region_name="auto")
    sent = json.loads(SENT.read_text()) if SENT.exists() else {}
    local = [p for p in sorted(ROOT.rglob("*.mp3")) if ".part" not in p.name]
    # Listed in the apps: what was live before the check began, and every file
    # that has passed it since.
    listed = set(json.loads(LISTED.read_text())) if LISTED.exists() else set()
    # A file is (re)sent when it passed the check and is new or remade.
    todo = [p for p in local if passed(p.relative_to(ROOT), p) and sent.get(str(p.relative_to(ROOT))) != p.stat().st_mtime]

    def send(path: Path) -> None:
        s3.upload_file(str(path), BUCKET, PREFIX + str(path.relative_to(ROOT)),
                       ExtraArgs={"ContentType": "audio/mpeg"})

    with ThreadPoolExecutor(max_workers=16) as pool:
        list(pool.map(send, todo))
    for path in todo:
        sent[str(path.relative_to(ROOT))] = path.stat().st_mtime
        listed.add(str(path.relative_to(ROOT).with_suffix("")))
    SENT.write_text(json.dumps(sent))
    LISTED.write_text(json.dumps(sorted(listed)))

    if not PUBLISH.exists():
        print(f"uploaded {len(todo)} files; not published (no PUBLISH file)")
        return 0
    editions: dict[str, dict[str, list[str]]] = {}
    for name in sorted(listed):
        edition, kind, stem = name.split("/")
        editions.setdefault(edition, {}).setdefault(kind, []).append(stem)
    for kinds in editions.values():
        for names in kinds.values():
            names.sort()
    count = sum(len(n) for k in editions.values() for n in k.values())
    manifest = {"version": count, "voices": VOICES, "editions": editions}
    s3.put_object(Bucket=BUCKET, Key=PREFIX + "manifest.json", Body=json.dumps(manifest, separators=(",", ":")).encode(),
                  ContentType="application/json")
    print(f"uploaded {len(todo)} checked files; manifest lists {count} narrations")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
