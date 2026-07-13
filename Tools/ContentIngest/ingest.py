#!/usr/bin/env python3
"""Darul Irfan content ingestion CLI.

Runs on the maintainer's machine (never inside the app) and turns
naqshbandiaowaisiah.org pages into the structured JSON the app's
``ContentSyncService`` understands. See README.md for usage and the
rights policy.

Subcommands:
    crawl     — fetch site sections politely and write output JSON
    validate  — check an output folder against the schema
    diff      — compare two output folders; report changes & curation conflicts

Dependencies: requests, beautifulsoup4 (see requirements.txt).
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urlparse
from urllib.robotparser import RobotFileParser

import requests

import parsers
import schema

# Make console output safe on Windows code pages (warnings may reference
# URLs only, but be defensive).
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        try:
            _stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

DEFAULT_BASE_URL = "https://www.naqshbandiaowaisiah.org"
USER_AGENT = "DarulIrfanContentIngest/1.0 (+mailto:contact-email-placeholder@example.org)"
DEFAULT_RATE_LIMIT_SECONDS = 1.5
DEFAULT_MAX_PAGES = 200
REQUEST_TIMEOUT_SECONDS = 30
RETRY_ATTEMPTS = 3
RETRY_BACKOFF_SECONDS = 2.0

ALL_SECTIONS = ("about", "lectures", "books", "magazines", "articles", "tafsir")

# Verified about pages (Docs/RESEARCH_NOTES.md) → ContentCategory rawValue.
ABOUT_PAGES = (
    ("/hazrat-ameer-abdul-qadeer-awan.html", "sheikhAbdulQadeerAwan"),
    ("/hazrat-ameer-muhammad-akram-awan-ra.html", "sheikhMuhammadAkramAwan"),
    ("/silsila-naqshbandia-owaisiah.html", "aboutSilsila"),
    ("/shajra-silsila-naqshbandia-owaisiah.html", "shajra"),
)

ITEM_FILES = ("articles.json", "documents.json", "media.json", "events.json")
TAFSIR_FILE = "quran_tafsir_manifest.json"
MANIFEST_FILE = "content_manifest.json"
OUTPUT_FILES = ITEM_FILES + (TAFSIR_FILE,)

# Fields a fresh crawl may update on a curated item. Everything else is
# preserved and reported as a conflict when the site disagrees.
URL_FIELDS = frozenset({
    "sourceUrl", "streamUrl", "downloadUrl", "transcriptUrl",
    "mediaUrls", "downloadUrls",
})

EXPECTED_TAFSIR_PAGES = 114


# ---------------------------------------------------------------------------
# Polite fetching
# ---------------------------------------------------------------------------

class PoliteFetcher:
    """requests wrapper with robots.txt awareness, a rate limit, a per-run
    page cap and retry-with-backoff."""

    def __init__(self, base_url: str, rate_limit: float, max_pages: int,
                 user_agent: str = USER_AGENT) -> None:
        self.base_url = base_url.rstrip("/")
        self.rate_limit = max(0.0, rate_limit)
        self.max_pages = max_pages
        self.user_agent = user_agent
        self.session = requests.Session()
        self.session.headers.update({"User-Agent": user_agent})
        self.robots: Optional[RobotFileParser] = None
        self.pages_fetched = 0
        self.cap_reached = False
        self._cap_warned = False
        self._last_request_at: Optional[float] = None
        self.warnings: List[str] = []

    def load_robots(self) -> None:
        """Verify robots.txt at runtime (the site is fully permissive, but
        check anyway)."""
        robots_url = self.base_url + "/robots.txt"
        try:
            self._pause()
            response = self.session.get(robots_url, timeout=REQUEST_TIMEOUT_SECONDS)
            self._last_request_at = time.monotonic()
        except requests.RequestException:
            self.warnings.append(
                "robots.txt could not be fetched; proceeding carefully "
                "(the site was verified fully permissive on 2026-07-09).")
            return
        if response.status_code == 200:
            parser = RobotFileParser()
            parser.parse(response.text.splitlines())
            self.robots = parser
            print("robots.txt loaded from %s" % robots_url)
        else:
            # Per convention a missing robots.txt (4xx) means crawling is
            # allowed.
            print("robots.txt returned HTTP %d — treating as permissive."
                  % response.status_code)

    def allowed(self, url: str) -> bool:
        if self.robots is None:
            return True
        return self.robots.can_fetch(self.user_agent, url)

    def _pause(self) -> None:
        if self._last_request_at is None:
            return
        elapsed = time.monotonic() - self._last_request_at
        if elapsed < self.rate_limit:
            time.sleep(self.rate_limit - elapsed)

    def fetch(self, url: str) -> Optional[str]:
        """GET a page's text, or None (with a recorded warning) on failure,
        robots disallow, or page-cap exhaustion."""
        if not self.allowed(url):
            self.warnings.append("robots.txt disallows %s — skipped." % url)
            return None
        last_error: Optional[Exception] = None
        for attempt in range(RETRY_ATTEMPTS):
            if self.pages_fetched >= self.max_pages:
                self.cap_reached = True
                if not self._cap_warned:
                    self._cap_warned = True
                    self.warnings.append(
                        "Page cap of %d requests reached — remaining pages "
                        "were not fetched. Re-run with --max-pages to raise "
                        "the cap." % self.max_pages)
                return None
            self._pause()
            self.pages_fetched += 1
            try:
                response = self.session.get(url, timeout=REQUEST_TIMEOUT_SECONDS)
                self._last_request_at = time.monotonic()
                response.raise_for_status()
                return response.text
            except requests.RequestException as error:
                self._last_request_at = time.monotonic()
                last_error = error
                if attempt + 1 < RETRY_ATTEMPTS:
                    time.sleep(RETRY_BACKOFF_SECONDS * (2 ** attempt))
        self.warnings.append("Failed to fetch %s after %d attempts (%s)."
                             % (url, RETRY_ATTEMPTS, last_error))
        return None


# ---------------------------------------------------------------------------
# Pure builders: parser output → schema item dicts (fixture-testable)
# ---------------------------------------------------------------------------

def _looks_urdu(text: str) -> bool:
    """True when the text contains Arabic-block characters (U+0600–U+06FF)."""
    return any("؀" <= ch <= "ۿ" for ch in text)


def media_items_from_lecture_page(result: parsers.LecturePageResult,
                                  page_url: str, year: Optional[int],
                                  rights_status: str
                                  ) -> Tuple[List[Dict[str, Any]], List[str]]:
    items: List[Dict[str, Any]] = []
    for row in result.items:
        source_url = row.get("detail_url") or page_url
        date_iso = row.get("date_iso")
        month: Optional[int] = None
        item_year = year
        if isinstance(date_iso, str) and len(date_iso) >= 7:
            item_year = int(date_iso[0:4])
            month = int(date_iso[5:7])
        item = schema.MediaItem(
            id=schema.slug_from_url(source_url),
            title=row["title"],
            language="ur",
            media_type="audio",
            source_url=source_url,
            category="audioLectures",
            rights_status=rights_status,
            speaker=row.get("speaker"),
            date=date_iso,
            stream_url=row["mp3_url"],
            download_url=row["mp3_url"],
            year=item_year,
            month=month,
        )
        items.append(item.to_dict())
    warnings: List[str] = []
    if result.skipped_wma:
        warnings.append(
            "%s: skipped %d .wma link(s) — WMA is not playable on iOS."
            % (page_url, result.skipped_wma))
    return items, warnings


def content_items_from_magazine_page(issues: List[Dict[str, Any]],
                                     page_url: str, rights_status: str
                                     ) -> List[Dict[str, Any]]:
    items: List[Dict[str, Any]] = []
    for issue in issues:
        published_at: Optional[str] = None
        year = issue.get("year")
        months = issue.get("months") or []
        if isinstance(year, int):
            first_month = months[0] if months else 1
            published_at = schema.iso_date_only(year, first_month, 1)
        item = schema.ContentItem(
            id=schema.slug_from_url(issue["pdf_url"]),
            source_url=page_url,
            type="magazine",
            title=issue["title"],
            language="ur",
            category="alMurshidMagazine",
            rights_status=rights_status,
            published_at=published_at,
            download_urls=[issue["pdf_url"]],
        )
        items.append(item.to_dict())
    return items


def content_items_from_books_page(books: List[Dict[str, Any]],
                                  page_url: str, rights_status: str
                                  ) -> List[Dict[str, Any]]:
    items: List[Dict[str, Any]] = []
    for book in books:
        haystack = (book["title"] + " " + book["pdf_url"]).lower()
        language = "en" if "english" in haystack else "ur"
        item = schema.ContentItem(
            id=schema.slug_from_url(book["pdf_url"]),
            source_url=page_url,
            type="book",
            title=book["title"],
            language=language,
            category="books",
            rights_status=rights_status,
            download_urls=[book["pdf_url"]],
        )
        items.append(item.to_dict())
    return items


def content_item_from_about_page(meta: Dict[str, Any], page_url: str,
                                 category: str, rights_status: str,
                                 include_body: bool) -> Dict[str, Any]:
    title = meta.get("title") or schema.slug_from_url(page_url).replace("-", " ").title()
    body = meta.get("body_plain_text") if include_body else None
    item = schema.ContentItem(
        id=schema.slug_from_url(page_url),
        source_url=page_url,
        type="page",
        title=title,
        language="ur" if _looks_urdu(title) else "en",
        category=category,
        rights_status=rights_status,
        excerpt=meta.get("excerpt"),
        body_plain_text=body,
    )
    return item.to_dict()


def content_item_from_article_link(link: Dict[str, Any], rights_status: str,
                                   meta: Optional[Dict[str, Any]] = None,
                                   include_body: bool = False) -> Dict[str, Any]:
    title = link.get("title") or ""
    excerpt: Optional[str] = None
    body: Optional[str] = None
    if meta is not None:
        title = meta.get("title") or title
        excerpt = meta.get("excerpt")
        if include_body:
            body = meta.get("body_plain_text")
    if not title:
        title = schema.slug_from_url(link["url"]).replace("-", " ").title()
    item = schema.ContentItem(
        id=schema.slug_from_url(link["url"]),
        source_url=link["url"],
        type="article",
        title=title,
        language="ur" if _looks_urdu(title) else "en",
        category="articles",
        rights_status=rights_status,
        excerpt=excerpt,
        body_plain_text=body,
    )
    return item.to_dict()


def tafsir_manifest_from_index(entries: List[Dict[str, Any]], index_url: str,
                               rights_status: str
                               ) -> Tuple[Dict[str, Any], List[str]]:
    edition = schema.QuranEdition(
        id="asrar-at-tanzil-en",
        title="Asrar-at-Tanzil",
        kind="tafsir",
        language="en",
        rights_status=rights_status,
        author="Hazrat Ameer Muhammad Akram Awan (RA)",
        source_url=index_url,
        is_available_offline=False,
    )
    manifest = {
        "version": schema.SCHEMA_VERSION,
        "edition": edition.to_dict(),
        "pages": [
            {"surahNumber": e["surah_number"], "title": e["title"], "url": e["url"]}
            for e in entries
        ],
    }
    warnings: List[str] = []
    if len(entries) != EXPECTED_TAFSIR_PAGES:
        warnings.append(
            "%s: expected %d surah tafsir pages, found %d — the index "
            "layout may have changed."
            % (index_url, EXPECTED_TAFSIR_PAGES, len(entries)))
    return manifest, warnings


# ---------------------------------------------------------------------------
# Output files: merge (curation-aware), write, manifest
# ---------------------------------------------------------------------------

def load_json(path: Path) -> Optional[Any]:
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, obj: Any) -> None:
    path.write_text(schema.json_dumps_stable(obj), encoding="utf-8", newline="\n")


def merge_items(new_items: List[Dict[str, Any]],
                existing_items: List[Dict[str, Any]],
                prune: bool = False
                ) -> Tuple[List[Dict[str, Any]], List[str], List[str]]:
    """Merge a fresh crawl into a previous output list.

    * Non-curated items: the fresh crawl wins.
    * Items marked ``"curated": true`` in the previous output keep every
      curated field; only URL fields and the checksum are updated, and any
      upstream change to a preserved field is reported as a conflict.
    * Items missing from the fresh crawl are retained (curated items
      always; others unless ``prune`` is set) so a partial crawl never
      silently deletes data.

    Returns (merged sorted by id, conflicts, notes).
    """
    existing_by_id: Dict[str, Dict[str, Any]] = {}
    for item in existing_items:
        if isinstance(item, dict) and isinstance(item.get("id"), str):
            existing_by_id[item["id"]] = item

    merged: List[Dict[str, Any]] = []
    conflicts: List[str] = []
    notes: List[str] = []
    new_ids = set()

    for item in new_items:
        new_ids.add(item["id"])
        existing = existing_by_id.get(item["id"])
        if existing is not None and existing.get("curated") is True:
            kept = dict(existing)
            for url_field in URL_FIELDS:
                if url_field in item:
                    kept[url_field] = item[url_field]
            for key, value in item.items():
                if key in URL_FIELDS or key == "checksum":
                    continue
                if key not in kept:
                    kept[key] = value
                elif kept[key] != value:
                    conflicts.append(
                        "id '%s': field '%s' changed upstream but the item "
                        "is curated — the curated value was preserved. "
                        "Review and update by hand if the site is right."
                        % (item["id"], key))
            schema.apply_checksum(kept)
            merged.append(kept)
        else:
            merged.append(item)

    for item_id, existing in existing_by_id.items():
        if item_id in new_ids:
            continue
        if existing.get("curated") is True:
            merged.append(existing)
            notes.append("id '%s': curated item is no longer on the site; "
                         "kept." % item_id)
        elif prune:
            notes.append("id '%s': absent upstream; removed (--prune)."
                         % item_id)
        else:
            merged.append(existing)
            notes.append("id '%s': not seen in this crawl; kept (use "
                         "--prune to remove stale items)." % item_id)

    merged.sort(key=lambda d: d.get("id", ""))
    return merged, conflicts, notes


def write_outputs(out_dir: Path, payload: Dict[str, Any],
                  generated_at: Optional[str] = None, prune: bool = False
                  ) -> Tuple[List[str], List[str]]:
    """Write all output files into ``out_dir``.

    ``payload`` keys: ``articles``, ``documents``, ``media``, ``events``
    (each a list of item dicts, or None meaning "this section was not
    crawled — leave any existing file untouched") and ``tafsir`` (the
    manifest dict, or None). Returns (conflicts, notes).
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    conflicts: List[str] = []
    notes: List[str] = []

    for file_name, key in (("articles.json", "articles"),
                           ("documents.json", "documents"),
                           ("media.json", "media"),
                           ("events.json", "events")):
        path = out_dir / file_name
        new_items = payload.get(key)
        if new_items is None:
            if load_json(path) is None:
                write_json(path, [])
            continue
        existing = load_json(path)
        existing_items = existing if isinstance(existing, list) else []
        merged, file_conflicts, file_notes = merge_items(
            new_items, existing_items, prune=prune)
        conflicts.extend("%s: %s" % (file_name, c) for c in file_conflicts)
        notes.extend("%s: %s" % (file_name, n) for n in file_notes)
        write_json(path, merged)

    tafsir_path = out_dir / TAFSIR_FILE
    new_tafsir = payload.get("tafsir")
    if new_tafsir is None:
        if load_json(tafsir_path) is None:
            write_json(tafsir_path, {"version": schema.SCHEMA_VERSION,
                                     "pages": []})
    else:
        existing_tafsir = load_json(tafsir_path)
        if isinstance(existing_tafsir, dict) and existing_tafsir.get("curated") is True:
            notes.append("%s: existing file is marked curated; the fresh "
                         "crawl was NOT applied." % TAFSIR_FILE)
        else:
            write_json(tafsir_path, new_tafsir)

    _write_manifest(out_dir, generated_at)
    return conflicts, notes


def _write_manifest(out_dir: Path, generated_at: Optional[str] = None) -> None:
    counts: Dict[str, int] = {}
    for file_name, count_key in (("articles.json", "articles"),
                                 ("documents.json", "documents"),
                                 ("media.json", "media"),
                                 ("events.json", "events")):
        data = load_json(out_dir / file_name)
        counts[count_key] = len(data) if isinstance(data, list) else 0
    tafsir = load_json(out_dir / TAFSIR_FILE)
    pages = tafsir.get("pages") if isinstance(tafsir, dict) else None
    counts["quranTafsirPages"] = len(pages) if isinstance(pages, list) else 0

    if generated_at is None:
        from datetime import datetime, timezone
        generated_at = schema.iso_datetime(datetime.now(timezone.utc))

    # `files` is a name->filename map matching the iOS app's understood
    # payload names (ContentSyncService.understoodNames): articles, documents,
    # media, events. Filenames resolve relative to the manifest's own URL.
    manifest = {
        "version": schema.SCHEMA_VERSION,
        "generatedAt": generated_at,
        "counts": counts,
        "files": {
            "articles": "articles.json",
            "documents": "documents.json",
            "media": "media.json",
            "events": "events.json",
            "tafsir": TAFSIR_FILE,
        },
    }
    write_json(out_dir / MANIFEST_FILE, manifest)


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

def validate_output_dir(out_dir: Path) -> Tuple[List[str], List[str]]:
    """Validate every output file present in ``out_dir``.

    Returns (errors, warnings). Checksums are recomputed and compared; a
    mismatch on a curated item is a warning (the curator likely edited
    fields by hand), on a non-curated item it is an error.
    """
    errors: List[str] = []
    warnings: List[str] = []

    validators = {
        "articles.json": schema.validate_content_item,
        "documents.json": schema.validate_content_item,
        "media.json": schema.validate_media_item,
        "events.json": schema.validate_community_event,
    }

    for file_name, validator in validators.items():
        path = out_dir / file_name
        data = load_json(path)
        if data is None:
            warnings.append("%s: file is missing." % file_name)
            continue
        if not isinstance(data, list):
            errors.append("%s: expected a JSON array of items." % file_name)
            continue
        seen_ids = set()
        for item in data:
            if not isinstance(item, dict):
                errors.append("%s: found a non-object entry." % file_name)
                continue
            for problem in validator(item):
                errors.append("%s: %s" % (file_name, problem))
            item_id = item.get("id")
            if isinstance(item_id, str):
                if item_id in seen_ids:
                    errors.append("%s: duplicate id '%s'." % (file_name, item_id))
                seen_ids.add(item_id)
            if isinstance(item.get("checksum"), str):
                recomputed = schema.checksum_for(item)
                if item["checksum"] != recomputed:
                    message = ("%s: id '%s' checksum does not match its "
                               "fields." % (file_name, item_id))
                    if item.get("curated") is True:
                        warnings.append(message + " (curated item — re-run "
                                        "a crawl or diff merge to refresh)")
                    else:
                        errors.append(message)

    tafsir = load_json(out_dir / TAFSIR_FILE)
    if tafsir is None:
        warnings.append("%s: file is missing." % TAFSIR_FILE)
    elif not isinstance(tafsir, dict):
        errors.append("%s: expected a JSON object." % TAFSIR_FILE)
    else:
        if not isinstance(tafsir.get("version"), int):
            errors.append("%s: 'version' must be an integer." % TAFSIR_FILE)
        if "edition" in tafsir:
            for problem in schema.validate_quran_edition(tafsir["edition"]):
                errors.append("%s: %s" % (TAFSIR_FILE, problem))
        pages = tafsir.get("pages")
        if not isinstance(pages, list):
            errors.append("%s: 'pages' must be a list." % TAFSIR_FILE)
        else:
            seen_numbers = set()
            for page in pages:
                if not isinstance(page, dict):
                    errors.append("%s: found a non-object page entry." % TAFSIR_FILE)
                    continue
                number = page.get("surahNumber")
                if not isinstance(number, int):
                    errors.append("%s: a page entry is missing an integer "
                                  "'surahNumber'." % TAFSIR_FILE)
                elif number in seen_numbers:
                    errors.append("%s: duplicate surahNumber %d." % (TAFSIR_FILE, number))
                else:
                    seen_numbers.add(number)
                for key in ("title", "url"):
                    if not isinstance(page.get(key), str) or not page.get(key):
                        errors.append("%s: page %s is missing '%s'."
                                      % (TAFSIR_FILE, number, key))
            if pages and len(pages) != EXPECTED_TAFSIR_PAGES:
                warnings.append("%s: %d tafsir pages listed (expected %d)."
                                % (TAFSIR_FILE, len(pages), EXPECTED_TAFSIR_PAGES))

    manifest = load_json(out_dir / MANIFEST_FILE)
    if manifest is None:
        warnings.append("%s: file is missing." % MANIFEST_FILE)
    elif not isinstance(manifest, dict):
        errors.append("%s: expected a JSON object." % MANIFEST_FILE)
    else:
        if not isinstance(manifest.get("version"), int):
            errors.append("%s: 'version' must be an integer." % MANIFEST_FILE)
        if not schema.is_iso_datetime(manifest.get("generatedAt")):
            errors.append("%s: 'generatedAt' must be an ISO-8601 datetime."
                          % MANIFEST_FILE)
        counts = manifest.get("counts")
        if not isinstance(counts, dict):
            errors.append("%s: 'counts' must be an object." % MANIFEST_FILE)
        else:
            actual = {
                "articles": load_json(out_dir / "articles.json"),
                "documents": load_json(out_dir / "documents.json"),
                "media": load_json(out_dir / "media.json"),
                "events": load_json(out_dir / "events.json"),
            }
            for key, data in actual.items():
                if isinstance(data, list) and counts.get(key) != len(data):
                    errors.append("%s: counts.%s is %s but %s has %d items."
                                  % (MANIFEST_FILE, key, counts.get(key),
                                     key + ".json", len(data)))
    return errors, warnings


# ---------------------------------------------------------------------------
# crawl command
# ---------------------------------------------------------------------------

def parse_years(spec: str) -> List[int]:
    """``2024-2026`` / ``2026`` / ``2024,2026`` → sorted list of ints."""
    years: List[int] = []
    for token in spec.split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            start_text, end_text = token.split("-", 1)
            start, end = int(start_text), int(end_text)
            if start > end:
                raise ValueError("year range '%s' is reversed" % token)
            years.extend(range(start, end + 1))
        else:
            years.append(int(token))
    if not years:
        raise ValueError("no years given")
    return sorted(set(years))


def parse_sections(spec: str) -> List[str]:
    sections = [s.strip().lower() for s in spec.split(",") if s.strip()]
    unknown = [s for s in sections if s not in ALL_SECTIONS]
    if unknown:
        raise ValueError("unknown section(s): %s (valid: %s)"
                         % (", ".join(unknown), ", ".join(ALL_SECTIONS)))
    return sections


def cmd_crawl(args: argparse.Namespace) -> int:
    try:
        sections = parse_sections(args.sections)
        years = parse_years(args.years)
    except ValueError as error:
        print("error: %s" % error)
        return 2

    if args.full_text and not args.rights_confirmed:
        print("error: --full-text also requires --rights-confirmed.")
        print("Full body text may only be ingested once the content owner "
              "has confirmed permission (the site's content is copyright "
              "reserved). Without permission, run without --full-text to "
              "ingest metadata and source links only.")
        return 2

    include_body = bool(args.full_text and args.rights_confirmed)
    rights_status = "permissionConfirmed" if include_body else "linkOnly"
    base_url = args.base_url.rstrip("/")

    fetcher = PoliteFetcher(base_url, args.rate_limit, args.max_pages)
    fetcher.load_robots()

    warnings: List[str] = []
    payload: Dict[str, Any] = {
        "articles": None, "documents": None, "media": None,
        "events": None, "tafsir": None,
    }
    if "about" in sections or "articles" in sections:
        payload["articles"] = []
    if "books" in sections or "magazines" in sections:
        payload["documents"] = []
    if "lectures" in sections:
        payload["media"] = []

    # -- about ------------------------------------------------------------
    if "about" in sections and not fetcher.cap_reached:
        for path, category in ABOUT_PAGES:
            if fetcher.cap_reached:
                break
            page_url = base_url + path
            html = fetcher.fetch(page_url)
            if html is None:
                continue
            meta = parsers.parse_article_page(html, page_url,
                                              include_body=include_body)
            payload["articles"].append(content_item_from_about_page(
                meta, page_url, category, rights_status, include_body))

    # -- lectures ---------------------------------------------------------
    if "lectures" in sections:
        for year in years:
            if fetcher.cap_reached:
                break
            page_url = "%s/lectures/%d" % (base_url, year)
            html = fetcher.fetch(page_url)
            if html is None:
                continue
            result = parsers.parse_lectures_year_page(html, page_url)
            if not result.items:
                warnings.append("%s: no lecture rows found — the page layout "
                                "may have changed." % page_url)
            items, page_warnings = media_items_from_lecture_page(
                result, page_url, year, rights_status)
            payload["media"].extend(items)
            warnings.extend(page_warnings)

    # -- magazines ----------------------------------------------------------
    if "magazines" in sections and not fetcher.cap_reached:
        index_url = base_url + "/almurshid-magazine.html"
        html = fetcher.fetch(index_url)
        archive_urls: List[str] = []
        if html is not None:
            archive_urls = parsers.parse_magazine_archive_index(html, index_url)
            if not archive_urls:
                warnings.append("%s: no magazine archive links found."
                                % index_url)
        for archive_url in archive_urls:
            if fetcher.cap_reached:
                break
            archive_html = fetcher.fetch(archive_url)
            if archive_html is None:
                continue
            issues = parsers.parse_magazine_archive_page(archive_html, archive_url)
            payload["documents"].extend(content_items_from_magazine_page(
                issues, archive_url, rights_status))

    # -- books --------------------------------------------------------------
    if "books" in sections and not fetcher.cap_reached:
        index_url = base_url + "/download"
        html = fetcher.fetch(index_url)
        book_page_urls: List[str] = []
        if html is not None:
            book_page_urls = parsers.parse_books_index(html, index_url)
        if not book_page_urls:
            book_page_urls = [base_url + "/books-on-tasawwuf.html"]
            warnings.append("Books index yielded no listing pages; falling "
                            "back to /books-on-tasawwuf.html.")
        for page_url in book_page_urls:
            if fetcher.cap_reached:
                break
            page_html = fetcher.fetch(page_url)
            if page_html is None:
                continue
            books = parsers.parse_books_page(page_html, page_url)
            payload["documents"].extend(content_items_from_books_page(
                books, page_url, rights_status))

    # -- articles -----------------------------------------------------------
    if "articles" in sections and not fetcher.cap_reached:
        index_url = base_url + "/articles"
        html = fetcher.fetch(index_url)
        if html is not None:
            links = parsers.parse_article_index(html, index_url)
            if not links:
                warnings.append("%s: no article links found." % index_url)
            for link in links:
                meta: Optional[Dict[str, Any]] = None
                if include_body and not fetcher.cap_reached:
                    article_html = fetcher.fetch(link["url"])
                    if article_html is not None:
                        meta = parsers.parse_article_page(
                            article_html, link["url"], include_body=True)
                payload["articles"].append(content_item_from_article_link(
                    link, rights_status, meta=meta, include_body=include_body))

    # -- tafsir index ---------------------------------------------------------
    if "tafsir" in sections and not fetcher.cap_reached:
        index_url = base_url + "/asrar-at-tanzil"
        html = fetcher.fetch(index_url)
        if html is not None:
            entries = parsers.parse_tafsir_index(html, index_url)
            manifest, tafsir_warnings = tafsir_manifest_from_index(
                entries, index_url, rights_status)
            payload["tafsir"] = manifest
            warnings.extend(tafsir_warnings)

    warnings.extend(fetcher.warnings)

    out_dir = Path(args.out)
    conflicts, notes = write_outputs(out_dir, payload, prune=args.prune)

    print("")
    print("Crawl complete: %d page(s) fetched, outputs in %s"
          % (fetcher.pages_fetched, out_dir))
    manifest = load_json(out_dir / MANIFEST_FILE)
    if isinstance(manifest, dict):
        print("Counts: %s" % json.dumps(manifest.get("counts", {}), sort_keys=True))
    for note in notes:
        print("note: %s" % note)
    for warning in warnings:
        print("warning: %s" % warning)
    for conflict in conflicts:
        print("CONFLICT: %s" % conflict)
    if conflicts:
        print("\n%d curated-field conflict(s) need review." % len(conflicts))
        return 3
    return 0


# ---------------------------------------------------------------------------
# validate command
# ---------------------------------------------------------------------------

def cmd_validate(args: argparse.Namespace) -> int:
    out_dir = Path(args.dir)
    if not out_dir.is_dir():
        print("error: %s is not a directory." % out_dir)
        return 2
    errors, warnings = validate_output_dir(out_dir)
    for warning in warnings:
        print("warning: %s" % warning)
    for error in errors:
        print("error: %s" % error)
    if errors:
        print("\nValidation failed with %d error(s)." % len(errors))
        return 1
    print("Validation passed (%d warning(s))." % len(warnings))
    return 0


# ---------------------------------------------------------------------------
# diff command
# ---------------------------------------------------------------------------

def cmd_diff(args: argparse.Namespace) -> int:
    previous_dir = Path(args.previous)
    current_dir = Path(args.current)
    for directory in (previous_dir, current_dir):
        if not directory.is_dir():
            print("error: %s is not a directory." % directory)
            return 2

    total_conflicts: List[str] = []

    for file_name in ITEM_FILES:
        previous = load_json(previous_dir / file_name)
        current = load_json(current_dir / file_name)
        previous_items = previous if isinstance(previous, list) else []
        current_items = current if isinstance(current, list) else []
        previous_by_id = {i["id"]: i for i in previous_items
                          if isinstance(i, dict) and isinstance(i.get("id"), str)}
        current_by_id = {i["id"]: i for i in current_items
                         if isinstance(i, dict) and isinstance(i.get("id"), str)}

        added = sorted(set(current_by_id) - set(previous_by_id))
        removed = sorted(set(previous_by_id) - set(current_by_id))
        changed = sorted(item_id for item_id in
                         set(previous_by_id) & set(current_by_id)
                         if previous_by_id[item_id] != current_by_id[item_id])
        print("%s: %d added, %d removed, %d changed"
              % (file_name, len(added), len(removed), len(changed)))
        for item_id in added:
            print("  + %s" % item_id)
        for item_id in removed:
            print("  - %s" % item_id)
        for item_id in changed:
            print("  ~ %s" % item_id)

        # Curated conflict report: a curated item in the previous output
        # whose preserved (non-URL) fields differ upstream.
        for item_id in set(previous_by_id) & set(current_by_id):
            old = previous_by_id[item_id]
            if old.get("curated") is not True:
                continue
            new = current_by_id[item_id]
            differing = sorted(
                key for key in new
                if key not in URL_FIELDS and key not in ("checksum", "curated")
                and key in old and old[key] != new[key])
            for key in differing:
                total_conflicts.append(
                    "%s: id '%s': curated field '%s' differs from the fresh "
                    "crawl — curated value is preserved on merge."
                    % (file_name, item_id, key))

    previous_tafsir = load_json(previous_dir / TAFSIR_FILE)
    current_tafsir = load_json(current_dir / TAFSIR_FILE)
    if previous_tafsir != current_tafsir:
        print("%s: changed" % TAFSIR_FILE)

    for conflict in total_conflicts:
        print("CONFLICT: %s" % conflict)

    if args.merged_out:
        merged_dir = Path(args.merged_out)
        payload: Dict[str, Any] = {"events": None}
        key_by_file = {"articles.json": "articles", "documents.json": "documents",
                       "media.json": "media", "events.json": "events"}
        merged_dir.mkdir(parents=True, exist_ok=True)
        for file_name, key in key_by_file.items():
            current = load_json(current_dir / file_name)
            payload[key] = current if isinstance(current, list) else []
            # Seed the merged dir with the previous output so curated
            # fields are preserved by the standard merge.
            previous = load_json(previous_dir / file_name)
            write_json(merged_dir / file_name,
                       previous if isinstance(previous, list) else [])
        if isinstance(previous_tafsir, (dict, list)):
            write_json(merged_dir / TAFSIR_FILE, previous_tafsir)
        payload["tafsir"] = current_tafsir if isinstance(current_tafsir, dict) else None
        conflicts, notes = write_outputs(merged_dir, payload)
        for note in notes:
            print("note: %s" % note)
        print("Merged output written to %s" % merged_dir)

    if total_conflicts:
        print("\n%d curated-field conflict(s) need review." % len(total_conflicts))
        return 3
    return 0


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="ingest.py",
        description="Darul Irfan content ingestion pipeline for "
                    "naqshbandiaowaisiah.org (runs on the maintainer's "
                    "machine, never inside the app).")
    subparsers = parser.add_subparsers(dest="command", required=True)

    crawl = subparsers.add_parser(
        "crawl", help="Fetch site sections politely and write output JSON.")
    crawl.add_argument("--sections", default=",".join(ALL_SECTIONS),
                       help="Comma-separated sections to crawl "
                            "(default: %(default)s).")
    crawl.add_argument("--years", default="2024-2026",
                       help="Lecture years, e.g. 2024-2026 or 2020,2023 "
                            "(default: %(default)s).")
    crawl.add_argument("--full-text", action="store_true",
                       help="Ingest full body text. Requires "
                            "--rights-confirmed (owner permission).")
    crawl.add_argument("--rights-confirmed", action="store_true",
                       help="Affirm that the content owner has confirmed "
                            "permission for full-text ingestion.")
    crawl.add_argument("--out", default="output",
                       help="Output directory (default: %(default)s).")
    crawl.add_argument("--rate-limit", type=float,
                       default=DEFAULT_RATE_LIMIT_SECONDS,
                       help="Seconds to wait between requests "
                            "(default: %(default)s).")
    crawl.add_argument("--max-pages", type=int, default=DEFAULT_MAX_PAGES,
                       help="Per-run request cap (default: %(default)s).")
    crawl.add_argument("--base-url", default=DEFAULT_BASE_URL,
                       help="Site root (default: %(default)s).")
    crawl.add_argument("--prune", action="store_true",
                       help="Remove non-curated items that are no longer "
                            "found on the site (default: keep them).")
    crawl.set_defaults(func=cmd_crawl)

    validate = subparsers.add_parser(
        "validate", help="Validate an output folder against the schema.")
    validate.add_argument("--dir", default="output",
                          help="Output directory to validate "
                               "(default: %(default)s).")
    validate.set_defaults(func=cmd_validate)

    diff = subparsers.add_parser(
        "diff", help="Compare two output folders and report curated-field "
                     "conflicts.")
    diff.add_argument("--previous", required=True,
                      help="Previous output directory (may contain curated "
                           "items).")
    diff.add_argument("--current", required=True,
                      help="Freshly crawled output directory.")
    diff.add_argument("--merged-out", default=None,
                      help="Optional directory to write a merged output "
                           "that preserves curated fields.")
    diff.set_defaults(func=cmd_diff)

    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
