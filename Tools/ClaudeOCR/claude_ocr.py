#!/usr/bin/env python3
"""Re-read Darul Irfan book pages from their scans with Claude vision.

The Surya OCR in the app garbles Nastaliq: about a quarter of the 6,660 book
pages are mostly unreliable. This sends each page's scan to Claude through the
Message Batches API (half price, results within 24 h) and keeps the answer as
structured blocks.

    claude_ocr.py pilot      24 chosen pages, each at effort low and medium
    claude_ocr.py status     where the pilot batch is

Resumable: the batch id is kept in state.json, so running it again collects
the same batch instead of paying twice. The API key is read from
ANTHROPIC_API_KEY or ~/.config/darul-irfan/anthropic_key (never printed).
"""

from __future__ import annotations

import argparse
import base64
import html
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import anthropic
from anthropic.types.message_create_params import MessageCreateParamsNonStreaming
from anthropic.types.messages.batch_create_params import Request

WORK = Path("/mnt/sata1tb/di-claude-ocr")
BOOKS = Path("/mnt/sata1tb/Darul Irfan/Books")
MANIFEST = WORK / "books_pages_manifest.json"
KEY_FILE = Path.home() / ".config/darul-irfan/anthropic_key"
MODEL = "claude-opus-5-5"
# Batch prices are half the standard $4 / $20 per million tokens.
BATCH_INPUT_PER_TOKEN = 2.00 / 1_000_000
BATCH_OUTPUT_PER_TOKEN = 10.00 / 1_000_000
LONG_EDGE = 2576

SYSTEM = """You transcribe scanned pages of printed books of the Naqshbandia Owaisiah Sufi order. Most pages are Urdu in Nastaliq; they quote Arabic (Qur'an, hadith, duas) and Persian poetry.

Transcribe exactly what is printed on this page:
- Copy the printed words as they are. Do not correct spelling or grammar, and never fill in or "fix" a Qur'an verse, hadith or couplet from memory: if the print differs from what you know, keep the print.
- A word you cannot read with confidence becomes [؟]. Never guess a word.
- Lines that only wrap inside a paragraph are joined into one paragraph. Start a new block where the page starts a new paragraph, heading, couplet, quotation or footnote.
- Poetry: one "verse" block per couplet or stanza, its printed lines separated by a newline.
- Arabic quotations are "arabic" blocks, with the diacritics that are printed and no others.
- The running header (book or chapter title repeated at the top) and the printed page number go in their own fields, not in blocks.
- Use standard Unicode Urdu letters (ی ے ہ ھ ک ۔), never Arabic presentation forms. Keep the digits the page uses.
- A cover, blank page or picture has no blocks; say what it is in notes."""

SCHEMA = {
    "type": "object",
    "properties": {
        "page_type": {"type": "string", "enum": ["text", "contents", "poetry", "mixed", "cover", "blank", "image"]},
        "printed_page_number": {"type": "string"},
        "running_header": {"type": "string"},
        "blocks": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "kind": {"type": "string", "enum": ["heading", "paragraph", "verse", "arabic", "footnote", "table", "caption"]},
                    "text": {"type": "string"},
                },
                "required": ["kind", "text"],
                "additionalProperties": False,
            },
        },
        "illegible_words": {"type": "integer"},
        "notes": {"type": "string"},
    },
    "required": ["page_type", "printed_page_number", "running_header", "blocks", "illegible_words", "notes"],
    "additionalProperties": False,
}


def client() -> anthropic.Anthropic:
    if not os.environ.get("ANTHROPIC_API_KEY") and KEY_FILE.exists():
        os.environ["ANTHROPIC_API_KEY"] = KEY_FILE.read_text(encoding="utf-8").strip()
    if not os.environ.get("ANTHROPIC_API_KEY"):
        sys.exit(f"No API key: set ANTHROPIC_API_KEY or put it in {KEY_FILE} (chmod 600)")
    return anthropic.Anthropic()


def render(pdf: Path, page: int, target: Path) -> Path:
    """The page as a JPEG at Claude's full resolution (2576 px long edge)."""
    if not target.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
        stem = target.with_suffix("")
        subprocess.run(["pdftoppm", "-f", str(page), "-l", str(page), "-r", "300", "-scale-to", str(LONG_EDGE),
                        "-jpeg", "-jpegopt", "quality=90", "-singlefile", str(pdf), str(stem)], check=True)
    return target


def request(custom_id: str, image: Path, effort: str) -> Request:
    data = base64.standard_b64encode(image.read_bytes()).decode("ascii")
    return Request(
        custom_id=custom_id,
        params=MessageCreateParamsNonStreaming(
            model=MODEL,
            max_tokens=16000,
            system=SYSTEM,
            output_config={"effort": effort, "format": {"type": "json_schema", "schema": SCHEMA}},
            messages=[{"role": "user", "content": [
                {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": data}},
                {"type": "text", "text": "Transcribe this page."},
            ]}],
        ),
    )


def pilot_pages(manifest: list[dict]) -> list[dict]:
    """Mostly the pages the old OCR failed on, across different books, plus
    pages it got right, so the pilot shows gains and any losses."""
    def share(p): return p["unresolved"] / max(p["blocks"], 1)
    must = [("book-ocr-bai-at-kiya-hai", 8), ("uploads-books-asaas-us-salook", 30),
            ("book-ocr-gard-e-safar", 30), ("book-dalael-us-salook-urdu", 30)]
    chosen = [p for key in must for p in manifest if (p["bookID"], p["page"]) == key]
    seen = {p["bookID"] for p in chosen}
    for wanted, limit in ((lambda p: share(p) >= 0.5, 12), (lambda p: 0 < share(p) < 0.5, 4), (lambda p: share(p) == 0, 4)):
        picked = 0
        for p in sorted(manifest, key=lambda p: (p["bookID"], p["page"])):
            if picked >= limit:
                break
            if p["bookID"] in seen or not wanted(p) or len(p["oldText"]) < 200:
                continue
            chosen.append(p); seen.add(p["bookID"]); picked += 1
    return chosen


def page_id(p: dict) -> str:
    return f"{p['bookID']}__p{p['page']:04d}"


def write_review(folder: Path, pages: list[dict], results: dict) -> None:
    """Scan beside the old text and both new readings, for a person to judge."""
    parts = ["<!doctype html><meta charset=utf-8><title>OCR pilot</title><style>"
             "body{font-family:sans-serif;margin:16px}section{border-top:2px solid #999;padding:12px 0}"
             ".row{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:12px}"
             "img{width:100%}pre{white-space:pre-wrap;direction:rtl;font-family:'Noto Nastaliq Urdu',serif;font-size:18px;line-height:2}"
             "h3{margin:4px 0;font-size:14px}</style><h1>OCR pilot: old Surya text vs Claude</h1>"]
    for p in pages:
        pid = page_id(p)
        parts.append(f"<section><h2>{html.escape(p['bookID'])} — page {p['page']}</h2><div class=row>"
                     f"<div><h3>Scan</h3><img src='images/{pid}.jpg' loading=lazy></div>"
                     f"<div><h3>Old (Surya), {p['unresolved']}/{p['blocks']} unsettled</h3><pre>{html.escape(p['oldText'])}</pre></div>")
        for effort in ("low", "medium"):
            r = results.get(f"{pid}__{effort}")
            body = "\n\n".join(b["text"] for b in r["page"]["blocks"]) if r and r.get("page") else (r or {}).get("error", "missing")
            usage = f" — {r['input_tokens']} in / {r['output_tokens']} out" if r and "input_tokens" in r else ""
            parts.append(f"<div><h3>Claude, effort {effort}{usage}</h3><pre>{html.escape(body)}</pre></div>")
        parts.append("</div></section>")
    (folder / "index.html").write_text("".join(parts), encoding="utf-8")


def pilot() -> int:
    folder = WORK / "pilot"
    folder.mkdir(parents=True, exist_ok=True)
    state_path = folder / "state.json"
    state = json.loads(state_path.read_text(encoding="utf-8")) if state_path.exists() else {}
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    pages = pilot_pages(manifest)
    api = client()

    if "batch_id" not in state:
        requests = []
        # custom_id is capped at 64 characters, so requests are numbered and
        # state.json keeps the order that maps a number back to its page.
        for number, p in enumerate(pages):
            image = render(BOOKS / p["pdf"], p["page"], folder / "images" / f"{page_id(p)}.jpg")
            for effort in ("low", "medium"):
                requests.append(request(f"{number:03d}__{effort}", image, effort))
        batch = api.messages.batches.create(requests=requests)
        state = {"batch_id": batch.id, "pages": [page_id(p) for p in pages], "created": time.time()}
        state_path.write_text(json.dumps(state), encoding="utf-8")
        print(f"submitted {len(requests)} requests as batch {batch.id}", flush=True)

    while True:
        batch = api.messages.batches.retrieve(state["batch_id"])
        if batch.processing_status == "ended":
            break
        print(f"{time.strftime('%H:%M')} {batch.processing_status}: {batch.request_counts.processing} still processing", flush=True)
        time.sleep(60)

    results = {}
    for item in api.messages.batches.results(state["batch_id"]):
        entry: dict = {}
        if item.result.type == "succeeded":
            message = item.result.message
            entry = {"input_tokens": message.usage.input_tokens, "output_tokens": message.usage.output_tokens,
                     "stop_reason": message.stop_reason}
            text = next((b.text for b in message.content if b.type == "text"), "")
            if message.stop_reason == "end_turn" and text:
                entry["page"] = json.loads(text)
            else:
                entry["error"] = f"stopped: {message.stop_reason}"
        else:
            entry = {"error": item.result.type}
        number, effort = item.custom_id.split("__")
        results[f"{state['pages'][int(number)]}__{effort}"] = entry
    (folder / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=1), encoding="utf-8")
    write_review(folder, pages, results)

    report = {}
    for effort in ("low", "medium"):
        done = [r for key, r in results.items() if key.endswith(f"__{effort}") and "input_tokens" in r]
        if not done:
            continue
        cost = sum(r["input_tokens"] * BATCH_INPUT_PER_TOKEN + r["output_tokens"] * BATCH_OUTPUT_PER_TOKEN for r in done)
        per_page = cost / len(done)
        report[effort] = {
            "pages": len(done),
            "failed": sum(1 for key, r in results.items() if key.endswith(f"__{effort}") and "page" not in r),
            "avg_input_tokens": round(sum(r["input_tokens"] for r in done) / len(done)),
            "avg_output_tokens": round(sum(r["output_tokens"] for r in done) / len(done)),
            "pilot_cost_usd": round(cost, 2),
            "per_page_usd": round(per_page, 4),
            "projected_books_6660_usd": round(per_page * 6660),
            "projected_al_murshid_17135_usd": round(per_page * 17135),
        }
    (folder / "report.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
    print(json.dumps(report, indent=1), flush=True)
    return 0


def status() -> int:
    state_path = WORK / "pilot" / "state.json"
    if not state_path.exists():
        print("no pilot batch yet")
        return 0
    batch = client().messages.batches.retrieve(json.loads(state_path.read_text())["batch_id"])
    print(batch.processing_status, batch.request_counts)
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["pilot", "status"])
    sys.exit(pilot() if parser.parse_args().command == "pilot" else status())
