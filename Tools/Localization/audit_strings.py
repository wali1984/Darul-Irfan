"""List every user-facing string literal in the Swift source and whether the
String Catalog translates it.

Xcode extracts these keys when the project is built *in Xcode*; the CI build
does not write the catalog back, so a string added in code but never added to
`Localizable.xcstrings` silently falls back to English in the Urdu UI. This
audit is what finds them. It reads the literals in the SwiftUI positions that
take a `LocalizedStringKey` (and `String(localized:)`), turns interpolations
into the catalog's format specifiers, and reports the keys with no Urdu.

Usage: audit_strings.py [--json OUT]   (exit 1 when any key lacks Urdu)
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = [ROOT / "DarulIrfanApp", ROOT / "Widgets"]
CATALOG = ROOT / "DarulIrfanApp" / "Resources" / "Localizations" / "Localizable.xcstrings"

# A Swift string literal (no multi-line literals in these positions).
LIT = r'"((?:[^"\\]|\\.)*)"'
CALLS = [
    r"\bText\(\s*" + LIT,
    r"\bLabel\(\s*" + LIT,
    r"\bButton\(\s*" + LIT,
    r"\bToggle\(\s*" + LIT,
    r"\bPicker\(\s*" + LIT,
    r"\bTextField\(\s*" + LIT,
    r"\bSecureField\(\s*" + LIT,
    r"\bLink\(\s*" + LIT,
    r"\bProgressView\(\s*" + LIT,
    r"\bStepper\(\s*" + LIT,
    r"\bMenu\(\s*" + LIT,
    r"\bSection\(\s*" + LIT,
    r"\bNavigationLink\(\s*" + LIT,
    r"\.navigationTitle\(\s*" + LIT,
    r"\.diPageHeading\(\s*" + LIT,
    r"\.alert\(\s*" + LIT,
    r"\.confirmationDialog\(\s*" + LIT,
    r"\.accessibilityLabel\(\s*" + LIT,
    r"\.accessibilityHint\(\s*" + LIT,
    r"\.accessibilityValue\(\s*" + LIT,
    r"\bString\(localized:\s*" + LIT,
    r"\bLocalizedStringKey\(\s*" + LIT,
    r"\b(?:titleKey|messageKey|subtitleKey|labelKey|detailKey|hintKey|captionKey|textKey):\s*" + LIT,
]
PATTERN = re.compile("|".join(f"(?:{c})" for c in CALLS))
INTERP = re.compile(r"\\\(([^()]*(?:\([^()]*\)[^()]*)*)\)")

# Interpolations whose value is an integer, judged from how they are named.
INT_HINT = re.compile(
    r"(count|Count|number|Number|index|Index|ayah|Ayah|surah\.id|\.id\b|page|Page|minutes|Minutes|"
    r"days|Days|hours|Hours|repeats|repetition|total|Total|rangeStart|rangeEnd|parah|year|offset|"
    r"ayahStart|ayahEnd|unresolved|completed|streak|target|Target|goal|Goal|seconds|Seconds)"
)
DOUBLE_HINT = re.compile(r"\b(pauseSeconds|rate|playbackRate|percent|fraction|progress)\b")


# Where the name-based guess picks the wrong placeholder (the value's type is
# not visible in its name), or a nested string literal cuts the match short,
# the key Swift really generates is recorded here.
KNOWN_KEYS = {
    "%@ minutes before": "%lld minutes before",
    "Go to %@ %@:%lld": "Go to %@ %lld:%lld",
    "Pages %@ to %@": "Pages %lld to %lld",
    "Live on Paltalk now · %@ listening": "Live on Paltalk now · %lld listening",
    "%@%": "%lld%",
    "%@. %@": "%lld. %@",
    "%lf% played": "%lld% played",
    "All of %lld": "All of %@",
    "In-book reference: Book %@, Hadith %@": "In-book reference: Book %lld, Hadith %lld",
    "Jump to %lld": "Jump to %@",
    "Last updated %lld": "Last updated %@",
    "Name %@ of 99": "Name %lld of 99",
    "Parah %@": "Parah %lld",
    "Pause \\(pauseSeconds, specifier: ": "Pause %.1f seconds",
    "Published %lld": "Published %@",
    "Qibla is %@° to your left": "Qibla is %lld° to your left",
    "Qibla is %@° to your right": "Qibla is %lld° to your right",
    "Qibla: %@° from North": "Qibla: %lld° from North",
    "Qibla: %@° from true north": "Qibla: %lld° from true north",
    "Qur'an %@:%@": "Qur'an %lld:%lld",
    "Qur'an %@:%@-%@": "Qur'an %lld:%lld-%lld",
    "Resume %@, %lf percent played": "Resume %@, %lld percent played",
    "Step %@ of %lld": "Step %lld of %lld",
    "Surah %@ (%@), Ayah %@": "Surah %@ (%lld), Ayah %@",
    "%@ minutes": "%lld minutes",
    "Surah %@ (%@), Ayat %@": "Surah %@ (%lld), Ayat %@",
    "Surah %@, Ayah %lld — Quran %@:%lld": "Surah %@, Ayah %lld — Quran %lld:%lld",
    "%@ attended": "%lld attended",
    "%@ listening": "%lld listening",
    "The group is at %@ of %lld": "The group is at %@ of %@",
    "The download could not be completed right now (server status %@). Please try again later.":
        "The download could not be completed right now (server status %lld). Please try again later.",
    "Updated \\(current.updatedAt.formatted(.relative(presentation: .named)))": "Updated %@",
    "Now in the zikr · \\(cue.at.formatted(.relative(presentation: .named)))": "Now in the zikr · %@",
}


def to_key(literal: str) -> str:
    def spec(match: re.Match) -> str:
        expression = match.group(1)
        if "specifier:" in expression:
            return re.search(r'specifier:\s*"([^"]+)"', expression).group(1)
        last = expression.split(".")[-1].strip()
        if DOUBLE_HINT.search(last):
            return "%lf"
        if INT_HINT.search(last):
            return "%lld"
        return "%@"
    key = INTERP.sub(spec, literal)
    key = key.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")
    return KNOWN_KEYS.get(key, key)


def literals() -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}
    for base in SOURCES:
        for path in sorted(base.rglob("*.swift")):
            text = path.read_text(encoding="utf-8")
            for match in PATTERN.finditer(text):
                line_start = text.rfind("\n", 0, match.start()) + 1
                if text[line_start:match.start()].lstrip().startswith("//"):
                    continue
                literal = next(group for group in match.groups() if group is not None)
                if not re.search(r"[A-Za-z]", literal):
                    continue
                line = text.count("\n", 0, match.start()) + 1
                found.setdefault(to_key(literal), []).append(f"{path.relative_to(ROOT)}:{line}")
    return found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json")
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))["strings"]
    found = literals()
    missing = {}
    for key, places in sorted(found.items()):
        entry = catalog.get(key, {})
        urdu = entry.get("localizations", {}).get("ur", {}).get("stringUnit", {}).get("value")
        if not urdu:
            missing[key] = places
    print(f"literals {len(found)} | in catalog with Urdu {len(found) - len(missing)} | missing Urdu {len(missing)}")
    if args.json:
        Path(args.json).write_text(json.dumps(missing, ensure_ascii=False, indent=1), encoding="utf-8", newline="\n")
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
