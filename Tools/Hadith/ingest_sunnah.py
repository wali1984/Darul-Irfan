#!/usr/bin/env python3
"""Full build-time hadith pipeline: enrich the bundled corpus from sunnah.com.

RUN THIS ON A NETWORK-ENABLED MACHINE OR IN THE `hadith-ingest` CI WORKFLOW —
not in the agent sandbox (which forbids scraping) and not on every app build
(it would exceed Codemagic's max_build_duration and hammer the site). It uses
only sunnah.com's keyless, same-origin endpoints; nothing here runs at app
runtime and no sunnah.com/quran.com string is emitted into shipped data.

DESIGN: ENRICH, DON'T RE-KEY
----------------------------
The bundled packs already carry sunnah.com's exact reference numbers — including
the lossless sub-numbered keys (402.2, 1390.2/.3) and canonicalID — verified
against the site. This pipeline therefore *enriches those existing records in
place* (matched by displayNumber) rather than re-deriving keys, so losslessness
is preserved by construction. It adds, per narration:

  * arabicSegments  — the Arabic split into typed spans (isnad / matn / verse),
                      with narratorId on isnad spans and surah/ayah on verse
                      spans (from the book page's <a href="/narrator/{id}"> and
                      openquran(surahIndex,begin,end); our surah = index + 1).
  * quranRefs       — the same verse refs, flat, for quick linking.
  * text_en         — filled from sunnah.com where the pack lacked it.
  * urduSanad / urduText — the Urdu chain + text, split (from /ajax/urdu).
  * chapter (bab)   — number + English/Arabic/Urdu title.

and, across the corpus, a narrator store (hadith_narrators.json): every narrator
referenced by any shipped chain, with a full biography in Arabic-English AND
Arabic-Urdu. Where the source lacks the Urdu, the existing bio is AUTO-TRANSLATED
into Urdu (see Translator). A narrator is marked "missing" only when the source
has no biography in any language — a bio that does not exist is never fabricated.

KEYLESS SOURCES
  * Book page HTML      https://sunnah.com/<c>/<book>     (anchored Arabic + EN + refs + chapters)
  * Urdu (JSON)         https://sunnah.com/ajax/urdu/<c>/<book>   (per-chapter fallback on 500)
  * Narrator bios       https://sunnah.com/narrator/<id>

OUTPUT (all four platforms, byte-identical) + a per-collection vetting report,
then a manifest bump. Gentle: throttle, cache, exponential backoff, resumable
(cache-keyed), idempotent (re-running yields identical bytes).

USAGE
    pip install requests beautifulsoup4 lxml
    # enrich + pack + vet + bump, all collections:
    python Tools/Hadith/ingest_sunnah.py --all --pack --vet --bump-manifest \
        --cache-dir .hadith_cache --throttle 1.0 --translate
    # one collection, no write (dry):
    python Tools/Hadith/ingest_sunnah.py --collections bukhari --out build/hadith
Translator config (for --translate): set DI_TRANSLATE_URL + DI_TRANSLATE_KEY to
an OpenAI-compatible chat endpoint; the model id via DI_TRANSLATE_MODEL. Without
them, bios keep their source languages and Urdu is marked pending (needsUrdu),
never fabricated.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import hashlib
from pathlib import Path

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError:  # pragma: no cover
    raise SystemExit("Install deps: pip install requests beautifulsoup4 lxml")

BASE = "https://sunnah.com"
IOS_ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = IOS_ROOT.parent
SEED_DIRS = [
    IOS_ROOT / "DarulIrfanApp/Resources/SeedData",
    REPO_ROOT / "DarulIrfanAndroid/app/src/main/assets/seed",
    REPO_ROOT / "DarulIrfanHarmony/entry/src/main/resources/rawfile/seed",
    REPO_ROOT / "DarulIrfanWeb/content",
]
PRIMARY_SEED = SEED_DIRS[0]

# Every collection sunnah.com publishes (slug == our slug). Arabic-only ones
# still enrich (segments/bios); their EN/UR stay honestly absent.
CORE = ["bukhari", "muslim", "nasai", "abudawud", "tirmidhi", "ibnmajah", "malik"]
SELECTIONS = ["nawawi40", "qudsi40", "riyadussalihin", "mishkat", "bulugh",
              "adab", "shamail", "forty", "hisn", "virtues"]
ADVANCED = ["ahmad", "darimi", "ibnkhuzayma", "ibnhibban", "hakim",
            "abdurrazzaq", "ibnabishayba", "daraqutni", "bayhaqi", "nasaikubra"]
ALL_COLLECTIONS = CORE + SELECTIONS + ADVANCED

NARRATOR_HREF = re.compile(r"/narrator/(\d+)")
OPENQURAN = re.compile(r"openquran\((\d+),\s*(\d+),\s*(\d+)\)")
MOJIBAKE = ["Ã¢", "Ã©", "Ã¨", "Ã¯", "Ã±", "Ã¼", "Â»", "Â«", "â€™", "â€œ"]


# --------------------------------------------------------------------------- #
# Fetching (throttled, cached, retrying, resumable)
# --------------------------------------------------------------------------- #
class Fetcher:
    def __init__(self, cache_dir: Path, throttle: float):
        self.cache = cache_dir
        self.cache.mkdir(parents=True, exist_ok=True)
        self.throttle = throttle
        self.s = requests.Session()
        self.s.headers["User-Agent"] = "DarulIrfan-build-ingest/2.0 (+contact via app maintainer)"

    def _cp(self, key: str) -> Path:
        return self.cache / re.sub(r"[^A-Za-z0-9._-]", "_", key)

    def get(self, path: str, *, expect_json: bool, retries: int = 5):
        cp = self._cp(path + (".json" if expect_json else ".html"))
        if cp.exists() and cp.stat().st_size > 0:
            t = cp.read_text(encoding="utf-8")
            try:
                return json.loads(t) if expect_json else t
            except json.JSONDecodeError:
                pass  # corrupt cache entry; refetch
        delay = self.throttle
        for _ in range(retries):
            time.sleep(delay)
            try:
                r = self.s.get(BASE + path, timeout=90)
                if r.status_code == 200:
                    if expect_json:
                        data = r.json()  # raises if not JSON (e.g. 500 HTML)
                        cp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
                        return data
                    cp.write_text(r.text, encoding="utf-8")
                    return r.text
            except (requests.RequestException, ValueError):
                pass
            delay = min(delay * 2, 45)
        return None


# --------------------------------------------------------------------------- #
# Urdu translation (explicit, pluggable). Only ever translates an EXISTING bio.
# --------------------------------------------------------------------------- #
class Translator:
    """Auto-translates an existing biography into Urdu via an OpenAI-compatible
    chat endpoint (configured by env). Never invents a bio: callers pass real
    source text only. Without configuration it returns None and the caller marks
    `needsUrdu` (honest pending state) rather than fabricating."""

    def __init__(self, enabled: bool):
        self.url = os.environ.get("DI_TRANSLATE_URL")
        self.key = os.environ.get("DI_TRANSLATE_KEY")
        self.model = os.environ.get("DI_TRANSLATE_MODEL", "gpt-4o-mini")
        self.enabled = bool(enabled and self.url and self.key)
        self._cache: dict[str, str] = {}

    def to_urdu(self, text: str, source: str) -> str | None:
        text = (text or "").strip()
        if not text or not self.enabled:
            return None
        h = hashlib.sha256((source + "|" + text).encode()).hexdigest()
        if h in self._cache:
            return self._cache[h]
        prompt = (
            "Translate this classical Islamic narrator-biography text from "
            f"{source} into natural, faithful Urdu. Preserve names, honorifics, "
            "hadith terminology and dates exactly; do not add or omit meaning; "
            "output only the Urdu translation.\n\n" + text
        )
        try:
            r = requests.post(
                self.url,
                headers={"Authorization": f"Bearer {self.key}",
                         "Content-Type": "application/json"},
                json={"model": self.model, "temperature": 0.2,
                      "messages": [{"role": "user", "content": prompt}]},
                timeout=120,
            )
            r.raise_for_status()
            out = r.json()["choices"][0]["message"]["content"].strip()
            self._cache[h] = out
            return out or None
        except Exception as e:  # pragma: no cover - network/endpoint dependent
            print(f"  ! translation failed: {e}")
            return None


# --------------------------------------------------------------------------- #
# Parsing
# --------------------------------------------------------------------------- #
def segment_arabic(html_fragment: str) -> tuple[list[dict], list[dict]]:
    """Split an Arabic hadith body (with its anchors) into typed segments and
    collect quran refs. Consecutive matn runs are merged."""
    soup = BeautifulSoup(html_fragment, "lxml")
    segs: list[dict] = []
    refs: list[dict] = []

    def push_matn(t: str):
        t = t or ""
        if not t:
            return
        if segs and segs[-1]["type"] == "matn":
            segs[-1]["text"] += t
        else:
            segs.append({"type": "matn", "text": t})

    root = soup.body or soup
    for el in root.descendants:
        name = getattr(el, "name", None)
        if name == "a":
            href = el.get("href", "") or ""
            txt = el.get_text()
            m = NARRATOR_HREF.search(href)
            q = OPENQURAN.search(href)
            if m:
                segs.append({"type": "isnad", "text": txt, "narratorId": int(m.group(1))})
            elif q:
                surah = int(q.group(1)) + 1
                a, b = int(q.group(2)), int(q.group(3))
                segs.append({"type": "verse", "text": txt, "surah": surah,
                             "ayahStart": a, "ayahEnd": b})
                refs.append({"surah": surah, "ayahStart": a, "ayahEnd": b})
            else:
                push_matn(txt)
        elif name is None and isinstance(el, str):
            if el.parent is not None and el.parent.name == "a":
                continue
            push_matn(str(el))

    for s in segs:
        s["text"] = re.sub(r"\s+", " ", s["text"]).strip()
    segs = [s for s in segs if s["text"]]
    # de-dupe refs preserving order
    seen = set()
    urefs = []
    for r in refs:
        k = (r["surah"], r["ayahStart"], r["ayahEnd"])
        if k not in seen:
            seen.add(k); uref = r; urefs.append(uref)
    return segs, urefs


def clean(t: str | None) -> str | None:
    if not t:
        return None
    t = re.sub(r"\s+", " ", t).strip()
    return t or None


def ref_number_from(cont) -> str | None:
    """The collection reference number as our lossless displayNumber.

    Verified against the live block (2026-08-08):
    "Reference : Sahih al-Bukhari 402bIn-book reference : Book 8, Hadith 54…".
    The collection number is the last number(+letter) before "In-book"; a letter
    suffix is sunnah.com's sub-number (402b = 402.2, 402c = 402.3), matching our
    existing lossless keys. The bare first narration has no letter (402 = 402)."""
    el = cont.select_one(".hadith_reference")
    if el is None:
        return None
    head = el.get_text(" ", strip=True).split("In-book")[0]
    m = re.search(r"(\d+)\s*([a-z]?)\s*$", head.strip()) or re.search(r"(\d+)([a-z]?)", head)
    if not m:
        return None
    base, letter = m.group(1), m.group(2)
    if letter and letter != "a":       # 402b -> 402.2, 402c -> 402.3
        return f"{base}.{ord(letter) - ord('a') + 1}"
    return base


def parse_book_page(html: str) -> dict[str, dict]:
    """Map displayNumber -> {segments, quranRefs, text_en, chapter...} for a book page."""
    soup = BeautifulSoup(html, "lxml")
    out: dict[str, dict] = {}
    for cont in soup.select(".actualHadithContainer"):
        num = ref_number_from(cont)
        if not num:
            continue
        ar_el = cont.select_one(".arabic_hadith_full")
        en_el = cont.select_one(".english_hadith_full")
        ch_en = cont.find_previous(class_=re.compile("englishchapter", re.I))
        ch_ar = cont.find_previous(class_=re.compile("arabicchapter", re.I))
        segs, refs = segment_arabic(str(ar_el)) if ar_el else ([], [])
        out[num] = {
            # The container's own id ("h119620") is the Arabic URN, which the
            # Urdu records carry as matchingArabicURN. It is the reliable join
            # key between the two — see the note in enrich_collection.
            "urn": (cont.get("id") or "").lstrip("h") or None,
            "arabicSegments": segs or None,
            "quranRefs": refs or None,
            "text_en": clean(en_el.get_text()) if en_el else None,
            "chapterTitleEnglish": clean(ch_en.get_text()) if ch_en else None,
            "chapterTitleArabic": clean(ch_ar.get_text()) if ch_ar else None,
        }
    return out


def _narrator_ids_in(scope) -> list[int]:
    ids = []
    for a in (scope.select("a[href*='/narrator/']") if scope else []):
        m = NARRATOR_HREF.search(a.get("href", ""))
        if m:
            ids.append(int(m.group(1)))
    # de-dup, preserve order
    seen, out = set(), []
    for i in ids:
        if i not in seen:
            seen.add(i); out.append(i)
    return out


def parse_narrator(html: str, nid: int) -> dict | None:
    """Full bio from a /narrator/{id} page, using the live class structure
    (verified 2026-08-08): .hero-title[.arabic] names, .pill-grade/.pill-text
    grade, .bio-row label/value rows, .lineage[.arabic], .verdict-scholar
    appraisals, .panel--teachers/.panel--students, and the "N Hadith Narrated"
    header. Returns None only if there is no identifiable person at all."""
    soup = BeautifulSoup(html, "lxml")
    def txt(sel, root=soup):
        el = root.select_one(sel)
        return clean(el.get_text()) if el else None

    name_en = txt(".hero-title:not(.arabic)")
    name_ar = txt(".hero-title.arabic")
    if not name_en and not name_ar:
        return None

    # Grade pills: first non-arabic = English, .arabic = Arabic.
    grades = soup.select(".pill-grade .pill-text, .pill-grade")
    grade_en = clean(grades[0].get_text()) if grades else None
    grade_ar = None
    for g in grades:
        cls = " ".join(g.get("class", []))
        if "arabic" in cls:
            grade_ar = clean(g.get_text()); break

    # Label/value fact rows.
    facts = {}
    for row in soup.select(".bio-row"):
        cells = [clean(c.get_text()) for c in row.find_all(recursive=False)]
        cells = [c for c in cells if c]
        if len(cells) >= 2:
            facts[cells[0].lower()] = cells[1]

    def fact(*keys):
        for k in facts:
            for want in keys:
                if want in k:
                    return facts[k]
        return None

    teachers = _narrator_ids_in(soup.select_one(".panel--teachers"))
    students = _narrator_ids_in(soup.select_one(".panel--students"))

    hcount = None
    m = re.search(r"([\d,]+)\s+Hadith\s+Narrated", soup.get_text())
    if m:
        hcount = int(m.group(1).replace(",", ""))

    # Appraisals (jarḥ wa-taʿdīl): scholar + text, English and Arabic columns.
    appraisals = []
    for sch in soup.select(".verdict-scholar, .tarjama-scholar"):
        who = clean(sch.get_text())
        body_el = sch.find_next_sibling()
        body = clean(body_el.get_text()) if body_el else None
        if not who and not body:
            continue
        is_ar = "arabic" in " ".join(sch.get("class", []))
        appraisals.append({
            "scholarArabic" if is_ar else "scholar": who,
            "textArabic" if is_ar else "textEnglish": body,
        })

    bio = {
        "id": nid,
        "nameEnglish": name_en,
        "nameArabic": name_ar,
        "gradeEnglish": grade_en if grade_en and not re.search(r"[؀-ۿ]", grade_en) else None,
        "gradeArabic": grade_ar,
        "kunya": fact("kunya"),
        "generation": fact("generation", "tabaqa"),
        "deathYear": fact("died", "death"),
        "cities": fact("cities", "region"),
        "affiliations": fact("affiliation", "nisba"),
        "lineageEnglish": txt(".lineage:not(.arabic)"),
        "lineageArabic": txt(".lineage.arabic"),
        "hadithCount": hcount,
        "teacherIds": teachers or None,
        "studentIds": students or None,
        "appraisals": appraisals or None,
    }
    return {k: v for k, v in bio.items() if v is not None}


# --------------------------------------------------------------------------- #
# Enrichment (merge onto existing lossless records)
# --------------------------------------------------------------------------- #
def load_pack(slug: str) -> list[dict] | None:
    p = PRIMARY_SEED / f"hadith_{slug}.json"
    if not p.exists():
        return None
    return json.loads(p.read_text(encoding="utf-8"))


def enrich_collection(slug: str, fetcher: Fetcher, report: dict) -> tuple[list[dict], set[int]]:
    records = load_pack(slug)
    if records is None:
        report.setdefault("skipped_no_pack", []).append(slug)
        return [], set()
    by_num = {r["displayNumber"]: r for r in records}
    landing = fetcher.get(f"/{slug}", expect_json=False)
    books = sorted({int(m) for m in re.findall(rf"/{slug}/(\d+)\"", landing)}) if landing else []
    narrator_ids: set[int] = set()
    enriched = 0

    for bk in books:
        page = fetcher.get(f"/{slug}/{bk}", expect_json=False)
        parsed = parse_book_page(page) if page else {}
        urdu = fetcher.get(f"/ajax/urdu/{slug}/{bk}", expect_json=True)
        if urdu is None:
            report.setdefault("urdu_book_failed", []).append(f"{slug}/{bk}")
            # No per-chapter fallback exists: /ajax/urdu/<slug>/<bk>/<chapter>
            # returns 404, and books that fail (e.g. bukhari 64, 65) return 500
            # at the book level on every variant. Those narrations simply have
            # no Urdu at source. See Docs/HADITH_INGEST_FINDINGS.md.
            urdu = []
        # Join Urdu to Arabic on the URN, not the hadith number. Measured over
        # the cached Bukhari corpus: URN matches 6,265/6,290 = 99.6% of
        # containers, the number join only 80.4%. The number join does not
        # degrade gracefully either — it misses whole books at a time, because
        # some send hadithNumber: 0 for every record (kitab 34 lost all 184
        # that way, with ourHadithNumber being a within-book sequence rather
        # than the global number). Number stays as a fallback for any record
        # whose container carried no id.
        urdu_by_urn = {str(u.get("matchingArabicURN")): u for u in urdu
                       if u.get("matchingArabicURN") is not None}
        urdu_by_num = {str(u.get("hadithNumber")): u for u in urdu}

        for num, extra in parsed.items():
            rec = by_num.get(num)
            if rec is None:
                report.setdefault("unmatched_ref", []).append(f"{slug}:{num}")
                continue
            if extra.get("arabicSegments"):
                rec["arabicSegments"] = extra["arabicSegments"]
                for s in extra["arabicSegments"]:
                    if s["type"] == "isnad" and s.get("narratorId"):
                        narrator_ids.add(s["narratorId"])
            if extra.get("quranRefs"):
                rec["quranRefs"] = extra["quranRefs"]
            if not rec.get("text_en") and extra.get("text_en"):
                rec["text_en"] = extra["text_en"]
            for k in ("chapterTitleEnglish", "chapterTitleArabic"):
                if extra.get(k):
                    rec[k] = extra[k]
            urn = extra.get("urn")
            u = (urdu_by_urn.get(urn) if urn else None) or urdu_by_num.get(num)
            if u:
                rec["urduSanad"] = clean(u.get("hadithSanad"))
                rec["urduText"] = clean(u.get("hadithText"))
                if u.get("babName"):
                    rec["chapterTitleUrdu"] = clean(u.get("babName"))
            enriched += 1

    report[slug] = {"records": len(records), "enriched": enriched,
                    "narrators": len(narrator_ids)}
    return records, narrator_ids


def build_narrators(ids: set[int], fetcher: Fetcher, translator: Translator,
                    report: dict) -> list[dict]:
    """Fetch + parse every referenced narrator, then auto-translate the EXISTING
    biography into Urdu (per-appraisal English→Urdu or Arabic→Urdu, plus the
    name). A narrator is flagged missing only when the page carries no biography
    at all; an existing bio is never left untranslated and never fabricated."""
    out = []
    for nid in sorted(ids):
        html = fetcher.get(f"/narrator/{nid}", expect_json=False)
        if not html:
            report.setdefault("narrator_fetch_failed", []).append(nid)
            continue
        bio = parse_narrator(html, nid)
        if not bio:
            report.setdefault("narrator_empty", []).append(nid)
            continue

        has_content = any(bio.get(k) for k in
                          ("appraisals", "lineageEnglish", "lineageArabic",
                           "gradeEnglish", "gradeArabic", "kunya", "generation"))
        produced_urdu = False

        # Name in Urdu (translate the English/Arabic name so the sheet has one).
        if not bio.get("nameUrdu"):
            nm = translator.to_urdu(bio.get("nameEnglish") or bio.get("nameArabic") or "",
                                    "English" if bio.get("nameEnglish") else "Arabic")
            if nm:
                bio["nameUrdu"] = nm; produced_urdu = True

        # Grade in Urdu.
        if bio.get("gradeEnglish") and not bio.get("gradeUrdu"):
            gu = translator.to_urdu(bio["gradeEnglish"], "English")
            if gu:
                bio["gradeUrdu"] = gu; produced_urdu = True

        # Each appraisal: fill textUrdu from its English (else Arabic) text.
        for ap in bio.get("appraisals", []) or []:
            if ap.get("textUrdu"):
                produced_urdu = True; continue
            src = ap.get("textEnglish") or ap.get("textArabic")
            lang = "English" if ap.get("textEnglish") else "Arabic"
            if src:
                tu = translator.to_urdu(src, lang)
                if tu:
                    ap["textUrdu"] = tu; produced_urdu = True

        if has_content:
            bio["needsUrdu"] = not produced_urdu     # pending only if MT unavailable
        else:
            # No biography in any language: honest missing state, nothing invented.
            bio["needsEnglish"] = True
            bio["needsUrdu"] = True
            report.setdefault("narrator_no_bio", []).append(nid)

        out.append({k: v for k, v in bio.items() if v is not None})
    report["narrators_built"] = len(out)
    return out


# --------------------------------------------------------------------------- #
# Packing + catalogue + manifest + vetting
# --------------------------------------------------------------------------- #
def write_records(path: Path, records: list[dict]) -> None:
    body = ",\n ".join(json.dumps(r, ensure_ascii=False) for r in records)
    path.write_text(f"[\n {body}\n]\n", encoding="utf-8", newline="\n")


def pack(slug: str, records: list[dict], narrators: list[dict]) -> None:
    for d in SEED_DIRS:
        if not d.exists():
            print(f"  ! skip missing seed dir {d}")
            continue
        if records:
            write_records(d / f"hadith_{slug}.json", records)
        if narrators:
            # Merge into the shared narrator store (union across collections).
            store_path = d / "hadith_narrators.json"
            existing = {}
            if store_path.exists():
                for n in json.loads(store_path.read_text(encoding="utf-8")):
                    existing[n["id"]] = n
            for n in narrators:
                existing[n["id"]] = n
            merged = [existing[k] for k in sorted(existing)]
            store_path.write_text(json.dumps(merged, ensure_ascii=False, indent=1) + "\n",
                                  encoding="utf-8", newline="\n")


def vet(slug: str, records: list[dict], report: dict) -> None:
    cids = [r["canonicalID"] for r in records]
    disp = [r["displayNumber"] for r in records]
    dup_c = len(cids) - len(set(cids))
    dup_d = len(disp) - len(set(disp))
    subs = sum(1 for r in records if r.get("numberMinor") is not None)
    moji = sum(1 for r in records for k in ("text_ar", "text_en", "text_ur", "urduText", "urduSanad")
               for m in MOJIBAKE if m in (r.get(k) or ""))
    cov = {
        "ar": sum(1 for r in records if (r.get("text_ar") or r.get("arabicSegments"))),
        "en": sum(1 for r in records if r.get("text_en")),
        "ur": sum(1 for r in records if (r.get("urduText") or r.get("text_ur"))),
        "segmented": sum(1 for r in records if r.get("arabicSegments")),
        "withVerses": sum(1 for r in records if r.get("quranRefs")),
    }
    report.setdefault("vet", {})[slug] = {
        "records": len(records), "dupCanonical": dup_c, "dupDisplay": dup_d,
        "subNumbered": subs, "mojibake": moji, "coverage": cov,
    }


def bump_manifest() -> None:
    for d in SEED_DIRS:
        mp = d / "manifest.json"
        if not mp.exists():
            continue
        m = json.loads(mp.read_text(encoding="utf-8"))
        m["version"] = int(m.get("version", 0)) + 1
        m["generatedAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        mp.write_text(json.dumps(m, indent=2) + "\n", encoding="utf-8", newline="\n")


def selftest() -> int:
    """Offline check of the pure parsers (no network) — run first in CI so a
    parser regression fails fast before any scraping. Mirrors the structures
    verified live on 2026-08-08."""
    frag = ('<div class="arabic_hadith_full arabic">حَدَّثَنَا '
            '<a href="/narrator/8297">يَحْيَى بْنُ بُكَيْرٍ</a> قَالَ بَيْنَا '
            '<a href="javascript:openquran(73,1,5)">يَا أَيُّهَا الْمُدَّثِّرُ</a> فَحَمِيَ</div>')
    segs, refs = segment_arabic(frag)
    assert any(s["type"] == "isnad" and s.get("narratorId") == 8297 for s in segs)
    assert any(s["type"] == "verse" and s["surah"] == 74 and s["ayahStart"] == 1
               and s["ayahEnd"] == 5 for s in segs)
    assert refs == [{"surah": 74, "ayahStart": 1, "ayahEnd": 5}]
    assert any(s["type"] == "matn" for s in segs)

    def cont(html):
        return BeautifulSoup(html, "lxml").select_one(".actualHadithContainer")
    tpl = '<div class="actualHadithContainer"><div class="hadith_reference">{}</div></div>'
    assert ref_number_from(cont(tpl.format("Reference : Sahih al-Bukhari 402In-book reference : Book 8, Hadith 53"))) == "402"
    assert ref_number_from(cont(tpl.format("Reference : Sahih al-Bukhari 402bIn-book reference : Book 8, Hadith 54"))) == "402.2"
    assert ref_number_from(cont(tpl.format("Reference : Sahih al-Bukhari 349In-book reference : Book 8, Hadith 1"))) == "349"
    print("ingest_sunnah selftest: PASS (segmentation, verse surah+1, sub-number keys)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--selftest", action="store_true", help="offline parser check; no network")
    ap.add_argument("--collections", nargs="*", default=[])
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--core", action="store_true", help="the seven core collections only")
    ap.add_argument("--cache-dir", type=Path, default=Path(".hadith_cache"))
    ap.add_argument("--throttle", type=float, default=1.0)
    ap.add_argument("--translate", action="store_true", help="auto-translate bios to Urdu")
    ap.add_argument("--pack", action="store_true", help="write to the four seed dirs")
    ap.add_argument("--vet", action="store_true")
    ap.add_argument("--bump-manifest", action="store_true")
    ap.add_argument("--out", type=Path, default=Path("build/hadith"))
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    slugs = (ALL_COLLECTIONS if args.all else
             CORE if args.core else (args.collections or ["bukhari"]))
    fetcher = Fetcher(args.cache_dir, args.throttle)
    translator = Translator(args.translate)
    if args.translate and not translator.enabled:
        print("  ! --translate set but DI_TRANSLATE_URL/KEY missing: Urdu bios "
              "will be marked pending (needsUrdu), never fabricated.")
    report: dict = {}
    args.out.mkdir(parents=True, exist_ok=True)
    all_ids: set[int] = set()

    for slug in slugs:
        print(f"== {slug} ==")
        records, ids = enrich_collection(slug, fetcher, report)
        all_ids |= ids
        if args.vet:
            vet(slug, records, report)
        (args.out / f"hadith_{slug}.json").write_text(
            json.dumps(records, ensure_ascii=False, indent=1), encoding="utf-8")
        if args.pack:
            pack(slug, records, [])

    narrators = build_narrators(all_ids, fetcher, translator, report) if all_ids else []
    if narrators:
        (args.out / "hadith_narrators.json").write_text(
            json.dumps(narrators, ensure_ascii=False, indent=1), encoding="utf-8")
        if args.pack:
            pack("__narrators__", [], narrators)  # writes only the store

    if args.pack and args.bump_manifest:
        bump_manifest()

    (args.out / "ingest_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps(report.get("vet", {}), ensure_ascii=False, indent=1))
    print("Done. Run Tools/ContentIntegrity/check_content.py to gate, then commit "
          "the four seed dirs (the CI workflow does this automatically).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
