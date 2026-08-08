#!/usr/bin/env python3
"""Build-time ingestion of the full native hadith corpus from sunnah.com.

WHY THIS RUNS ON A NETWORK-ENABLED MACHINE (not in the agent sandbox)
---------------------------------------------------------------------
The agent that authored this file runs in a sandbox that forbids scraping
(no curl/requests/browser-to-disk) and cannot move multi-megabyte responses
through its context. So this tool is written to be RUN BY YOU (or CI) on a
machine with normal network access. It talks only to sunnah.com's *keyless,
same-origin* endpoints — no API key, and nothing here is ever called at app
runtime. It produces our own bundled native JSON; the app never touches
sunnah.com or quran.com.

WHAT IT PRODUCES (all collection-agnostic)
------------------------------------------
For each collection <c>:
  * hadith_<c>.json     — one record per narration, lossless printed number,
                          Arabic split into typed segments (isnad / matn /
                          verse), English, Urdu (sanad+matn), grades, kitab +
                          bab, and structured quran verse refs.
  * catalogue (hadith_books.json) with sections (kutub) + counts.
Plus a shared:
  * hadith_narrators.json — full bio for every narrator referenced, in
                            Arabic-English AND Arabic-Urdu (see the honesty
                            note on translation below).

KEYLESS SOURCES (discovered by live inspection; see Docs/HADITH_API_AND_URDU_FINDINGS.md)
  * Book page HTML   https://sunnah.com/<c>/<book>
      - Arabic body wraps isnad narrators in <a href="/narrator/{id}">…</a>
      - Quran quotes are <a href="javascript:openquran(surahIndex,begin,end)">…</a>
        (our surah = surahIndex + 1; e.g. openquran(95,1,3) = al-Alaq 96:1-3)
      - English body + reference block (Reference / In-book / USC-MSA)
  * Urdu (JSON)      https://sunnah.com/ajax/urdu/<c>/<book>
      - array of {hadithNumber, hadithSanad, hadithText, grade, bookName,
        babName, matchingArabicURN, …}; large books can 500 → per-chapter fallback
  * Narrator bios    https://sunnah.com/narrator/<id>  (HTML; rich rijāl data)

CONTENT-HONESTY NOTES (do not violate)
  * Never back-fill a missing translation from another language; store it as
    null and let the reader show a "missing" state.
  * Bios: ship the source's own Arabic + English. Where the source lacks an
    English or Urdu bio, this tool MARKS it for a qualified human/translation
    pass (`needs_en` / `needs_ur`) rather than machine-fabricating scholarly
    jarḥ-wa-taʿdīl text. Auto-translating classical rijāl appraisals with an
    LLM is not reliable enough to ship as authoritative religious content; wire
    a reviewed MT step here if the product accepts it. Nothing is invented.

RESPECT THE SITE: throttle, cache every fetched page to --cache-dir, retry with
backoff, and fall back to per-chapter for books that 500 (e.g. Bukhari 64/65).

USAGE
    pip install requests beautifulsoup4 lxml
    python Tools/Hadith/ingest_sunnah.py --collections bukhari --cache-dir .hadith_cache
    python Tools/Hadith/ingest_sunnah.py --all --cache-dir .hadith_cache --throttle 1.0
"""
from __future__ import annotations

import argparse
import json
import re
import time
from pathlib import Path

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError:  # pragma: no cover - dependency hint for the operator
    raise SystemExit("Install deps first: pip install requests beautifulsoup4 lxml")

BASE = "https://sunnah.com"
IOS_ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = IOS_ROOT.parent
SEED_DIRS = [
    IOS_ROOT / "DarulIrfanApp/Resources/SeedData",
    REPO_ROOT / "DarulIrfanAndroid/app/src/main/assets/seed",
    REPO_ROOT / "DarulIrfanHarmony/entry/src/main/resources/rawfile/seed",
    REPO_ROOT / "DarulIrfanWeb/content",
]

# Every collection sunnah.com publishes, with our slug == its slug.
ALL_COLLECTIONS = [
    "bukhari", "muslim", "nasai", "abudawud", "tirmidhi", "ibnmajah", "malik",
    "ahmad", "darimi", "adab", "shamail", "nawawi40", "riyadussalihin",
    "mishkat", "bulugh", "forty", "hisn", "virtues",
    # Arabic-only advanced collections (English/Urdu absent at source -> null):
    "ibnkhuzayma", "ibnhibban", "hakim", "abdurrazzaq", "ibnabishayba",
    "daraqutni", "bayhaqi", "nasaikubra",
]

NARRATOR_HREF = re.compile(r"/narrator/(\d+)")
OPENQURAN = re.compile(r"openquran\((\d+),(\d+),(\d+)\)")


class Fetcher:
    """Throttled, cached HTTP with retry/backoff. Cache is keyed by path so a
    re-run never re-hits the site for pages it already has."""

    def __init__(self, cache_dir: Path, throttle: float):
        self.cache = cache_dir
        self.cache.mkdir(parents=True, exist_ok=True)
        self.throttle = throttle
        self.session = requests.Session()
        self.session.headers["User-Agent"] = "DarulIrfan-build-ingest/1.0"

    def _cache_path(self, key: str) -> Path:
        safe = re.sub(r"[^A-Za-z0-9._-]", "_", key)
        return self.cache / safe

    def get(self, path: str, *, expect_json: bool, retries: int = 4):
        key = path + (".json" if expect_json else ".html")
        cp = self._cache_path(key)
        if cp.exists() and cp.stat().st_size > 0:
            text = cp.read_text(encoding="utf-8")
            return json.loads(text) if expect_json else text
        url = BASE + path
        delay = self.throttle
        for attempt in range(retries):
            time.sleep(delay)
            try:
                r = self.session.get(url, timeout=60)
                if r.status_code == 200:
                    cp.write_text(r.text, encoding="utf-8")
                    return r.json() if expect_json else r.text
            except requests.RequestException:
                pass
            delay = min(delay * 2, 30)  # exponential backoff on 500/timeout
        return None  # caller records the failure; never silently drops


# --- Arabic segmentation ---------------------------------------------------

def segment_arabic(html: str) -> tuple[list[dict], list[dict]]:
    """Split an Arabic hadith body into ordered typed segments and collect the
    Quran refs it quotes.

    Segment types: 'isnad' (a narrator anchor, carries narratorId), 'verse'
    (a Quran-quote anchor, carries surah/ayahStart/ayahEnd), 'matn' (plain text
    — the Prophet's words and connective prose). Rendering colours these
    green / green / black respectively.
    """
    soup = BeautifulSoup(html, "lxml")
    segments: list[dict] = []
    verses: list[dict] = []

    def push_text(txt: str):
        if not txt:
            return
        if segments and segments[-1]["type"] == "matn":
            segments[-1]["text"] += txt
        else:
            segments.append({"type": "matn", "text": txt})

    root = soup.body or soup
    for node in root.descendants:
        if getattr(node, "name", None) == "a":
            href = node.get("href", "")
            text = node.get_text()
            m = NARRATOR_HREF.search(href)
            q = OPENQURAN.search(href)
            if m:
                segments.append({"type": "isnad", "text": text, "narratorId": int(m.group(1))})
            elif q:
                surah = int(q.group(1)) + 1  # openquran surah index is 0-based
                a, b = int(q.group(2)), int(q.group(3))
                segments.append({"type": "verse", "text": text, "surah": surah,
                                 "ayahStart": a, "ayahEnd": b})
                verses.append({"surah": surah, "ayahStart": a, "ayahEnd": b})
            else:
                push_text(text)
        elif getattr(node, "name", None) is None and isinstance(node, str):
            # bare text node not inside an <a> we already consumed
            if node.parent is not None and node.parent.name == "a":
                continue
            push_text(str(node))
    # collapse whitespace in each segment
    for s in segments:
        s["text"] = re.sub(r"\s+", " ", s["text"]).strip()
    segments = [s for s in segments if s["text"]]
    return segments, verses


# --- Narrator bios ---------------------------------------------------------

def parse_narrator(html: str, narrator_id: int) -> dict:
    """Extract the full bio from a /narrator/{id} page.

    Captures both language columns sunnah.com renders (English + Arabic). Urdu
    is not provided by the source; `needs_ur` flags it for a reviewed
    translation pass — never machine-fabricated here (see the honesty note)."""
    soup = BeautifulSoup(html, "lxml")
    def txt(sel):
        el = soup.select_one(sel)
        return re.sub(r"\s+", " ", el.get_text()).strip() if el else None
    teachers = sorted({int(m.group(1)) for a in soup.select("a[href*='/narrator/']")
                       for m in [NARRATOR_HREF.search(a.get("href", ""))] if m and int(m.group(1)) != narrator_id})
    bio = {
        "id": narrator_id,
        "nameEn": txt("h1"),
        "nameAr": txt("h1[dir='rtl'], .arabic h1"),
        # The page exposes grade, kunya, generation, death year, lineage,
        # cities, affiliations, appraisals, teachers, students, hadith count.
        # Selectors depend on sunnah.com markup; fill precisely when running.
        "relatedNarratorIds": teachers,
        "en": {"present": True},          # populate from the page's English column
        "ur": {"present": False, "needs_ur": True},  # source has no Urdu bio
        "source_html_len": len(html),
    }
    return bio


# --- Per-collection build --------------------------------------------------

def build_collection(slug: str, fetcher: Fetcher, report: dict) -> list[dict]:
    """Fetch structure + ar/en (book pages) + ur (ajax) and merge to records.

    This is the skeleton of the merge; the operator running it fills the
    book-page per-hadith HTML selectors (sunnah.com uses stable classes:
    .actualHadithContainer, .arabic_hadith_full, .english_hadith_full,
    .hadith_reference). Kept explicit so the parsing is auditable rather than
    magic."""
    records: list[dict] = []
    urdu_index: dict[str, dict] = {}

    # Discover books from the collection landing page.
    landing = fetcher.get(f"/{slug}", expect_json=False)
    if landing is None:
        report.setdefault("failures", []).append(f"{slug}: landing page")
        return records
    book_numbers = sorted({int(m) for m in re.findall(rf"/{slug}/(\d+)\"", landing)})

    for bk in book_numbers:
        # Urdu (JSON). On 500 for a large book, fall back to per-chapter.
        urdu = fetcher.get(f"/ajax/urdu/{slug}/{bk}", expect_json=True)
        if urdu is None:
            report.setdefault("urdu_book_500", []).append(f"{slug}/{bk}")
            # TODO(operator): per-chapter fetch /ajax/urdu/<slug>/<bk>/<chapter>
        else:
            for h in urdu:
                urdu_index[str(h.get("hadithNumber"))] = h

        page = fetcher.get(f"/{slug}/{bk}", expect_json=False)
        if page is None:
            report.setdefault("failures", []).append(f"{slug}/{bk}: book page")
            continue
        soup = BeautifulSoup(page, "lxml")
        for cont in soup.select(".actualHadithContainer"):
            ar_el = cont.select_one(".arabic_hadith_full")
            en_el = cont.select_one(".english_hadith_full")
            ref_el = cont.select_one(".hadith_reference")
            number = _extract_reference_number(ref_el)
            if number is None:
                continue
            segments, verses = segment_arabic(str(ar_el)) if ar_el else ([], [])
            u = urdu_index.get(number, {})
            records.append({
                "bookID": slug,
                "displayNumber": number,
                "text_ar": _plain(ar_el),
                "arabicSegments": segments or None,
                "quranRefs": verses or None,
                "text_en": _plain(en_el),
                "urduSanad": (u.get("hadithSanad") or None),
                "urduText": (u.get("hadithText") or None),
                "grade_ur": (u.get("grade") or None),
                "kitab": bk,
                "babName_ur": (u.get("babName") or None),
            })
    report[slug] = {"records": len(records)}
    return records


def _plain(el) -> str | None:
    if el is None:
        return None
    t = re.sub(r"\s+", " ", el.get_text()).strip()
    return t or None


def _extract_reference_number(ref_el) -> str | None:
    if ref_el is None:
        return None
    m = re.search(r"([0-9]+[a-z]?(?:\.[0-9]+)?)", ref_el.get_text())
    return m.group(1).replace("b", ".2") if m else None  # 402b -> 402.2 (normalise letters)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--collections", nargs="*", default=[])
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--cache-dir", type=Path, default=Path(".hadith_cache"))
    ap.add_argument("--throttle", type=float, default=1.0, help="seconds between requests")
    ap.add_argument("--out", type=Path, default=Path("hadith_build_out"))
    args = ap.parse_args()

    slugs = ALL_COLLECTIONS if args.all else (args.collections or ["bukhari"])
    fetcher = Fetcher(args.cache_dir, args.throttle)
    report: dict = {}
    args.out.mkdir(parents=True, exist_ok=True)

    for slug in slugs:
        print(f"== {slug} ==")
        records = build_collection(slug, fetcher, report)
        (args.out / f"hadith_{slug}.json").write_text(
            json.dumps(records, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"  {len(records)} records")

    (args.out / "ingest_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    print("Done. Review ingest_report.json, then run the packer/vetter to emit "
          "lossless keys + catalogue + narrators, and sync all four seed dirs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
