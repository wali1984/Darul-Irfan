#!/usr/bin/env python3
"""Fill Urdu gaps from ahlesunnatpak.com by matching the Arabic itself.

WHY THIS SOURCE
sunnah.com's Urdu endpoint returns 500 for Mishkat, Musnad Ahmad and others,
and Bukhari books 64-65 and ~1,800 Nasa'i narrations have no Urdu there at all.
ahlesunnatpak.com carries paired Arabic+Urdu for those works (robots.txt allows
all crawling; no edition attribution is published — recorded in
Docs/HADITH_COVERAGE_GAPS.md).

WHY CONTENT-JOIN, NOT POSITION OR NUMBER
Their numbering uses grouped labels — "(۵،۶)" printed on two or three
consecutive blocks — so numbers neither align with ours nor identify a single
narration. Positional pairing is what corrupted the Asrar Urdu tafsir. So each
of their Arabic texts is keyed with the same folded `arabic_key` used by the
sunnah.com enrichment (their Arabic is typeset with Urdu code points; the key
folds them), and their Urdu attaches ONLY to a record whose Arabic keys
identically and uniquely on both sides. No key, no unique match -> no fill.

WHAT IT WRITES
Only records whose `text_ur` is empty gain one, tagged
    urduSource: "ahlesunnatpak.com"
    urduReviewState: "machine_provisional"
Existing Urdu (fawazahmed0 / sunnah.com) is never replaced. Report-only unless
--apply; with --apply it writes all four platform seed dirs.

USAGE
    python Tools/Hadith/asp_urdu_ingest.py --cache-dir CACHE [--apply]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ingest_sunnah import (  # noqa: E402
    Fetcher, SEED_DIRS, PRIMARY_SEED, arabic_key, clean,
)
from bs4 import BeautifulSoup  # noqa: E402

ASP = "https://ahlesunnatpak.com"
# their slug -> our pack slug
TARGETS = {
    "mishkat": "mishkat",
    "musnad_ahmed": "ahmad",
    "nasai": "nasai",
    "bukhari": "bukhari",
}
ARABIC_SEL = ".al-qalam-quran-font"
URDU_SEL = ".urdu.nastaleeq-font"
# "۔ (۵،۶)۔" — the printed label, kept verbatim for provenance only.
LABEL = re.compile(r"^\W{0,4}\(([۰-۹0-9،,\s]+)\)")


class AspFetcher(Fetcher):
    """Same throttle/cache/backoff behaviour, different host."""

    def get(self, path: str, *, expect_json: bool = False, retries: int = 5):
        # Cache keys are prefixed so they never collide with sunnah.com pages.
        import time as _t
        cp = self._cp("ASP_" + path + ".html")
        if cp.exists() and cp.stat().st_size > 0:
            return cp.read_text(encoding="utf-8")
        delay = self.throttle
        for _ in range(retries):
            _t.sleep(delay)
            try:
                r = self.s.get(ASP + path, timeout=90)
                if r.status_code == 200:
                    cp.write_text(r.text, encoding="utf-8")
                    return r.text
            except Exception:
                pass
            delay = min(delay * 2, 45)
        return None


def paired_blocks(html: str) -> list[tuple[str, str, str | None]]:
    """(arabic, urdu, printed_label) pairs in document order.

    Pairing walks the DOM: each Arabic block takes the Urdu blocks that follow
    it up to the next Arabic block. One Arabic + one Urdu is a pair; anything
    else on that stretch (zero, or several Urdu, as with chapter headings) is
    dropped rather than guessed — a wrong pairing is worse than a gap.
    """
    soup = BeautifulSoup(html, "lxml")
    events: list[tuple[str, str]] = []
    for el in soup.select(f"{ARABIC_SEL}, {URDU_SEL}"):
        classes = " ".join(el.get("class") or [])
        text = re.sub(r"\s+", " ", el.get_text()).strip()
        if not text:
            continue
        kind = "ar" if "al-qalam-quran-font" in classes else "ur"
        # The Urdu selector also matches unrelated nastaleeq chrome (headings,
        # "حدیث نمبر" captions); keep only substantive blocks.
        if kind == "ur" and len(text) < 25:
            continue
        events.append((kind, text))

    pairs: list[tuple[str, str, str | None]] = []
    i = 0
    while i < len(events):
        if events[i][0] != "ar":
            i += 1
            continue
        arabic = events[i][1]
        urdus = []
        j = i + 1
        while j < len(events) and events[j][0] == "ur":
            urdus.append(events[j][1])
            j += 1
        if len(urdus) == 1:
            label = LABEL.match(arabic)
            pairs.append((arabic, urdus[0], label.group(1) if label else None))
        i = j
    return pairs


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cache-dir", type=Path, required=True)
    ap.add_argument("--throttle", type=float, default=1.0)
    ap.add_argument("--apply", action="store_true",
                    help="write filled packs to all four seed dirs")
    ap.add_argument("--slugs", nargs="*", default=list(TARGETS))
    args = ap.parse_args()

    fetcher = AspFetcher(args.cache_dir, args.throttle)
    report: dict = {}

    for asp_slug in args.slugs:
        ours = TARGETS[asp_slug]
        pack_path = PRIMARY_SEED / f"hadith_{ours}.json"
        if not pack_path.exists():
            print(f"== {asp_slug}: no local pack hadith_{ours}.json, skipped ==")
            continue
        records = json.loads(pack_path.read_text(encoding="utf-8"))

        # Unique-key index of OUR records, same discipline as the sunnah join:
        # a key two records share is unusable, because filling either would be
        # a guess.
        index: dict[str, dict | None] = {}
        for r in records:
            # From-scratch packs built before the text_ar fix carry only typed
            # segments; key from their joined text when the plain field is
            # empty so those packs are still joinable.
            text = r.get("text_ar") or " ".join(
                s.get("text", "") for s in (r.get("arabicSegments") or []))
            k = arabic_key(text)
            if k:
                index[k] = r if k not in index else None
        index = {k: v for k, v in index.items() if v is not None}

        landing = fetcher.get(f"/hadith/{asp_slug}")
        if landing is None:
            report[asp_slug] = {"error": "landing page unreachable"}
            print(f"== {asp_slug}: landing unreachable ==")
            continue
        book_ids = sorted(
            {int(m) for m in re.findall(rf"/hadith-details/{asp_slug}/(\d+)", landing)}
        )
        print(f"== {asp_slug} -> {ours}: {len(book_ids)} book pages, "
              f"{len(index)} unique local keys ==")

        pairs_total = matched = filled = already = ambiguous = 0
        for bid in book_ids:
            page = fetcher.get(f"/hadith-details/{asp_slug}/{bid}")
            if page is None:
                report.setdefault("failures", []).append(f"{asp_slug}/{bid}")
                continue
            for arabic, urdu, label in paired_blocks(page):
                pairs_total += 1
                k = arabic_key(arabic)
                if not k:
                    continue
                rec = index.get(k)
                if rec is None:
                    ambiguous += k in index
                    continue
                matched += 1
                if rec.get("text_ur") or rec.get("urduText"):
                    already += 1
                    continue
                rec["text_ur"] = clean(urdu)
                rec["urduText"] = rec["text_ur"]
                rec["urduSource"] = "ahlesunnatpak.com"
                rec["urduReviewState"] = "machine_provisional"
                if label:
                    rec["urduSourceLabel"] = label
                filled += 1

        report[asp_slug] = {
            "bookPages": len(book_ids), "pairs": pairs_total, "matched": matched,
            "alreadyHadUrdu": already, "filled": filled, "ambiguousKey": ambiguous,
        }
        print(f"   pairs={pairs_total} matched={matched} "
              f"already={already} FILLED={filled}")

        if args.apply and filled:
            text = json.dumps(records, ensure_ascii=False, indent=1) + "\n"
            for seed in SEED_DIRS:
                (seed / f"hadith_{ours}.json").write_text(
                    text, encoding="utf-8", newline="\n")
            print(f"   wrote hadith_{ours}.json to {len(SEED_DIRS)} seed dirs")

    print(json.dumps(report, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
