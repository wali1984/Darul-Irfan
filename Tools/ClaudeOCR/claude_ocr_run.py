#!/usr/bin/env python3
"""Full Claude re-read of the 43 books and Asrar-ut-Tanzil (Urdu), under a budget.

Same model, prompt and settings as the pilot (claude_ocr.py): Opus 5.5 at low
effort, full-resolution scans, Message Batches API at half price.

Speed: pages go out in batches of 150, many in flight at once, so the work runs
in parallel instead of as one long batch.

Budget: the books are submitted first, then Asrar. A batch is submitted only if
the money already spent, plus a cautious estimate for everything in flight and
for that batch, stays under BUDGET_USD. The estimate starts at the pilot's cost
per page plus 30% and switches to the measured average (plus 15%) once enough
pages have come back. Whatever does not fit stays in the queue for next month.

Resumable: state.json holds every batch id and the queue, so a restart collects
batches already paid for instead of resubmitting them.

    claude_ocr_run.py run       submit, collect and keep going until done
    claude_ocr_run.py status    one-line progress (also in status.json)
"""

from __future__ import annotations

import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

import anthropic

import claude_ocr as pilot

RUN = pilot.WORK / "run"
PAGES_OUT = RUN / "pages"
IMAGES = RUN / "images"
STATE = RUN / "state.json"
STATUS = RUN / "status.json"
ASRAR_UR = Path("/mnt/sata1tb/Darul Irfan/Asrar-at-Tanzil — Urdu tafsir")
ASRAR_MANIFEST = pilot.WORK / "asrar_ur_pages.json"

BUDGET_USD = 195.00 - 1.08          # $195 ceiling, less what the pilot spent
PILOT_PER_PAGE = 0.022
BATCH_PAGES = 150
MAX_ATTEMPTS = 3


def log(message: str) -> None:
    line = f"[{datetime.now().strftime('%F %T')}] {message}"
    print(line, flush=True)
    with (RUN / "run.log").open("a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def all_pages() -> list[dict]:
    books = json.loads(pilot.MANIFEST.read_text(encoding="utf-8"))
    asrar = json.loads(ASRAR_MANIFEST.read_text(encoding="utf-8"))
    pages = [{"id": pilot.page_id(p), "bookID": p["bookID"], "page": p["page"], "pdf": str(pilot.BOOKS / p["pdf"])} for p in books]
    pages += [{"id": pilot.page_id(p), "bookID": p["bookID"], "page": p["page"], "pdf": str(ASRAR_UR / p["pdf"])} for p in asrar]
    return pages


def page_cost(usage: dict) -> float:
    return usage["input_tokens"] * pilot.BATCH_INPUT_PER_TOKEN + usage["output_tokens"] * pilot.BATCH_OUTPUT_PER_TOKEN


def save(state: dict) -> None:
    temporary = STATE.with_suffix(".tmp")
    temporary.write_text(json.dumps(state), encoding="utf-8")
    temporary.replace(STATE)


def estimate(state: dict) -> float:
    if state["done_pages"] >= 300:
        return state["spent"] / state["done_pages"] * 1.15
    return PILOT_PER_PAGE * 1.30


def write_status(state: dict, total: int, note: str = "") -> dict:
    in_flight = sum(len(b["pages"]) for b in state["batches"].values() if not b.get("collected"))
    status = {
        "updated": datetime.now().strftime("%F %T"),
        "total_pages": total,
        "done_pages": state["done_pages"],
        "in_flight_pages": in_flight,
        "queued_pages": len(state["queue"]),
        "failed_pages": len(state["failed"]),
        "spent_usd": round(state["spent"], 2),
        "budget_usd": BUDGET_USD,
        "per_page_usd": round(state["spent"] / state["done_pages"], 4) if state["done_pages"] else None,
        "batches_in_flight": sum(1 for b in state["batches"].values() if not b.get("collected")),
        "finished": in_flight == 0 and (not state["queue"] or state.get("budget_stop", False)),
        "budget_stop": state.get("budget_stop", False),
        "note": note,
    }
    STATUS.write_text(json.dumps(status, indent=1), encoding="utf-8")
    return status


def render_all(pages: list[dict]) -> None:
    def one(p):
        pilot.render(Path(p["pdf"]), p["page"], IMAGES / f"{p['id']}.jpg")
    with ThreadPoolExecutor(max_workers=24) as pool:
        list(pool.map(one, pages))


def submit(api: anthropic.Anthropic, state: dict, by_id: dict) -> bool:
    """Submit the next batch if the budget allows; False when nothing went out."""
    if not state["queue"]:
        return False
    chunk = state["queue"][:BATCH_PAGES]
    in_flight = sum(len(b["pages"]) for b in state["batches"].values() if not b.get("collected"))
    per_page = estimate(state)
    committed = state["spent"] + in_flight * per_page
    if committed + len(chunk) * per_page > BUDGET_USD:
        # A smaller final batch may still fit.
        room = int((BUDGET_USD - committed) / per_page)
        if room < 10:
            if in_flight == 0:
                state["budget_stop"] = True
                log(f"budget reached: ${state['spent']:.2f} spent, {len(state['queue'])} pages left for next month")
            return False
        chunk = chunk[:room]
    pages = [by_id[pid] for pid in chunk]
    render_all(pages)
    number = state["next_batch"]
    requests = [pilot.request(f"b{number:03d}-{i:03d}", IMAGES / f"{p['id']}.jpg", "low") for i, p in enumerate(pages)]
    for attempt in range(5):
        try:
            batch = api.messages.batches.create(requests=requests)
            break
        except (anthropic.RateLimitError, anthropic.InternalServerError, anthropic.APIConnectionError) as error:
            log(f"batch {number} not accepted yet ({type(error).__name__}), retrying in 60 s")
            time.sleep(60)
    else:
        return False
    state["batches"][batch.id] = {"number": number, "pages": chunk, "collected": False}
    state["queue"] = state["queue"][len(chunk):]
    state["next_batch"] = number + 1
    save(state)
    log(f"submitted batch {number} ({len(chunk)} pages) as {batch.id}; committed about ${committed + len(chunk) * per_page:.0f}")
    return True


def collect(api: anthropic.Anthropic, state: dict) -> None:
    for batch_id, info in state["batches"].items():
        if info.get("collected"):
            continue
        batch = api.messages.batches.retrieve(batch_id)
        if batch.processing_status != "ended":
            continue
        cost = 0.0
        for item in api.messages.batches.results(batch_id):
            index = int(item.custom_id.split("-")[1])
            pid = info["pages"][index]
            entry = {"id": pid, "model": pilot.MODEL, "effort": "low"}
            if item.result.type == "succeeded":
                message = item.result.message
                usage = {"input_tokens": message.usage.input_tokens, "output_tokens": message.usage.output_tokens}
                cost += page_cost(usage)
                entry["usage"] = usage
                text = next((b.text for b in message.content if b.type == "text"), "")
                if message.stop_reason == "end_turn" and text:
                    entry["page"] = json.loads(text)
                    (PAGES_OUT / f"{pid}.json").write_text(json.dumps(entry, ensure_ascii=False), encoding="utf-8")
                    state["done_pages"] += 1
                    continue
                entry["error"] = f"stopped: {message.stop_reason}"
            else:
                entry["error"] = item.result.type
            state["attempts"][pid] = state["attempts"].get(pid, 0) + 1
            if state["attempts"][pid] < MAX_ATTEMPTS:
                state["queue"].append(pid)
            else:
                state["failed"].append({"id": pid, "error": entry["error"]})
        state["spent"] += cost
        info["collected"] = True
        info["cost"] = round(cost, 4)
        save(state)
        log(f"collected batch {info['number']}: ${cost:.2f}; total ${state['spent']:.2f}, {state['done_pages']} pages done")


def run() -> int:
    RUN.mkdir(parents=True, exist_ok=True)
    PAGES_OUT.mkdir(exist_ok=True)
    pages = all_pages()
    by_id = {p["id"]: p for p in pages}
    if STATE.exists():
        state = json.loads(STATE.read_text(encoding="utf-8"))
    else:
        state = {"queue": [p["id"] for p in pages], "batches": {}, "next_batch": 0,
                 "spent": 0.0, "done_pages": 0, "attempts": {}, "failed": []}
        save(state)
    api = pilot.client()
    log(f"run started: {len(state['queue'])} pages queued, ${state['spent']:.2f} spent, budget ${BUDGET_USD:.2f}")
    while True:
        collect(api, state)
        # Keep submitting while the budget allows; the batches run in parallel.
        while submit(api, state, by_id):
            pass
        status = write_status(state, len(pages))
        if status["finished"]:
            log(f"finished: {state['done_pages']} pages, ${state['spent']:.2f}, {len(state['failed'])} failed, "
                f"{len(state['queue'])} left for next month")
            return 0
        time.sleep(60)


def status() -> int:
    print(STATUS.read_text(encoding="utf-8") if STATUS.exists() else "not started")
    return 0


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    sys.exit(run() if command == "run" else status())
