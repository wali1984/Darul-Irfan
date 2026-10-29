"""Read and write the bundled seed JSON without changing its layout.

Each seed file was written by a different tool, so they differ in indent
(none, 1 or 2), separators and the final newline. Rewriting one with a
different layout turns a one-field fix into a whole-file diff, which hides the
change from review. `load` works out the exact layout that reproduces the
file byte for byte, and `dump` writes the edited data back the same way.

Only the iOS seed folder is written. The other three platforms get the same
bytes from the release sync, which also bumps manifest.json once.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

IOS_ROOT = Path(__file__).resolve().parents[2]
SEED = IOS_ROOT / "DarulIrfanApp" / "Resources" / "SeedData"


@dataclass(frozen=True)
class Layout:
    indent: int | None
    separators: tuple[str, str] | None
    ensure_ascii: bool
    final_newline: bool

    def render(self, data: object) -> str:
        body = json.dumps(data, ensure_ascii=self.ensure_ascii, indent=self.indent,
                          separators=self.separators)
        return body + ("\n" if self.final_newline else "")


CANDIDATES = [
    Layout(indent, separators, ensure_ascii, newline)
    for indent, separators in ((None, (",", ":")), (None, None), (1, None), (2, None), (4, None))
    for ensure_ascii in (False, True)
    for newline in (False, True)
]


def load(name: str) -> tuple[object, Layout]:
    """Return the decoded seed file and the layout that reproduces it exactly."""
    raw = (SEED / name).read_text(encoding="utf-8")
    data = json.loads(raw)
    for layout in CANDIDATES:
        if layout.render(data) == raw:
            return data, layout
    raise SystemExit(f"{name}: no known JSON layout reproduces this file byte for byte")


def dump(name: str, data: object, layout: Layout) -> None:
    """Write `data` with the file's original layout (UTF-8, LF, no BOM)."""
    (SEED / name).write_text(layout.render(data), encoding="utf-8", newline="")
