"""Add English + Urdu entries to Localizable.xcstrings from a {key: urdu} file.

Keys already translated are left exactly as they are; a key present without
Urdu gains it. The catalog is written back in the format Xcode itself uses
(2-space JSON, CRLF, no final newline), so the diff shows only new entries.

Usage: add_catalog_entries.py urdu_additions.json
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "DarulIrfanApp" / "Resources" / "Localizations" / "Localizable.xcstrings"
SPEC = re.compile(r"%(?:\d+\$)?(?:lld|@|lf|\.\d+f|d)")


def specs(text: str) -> list[str]:
    return sorted(re.sub(r"\d+\$", "", s) for s in SPEC.findall(text))


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    additions = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    raw = CATALOG.read_bytes().decode("utf-8")
    catalog = json.loads(raw)
    strings = catalog["strings"]
    added = filled = kept = 0
    for key, urdu in additions.items():
        # A translation must carry the same placeholders as its key, or the
        # formatted string crashes or drops a value at runtime.
        if specs(key) != specs(urdu):
            raise SystemExit(f"placeholder mismatch: {key!r} -> {urdu!r}")
        unit = {"stringUnit": {"state": "translated", "value": urdu}}
        entry = strings.get(key)
        if entry is None:
            strings[key] = {
                "extractionState": "manual",
                "localizations": {
                    "en": {"stringUnit": {"state": "translated", "value": key}},
                    "ur": unit,
                },
            }
            added += 1
        elif not entry.get("localizations", {}).get("ur", {}).get("stringUnit", {}).get("value"):
            entry.setdefault("localizations", {})["ur"] = unit
            filled += 1
        else:
            kept += 1
    out = json.dumps(catalog, ensure_ascii=False, indent=2).replace("\n", "\r\n")
    CATALOG.write_bytes(out.encode("utf-8"))
    print(f"added {added}, filled {filled}, already translated {kept}; catalog now {len(strings)} keys")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
