"""Gather the reviewed decisions into `decisions.json`.

A finding that changes wording (not spacing, punctuation or a one-letter
slip) is read by a reviewer, who writes `apply` or `hold` and a short reason.
The reviews are kept as batches outside the repository
(`outputs/darul-urdu-proofread-apply/review/decisions-NN.json`, each
`{finding id: [decision, note]}`); this gathers them into the one file
`apply_proofread.py` reads. A decision already in `decisions.json` is kept:
later batches only add.

    python Tools/Content/urdu_proofread/merge_decisions.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from apply_proofread import HERE, OUT


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    target = HERE / "decisions.json"
    decisions = json.loads(target.read_text(encoding="utf-8")) if target.exists() else {}
    added = 0
    for batch in sorted((OUT / "review").glob("decisions-*.json")):
        for fid, (action, note) in json.loads(batch.read_text(encoding="utf-8")).items():
            if fid in decisions:
                continue
            if action not in ("apply", "hold"):
                raise SystemExit(f"{batch.name}: {fid} has the decision {action!r}")
            decisions[fid] = {"action": action, "note": note}
            added += 1
    target.write_text(json.dumps(dict(sorted(decisions.items())), ensure_ascii=False, indent=1) + "\n",
                      encoding="utf-8", newline="\n")
    counts = {action: sum(1 for d in decisions.values() if d["action"] == action) for action in ("apply", "apply-as", "hold")}
    print(f"decisions.json: {len(decisions)} decisions ({added} new): {counts}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
