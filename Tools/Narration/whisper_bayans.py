#!/usr/bin/env python3
"""Transcribe the downloaded bayans with Whisper, one recording at a time.

Started only by gpu_queue.sh once the card is idle. Resumable: a recording that
already has a transcript is never redone, so a stop or reboot loses at most the
recording in hand.

The output is machine transcription for search and timestamps. Whisper can
invent text, so every transcript is marked machine_provisional and must not be
shown as the Sheikh's words until someone has listened to it.
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path("/mnt/sata1tb/di-bayans")
AUDIO = ROOT / "audio"
TRANSCRIPTS = ROOT / "transcripts"
MANIFEST = ROOT / "bayans.tsv"
STOP = Path("/mnt/sata1tb/di-queue/HALTED")
MODEL = "large-v3"
# Whisper's own hallucination signals; a segment past either is flagged, not dropped.
MAX_COMPRESSION = 2.4
MIN_LOGPROB = -1.0
HOT_C = 83
COOL_C = 70


def log(message: str) -> None:
    print(f"[{datetime.now().strftime('%F %T')}] {message}", flush=True)


def load_audio(path) -> "np.ndarray":
    """16 kHz mono float32 via ffmpeg. faster-whisper's own decoder needs a PyAV
    release (<15) that has no wheel for this Python, so it is bypassed."""
    import numpy as np
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", "16000", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def gpu_temperature() -> int:
    output = subprocess.run(["nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader,nounits"],
                            check=True, capture_output=True, text=True).stdout
    return int(output.split()[0])


def let_gpu_cool() -> None:
    if gpu_temperature() < HOT_C:
        return
    log(f"GPU at {gpu_temperature()}C, pausing until it is below {COOL_C}C")
    while gpu_temperature() >= COOL_C:
        time.sleep(30)


def recordings() -> list[dict]:
    rows = []
    for line in MANIFEST.read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if len(parts) >= 4 and parts[0]:
            rows.append({"id": parts[0], "url": parts[1], "language": parts[2] or "ur", "title": parts[3]})
    return rows


def duration(path: Path) -> float:
    output = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                            check=True, capture_output=True, text=True).stdout
    return float(output.strip())


def atomic_json(path: Path, payload: object) -> None:
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def transcribe(model, row: dict, settings: dict) -> dict:
    audio = AUDIO / f"{row['id']}.mp3"
    started = time.monotonic()
    segments, info = model.transcribe(load_audio(audio), language=row["language"], **settings)
    out = []
    for segment in segments:
        out.append({
            "start": round(segment.start, 2),
            "end": round(segment.end, 2),
            "text": segment.text.strip(),
            "avg_logprob": round(segment.avg_logprob, 3),
            "no_speech_prob": round(segment.no_speech_prob, 3),
            "compression_ratio": round(segment.compression_ratio, 3),
            "suspect": segment.compression_ratio > MAX_COMPRESSION or segment.avg_logprob < MIN_LOGPROB,
            "words": [[round(w.start, 2), round(w.end, 2), w.word, round(w.probability, 3)] for w in (segment.words or [])],
        })
    return {
        "schema_version": 1,
        "id": row["id"],
        "title": row["title"],
        "source_url": row["url"],
        "language": info.language,
        "duration_seconds": round(info.duration, 1),
        "model": f"faster-whisper {MODEL}",
        "settings": {key: value for key, value in settings.items() if key != "vad_parameters"},
        "verification_status": "machine_provisional",
        "transcribed_at": datetime.now(timezone.utc).isoformat(),
        "seconds_taken": round(time.monotonic() - started, 1),
        "segments": out,
    }


def pilot_rows(rows: list[dict], count: int) -> list[dict]:
    """Shortest to longest, evenly spaced, so the pilot sees every length."""
    present = sorted((r for r in rows if (AUDIO / f"{r['id']}.mp3").exists()),
                     key=lambda r: (AUDIO / f"{r['id']}.mp3").stat().st_size)
    if len(present) <= count:
        return present
    step = (len(present) - 1) / (count - 1)
    return [present[round(i * step)] for i in range(count)]


def report(done: list[dict]) -> dict:
    audio = sum(t["duration_seconds"] for t in done)
    wall = sum(t["seconds_taken"] for t in done)
    segments = [s for t in done for s in t["segments"]]
    return {
        "recordings": len(done),
        "audio_hours": round(audio / 3600, 2),
        "wall_hours": round(wall / 3600, 2),
        "speed_x_realtime": round(audio / wall, 1) if wall else None,
        "segments": len(segments),
        "median_avg_logprob": round(statistics.median(s["avg_logprob"] for s in segments), 3) if segments else None,
        "suspect_share": round(sum(s["suspect"] for s in segments) / len(segments), 3) if segments else None,
        "empty_transcripts": [t["id"] for t in done if not t["segments"]],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--pilot", type=int, metavar="N")
    group.add_argument("--all", action="store_true")
    args = parser.parse_args()

    from faster_whisper import WhisperModel

    TRANSCRIPTS.mkdir(parents=True, exist_ok=True)
    settings = {
        "task": "transcribe",
        "beam_size": 5,
        "vad_filter": True,
        "vad_parameters": {"min_silence_duration_ms": 500},
        "word_timestamps": True,
        # Not feeding earlier text back in stops one bad stretch repeating for minutes.
        "condition_on_previous_text": False,
    }
    log(f"loading {MODEL} on the GPU")
    model = WhisperModel(MODEL, device="cuda", compute_type="int8_float16")

    rows = recordings()
    chosen = pilot_rows(rows, args.pilot) if args.pilot else rows
    finished = []
    for index, row in enumerate(chosen, 1):
        if STOP.exists():
            log("queue halted, stopping between recordings")
            return 4
        target = TRANSCRIPTS / f"{row['id']}.json"
        if target.exists():
            finished.append(json.loads(target.read_text(encoding="utf-8")))
            continue
        if not (AUDIO / f"{row['id']}.mp3").exists():
            continue
        let_gpu_cool()
        transcript = transcribe(model, row, settings)
        atomic_json(target, transcript)
        finished.append(transcript)
        suspect = sum(s["suspect"] for s in transcript["segments"])
        log(f"{index}/{len(chosen)} {row['id']}: {transcript['duration_seconds'] / 60:.0f} min audio in "
            f"{transcript['seconds_taken'] / 60:.1f} min, {len(transcript['segments'])} segments, {suspect} flagged")

    summary = report(finished)
    name = "pilot-report.json" if args.pilot else "report.json"
    atomic_json(ROOT / name, summary)
    log(f"{name}: {json.dumps(summary, ensure_ascii=False)}")
    if args.pilot:
        # The full run only follows a pilot that produced real, mostly confident text.
        ok = (summary["recordings"] >= min(args.pilot, 3) and not summary["empty_transcripts"]
              and summary["median_avg_logprob"] is not None and summary["median_avg_logprob"] > -0.8
              and summary["suspect_share"] < 0.25)
        if not ok:
            log("pilot quality gate failed; the full run waits for a person to look")
            return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
