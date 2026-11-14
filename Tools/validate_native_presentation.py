"""Fail release builds when public copy sends people to website content.

Source and media URLs remain valid transport metadata. This check inspects only
copy that the app can present to a reader.
"""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = re.compile(
    r"\bwebsite\b|naqshbandiaowaisiah\.(?:org|us)|view source|full version|read from (?:a |the )?url",
    re.IGNORECASE,
)

SEED_COPY_FIELDS = {
    "announcements.json": {"title", "body"},
    "events.json": {"title", "titleUrdu", "details", "venue"},
    "zikr_sessions.json": {"title", "instructions", "availabilityNote"},
}

# Reporting filters identify where attendees joined; they are not links that
# hand native reading off to a browser. Keep the exception exact and confined
# to localization labels, so content and new handoff copy remain checked.
ADMIN_CHANNEL_LABELS = {"App or website", "On the website", "Website", "Website visitors"}


def load_json(path: Path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def check(label: str, value: object, failures: list[str], *, admin_channel_label: bool = False) -> None:
    if admin_channel_label and isinstance(value, str) and value in ADMIN_CHANNEL_LABELS:
        return
    if isinstance(value, str) and FORBIDDEN.search(value):
        failures.append(f"{label}: {value}")


def main() -> int:
    failures: list[str] = []
    seed_root = ROOT / "DarulIrfanApp" / "Resources" / "SeedData"
    for filename, fields in SEED_COPY_FIELDS.items():
        rows = load_json(seed_root / filename)
        for index, row in enumerate(rows):
            for field in fields:
                check(f"{filename}[{index}].{field}", row.get(field), failures)

    catalog = load_json(
        ROOT / "DarulIrfanApp" / "Resources" / "Localizations" / "Localizable.xcstrings"
    )
    for key, entry in catalog.get("strings", {}).items():
        admin_label = key in ADMIN_CHANNEL_LABELS
        check(f"Localizable key {key!r}", key, failures, admin_channel_label=admin_label)
        for language, localization in entry.get("localizations", {}).items():
            value = localization.get("stringUnit", {}).get("value")
            check(f"Localizable {language} value for {key!r}", value, failures, admin_channel_label=admin_label)

    if failures:
        print("Public copy must remain app-native:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("Native-presentation copy check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
