#!/usr/bin/env python3
"""Score the A/B variants on the fixed sample: exact-text check (the same
compare() the publishing gate uses, on the word-timed transcripts), pauses and
pace (pause_detect), hiss (hiss2/hiss3). CPU only; run with the Whisper venv's
python (verify_narration imports faster_whisper)."""
import json
import statistics
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

N = Path("/mnt/sata1tb/di-voices/nov-fixes")
sys.path.insert(0, "/mnt/sata1tb/di-voices")
import verify_narration as vn  # noqa: E402

texts = {**vn.sources("translation"), **vn.sources("tafsir")}
rows = defaultdict(dict)
for line in open(N / "scan/words_ab.jsonl", encoding="utf-8"):
    r = json.loads(line)
    p = Path(r["file"])
    variant = p.parts[1]
    key = "/".join(p.parts[2:])[:-4]
    if key not in texts:
        continue
    heard = " ".join(w[2] for w in r["words"])
    c = vn.compare(texts[key], heard)
    rows[variant][key] = {"flag": c["flag"], "ratio": c["ratio"]}
subprocess.run(["/mnt/sata1tb/di-voices/vox/bin/python", str(N / "pause_detect.py"), str(N / "scan/words_ab.jsonl"),
                str(N / "scan/pause_ab.json")], cwd=N, check=True, capture_output=True)
pd = json.load(open(N / "scan/pause_ab.json", encoding="utf-8"))
files = sorted(str(p.relative_to(N)) for p in (N / "ab").rglob("*.mp3"))
(N / "scan/ab_files.txt").write_text(chr(10).join(files))
subprocess.run(["python3", "hiss2.py", "scan/h2_ab.json", "24000", "@scan/ab_files.txt"], cwd=N, capture_output=True)
subprocess.run(["python3", "hiss3.py", "scan/h3_ab.json", "24000", "@scan/ab_files.txt"], cwd=N, capture_output=True)
h2 = {x["file"]: x for x in json.load(open(N / "scan/h2_ab.json"))}
h3 = {x["file"]: x for x in json.load(open(N / "scan/h3_ab.json"))}
summary = {}
for variant in sorted(rows):
    keys = rows[variant]
    fl = [k for k, v in keys.items() if v["flag"]]
    vf = [f for f in files if f.startswith(f"ab/{variant}/")]
    pds = [pd[f] for f in vf if f in pd]
    def med(name, src):
        vals = [src[f][name] for f in vf if f in src and src[f].get(name) is not None]
        return round(statistics.median(vals), 1) if vals else None
    summary[variant] = {
        "files": len(keys), "failed_exact_text": len(fl), "failed": [k.rsplit("/", 1)[1] for k in fl],
        "mid_phrase_pauses": sum(x["mid"] for x in pds), "missed_clause_pauses": sum(x["missed"] for x in pds),
        "clause_pause_share": round(sum(x["at_clause"] for x in pds) / max(1, sum(x["clauses"] for x in pds)), 2),
        "longest_run_letters_median": statistics.median(x["run"] for x in pds) if pds else None,
        "speaking_lps_median": statistics.median(x["lps"] for x in pds) if pds else None,
        "speaking_lps_p90": sorted(x["lps"] for x in pds)[int(.9 * len(pds))] if pds else None,
        "sizzle_rel_median": med("sizzle_rel", h2), "pause_db_median": med("pause_db", h2), "core_db_median": med("core_db", h2),
        "noise_bursts": sum(len([r for r in h3[f]["runs"] if r[1] >= 120]) for f in vf if f in h3),
        "seconds_total": round(sum(h2[f]["seconds"] for f in vf if f in h2)),
    }
(N / "scan/ab_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=1))
for v, s in summary.items():
    print(v, json.dumps(s, ensure_ascii=False))
