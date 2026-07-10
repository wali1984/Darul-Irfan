"""Schema definitions for the Darul Irfan content ingestion pipeline.

The dataclasses here mirror the Swift Codable models in
``DarulIrfanApp/Models/*.swift`` (schema v1). The JSON these classes emit
MUST decode with Swift's ``JSONDecoder`` configured with
``dateDecodingStrategy = .iso8601`` and the default key strategy, i.e.:

* keys are exact camelCase matches of the Swift property names,
* dates are ISO-8601 strings without fractional seconds (``...T00:00:00Z``),
* enum fields carry the Swift enum rawValue strings,
* optional Swift properties may simply be omitted from the JSON object.

Stability rules (idempotent re-runs):

* item IDs are slugs derived from the item's source URL path,
* the ``checksum`` is a sha256 over the canonical JSON of the item's
  fields excluding ``checksum`` and ``curated``,
* serialization sorts object keys and never embeds run timestamps.

Only the Python standard library is used in this module.
"""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from urllib.parse import unquote, urlparse

SCHEMA_VERSION = 1

_ISO_FORMAT = "%Y-%m-%dT%H:%M:%SZ"

# ---------------------------------------------------------------------------
# Enum rawValues copied from the Swift models (do not edit casually — they
# are a wire contract with the app).
# ---------------------------------------------------------------------------

RIGHTS_STATUSES = frozenset({"linkOnly", "permissionConfirmed", "publicDomain"})

CONTENT_TYPES = frozenset({
    "article", "book", "booklet", "magazine", "document",
    "announcement", "pressRelease", "poetry", "page",
})

CONTENT_CATEGORIES = frozenset({
    "aboutSilsila", "sheikhAbdulQadeerAwan", "sheikhMuhammadAkramAwan",
    "shajra", "tasawwuf", "tazkiyahNafs", "zikrAllah", "methodOfZikr",
    "baiat", "articles", "books", "booklets", "sufiPoetry",
    "trainingCourses", "importantDocuments", "alMurshidMagazine",
    "pressReleases", "announcements", "featureArticles", "aqwalESheikh",
})

MEDIA_TYPES = frozenset({"audio", "video", "youtube"})

MEDIA_CATEGORIES = frozenset({
    "audioLectures", "videoLectures", "tafseerQuranVideos", "alMurshidTV",
    "alMurshidQA", "shortClips", "recommended", "kalamESheikh",
})

EVENT_KINDS = frozenset({
    "monthlyIjtema", "salanaIjtema", "ramadanAitekaaf", "announcement", "other",
})

QURAN_EDITION_KINDS = frozenset({"translation", "tafsir"})


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def iso_datetime(dt: datetime) -> str:
    """Format a datetime as the exact ISO-8601 shape Swift's .iso8601 expects."""
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt.strftime(_ISO_FORMAT)


def iso_date_only(year: int, month: int, day: int) -> str:
    """Midnight-UTC ISO string for a date-only source value."""
    return "%04d-%02d-%02dT00:00:00Z" % (year, month, day)


def is_iso_datetime(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    try:
        datetime.strptime(value, _ISO_FORMAT)
        return True
    except ValueError:
        return False


_EXTENSION_RE = re.compile(r"\.(html?|pdf|mp3|wma|php|aspx?)$", re.IGNORECASE)
_NON_SLUG_RE = re.compile(r"[^a-z0-9]+")


def slug_from_url(url: str) -> str:
    """Stable item ID: the URL path, lowercased, slugified, extension dropped.

    Example: ``https://site/lecture/3725/2026-01-02-dawat.html`` →
    ``lecture-3725-2026-01-02-dawat``.
    """
    path = unquote(urlparse(url).path)
    path = _EXTENSION_RE.sub("", path)
    slug = _NON_SLUG_RE.sub("-", path.lower()).strip("-")
    return slug or "item"


def canonical_json(payload: Any) -> str:
    """Deterministic JSON used for checksums (sorted keys, ascii escapes)."""
    return json.dumps(payload, sort_keys=True, ensure_ascii=True,
                      separators=(",", ":"))


def checksum_for(item: Dict[str, Any]) -> str:
    """sha256 over the item's normalized content fields.

    ``checksum`` itself and the curator-owned ``curated`` marker are
    excluded so that recomputing is stable and curation flags do not
    perturb the digest.
    """
    payload = {k: v for k, v in item.items() if k not in ("checksum", "curated")}
    digest = hashlib.sha256(canonical_json(payload).encode("utf-8"))
    return digest.hexdigest()


def apply_checksum(item: Dict[str, Any]) -> Dict[str, Any]:
    """(Re)compute and store the checksum on an item dict, in place."""
    item.pop("checksum", None)
    item["checksum"] = checksum_for(item)
    return item


def json_dumps_stable(obj: Any) -> str:
    """The single serializer used for every output file: sorted keys,
    2-space indent, UTF-8 friendly (no ascii escaping), trailing newline."""
    return json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def _put(d: Dict[str, Any], key: str, value: Any) -> None:
    """Set an optional key only when a value exists (Swift optionals may be
    omitted entirely from the JSON)."""
    if value is not None:
        d[key] = value


# ---------------------------------------------------------------------------
# Dataclasses mirroring the app models
# ---------------------------------------------------------------------------

@dataclass
class ContentItem:
    """Mirror of ``ContentItem`` in ``ContentModels.swift`` (articles.json /
    documents.json)."""
    id: str
    source_url: str
    type: str
    title: str
    language: str
    category: str
    rights_status: str = "linkOnly"
    title_urdu: Optional[str] = None
    author: Optional[str] = None
    body_html: Optional[str] = None
    body_plain_text: Optional[str] = None
    excerpt: Optional[str] = None
    published_at: Optional[str] = None
    updated_at: Optional[str] = None
    media_urls: List[str] = field(default_factory=list)
    download_urls: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        d: Dict[str, Any] = {
            "id": self.id,
            "sourceUrl": self.source_url,
            "type": self.type,
            "title": self.title,
            "language": self.language,
            "category": self.category,
            "rightsStatus": self.rights_status,
            "mediaUrls": list(self.media_urls),
            "downloadUrls": list(self.download_urls),
        }
        _put(d, "titleUrdu", self.title_urdu)
        _put(d, "author", self.author)
        _put(d, "bodyHtml", self.body_html)
        _put(d, "bodyPlainText", self.body_plain_text)
        _put(d, "excerpt", self.excerpt)
        _put(d, "publishedAt", self.published_at)
        _put(d, "updatedAt", self.updated_at)
        return apply_checksum(d)


@dataclass
class MediaItem:
    """Mirror of ``MediaItem`` in ``MediaModels.swift`` (media.json)."""
    id: str
    title: str
    language: str
    media_type: str
    source_url: str
    category: str
    rights_status: str = "linkOnly"
    speaker: Optional[str] = None
    date: Optional[str] = None
    duration_seconds: Optional[float] = None
    stream_url: Optional[str] = None
    download_url: Optional[str] = None
    youtube_id: Optional[str] = None
    year: Optional[int] = None
    month: Optional[int] = None
    transcript_url: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        d: Dict[str, Any] = {
            "id": self.id,
            "title": self.title,
            "language": self.language,
            "mediaType": self.media_type,
            "sourceUrl": self.source_url,
            "category": self.category,
            "rightsStatus": self.rights_status,
        }
        _put(d, "speaker", self.speaker)
        _put(d, "date", self.date)
        _put(d, "durationSeconds", self.duration_seconds)
        _put(d, "streamUrl", self.stream_url)
        _put(d, "downloadUrl", self.download_url)
        _put(d, "youtubeId", self.youtube_id)
        _put(d, "year", self.year)
        _put(d, "month", self.month)
        _put(d, "transcriptUrl", self.transcript_url)
        return apply_checksum(d)


@dataclass
class CommunityEvent:
    """Mirror of ``CommunityEvent`` in ``EventModels.swift`` (events.json)."""
    id: str
    kind: str
    title: str
    dates_are_approximate: bool = False
    title_urdu: Optional[str] = None
    details: Optional[str] = None
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    venue: Optional[str] = None
    source_url: Optional[str] = None
    updated_at: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        d: Dict[str, Any] = {
            "id": self.id,
            "kind": self.kind,
            "title": self.title,
            "datesAreApproximate": bool(self.dates_are_approximate),
        }
        _put(d, "titleUrdu", self.title_urdu)
        _put(d, "details", self.details)
        _put(d, "startDate", self.start_date)
        _put(d, "endDate", self.end_date)
        _put(d, "venue", self.venue)
        _put(d, "sourceUrl", self.source_url)
        _put(d, "updatedAt", self.updated_at)
        return apply_checksum(d)


@dataclass
class QuranEdition:
    """Mirror of ``QuranEdition`` in ``QuranModels.swift`` (used inside
    quran_tafsir_manifest.json)."""
    id: str
    title: str
    kind: str
    language: str
    rights_status: str = "linkOnly"
    author: Optional[str] = None
    source_url: Optional[str] = None
    is_available_offline: bool = False

    def to_dict(self) -> Dict[str, Any]:
        d: Dict[str, Any] = {
            "id": self.id,
            "title": self.title,
            "kind": self.kind,
            "language": self.language,
            "rightsStatus": self.rights_status,
            "isAvailableOffline": bool(self.is_available_offline),
        }
        _put(d, "author", self.author)
        _put(d, "sourceUrl", self.source_url)
        return d


# ---------------------------------------------------------------------------
# Validators (used by `ingest.py validate`)
# ---------------------------------------------------------------------------

def _require_str(d: Dict[str, Any], key: str, errors: List[str], label: str) -> None:
    value = d.get(key)
    if not isinstance(value, str) or not value:
        errors.append("%s: required string field '%s' is missing or empty" % (label, key))


def _optional_str(d: Dict[str, Any], key: str, errors: List[str], label: str) -> None:
    if key in d and not isinstance(d[key], str):
        errors.append("%s: field '%s' must be a string" % (label, key))


def _optional_iso(d: Dict[str, Any], key: str, errors: List[str], label: str) -> None:
    if key in d and not is_iso_datetime(d[key]):
        errors.append("%s: field '%s' is not an ISO-8601 datetime like "
                      "2026-01-02T00:00:00Z" % (label, key))


def _url_is_wma(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    return urlparse(value).path.lower().endswith(".wma")


def validate_content_item(d: Dict[str, Any]) -> List[str]:
    errors: List[str] = []
    label = "content item '%s'" % d.get("id", "<no id>")
    for key in ("id", "sourceUrl", "type", "title", "language", "category", "rightsStatus"):
        _require_str(d, key, errors, label)
    for key in ("mediaUrls", "downloadUrls"):
        value = d.get(key)
        if not isinstance(value, list) or any(not isinstance(u, str) for u in value):
            errors.append("%s: field '%s' must be a list of strings" % (label, key))
    if isinstance(d.get("type"), str) and d["type"] not in CONTENT_TYPES:
        errors.append("%s: unknown type '%s'" % (label, d["type"]))
    if isinstance(d.get("category"), str) and d["category"] not in CONTENT_CATEGORIES:
        errors.append("%s: unknown category '%s'" % (label, d["category"]))
    if isinstance(d.get("rightsStatus"), str) and d["rightsStatus"] not in RIGHTS_STATUSES:
        errors.append("%s: unknown rightsStatus '%s'" % (label, d["rightsStatus"]))
    for key in ("titleUrdu", "author", "bodyHtml", "bodyPlainText", "excerpt", "checksum"):
        _optional_str(d, key, errors, label)
    for key in ("publishedAt", "updatedAt"):
        _optional_iso(d, key, errors, label)
    if d.get("rightsStatus") == "linkOnly" and (d.get("bodyHtml") or d.get("bodyPlainText")):
        errors.append("%s: linkOnly items must not carry body text — metadata "
                      "and source link only until permission is confirmed" % label)
    return errors


def validate_media_item(d: Dict[str, Any]) -> List[str]:
    errors: List[str] = []
    label = "media item '%s'" % d.get("id", "<no id>")
    for key in ("id", "title", "language", "mediaType", "sourceUrl", "category", "rightsStatus"):
        _require_str(d, key, errors, label)
    if isinstance(d.get("mediaType"), str) and d["mediaType"] not in MEDIA_TYPES:
        errors.append("%s: unknown mediaType '%s'" % (label, d["mediaType"]))
    if isinstance(d.get("category"), str) and d["category"] not in MEDIA_CATEGORIES:
        errors.append("%s: unknown category '%s'" % (label, d["category"]))
    if isinstance(d.get("rightsStatus"), str) and d["rightsStatus"] not in RIGHTS_STATUSES:
        errors.append("%s: unknown rightsStatus '%s'" % (label, d["rightsStatus"]))
    for key in ("speaker", "streamUrl", "downloadUrl", "youtubeId", "transcriptUrl", "checksum"):
        _optional_str(d, key, errors, label)
    _optional_iso(d, "date", errors, label)
    if "durationSeconds" in d and not isinstance(d["durationSeconds"], (int, float)):
        errors.append("%s: durationSeconds must be a number" % label)
    for key in ("year", "month"):
        if key in d and not isinstance(d[key], int):
            errors.append("%s: %s must be an integer" % (label, key))
    for key in ("streamUrl", "downloadUrl"):
        if _url_is_wma(d.get(key)):
            errors.append("%s: %s points at a .wma file, which iOS cannot "
                          "play — WMA links must be excluded at ingest" % (label, key))
    return errors


def validate_community_event(d: Dict[str, Any]) -> List[str]:
    errors: List[str] = []
    label = "event '%s'" % d.get("id", "<no id>")
    for key in ("id", "kind", "title"):
        _require_str(d, key, errors, label)
    if isinstance(d.get("kind"), str) and d["kind"] not in EVENT_KINDS:
        errors.append("%s: unknown kind '%s'" % (label, d["kind"]))
    if not isinstance(d.get("datesAreApproximate"), bool):
        errors.append("%s: required boolean field 'datesAreApproximate' is "
                      "missing" % label)
    for key in ("titleUrdu", "details", "venue", "sourceUrl", "checksum"):
        _optional_str(d, key, errors, label)
    for key in ("startDate", "endDate", "updatedAt"):
        _optional_iso(d, key, errors, label)
    return errors


def validate_quran_edition(d: Dict[str, Any]) -> List[str]:
    errors: List[str] = []
    label = "quran edition '%s'" % d.get("id", "<no id>")
    for key in ("id", "title", "kind", "language", "rightsStatus"):
        _require_str(d, key, errors, label)
    if isinstance(d.get("kind"), str) and d["kind"] not in QURAN_EDITION_KINDS:
        errors.append("%s: unknown kind '%s'" % (label, d["kind"]))
    if isinstance(d.get("rightsStatus"), str) and d["rightsStatus"] not in RIGHTS_STATUSES:
        errors.append("%s: unknown rightsStatus '%s'" % (label, d["rightsStatus"]))
    if not isinstance(d.get("isAvailableOffline"), bool):
        errors.append("%s: required boolean field 'isAvailableOffline' is "
                      "missing" % label)
    for key in ("author", "sourceUrl"):
        _optional_str(d, key, errors, label)
    return errors
