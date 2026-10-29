#!/usr/bin/env python3
"""A careful second look at every ayah where the printed Akram-ut-Tarajum and
the app's text differ (tarajum_compare.py), before any word is changed.

The owner ruled (2026-10-28) that the printed book is authoritative. The first
reading (low effort) found 874 ayat that differ in letters or word breaks; some
of those are its own misreadings ("تیموں" for "یتیموں"). Here Opus 5.5 at medium
effort reads that one ayah again from the page image(s), independently of both
texts it is shown, and says what is printed and what each difference is.

Batch API (half price), hard budget BUDGET_USD, resumable through state.json.

A third look (--held held.json) takes the ayat the second look was unsure of
or disagreed with the first reading on, at high effort, with the pages before
and after so an ayah that crosses a page or a line can be placed.

    tarajum_adjudicate.py run [--held held.json]
    tarajum_adjudicate.py status
"""

from __future__ import annotations

import base64
import json
import sys
import time
from datetime import datetime
from pathlib import Path

from anthropic.types.message_create_params import MessageCreateParamsNonStreaming
from anthropic.types.messages.batch_create_params import Request

sys.path.insert(0, "/mnt/sata1tb/di-claude-ocr")
import claude_ocr as base  # noqa: E402

WORK = Path("/mnt/sata1tb/di-claude-ocr/tarajum")
HELD = sys.argv[sys.argv.index("--held") + 1] if "--held" in sys.argv else None
SUFFIX = "-3" if HELD else ""
OUT = WORK / f"adjudicated{SUFFIX}"
STATE, LOG = WORK / f"adjudicate{SUFFIX}_state.json", WORK / f"adjudicate{SUFFIX}.log"
EFFORT = "high" if HELD else "medium"
BUDGET_USD = 10.00 if HELD else 45.00
PER_ITEM_GUESS = 0.12 if HELD else 0.05
# A batch request is capped at 256 MB; a third-look ayah carries up to five pages.
BATCH_ITEMS = 20 if HELD else 100

SYSTEM = """You check the Urdu translation of one ayah in the printed Akram-ut-Tarajum (Hazrat Ameer Muhammad Akram Awan (RA)) against a typed copy. The page images are the authority. Each page has lines of Qur'anic Arabic, each with a boxed line of Urdu translation under it; an ayah ends at a marker carrying its number, and its translation may run across lines and onto the next page.
1. Find the asked ayah and read its printed Urdu translation yourself, word by word, slowly. Read it from the image: the two texts you are given may both be wrong, and the "first reading" was made quickly and has mistakes of its own.
2. Write "printed": the whole translation of that ayah exactly as printed - every word, the printed spelling, printed brackets and punctuation, and a space exactly where the print separates words. Never correct the print or fill it in from memory. A word you cannot make out becomes [؟].
3. List every place where the typed copy ("app") differs from the print, each with its kind:
   - typo_in_app: the app has a typing error in a word the print has (wrong, missing or extra letter, or a space that splits/joins words wrongly so a word changes, e.g. "او رجو" for "اور جو", "اندھیر اچھا" for "اندھیرا چھا")
   - missing_from_app: printed words the app leaves out
   - extra_in_app: words in the app that the print does not have
   - different_wording: the app says it with different words than the print
   - spelling_only: the same word in another accepted spelling (لیے/لیئے, انہیں/انھیں, دیجئے/دیجیے) or a space merely present or absent between two words (جوکچھ/جو کچھ)
   Do not list differences of vowel marks or punctuation alone.
4. "first_reading_wrong": true if the first reading disagrees with the print anywhere.
5. "certain": false if any part of the printed ayah is hard to read or you are not sure where it starts or ends."""

SCHEMA = {
    "type": "object",
    "properties": {
        "printed": {"type": "string"},
        "differences": {"type": "array", "items": {
            "type": "object",
            "properties": {
                "app": {"type": "string"}, "printed": {"type": "string"},
                "kind": {"type": "string", "enum": ["typo_in_app", "missing_from_app", "extra_in_app", "different_wording", "spelling_only"]},
            },
            "required": ["app", "printed", "kind"], "additionalProperties": False,
        }},
        "first_reading_wrong": {"type": "boolean"},
        "certain": {"type": "boolean"},
        "notes": {"type": "string"},
    },
    "required": ["printed", "differences", "first_reading_wrong", "certain", "notes"],
    "additionalProperties": False,
}


def log(message: str) -> None:
    line = f"[{datetime.now().strftime('%F %T')}] {message}"
    print(line, flush=True)
    with LOG.open("a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def neighbours(pages: list[str]) -> list[str]:
    """The pages before and after, when they exist."""
    before = f"{pages[0][:4]}{int(pages[0][4:]) - 1:03d}"
    after = f"{pages[-1][:4]}{int(pages[-1][4:]) + 1:03d}"
    return [p for p in [before, *pages, after] if (WORK / "images" / f"{p}.jpg").exists()]


def items() -> list[dict]:
    differences = json.loads((WORK / "differences.json").read_text(encoding="utf-8"))["differences"]
    chosen = [d for d in differences if d["kind"] in ("letters", "spacing")]
    if HELD:
        held = set(json.loads(Path(HELD).read_text()))
        chosen = [{**d, "pages": neighbours(d["pages"])} for d in chosen if f"{d['surah']}:{d['ayah']}" in held]
    return chosen


def request(custom_id: str, item: dict) -> Request:
    content = []
    for page in item["pages"][:5 if HELD else 3]:
        data = base64.standard_b64encode((WORK / "images" / f"{page}.jpg").read_bytes()).decode("ascii")
        content.append({"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": data}})
    content.append({"type": "text", "text": (
        f"Ayah {item['surah']}:{item['ayah']} (surah {item['surah']}, ayah {item['ayah']}); "
        + ("these are the pages around it, in order: find the ayah by its marker and read only its translation. "
           "Where its start or end is unclear, use the Arabic - an ayah's translation renders that ayah's Arabic.\n\n"
           if HELD else
           f"{'its translation is on these pages in order' if len(item['pages']) > 1 else 'its translation is on this page'}.\n\n")
        + f"App (typed copy):\n{item['app']}\n\nFirst reading of the print:\n{item['printed']}")})
    return Request(custom_id=custom_id, params=MessageCreateParamsNonStreaming(
        model=base.MODEL, max_tokens=16000, system=SYSTEM,
        output_config={"effort": EFFORT, "format": {"type": "json_schema", "schema": SCHEMA}},
        messages=[{"role": "user", "content": content}],
    ))


def save(state: dict) -> None:
    temporary = STATE.with_suffix(".tmp")
    temporary.write_text(json.dumps(state), encoding="utf-8")
    temporary.replace(STATE)


def run() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    all_items = {f"{i['surah']:03d}{i['ayah']:03d}": i for i in items()}
    state = json.loads(STATE.read_text(encoding="utf-8")) if STATE.exists() else \
        {"queue": sorted(all_items), "batches": {}, "spent": 0.0, "done": 0, "attempts": {}, "failed": []}
    api = base.client()
    log(f"run: {len(state['queue'])} ayat queued, ${state['spent']:.2f} spent, budget ${BUDGET_USD:.2f}")
    while True:
        for batch_id, info in state["batches"].items():
            if info.get("collected") or api.messages.batches.retrieve(batch_id).processing_status != "ended":
                continue
            spent = 0.0
            for result in api.messages.batches.results(batch_id):
                key = info["items"][int(result.custom_id.split("-")[1])]
                if result.result.type == "succeeded":
                    message = result.result.message
                    spent += message.usage.input_tokens * base.BATCH_INPUT_PER_TOKEN + message.usage.output_tokens * base.BATCH_OUTPUT_PER_TOKEN
                    text = next((b.text for b in message.content if b.type == "text"), "")
                    if message.stop_reason == "end_turn" and text:
                        (OUT / f"{key}.json").write_text(json.dumps({**all_items[key], "check": json.loads(text)}, ensure_ascii=False),
                                                         encoding="utf-8")
                        state["done"] += 1
                        continue
                state["attempts"][key] = state["attempts"].get(key, 0) + 1
                (state["queue"] if state["attempts"][key] < 3 else state["failed"]).append(key)
            state["spent"] += spent
            info["collected"] = True
            save(state)
            log(f"collected batch {info['number']}: ${spent:.2f}; ${state['spent']:.2f} total, {state['done']} ayat checked")
        in_flight = sum(len(b["items"]) for b in state["batches"].values() if not b.get("collected"))
        per_item = state["spent"] / state["done"] * 1.15 if state["done"] >= 100 else PER_ITEM_GUESS
        while state["queue"]:
            chunk = state["queue"][:BATCH_ITEMS]
            committed = state["spent"] + in_flight * per_item
            if committed + len(chunk) * per_item > BUDGET_USD:
                break
            number = len(state["batches"])
            batch = api.messages.batches.create(requests=[request(f"a{number:03d}-{i:03d}", all_items[key]) for i, key in enumerate(chunk)])
            state["batches"][batch.id] = {"number": number, "items": chunk, "collected": False}
            state["queue"] = state["queue"][len(chunk):]
            in_flight += len(chunk)
            save(state)
            log(f"submitted batch {number} ({len(chunk)} ayat); about ${committed + len(chunk) * per_item:.0f} committed")
        if in_flight == 0:
            log(f"finished: {state['done']} ayat checked, ${state['spent']:.2f}, {len(state['failed'])} failed, {len(state['queue'])} left")
            return 0
        time.sleep(60)


if __name__ == "__main__":
    if (sys.argv[1:] or ["status"])[0] == "run":
        sys.exit(run())
    state = json.loads(STATE.read_text(encoding="utf-8")) if STATE.exists() else {}
    print(f"{state.get('done', 0)} checked, ${state.get('spent', 0):.2f}, {len(state.get('queue', []))} queued")
