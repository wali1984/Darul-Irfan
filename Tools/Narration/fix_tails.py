#!/usr/bin/env python3
"""One-off: give the Higgs files made before the fades went in the same ending
as new ones (80 ms fade-out, 0.35 s of silence), in place. Files already done
are listed in tails_fixed.txt and never touched twice."""
import subprocess, sys
from pathlib import Path

ROOT = Path("/mnt/sata1tb/di-voices/quran-higgs")
DONE = Path("/mnt/sata1tb/di-voices/tails_fixed.txt")
cutoff = float(sys.argv[1])  # files modified before this time get the new ending
done = set(DONE.read_text().split()) if DONE.exists() else set()
count = 0
with DONE.open("a") as log:
    for path in sorted(ROOT.rglob("*.mp3")):
        key = str(path.relative_to(ROOT))
        if key in done or path.stat().st_mtime >= cutoff:
            continue
        temp = path.with_suffix(".tmp.mp3")
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(path), "-af",
                        "areverse,afade=t=in:d=0.08,areverse,apad=pad_dur=0.35",
                        "-ac", "1", "-b:a", "64k", str(temp)], check=True)
        temp.replace(path)
        log.write(key + "\n")
        count += 1
print(f"{count} files given the new ending")
