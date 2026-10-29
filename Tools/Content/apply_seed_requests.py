"""Apply seed change requests written by other work tracks.

A request file is a JSON list of
    {"file": "media_items.json", "match": {"id": "..."}, "set": {"field": value}, "why": "..."}
or, to add a row,
    {"file": "library_items.json", "add": {...the whole row...}, "after": "<id>", "why": "..."}
Each request is applied to the iOS seed only after it has been checked by the
person running this (the requests are not trusted blindly). The file keeps its
layout; a row written with sorted keys stays sorted, otherwise a new key goes
just before the row's checksum (or at the end); rows that carry a checksum get
a fresh one (Tools/ContentIngest/schema.py rule). A request whose row does not
exist stops the run, and so does an added row whose id is already used by a
different row.

    python Tools/Content/apply_seed_requests.py requests.json [more.json ...]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "ContentIngest"))
import schema  # noqa: E402

from seed_io import dump, load  # noqa: E402


def place(row: dict, key: str, value) -> dict:
    if key in row:
        row[key] = value
        return row
    if list(row) == sorted(row):
        row[key] = value
        return {k: row[k] for k in sorted(row)}
    keys = list(row)
    at = keys.index("checksum") if "checksum" in keys else len(keys)
    rebuilt = {k: row[k] for k in keys[:at]}
    rebuilt[key] = value
    rebuilt.update((k, row[k]) for k in keys[at:])
    return rebuilt


def main(paths: list[str]) -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    requests = [request for path in paths for request in json.loads(Path(path).read_text(encoding="utf-8"))]
    by_file: dict[str, list[dict]] = {}
    for request in requests:
        by_file.setdefault(request["file"], []).append(request)
    for name, batch in by_file.items():
        rows, layout = load(name)
        index = {row["id"]: i for i, row in enumerate(rows)}
        changed = 0
        for request in batch:
            if "add" in request:
                new = request["add"]
                if new["id"] in index:
                    if rows[index[new["id"]]] != new:
                        raise SystemExit(f"{name}: id {new['id']} is already used by a different row")
                    continue
                at = index[request["after"]] + 1 if request.get("after") in index else len(rows)
                rows.insert(at, new)
                index = {row["id"]: i for i, row in enumerate(rows)}
                changed += 1
                continue
            position = index.get(request["match"]["id"])
            if position is None:
                raise SystemExit(f"{name}: no row with id {request['match']['id']}")
            row = rows[position]
            was_sorted = list(row) == sorted(row)
            before = dict(row)
            for key, value in request["set"].items():
                row = place(row, key, value)
            if row != before:
                if "checksum" in row:
                    row["checksum"] = schema.checksum_for(row)
                if was_sorted:
                    row = {k: row[k] for k in sorted(row)}
                rows[position] = row
                changed += 1
        dump(name, rows, layout)
        print(f"{name}: {changed} of {len(batch)} requested rows changed")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    raise SystemExit(main(sys.argv[1:]))
