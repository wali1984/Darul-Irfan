"""Copy the iOS seed to Android, HarmonyOS and Web, and bump the manifest once.

Content fixes are made in the iOS seed (DarulIrfanApp/Resources/SeedData). A
release then copies every seed file that differs to the other three platforms,
byte for byte, raises `manifest.json`'s version by one on all four, sets
`generatedAt`, and checks that the four folders are identical, which is what
Tools/ContentIntegrity/check_content.py requires.

    python Tools/Release/sync_seeds.py            report what differs
    python Tools/Release/sync_seeds.py --write    copy, bump, check
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

IOS = Path(__file__).resolve().parents[2]
ROOT = IOS.parent
SEEDS = {
    "iOS": IOS / "DarulIrfanApp/Resources/SeedData",
    "Android": ROOT / "DarulIrfanAndroid/app/src/main/assets/seed",
    "HarmonyOS": ROOT / "DarulIrfanHarmony/entry/src/main/resources/rawfile/seed",
    "Web": ROOT / "DarulIrfanWeb/content",
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def differing() -> dict[str, list[str]]:
    source = SEEDS["iOS"]
    names = sorted(p.name for p in source.iterdir() if p.is_file() and p.name != "manifest.json")
    out = {}
    for platform, folder in SEEDS.items():
        if platform == "iOS":
            continue
        out[platform] = [name for name in names
                         if not (folder / name).exists() or digest(folder / name) != digest(source / name)]
        extra = sorted(p.name for p in folder.iterdir() if p.is_file() and not (source / p.name).exists())
        if extra:
            print(f"{platform} has files the iOS seed does not: {extra} (left alone)")
    return out


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    changes = differing()
    for platform, names in changes.items():
        print(f"{platform}: {len(names)} file(s) differ" + (f": {', '.join(names)}" if names else ""))
    if "--write" not in sys.argv:
        print("report only; pass --write to copy and bump the manifest")
        return 0
    source = SEEDS["iOS"]
    for platform, names in changes.items():
        for name in names:
            (SEEDS[platform] / name).write_bytes((source / name).read_bytes())
    versions = {json.loads((folder / "manifest.json").read_text(encoding="utf-8"))["version"] for folder in SEEDS.values()}
    version = max(versions) + 1
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    raw = (source / "manifest.json").read_text(encoding="utf-8")
    raw = re.sub(r'"version":\s*\d+', f'"version": {version}', raw, count=1)
    raw = re.sub(r'"generatedAt":\s*"[^"]*"', f'"generatedAt": "{stamp}"', raw, count=1)
    for folder in SEEDS.values():
        (folder / "manifest.json").write_text(raw, encoding="utf-8", newline="")
    left = {platform: names for platform, names in differing().items() if names}
    manifests = {digest(folder / "manifest.json") for folder in SEEDS.values()}
    if left or len(manifests) != 1:
        print(f"NOT identical after the copy: {left}")
        return 1
    print(f"copied; manifest {version} ({stamp}) on all four platforms; the four seed folders are identical")
    return 0


if __name__ == "__main__":
    sys.exit(main())
