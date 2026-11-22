"""Copy the proofread seed files from iOS to Android and the desktop, byte for byte.

    python Tools/Content/urdu_proofread/spread.py

Every seed file that differs goes to the Android checkout beside this one
(`pw/a-proof`) and to the desktop checkout (`DarulIrfanDesktop-proof`).
Afterwards the three folders are compared.
"""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path

IOS = Path(__file__).resolve().parents[3]
FILES = ("book_pages.json", "book_links.json", "quran_tafsir.json", "manifest.json")
SEEDS = {
    "iOS": IOS / "DarulIrfanApp" / "Resources" / "SeedData",
    "Android": IOS.parent / "a-proof" / "app" / "src" / "main" / "assets" / "seed",
    "Desktop": IOS.parents[1] / "DarulIrfanDesktop-proof" / "content",
}


def main() -> int:
    source = SEEDS["iOS"]
    for platform, folder in SEEDS.items():
        if platform == "iOS":
            continue
        if not folder.is_dir():
            print(f"{platform}: {folder} is not there")
            return 1
        # Every seed file both sides have, wherever the bytes differ; the four
        # the proofreading writes are copied even where the other side lacks them.
        names = sorted({path.name for path in source.iterdir() if path.is_file() and (folder / path.name).exists()} | set(FILES))
        for name in names:
            data = (source / name).read_bytes()
            if not (folder / name).exists() or (folder / name).read_bytes() != data:
                (folder / name).write_bytes(data)
                print(f"{platform}: {name} copied")
        missing = sorted(path.name for path in source.iterdir() if path.is_file() and not (folder / path.name).exists())
        if missing:
            print(f"{platform}: does not carry {missing}")
    # Every seed file the platforms share must be the same bytes, not only the four.
    different = []
    for path in sorted(source.iterdir()):
        if not path.is_file():
            continue
        digest = hashlib.sha256(path.read_bytes()).digest()
        for platform, folder in SEEDS.items():
            other = folder / path.name
            if platform != "iOS" and other.exists() and hashlib.sha256(other.read_bytes()).digest() != digest:
                different.append(f"{platform}/{path.name}")
    print("the three seed folders hold the same bytes" if not different else f"DIFFERENT: {different}")
    return 1 if different else 0


if __name__ == "__main__":
    raise SystemExit(main())
