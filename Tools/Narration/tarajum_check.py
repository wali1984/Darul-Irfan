#!/usr/bin/env python3
"""Read the printed Akram-ut-Tarajum and find where the app's Urdu text differs.

The app's Urdu translation was typed from naqshbandiaowaisiah.org, and the
website has typing errors: Al-Falaq 113:3 reads "اندھیر اچھا جائے" where the
printed book has "اندھیرا چھا جائے". The owner asked for every ayah to be
checked against the print. Claude (Opus 5.5, low effort, Batch API at half
price - the settings that re-read the books) transcribes only the Urdu
translation on each of the 1,142 printed pages, ayah by ayah; compare.py then
sets each reading beside the app's text, and every difference goes back to
Claude with the page for a careful second look (adjudicate) before anything is
changed.

Hard budget: BUDGET_USD for the reading pass. Resumable through state.json.

    tarajum_check.py run       render, submit, collect until done
    tarajum_check.py status
"""

from __future__ import annotations

import base64
import json
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

import anthropic
from anthropic.types.message_create_params import MessageCreateParamsNonStreaming
from anthropic.types.messages.batch_create_params import Request

sys.path.insert(0, "/mnt/sata1tb/di-claude-ocr")
import claude_ocr as base  # noqa: E402  (client, prices, model)

WORK = Path("/mnt/sata1tb/di-claude-ocr/tarajum")
PDFS = Path("/mnt/sata1tb/Darul Irfan/Akram-ut-Tarajum — Quran Urdu translation")
IMAGES, PAGES = WORK / "images", WORK / "pages"
STATE, LOG = WORK / "state.json", WORK / "run.log"
BUDGET_USD = 40.00
PER_PAGE_GUESS = 0.03
BATCH_PAGES = 100

SYSTEM = """You read pages of the printed Akram-ut-Tarajum, the Urdu translation of the Qur'an by Hazrat Ameer Muhammad Akram Awan (RA). Each page has lines of Qur'anic Arabic, and under each Arabic line a boxed line of Urdu translation in Nastaliq.
Transcribe ONLY the Urdu translation, exactly as printed:
- Not the Arabic, not the running header, not the surah title band, not the line "آیات ... مکہ مکرمہ میں نازل ہوئی ... رکوع". Skip the Bismillah translation line ("شروع اللہ کے نام سے ...") EXCEPT in Surah Al-Fatiha, where it is ayah 1.
- Split the translation by ayah. Each ayah ends with a marker in the Arabic line carrying its number; the Urdu under it is spaced to match. Use the surah number from the running header or the surah title (Al-Fatiha is 1, Al-Baqarah 2, ... An-Nas 114).
- Copy every word as printed. Do not correct spelling, grammar or spacing, and never supply the translation from memory: if the print differs from what you know, keep the print.
- Word spacing matters: write a space exactly where the print separates two words, and none where it does not. (For example the print may read "اندھیرا چھا جائے"; never move a letter across a space.)
- Keep printed brackets ( ) and punctuation (۔ ، ؟ !) as printed. Keep printed vowel marks only where they are clearly printed (اُس).
- A word you cannot read with confidence becomes [؟]. Never guess.
- If the page begins in the middle of an ayah's translation, include that part with starts_on_page false; if it ends mid-ayah, ends_on_page false.
- Use standard Unicode Urdu letters (ی ے ہ ھ ک ۔), never presentation forms.
- A page with no translation (cover, contents, picture) has no ayat; say what it is in notes."""

SCHEMA = {
    "type": "object",
    "properties": {
        "running_header": {"type": "string"},
        "ayat": {"type": "array", "items": {
            "type": "object",
            "properties": {
                "surah": {"type": "integer"}, "ayah": {"type": "integer"}, "urdu": {"type": "string"},
                "starts_on_page": {"type": "boolean"}, "ends_on_page": {"type": "boolean"},
            },
            "required": ["surah", "ayah", "urdu", "starts_on_page", "ends_on_page"],
            "additionalProperties": False,
        }},
        "unreadable_words": {"type": "integer"},
        "notes": {"type": "string"},
    },
    "required": ["running_header", "ayat", "unreadable_words", "notes"],
    "additionalProperties": False,
}


def log(message: str) -> None:
    line = f"[{datetime.now().strftime('%F %T')}] {message}"
    print(line, flush=True)
    with LOG.open("a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def all_pages() -> list[dict]:
    pages = []
    for parah in range(1, 31):
        pdf = PDFS / f"Akram-ut-Tarajum-Parah{parah:02d}.pdf"
        count = int(next(line.split()[1] for line in subprocess.run(["pdfinfo", str(pdf)], capture_output=True, text=True,
                                                                     check=True).stdout.splitlines() if line.startswith("Pages:")))
        pages += [{"id": f"p{parah:02d}-{page:03d}", "pdf": str(pdf), "page": page, "parah": parah} for page in range(1, count + 1)]
    return pages


def request(custom_id: str, image: Path) -> Request:
    data = base64.standard_b64encode(image.read_bytes()).decode("ascii")
    return Request(custom_id=custom_id, params=MessageCreateParamsNonStreaming(
        model=base.MODEL, max_tokens=16000, system=SYSTEM,
        output_config={"effort": "low", "format": {"type": "json_schema", "schema": SCHEMA}},
        messages=[{"role": "user", "content": [
            {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": data}},
            {"type": "text", "text": "Transcribe the Urdu translation on this page, ayah by ayah."},
        ]}],
    ))


def save(state: dict) -> None:
    temporary = STATE.with_suffix(".tmp")
    temporary.write_text(json.dumps(state), encoding="utf-8")
    temporary.replace(STATE)


def cost(usage) -> float:
    return usage.input_tokens * base.BATCH_INPUT_PER_TOKEN + usage.output_tokens * base.BATCH_OUTPUT_PER_TOKEN


def run() -> int:
    for folder in (WORK, IMAGES, PAGES):
        folder.mkdir(parents=True, exist_ok=True)
    pages = all_pages()
    by_id = {p["id"]: p for p in pages}
    state = json.loads(STATE.read_text(encoding="utf-8")) if STATE.exists() else \
        {"queue": [p["id"] for p in pages], "batches": {}, "spent": 0.0, "done": 0, "attempts": {}, "failed": []}
    api = base.client()
    log(f"run: {len(state['queue'])} pages queued, ${state['spent']:.2f} spent, budget ${BUDGET_USD:.2f}")
    while True:
        for batch_id, info in state["batches"].items():
            if info.get("collected") or api.messages.batches.retrieve(batch_id).processing_status != "ended":
                continue
            spent = 0.0
            for item in api.messages.batches.results(batch_id):
                pid = info["pages"][int(item.custom_id.split("-")[1])]
                if item.result.type == "succeeded":
                    message = item.result.message
                    spent += cost(message.usage)
                    text = next((b.text for b in message.content if b.type == "text"), "")
                    if message.stop_reason == "end_turn" and text:
                        (PAGES / f"{pid}.json").write_text(json.dumps({"id": pid, **by_id[pid], "reading": json.loads(text)},
                                                                      ensure_ascii=False), encoding="utf-8")
                        state["done"] += 1
                        continue
                state["attempts"][pid] = state["attempts"].get(pid, 0) + 1
                (state["queue"] if state["attempts"][pid] < 3 else state["failed"]).append(pid)
            state["spent"] += spent
            info["collected"] = True
            save(state)
            log(f"collected batch {info['number']}: ${spent:.2f}; ${state['spent']:.2f} total, {state['done']} pages read")
        in_flight = sum(len(b["pages"]) for b in state["batches"].values() if not b.get("collected"))
        per_page = state["spent"] / state["done"] * 1.15 if state["done"] >= 100 else PER_PAGE_GUESS
        while state["queue"]:
            chunk = state["queue"][:BATCH_PAGES]
            committed = state["spent"] + in_flight * per_page
            if committed + len(chunk) * per_page > BUDGET_USD:
                break
            with ThreadPoolExecutor(max_workers=16) as pool:
                list(pool.map(lambda pid: base.render(Path(by_id[pid]["pdf"]), by_id[pid]["page"], IMAGES / f"{pid}.jpg"), chunk))
            number = len(state["batches"])
            batch = api.messages.batches.create(requests=[request(f"b{number:03d}-{i:03d}", IMAGES / f"{pid}.jpg")
                                                          for i, pid in enumerate(chunk)])
            state["batches"][batch.id] = {"number": number, "pages": chunk, "collected": False}
            state["queue"] = state["queue"][len(chunk):]
            in_flight += len(chunk)
            save(state)
            log(f"submitted batch {number} ({len(chunk)} pages); about ${committed + len(chunk) * per_page:.0f} committed")
        if in_flight == 0:
            log(f"finished: {state['done']} pages read, ${state['spent']:.2f}, {len(state['failed'])} failed, "
                f"{len(state['queue'])} left (budget)")
            return 0
        time.sleep(60)


if __name__ == "__main__":
    if (sys.argv[1:] or ["status"])[0] == "run":
        sys.exit(run())
    state = json.loads(STATE.read_text(encoding="utf-8")) if STATE.exists() else {}
    print(f"{state.get('done', 0)} read, ${state.get('spent', 0):.2f}, {len(state.get('queue', []))} queued, "
          f"{len(state.get('failed', []))} failed")
