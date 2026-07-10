"""HTML parsers for naqshbandiaowaisiah.org page types.

One parser per page type, built against the URL patterns verified in
``Docs/RESEARCH_NOTES.md``. Parsers are pure functions over HTML text —
no network access — so they can be exercised with saved fixtures.

Hard rules encoded here:

* MP3 URLs are ALWAYS harvested from actual ``href`` attributes; filenames
  are irregular on the site (e.g. ``06-02-2026%20s.mp3``) and must never
  be constructed.
* ``.wma`` links are skipped and counted so the caller can emit a warning
  (iOS cannot play WMA).
* Lecture dates ``DD-MMM-YYYY`` are converted to ISO-8601 midnight UTC.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import unquote, urljoin, urlparse

from bs4 import BeautifulSoup

_MONTHS_BY_PREFIX = {
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
}

_MONTH_NAME_RE = re.compile(
    r"\b(january|february|march|april|may|june|july|august|september|"
    r"october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|"
    r"oct|nov|dec)\b", re.IGNORECASE)

_YEAR_RE = re.compile(r"\b((?:19|20)\d{2})\b")

_DISPLAY_DATE_RE = re.compile(r"(\d{1,2})-([A-Za-z]{3,9})-(\d{4})")

_LECTURE_DETAIL_RE = re.compile(r"/lecture/\d+/[^/]+\.html?$", re.IGNORECASE)

_TAFSIR_PAGE_RE = re.compile(r"/asrar-at-tanzil/\d+/[^/]+\.html?$", re.IGNORECASE)

_MAGAZINE_ARCHIVE_RE = re.compile(
    r"almurshid-magazine-\d{4}-to-\d{4}\.html?$", re.IGNORECASE)

_MAGAZINE_FILENAME_RE = re.compile(
    r"almurshid_([a-z_]+)_(\d{4})\.pdf$", re.IGNORECASE)

_BOOKS_PAGE_RE = re.compile(r"/books-[a-z0-9-]+\.html?$", re.IGNORECASE)


def _soup(html: str) -> BeautifulSoup:
    return BeautifulSoup(html, "html.parser")


def _href_path(href: str) -> str:
    """Lowercased URL path of an href (query string and fragment ignored)."""
    return urlparse(href).path.lower()


def _month_number(name: str) -> Optional[int]:
    name = name.strip().lower()
    if len(name) < 3:
        return None
    return _MONTHS_BY_PREFIX.get(name[:3])


def parse_display_date(text: str) -> Optional[str]:
    """``02-Jan-2026`` (or ``02-January-2026``) → ``2026-01-02T00:00:00Z``."""
    match = _DISPLAY_DATE_RE.search(text)
    if not match:
        return None
    day = int(match.group(1))
    month = _month_number(match.group(2))
    year = int(match.group(3))
    if month is None or not (1 <= day <= 31):
        return None
    return "%04d-%02d-%02dT00:00:00Z" % (year, month, day)


# ---------------------------------------------------------------------------
# Lecture year pages  (/lectures/{YYYY})
# ---------------------------------------------------------------------------

@dataclass
class LecturePageResult:
    """Parsed rows plus the count of skipped .wma links (warning material)."""
    items: List[Dict[str, Any]] = field(default_factory=list)
    skipped_wma: int = 0


def _contains_audio_link(node: Any) -> bool:
    for a in node.find_all("a", href=True):
        path = _href_path(a["href"])
        if path.endswith(".mp3") or path.endswith(".wma"):
            return True
    return False


def _row_container(anchor: Any) -> Optional[Any]:
    """Nearest ancestor that plausibly represents one lecture row."""
    for parent in anchor.parents:
        name = getattr(parent, "name", None)
        if name in ("tr", "li", "article"):
            return parent
        if name in ("div", "p") and _contains_audio_link(parent):
            return parent
        if name in ("table", "tbody", "ul", "ol", "body", "html"):
            return None
    return None


def _find_speaker(row: Any) -> Optional[str]:
    for text in row.stripped_strings:
        if "Sheikh" in text or "Hazrat" in text:
            return text
    return None


def parse_lectures_year_page(html: str, page_url: str) -> LecturePageResult:
    """Parse one ``/lectures/{YYYY}`` archive page.

    Each returned item dict has keys ``title``, ``speaker``, ``date_iso``,
    ``mp3_url`` and ``detail_url``. MP3 URLs come from the real hrefs
    (percent-encoding preserved). Rows without an MP3 link are skipped;
    every ``.wma`` link on the page increments ``skipped_wma``.
    """
    soup = _soup(html)
    result = LecturePageResult()

    for a in soup.find_all("a", href=True):
        if _href_path(a["href"]).endswith(".wma"):
            result.skipped_wma += 1

    seen_rows = set()
    for detail_anchor in soup.find_all("a", href=True):
        if not _LECTURE_DETAIL_RE.search(urlparse(detail_anchor["href"]).path):
            continue
        row = _row_container(detail_anchor)
        if row is None or id(row) in seen_rows:
            continue
        seen_rows.add(id(row))

        mp3_url: Optional[str] = None
        for link in row.find_all("a", href=True):
            if _href_path(link["href"]).endswith(".mp3"):
                mp3_url = urljoin(page_url, link["href"])
                break
        if mp3_url is None:
            # WMA-only or missing audio; the wma counter above already
            # recorded any skipped links.
            continue

        result.items.append({
            "title": detail_anchor.get_text(strip=True),
            "speaker": _find_speaker(row),
            "date_iso": parse_display_date(row.get_text(" ", strip=True)),
            "mp3_url": mp3_url,
            "detail_url": urljoin(page_url, detail_anchor["href"]),
        })
    return result


# ---------------------------------------------------------------------------
# Al-Murshid magazine archive pages  (almurshid-magazine-{Y1}-to-{Y2}.html)
# ---------------------------------------------------------------------------

def _months_year_from_text(text: str) -> Tuple[List[int], Optional[int]]:
    months: List[int] = []
    for match in _MONTH_NAME_RE.finditer(text):
        number = _month_number(match.group(1))
        if number is not None and number not in months:
            months.append(number)
    year_match = _YEAR_RE.search(text)
    year = int(year_match.group(1)) if year_match else None
    return months, year


def parse_magazine_archive_page(html: str, page_url: str) -> List[Dict[str, Any]]:
    """Parse one 5-year magazine archive page into issue dicts with keys
    ``title``, ``year``, ``months`` and ``pdf_url``.

    Month/year come from the PDF filename
    (``almurshid_{month(s)}_{year}.pdf``); when the filename does not match
    that pattern, the link text is used as a fallback.
    """
    soup = _soup(html)
    issues: List[Dict[str, Any]] = []
    seen_urls = set()

    for a in soup.find_all("a", href=True):
        path = unquote(urlparse(a["href"]).path)
        if not path.lower().endswith(".pdf"):
            continue
        pdf_url = urljoin(page_url, a["href"])
        if pdf_url in seen_urls:
            continue
        seen_urls.add(pdf_url)

        basename = path.rsplit("/", 1)[-1]
        link_text = a.get_text(" ", strip=True)

        match = _MAGAZINE_FILENAME_RE.search(basename)
        if match:
            month_parts = [p for p in match.group(1).split("_") if p]
            months = []
            for part in month_parts:
                number = _month_number(part)
                if number is not None and number not in months:
                    months.append(number)
            year: Optional[int] = int(match.group(2))
        else:
            months, year = _months_year_from_text(link_text)

        title = link_text or basename
        issues.append({
            "title": title,
            "year": year,
            "months": months,
            "pdf_url": pdf_url,
        })
    return issues


def parse_magazine_archive_index(html: str, page_url: str) -> List[str]:
    """Harvest the 5-year archive page URLs from ``/almurshid-magazine.html``."""
    soup = _soup(html)
    urls: List[str] = []
    for a in soup.find_all("a", href=True):
        if _MAGAZINE_ARCHIVE_RE.search(urlparse(a["href"]).path):
            absolute = urljoin(page_url, a["href"])
            if absolute not in urls:
                urls.append(absolute)
    return urls


# ---------------------------------------------------------------------------
# Books pages  (/books-on-tasawwuf.html etc.)
# ---------------------------------------------------------------------------

def parse_books_page(html: str, page_url: str) -> List[Dict[str, Any]]:
    """Parse a books listing page into dicts with ``title`` and ``pdf_url``.

    The title is the PDF link's text; when the link has no text the title
    falls back to the filename with hyphens spaced out.
    """
    soup = _soup(html)
    books: List[Dict[str, Any]] = []
    seen_urls = set()
    for a in soup.find_all("a", href=True):
        path = unquote(urlparse(a["href"]).path)
        if not path.lower().endswith(".pdf"):
            continue
        pdf_url = urljoin(page_url, a["href"])
        if pdf_url in seen_urls:
            continue
        seen_urls.add(pdf_url)
        title = a.get_text(" ", strip=True)
        if not title:
            basename = path.rsplit("/", 1)[-1]
            title = re.sub(r"\.pdf$", "", basename, flags=re.IGNORECASE)
            title = title.replace("-", " ").replace("_", " ").strip()
        books.append({"title": title, "pdf_url": pdf_url})
    return books


def parse_books_index(html: str, page_url: str) -> List[str]:
    """Harvest books listing page URLs (``books-*.html``) from ``/download``."""
    soup = _soup(html)
    urls: List[str] = []
    for a in soup.find_all("a", href=True):
        if _BOOKS_PAGE_RE.search(urlparse(a["href"]).path):
            absolute = urljoin(page_url, a["href"])
            if absolute not in urls:
                urls.append(absolute)
    return urls


# ---------------------------------------------------------------------------
# About / article pages
# ---------------------------------------------------------------------------

def parse_article_page(html: str, page_url: str,
                       include_body: bool = False) -> Dict[str, Any]:
    """Extract metadata (and, only when ``include_body`` is true, the main
    plain text) from an about/article page.

    Returns ``{"title", "excerpt", "body_plain_text"}`` where
    ``body_plain_text`` is None unless ``include_body`` was requested — the
    caller enforces the rights policy (``--full-text --rights-confirmed``).
    """
    soup = _soup(html)

    title = ""
    h1 = soup.find("h1")
    if h1 is not None:
        title = h1.get_text(" ", strip=True)
    if not title and soup.title is not None:
        title = soup.title.get_text(" ", strip=True)

    excerpt: Optional[str] = None
    meta = soup.find("meta", attrs={"name": "description"})
    if meta is not None:
        content = meta.get("content")
        if isinstance(content, str) and content.strip():
            excerpt = content.strip()

    body: Optional[str] = None
    if include_body:
        node = (soup.find("main") or soup.find("article")
                or soup.find(id="content")
                or soup.find("div", class_="content")
                or soup.body or soup)
        for junk in node.find_all(["script", "style", "nav", "header", "footer"]):
            junk.decompose()
        lines = [line.strip() for line in node.get_text("\n").splitlines()]
        body = "\n".join(line for line in lines if line) or None

    return {"title": title, "excerpt": excerpt, "body_plain_text": body}


def parse_article_index(html: str, page_url: str) -> List[Dict[str, Any]]:
    """Harvest article links from the ``/articles`` index page.

    Prefers links whose path lives under ``/articles``; if none exist the
    parser falls back to same-host ``.html`` links that do not belong to
    other known site sections. Returns dicts with ``title`` and ``url``.
    """
    soup = _soup(html)
    page_host = urlparse(page_url).netloc

    def collect(predicate) -> List[Dict[str, Any]]:
        found: List[Dict[str, Any]] = []
        seen = set()
        for a in soup.find_all("a", href=True):
            absolute = urljoin(page_url, a["href"])
            parsed = urlparse(absolute)
            if parsed.netloc != page_host:
                continue
            if absolute == page_url:
                continue
            if not predicate(parsed.path):
                continue
            if absolute in seen:
                continue
            seen.add(absolute)
            title = a.get_text(" ", strip=True)
            found.append({"title": title, "url": absolute})
        return found

    articles = collect(lambda path: path.lower().startswith("/articles")
                       and path.lower().endswith((".html", ".htm")))
    if articles:
        return articles

    excluded_prefixes = (
        "/lecture", "/lectures", "/almurshid", "/books-", "/download",
        "/asrar-at-tanzil", "/akram-ut", "/zikr", "/method-of-zikr",
        "/online-zikr", "/video", "/hazrat-", "/silsila", "/shajra",
    )

    def is_articleish(path: str) -> bool:
        lowered = path.lower()
        if not lowered.endswith((".html", ".htm")):
            return False
        return not any(lowered.startswith(p) for p in excluded_prefixes)

    return collect(is_articleish)


# ---------------------------------------------------------------------------
# Asrar-at-Tanzil tafsir index  (/asrar-at-tanzil)
# ---------------------------------------------------------------------------

def _surah_title_from_slug(path: str) -> str:
    basename = path.rsplit("/", 1)[-1]
    basename = re.sub(r"\.html?$", "", basename, flags=re.IGNORECASE)
    if "surah-" in basename:
        basename = basename.split("surah-", 1)[1]
    parts = [part.capitalize() for part in basename.split("-") if part]
    return "-".join(parts)


def parse_tafsir_index(html: str, page_url: str) -> List[Dict[str, Any]]:
    """Harvest the 114 surah tafsir page links from the Asrar-at-Tanzil
    index. Returns dicts with ``surah_number`` (1-based document order),
    ``title`` and ``url``.
    """
    soup = _soup(html)
    entries: List[Dict[str, Any]] = []
    seen_urls = set()
    for a in soup.find_all("a", href=True):
        path = urlparse(a["href"]).path
        if not _TAFSIR_PAGE_RE.search(path):
            continue
        absolute = urljoin(page_url, a["href"])
        if absolute in seen_urls:
            continue
        seen_urls.add(absolute)
        title = a.get_text(" ", strip=True) or _surah_title_from_slug(path)
        entries.append({
            "surah_number": len(entries) + 1,
            "title": title,
            "url": absolute,
        })
    return entries
