"""Write out the findings that still wait for a reading, and the held ones.

After `apply_proofread.py` has run, some findings change wording and have no
decision yet. This writes them as batches for a reviewer
(`outputs/darul-urdu-proofread-apply/review/batch-<stamp>-NN.json`); the
reviewer's answers go beside them as `decisions-<stamp>-NN.json`
(`{finding id: ["apply" | "hold", note]}`) and `merge_decisions.py` gathers
them.

It also writes `HELD.csv`: every finding that is not applied, with the reason,
for the owner to look through - the reader's questions about the printed
page, the changes to Arabic that were refused, the wording changes held.

    python Tools/Content/urdu_proofread/review_queue.py
"""

from __future__ import annotations

import csv
import json
import sys
from collections import Counter
from datetime import datetime

from apply_proofread import OUT

BATCH = 180
EVIDENCE = ("resolutionStatus", "originalInspection", "originalPageInspection", "parentRecheckNote")


def slim(finding: dict) -> dict:
    item = {"id": finding["id"], "confidence": finding["confidence"], "category": finding["category"],
            "flag": finding["ledger"]["why"], "original": finding["original"], "proposed": finding["suggested"],
            "reason": finding["reasonUrdu"], "context": finding["context"]}
    for key in EVIDENCE:
        if finding.get(key):
            value = finding[key] if isinstance(finding[key], str) else json.dumps(finding[key], ensure_ascii=False)
            item[key] = value[:500]
    return item


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    left = json.loads((OUT / "not-applied.json").read_text(encoding="utf-8"))
    waiting = [slim(finding) for finding in left if finding["ledger"]["status"] == "review"]
    folder = OUT / "review"
    folder.mkdir(exist_ok=True)
    stamp = datetime.now().strftime("%m%d-%H%M")
    names = []
    for number, start in enumerate(range(0, len(waiting), BATCH), 1):
        name = f"batch-{stamp}-{number:02d}.json"
        (folder / name).write_text(json.dumps(waiting[start:start + BATCH], ensure_ascii=False, indent=1), encoding="utf-8")
        names.append(name)
    print(f"{len(waiting)} findings wait for a reading: {names or 'nothing to write'}")

    with (OUT / "HELD.csv").open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["id", "book", "page", "status", "why", "confidence", "category", "as it stands", "proposed", "reader's reason"])
        for finding in left:
            entry = finding["ledger"]
            writer.writerow([finding["id"], finding["bookID"], finding["page"], entry["status"], entry["why"],
                             finding["confidence"], finding["category"], finding["original"], finding.get("suggested") or "",
                             finding["reasonUrdu"]])
    reasons = Counter((finding["ledger"]["status"], finding["ledger"]["why"].split(":")[0][:60]) for finding in left)
    print(f"HELD.csv: {len(left)} findings not applied")
    for (status, why), count in reasons.most_common(12):
        print(f"  {count:6}  {status}: {why}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
