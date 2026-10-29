"""Polite access to naqshbandiaowaisiah.org for the content scripts.

At most four requests at a time, a real User-Agent, 30 s timeouts and one
retry, and ranged GETs for media so a check never downloads a whole lecture.
Pages can be cached in a directory so a re-run (or a review of what was read)
does not fetch them again.
"""

from __future__ import annotations

import hashlib
import re
import time
import unicodedata
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path
from urllib.parse import quote

import requests
from bs4 import BeautifulSoup

SITE = "https://www.naqshbandiaowaisiah.org"
USER_AGENT = "Mozilla/5.0 (DarulIrfanAudit/1.0)"
WORKERS = 4
TIMEOUT = 30


def encode_url(url: str) -> str:
    """Percent-encode spaces and non-ASCII letters, keeping URL delimiters.

    The site links files with raw spaces and Urdu letters in their names.
    Android cannot open such a URL, so the seed stores the encoded form (the
    same scheme as the corrected rows in media_items.json).
    """
    return quote(url, safe=":/?#[]@!$&'()*+,;=%")


def _cache_name(url: str) -> str:
    tail = re.sub(r"[^A-Za-z0-9]+", "_", url.split("://", 1)[-1])[-40:]
    return f"{tail}_{hashlib.sha1(url.encode()).hexdigest()[:10]}.html"


def get(url: str, cache: Path | None = None, headers: dict | None = None) -> tuple[int | None, bytes, str]:
    """GET with one retry. Returns (status, body, final URL); status None on failure."""
    if cache is not None and headers is None:
        cached = cache / _cache_name(url)
        if cached.exists():
            return 200, cached.read_bytes(), url
    error = ""
    for attempt in (1, 2):
        try:
            response = requests.get(url, timeout=TIMEOUT,
                                    headers={"User-Agent": USER_AGENT, **(headers or {})})
            if cache is not None and headers is None and response.status_code == 200:
                cache.mkdir(parents=True, exist_ok=True)
                (cache / _cache_name(url)).write_bytes(response.content)
            return response.status_code, response.content, response.url
        except requests.RequestException as exc:
            error = repr(exc)
            if attempt == 1:
                time.sleep(2)
    return None, error.encode(), url


def get_many(urls: list[str], cache: Path | None = None) -> dict[str, tuple[int | None, bytes, str]]:
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        return dict(zip(urls, pool.map(lambda u: get(u, cache), urls)))


def sniff_audio(url: str) -> dict:
    """Ranged GET of the first 2 KB: does the link answer, and with what?"""
    status, body, _ = get(url, headers={"Range": "bytes=0-2047"})
    kind = "none"
    if body[:3] == b"ID3" or (len(body) > 1 and body[0] == 0xFF and (body[1] & 0xE0) == 0xE0):
        kind = "mp3"
    elif body[4:8] == b"ftyp":
        kind = "mp4"
    elif body[:1] in (b"<", b"\n", b"\r") or b"<html" in body[:200].lower():
        kind = "html"
    return {"status": status, "kind": kind, "ok": status in (200, 206) and kind in ("mp3", "mp4")}


def sniff_many(urls: list[str]) -> dict[str, dict]:
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        return dict(zip(urls, pool.map(sniff_audio, urls)))


def clean_text(text: str) -> str:
    """Canonical form for a title: NFC, single spaces, trimmed."""
    return unicodedata.normalize("NFC", re.sub(r"\s+", " ", text or "")).strip()


def lecture_rows(html: str) -> list[dict]:
    """The rows of one /lectures/<year> page.

    Each lecture is its own div.lectures-not-uploaded. Media and dates are only
    ever read from inside that div: a YouTube-only row has no audio link, and
    looking outside the row is how five lectures came to play another
    lecture's recording.
    """
    soup = BeautifulSoup(html, "html.parser")
    rows = []
    for row in soup.select("div.lectures-not-uploaded"):
        title = row.select_one("div.lecture-title a[data-id]")
        if title is None:
            continue
        spans = [s.get_text(" ", strip=True) for s in row.select("div.lecture-date span")]
        date = next((s for s in spans if re.match(r"\d{2}-[A-Za-z]{3}-\d{4}$", s)), None)
        rows.append({
            "lectureID": title["data-id"],
            "title": title.get("data-title", "") or title.get_text(" ", strip=True),
            "href": title["href"],
            "date": datetime.strptime(date, "%d-%b-%Y").date() if date else None,
            "speaker": next((s for s in spans if s.startswith("By ")), None),
            "mp3": [a["href"] for a in row.select('a[data-linktype="audio-mp3"]')],
            "wma": [a["href"] for a in row.select('a[data-linktype="audio-wma"]')],
            "youtube": bool(row.select('a[data-linktype="youtube-link"]')),
        })
    return rows


def youtube_ids(html: str) -> list[str]:
    found = re.findall(r"(?:youtube(?:-nocookie)?\.com/(?:embed/|watch\?v=)|youtu\.be/)([A-Za-z0-9_-]{11})", html)
    return list(dict.fromkeys(found))


def youtube_playable(video_id: str) -> dict:
    """YouTube oEmbed answers 200 for a public, embeddable video; 401/403 when
    embedding is off or the video is private, 404 when it was removed."""
    status, body, _ = get("https://www.youtube.com/oembed?format=json&url="
                          + quote(f"https://www.youtube.com/watch?v={video_id}", safe=""),
                          headers={"Accept": "application/json"})
    return {"status": status, "ok": status == 200}


def youtube_playable_many(video_ids: list[str]) -> dict[str, dict]:
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        return dict(zip(video_ids, pool.map(youtube_playable, video_ids)))


def listing_items(html: str) -> list[dict]:
    """Items of a /video-lectures or /almurshid-programs listing page.

    Each item is a title link (data-id), its speaker, place and date lines,
    and a YouTube block carrying the same data-id, so the video is matched to
    its item by id rather than by position on the page.
    """
    soup = BeautifulSoup(html, "html.parser")
    videos: dict[str, list[str]] = {}
    for block in soup.select("div[data-linktype=youtube]"):
        if block.get("id"):
            videos.setdefault(block.get("data-id"), []).append(block["id"])
    items = []
    for link in soup.select('a[data-linktype="event-title"]'):
        box = link.find_parent("div")
        spans = [s.get_text(" ", strip=True) for s in box.select("span.margin-left-5")] if box else []
        date = next((s for s in spans if re.match(r"\d{2}-[A-Za-z]{3}-\d{4}$", s)), None)
        items.append({
            "itemID": link.get("data-id"),
            "title": link.get("data-title") or link.get_text(" ", strip=True),
            "href": link["href"],
            "date": datetime.strptime(date, "%d-%b-%Y").date() if date else None,
            "speaker": next((s for s in spans if s.startswith("By ")), None),
            "youtube": list(dict.fromkeys(videos.get(link.get("data-id"), []))),
        })
    return items
