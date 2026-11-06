"""Paltalk hosts' cue messages -> the platform's stage ids, so the room's
cues land in the platform's one list (POST /v1/service/groups/:id/zikr-cues).

Hosts write cues as they always have ("1st Latifa", then "2nd", "3rd"...;
"Ahdiat", "Maeiat", "Akrabiat", "M-Nabvee"). Anything not recognised is not
a cue and is never sent."""

from __future__ import annotations

import json
import re
import urllib.error
import urllib.request
import uuid

USER_AGENT = "DarulIrfanRelay/1.0"

_ORDINALS = {"1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7,
             "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7}

# (pattern on the folded text, stage id). First match wins.
_NAMED = [
    (r"\bm\s*-?\s*nab[a-z]*|masjid\s*-?\s*e?\s*-?\s*nab[a-z]*", "masjid-nabawi"),
    (r"\bsa[iy]?re?\b.*\bka.?h?.?a?ba\b|\bka.?h?.?aba\b|\bkahba\b", "sair-kaaba"),
    (r"\brau?[zw]a\b|\broza\b|\bathar\b", "rauza-athar"),
    (r"\bah?a?di[ay]+[ae]?t\b|\bahdiat\b|\bahadiyat\b", "ahadiyat"),
    (r"\bma.?[ei]+y*[ae]?t\b|\bmaeiat\b|\bmaiyyat\b", "maiyyat"),
    (r"\ba[kq]rabi[ay]+[ae]?t\b|\bakrabiat\b", "aqrabiyyat"),
    (r"\bra+bi?ta\b|\brabta\b", "raabta"),
    (r"\btasb[ie]+h\b", "tasbih"),
    (r"\bistighfar\b|\bastaghfirullah\b", "istighfar"),
    (r"\bshahad[ah]+\b|\bkalim[ah]+\b", "shahadah"),
    (r"\bta.?awwu?dh\b|\ba.?u?o?zu?\s*billah\b", "taawwudh"),
    (r"\bbas?mala\b|\bbismillah\b", "basmalah"),
]


def is_dua(text: str) -> bool:
    """A host announcing the closing dua ("Dua", "دعا")."""
    folded = re.sub(r"\s+", " ", text.strip().lower())
    return bool(re.fullmatch(r"(dua|du'a|duaa|doa|دعا|دُعا)[.!]*", folded))


def stage_id(text: str) -> str | None:
    folded = re.sub(r"\s+", " ", text.strip().lower())
    if not folded or len(folded) > 40:
        return None  # a cue is a word or two, never a sentence
    # "1st Latifa", "3rd", "L-3", "latifa 5", "7th latifa"
    match = re.fullmatch(r"(?:l\s*-?\s*|latifa\s*)?(\d)(?:st|nd|rd|th)?(?:\s*latifa)?", folded) \
        or re.fullmatch(r"(first|second|third|fourth|fifth|sixth|seventh)(?:\s*latifa)?", folded)
    if match:
        number = _ORDINALS.get(match.group(1))
        return f"latifa-{number}" if number else None
    for pattern, stage in _NAMED:
        if re.search(pattern, folded):
            return stage
    return None


class PlatformCues:
    """Posts recognised cues to the platform; each cue keeps one id across
    retries, so a retry never makes a second cue."""

    def __init__(self, platform: str, halqah: str, token: str, test: bool = False) -> None:
        base = f"{platform.rstrip('/')}/v1/service/groups/{halqah}"
        self.url, self.live_url = f"{base}/zikr-cues", f"{base}/live"
        self.token = token
        self.test = test

    def _send(self, url: str, body: dict) -> tuple[int, str]:
        request = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST", headers={
            "content-type": "application/json", "authorization": f"Bearer {self.token}", "user-agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                return response.status, response.read().decode("utf-8", "replace")[:200]
        except urllib.error.HTTPError as error:
            return error.code, {401: "bad token", 409: "no live Zikr on the platform"}.get(error.code, "refused")
        except Exception as error:  # noqa: BLE001
            return 0, type(error).__name__

    def post(self, stage: str, cue_id: str | None = None) -> tuple[int, str]:
        return self._send(self.url, {"id": cue_id or str(uuid.uuid4()), "stageID": stage})

    def start(self, title: str) -> tuple[int, str]:
        """Starts the Halqah's Zikr (201), or finds it already live (200)."""
        body = {"state": "live", "title": title}
        if self.test:
            body["test"] = True  # the platform's Test Zikr: admins only, no push
        return self._send(self.live_url, body)

    def dua(self) -> tuple[int, str]:
        """The dua has begun: the platform ends the session 5 minutes later."""
        return self._send(self.live_url, {"state": "dua"})
