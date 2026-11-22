"""Apply the Urdu proofreading register to the library's page text.

The register (`findings.json`) is written by a reader working through every
Urdu page of `book_pages.json`. Each finding names a page, the words as they
stand, the words proposed, how sure the reader is, and where on the page the
words are. The register is anchored to the seed as it stood at BASE: every
finding carries the SHA-256 of its page's text and a UTF-16 offset into it.

This tool never patches the seed in place. It always starts again from the
BASE text, applies every finding the policy accepts, and writes the result.
Running it twice gives the same bytes; running it after the register has
grown adds the new corrections and keeps the old ones.

What is applied

  * `high`: the reader is sure. Applied when the change is form only
    (spacing, punctuation, vowel marks) or a slip of one or two letters. A
    larger change, a change of a number, or one that adds or drops a negation,
    waits for a decision in `decisions.json`.
  * `editorial`, `medium`, `probable`: applied when the change is form only.
    A change of letters in these classes waits for a decision.
  * everything else (`query`, `requires_original`, `uncertain`, `needs-review`,
    `low`): the reader asks for the printed page or an editor. Held, unless
    `decisions.json` says otherwise.

Arabic

  * `quran_ayahs.json` is never touched, and is the measure for the rest.
  * Arabic quoted in the books changes only where the owner approved that
    very finding (`arabic_approved.json`: the 45 shown and approved on 21
    November 2026, a Qur'an quotation in them as the mushaf writes it). A new
    slip is listed for approval (arabic-awaiting-approval.json) and left.
  * Any other change to Arabic is refused. A change counts as touching Arabic
    when it alters a word that
    belongs to a run of three or more words found in the mushaf
    (`quran_ayahs.json`), a fully vowelled Arabic word, or a vowelled or
    mushaf-matching word inside a block the page's layout marks as an Arabic
    quotation - and when it falls between two such words.

After the findings, the same build tidies every Urdu page the same way,
whether the reader has reached it or not: a space after ۔ ، ؟ ! where the next
word was run on, none before them, no doubled or trailing spaces, no spaces
inside brackets. Arabic quotations, tables and verse are left as printed.

The Urdu tafsir under an ayah (`quran_tafsir.json`) was cut from these same
pages, so every correction is carried to the passage it came from there, and
those passages are tidied alike.

Asrar-at-Tanzil prints its headings in the margin. Where one was read into the
middle of a sentence, the sentence is made whole and the heading is set just
above it (or just below it, where the sentence's opening cannot be found).

Two findings that want different things at the same place are not merged: the
surer one (then the longer one) is applied and the other is reported.

    python Tools/Content/urdu_proofread/apply_proofread.py            report only
    python Tools/Content/urdu_proofread/apply_proofread.py --write    write the iOS seed
"""

from __future__ import annotations

import difflib
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
IOS = HERE.parents[2]
SEED = IOS / "DarulIrfanApp" / "Resources" / "SeedData"
WORKSPACE = Path(os.environ.get("DI_WORKSPACE", r"C:\Users\wajid.ali\Desktop\Automation"))
REGISTER = Path(os.environ.get("DI_PROOFREAD_REGISTER", WORKSPACE / "outputs" / "darul-urdu-proofread-2026-11-20"))
OUT = Path(os.environ.get("DI_PROOFREAD_OUT", WORKSPACE / "outputs" / "darul-urdu-proofread-apply"))

# The commit whose book_pages.json the register is anchored to.
BASE = "3ae7029"
BASE_SHA256 = "43ef075d7223ed847fc8512734b9013a536b7ef28276827a0ec8135b8247bda6"

# The changes to Arabic the owner approved, each by its finding. The rule is
# the list: a new slip is never mended because an old one like it was approved.
APPROVED = {entry["id"]: entry for entry in json.loads((HERE / "arabic_approved.json").read_text(encoding="utf-8"))}
AWAITING: dict[str, dict] = {}
# Findings read as a change to Arabic that the rules cannot see (scan_arabic.py
# lists the candidates): they wait for the owner like the others.
READ_AS_ARABIC = json.loads((HERE / "arabic_held.json").read_text(encoding="utf-8"))


def await_owner(finding: dict, how: str, put: str) -> None:
    AWAITING.setdefault(finding["id"], {"id": finding["id"], "book": finding.get("bookID"), "page": finding.get("page"),
                                        "how": how, "was": finding["original"], "now": put})

# What every page's reviewState says in the seed that is written.
PAGE_STATE = "final"

SURE = {"high"}
FORM_ONLY_OK = {"editorial", "medium", "probable"}
CONFIRMED = {
    "original_confirmed_transcription_correction",
    "original_confirmed_transcription_correction_proposed",
    "original_confirms_missing_letter_proposed",
    "original_confirms_transcription_error_proposed",
    "original_confirmed_spacing_only",
}
RANK = {"decision": 0, "high": 1, "confirmed": 1, "arabic": 1, "editorial": 2, "medium": 3, "probable": 4}

HARAKAT = set("\u064b\u064c\u064d\u064e\u064f\u0650\u0651\u0652\u0656\u0657\u0670")
TOKEN = re.compile(r"\s+|[^\W_]+(?:[\u200c\u200d][^\W_]+)*|.", re.S)


def is_word_char(ch: str) -> bool:
    cat = unicodedata.category(ch)
    return cat[0] in "LMN" or ch in "\u200c\u200d"


def tokens(text: str) -> list[tuple[int, int, str]]:
    """(start, end, text) for every word, run of white space, and other character."""
    out, i, n = [], 0, len(text)
    while i < n:
        ch = text[i]
        j = i + 1
        if ch.isspace():
            while j < n and text[j].isspace():
                j += 1
        elif is_word_char(ch):
            while j < n and is_word_char(text[j]):
                j += 1
        out.append((i, j, text[i:j]))
        i = j
    return out


SKELETON = str.maketrans({
    "أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "\ufe8e": "ا",
    "ى": "ی", "ي": "ی", "ے": "ی", "ئ": "ی",
    "ك": "ک", "ڪ": "ک",
    "ة": "ه", "ۃ": "ه", "ہ": "ه", "ھ": "ه", "ۂ": "ه",
    "ؤ": "و",
})


def skeleton(word: str) -> str:
    """The consonant frame of an Arabic-script word: no marks, no alef, one
    form for each letter Urdu and Arabic type differently."""
    out = []
    for ch in unicodedata.normalize("NFC", word).translate(SKELETON):
        cat = unicodedata.category(ch)
        if cat != "Lo" or ch in "اء\u066e\u0674":
            continue
        out.append(ch)
    return "".join(out)


def form_key(text: str) -> str:
    """The letters alone: no spacing, punctuation, vowel marks or tatweel."""
    out = []
    for ch in unicodedata.normalize("NFD", text):
        cat = unicodedata.category(ch)
        if cat[0] in "MPZ" or cat in ("Cc", "Cf", "Sk") or ch == "\u0640" or ch.isspace():
            continue
        out.append(ch)
    return "".join(out)


def distance(a: str, b: str) -> int:
    if len(a) < len(b):
        a, b = b, a
    row = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        nxt = [i]
        for j, cb in enumerate(b, 1):
            nxt.append(min(row[j] + 1, nxt[j - 1] + 1, row[j - 1] + (ca != cb)))
        row = nxt
    return row[-1]


# Words the reader uses when the "proposal" is a note to an editor, not text.
NOTE_WORDS = ("اصل صفح", "بحال", "ناشر", "تصدیق", "ادارتی", "مطبوعہ", "درج کریں", "جانچ", "مجوزہ", "[", "]")
NEGATIONS = ("نہ", "نہیں", "نا", "مت", "بغیر", "غیر", "لا", "بے")
DIGITS = set("0123456789۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩")


def digits_of(text: str) -> str:
    return "".join(ch for ch in text if ch in DIGITS)


def negations_of(text: str) -> list[str]:
    return sorted(t for _, _, t in tokens(text) if t in NEGATIONS)


# Categories where the reader changes what is said (grammar, agreement, a
# missing or extra word, a name, an honorific) and not how a word is spelt.
WORDING = (
    "grammar", "agreement", "verb", "word_order", "wording", "word_choice", "honorific_agreement", "honorific",
    "missing_word", "missing_particle", "missing_postposition", "missing_link", "extra_word", "intrusive",
    "relative", "pronoun", "possessive", "oblique", "postposition", "case_", "name", "label", "title", "plural",
    "syntax", "duplicat", "repetition", "word_omission", "editorial", "copyedit", "source", "reading",
    "reference", "narrator",
    "نحو", "مطابقت", "تذکیر", "واحد", "فعل", "اضافت", "اصل", "لفظ", "ترکیب", "حرفِ",
)


SPELLING = {
    "honorific_spelling", "word_spelling", "title_spelling_consistency", "lفظی املا", "لفظی املا", "لفظی فاصلہ",
    "place_name_spelling", "verb_spelling", "greeting_spelling", "technical_term_spelling", "term_spelling",
    "bibliographic_spelling", "reference_spelling", "number_word_spelling", "compound_spelling",
}


class Mushaf:
    def __init__(self, path: Path):
        ayahs = json.loads(path.read_text(encoding="utf-8"))
        self.trigrams: set[tuple[str, str, str]] = set()
        self.bigrams: set[tuple[str, str]] = set()
        self.words: set[str] = set()
        by_surah: dict[int, list[str]] = defaultdict(list)
        for ayah in ayahs:
            for word in ayah["textArabic"].split():
                frame = skeleton(word)
                if frame:
                    by_surah[ayah["surahNumber"]].append(frame)
        for frames in by_surah.values():
            self.words.update(frames)
            self.bigrams.update(zip(frames, frames[1:]))
            self.trigrams.update(zip(frames, frames[1:], frames[2:]))

    def protected(self, text: str, layout: str | None) -> list[tuple[int, int, int]]:
        """(start, end, run) for every word of the page that is the Qur'an's
        Arabic or other vowelled Arabic. Words of one run share its number."""
        toks = tokens(text)
        words = [(s, e, t) for s, e, t in toks if is_word_char(t[0])]
        frames = [skeleton(t) for _, _, t in words]
        marks = [sum(ch in HARAKAT for ch in t) for _, _, t in words]
        hit = [False] * len(words)
        # A break between words (a blank line, a sentence mark) does not stop
        # the mushaf: ayat run on. Only the frames are compared.
        idx = [i for i, f in enumerate(frames) if f]
        for a, b, c in zip(idx, idx[1:], idx[2:]):
            if (frames[a], frames[b], frames[c]) in self.trigrams:
                hit[a] = hit[b] = hit[c] = True
        for a, b in zip(idx, idx[1:]):
            if marks[a] >= 2 and marks[b] >= 2 and (frames[a], frames[b]) in self.bigrams:
                hit[a] = hit[b] = True
        for i in idx:
            if marks[i] >= 3:
                hit[i] = True
        if layout:
            bounds = block_bounds(text)
            if len(bounds) == len(layout):
                arabic = [(s, e) for (s, e), kind in zip(bounds, layout) if kind == "a"]

                def in_arabic(i: int) -> bool:
                    s, e, _ = words[i]
                    return any(bs <= s and e <= be for bs, be in arabic)

                for i in idx:
                    if marks[i] >= 1 and in_arabic(i):
                        hit[i] = True
                for a, b in zip(idx, idx[1:]):
                    if in_arabic(a) and in_arabic(b) and (frames[a], frames[b]) in self.bigrams:
                        hit[a] = hit[b] = True
        out, run, last = [], 0, None
        for i, (s, e, _) in enumerate(words):
            if not hit[i]:
                continue
            if last is None or last != i - 1:
                run += 1
            out.append((s, e, run))
            last = i
        return out


def block_bounds(text: str) -> list[tuple[int, int]]:
    out, start = [], 0
    for match in re.finditer("\n\n", text):
        out.append((start, match.start()))
        start = match.end()
    out.append((start, len(text)))
    return out


def atomic_edits(original: str, suggested: str) -> list[tuple[int, int, str]]:
    """The smallest token-level changes that turn `original` into `suggested`,
    as (start, end, replacement) offsets into `original`."""
    a, b = tokens(original), tokens(suggested)
    matcher = difflib.SequenceMatcher(None, [t for _, _, t in a], [t for _, _, t in b], autojunk=False)
    edits = []
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        start = a[i1][0] if i1 < len(a) else len(original)
        end = a[i2 - 1][1] if i2 > i1 else start
        edits.append((start, end, "".join(t for _, _, t in b[j1:j2])))
    return edits


def occurrences(text: str, needle: str) -> list[int]:
    out, at = [], text.find(needle)
    while at != -1:
        out.append(at)
        at = text.find(needle, at + len(needle))
    return out


def stands_alone(text: str, at: int, needle: str) -> bool:
    """The match is not a piece of a longer word."""
    if is_word_char(needle[0]) and at > 0 and is_word_char(text[at - 1]):
        return False
    end = at + len(needle)
    if is_word_char(needle[-1]) and end < len(text) and is_word_char(text[end]):
        return False
    return True


def oblique_only(original: str, suggested: str) -> bool:
    """The only letters that change are a final ہ written ے before a postposition."""
    changed = False
    for start, end, replacement in atomic_edits(original, suggested):
        was = original[start:end]
        if form_key(was) == form_key(replacement):
            continue
        before = [form_key(t) for _, _, t in tokens(was) if is_word_char(t[0])]
        after = [form_key(t) for _, _, t in tokens(replacement) if is_word_char(t[0])]
        if len(before) != len(after):
            return False
        for a, b in zip(before, after):
            if a == b:
                continue
            if len(a) >= 3 and a.endswith("ہ") and b == a[:-1] + "ے":
                changed = True
            else:
                return False
    return changed


def read_json(path: Path, attempts: int = 6):
    """The register is being written while we read it: try again on a torn read."""
    for attempt in range(attempts):
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            if attempt == attempts - 1:
                raise
            time.sleep(2)


def base_file(name: str) -> Path:
    """The seed file as it stood at BASE, kept outside the repository."""
    cache = OUT / "base" / name
    if not cache.exists():
        cache.parent.mkdir(parents=True, exist_ok=True)
        data = subprocess.run(["git", "-C", str(IOS), "show", f"{BASE}:DarulIrfanApp/Resources/SeedData/{name}"],
                              check=True, capture_output=True).stdout
        cache.write_bytes(data)
    return cache


def classify(finding: dict, decisions: dict) -> tuple[str, str | None, str]:
    """(verdict, replacement, why). Verdict is `apply`, `hold` or `review`."""
    decision = decisions.get(finding["id"])
    suggested = finding.get("suggested")
    if finding["id"] in APPROVED:
        return "arabic", suggested, "approved by the owner"
    if finding["id"] in READ_AS_ARABIC and suggested:
        await_owner(finding, READ_AS_ARABIC[finding["id"]], suggested)
        return "hold", None, "Arabic quotation: waiting for the owner's approval"
    if (suggested and finding["confidence"] in SURE and oblique_only(finding["original"], suggested)
            and not (decision or {}).get("firm")):
        # "واقعہ سے" and "واقعے سے" are one spoken word written two ways; the
        # second is how it is read aloud. Treated alike wherever it occurs.
        return "apply", suggested, "high"
    if decision:
        action = decision["action"]
        if action == "hold":
            return "hold", None, "decision: " + decision.get("note", "held")
        if action == "apply-as":
            return "apply", decision["text"], "decision"
        if action == "apply":
            if suggested is None:
                return "hold", None, "decision says apply but the register proposes no words"
            return "apply", suggested, "decision"
    if suggested is None:
        return "hold", None, "no replacement proposed"
    original = finding["original"]
    if suggested == original:
        return "hold", None, "proposal is the same as the text"
    confidence = finding["confidence"]
    category = finding.get("category", "").lower()
    if any(word in suggested and word not in original for word in NOTE_WORDS):
        return "hold", None, "proposal reads as a note to an editor, not as replacement words"
    if "quran" in category or "arabic" in category or finding.get("localQuranReference"):
        return "arabic", suggested, "filed as a Qur'an or Arabic quotation"
    old_letters, new_letters = form_key(original), form_key(suggested)
    form_only = old_letters == new_letters
    confirmed = finding.get("resolutionStatus") in CONFIRMED
    if form_only:
        if confidence in SURE or confirmed or confidence in FORM_ONLY_OK:
            return "apply", suggested, "confirmed" if confirmed else confidence
        return "hold", None, f"{confidence}: the reader asks for the printed page or an editor"
    if confidence not in SURE and not confirmed and confidence not in FORM_ONLY_OK:
        return "hold", None, f"{confidence}: the reader asks for the printed page or an editor"
    if confidence in FORM_ONLY_OK and not confirmed:
        return "review", suggested, f"{confidence}: letters change"
    if digits_of(original) != digits_of(suggested):
        return "review", suggested, "high: a number changes"
    if negations_of(original) != negations_of(suggested):
        return "review", suggested, "high: a negation is added or dropped"
    if distance(old_letters, new_letters) > 2:
        return "review", suggested, "high: more than two letters change"
    if category not in SPELLING and any(word in category for word in WORDING):
        return "review", suggested, "high: wording, grammar or a name, not a slip of the pen"
    return "apply", suggested, "confirmed" if confirmed else "high"


# --------------------------------------------------------------------------
# Edits

Edit = tuple[int, int, str]


def apply_edits(text: str, edits: list[Edit]) -> str:
    """`edits` are (start, end, replacement) in `text`, sorted, not overlapping."""
    new, cursor, after_edit = [], 0, False
    for s, e, r in edits:
        piece = text[cursor:s]
        if piece:
            after_edit = False
        new.append(piece)
        if after_edit and s == e and r:
            # Two findings met at one place (one rewrote the word before, the
            # other adds after it): do not say the same thing twice.
            tail = "".join(new[-2:])
            if tail.endswith(r):
                r = ""
            elif tail.endswith(" ") and r.startswith(" "):
                r = r.lstrip(" ")
        new.append(r)
        cursor = e
        after_edit = True
    new.append(text[cursor:])
    return "".join(new)


def moved(edits: list[Edit], pos: int, closing: bool) -> int | None:
    """Where an old offset lies after `edits`; None inside a change. Words
    added exactly at `pos` fall before an opening offset and after a closing one."""
    shift = 0
    for s, e, r in edits:
        if s == e:
            if s < pos or (s == pos and not closing):
                shift += len(r)
        elif e <= pos:
            shift += len(r) - (e - s)
        elif s < pos:
            return None
    return pos + shift


def relayout(row: dict, old: str, new: str, edits: list[Edit]) -> None:
    """Keep one layout letter per blank-line-separated part when parts were joined or split."""
    if old.count("\n\n") == new.count("\n\n"):
        return
    layout = row.get("layout")
    if layout is not None:
        # Where each old part begins in the new text (None: its opening was rewritten).
        old_starts = [(moved(edits, s, False), layout[i] if i < len(layout) else "p")
                      for i, (s, _) in enumerate(block_bounds(old))]
        kinds = []
        for start, _ in block_bounds(new):
            # A part takes the kind of the old part it begins in.
            kind = None
            for at, letter in old_starts:
                if at is not None and at <= start:
                    kind = letter
            if kind is None:
                # A part put in above the page's first: a restored heading, or prose.
                part = new[start:].split("\n\n", 1)[0]
                kind = "h" if len(part) < 80 and "۔" not in part else "p"
            kinds.append(kind)
        row["layout"] = "".join(kinds)
    if "blocks" in row:
        row["blocks"] += new.count("\n\n") - old.count("\n\n")


def remap_entries(entries: list[dict], old: str, new: str, edits: list[Edit]) -> tuple[list[dict], int]:
    """A link's text must be on its page letter for letter. Where a correction
    changed the words a link is made of, the link follows the correction."""
    fresh, seen, changed = [], set(), 0
    for entry in entries:
        mark = entry["m"]
        places = occurrences(old, mark)
        touched = any((s < at + len(mark) and at < e) or (s == e and at < s < at + len(mark))
                      for at in places for s, e, _ in edits)
        marks = [mark]
        if touched or mark not in new:
            marks = []
            for at in places:
                a, b = moved(edits, at, False), moved(edits, at + len(mark), True)
                if a is None or b is None:
                    continue
                now = new[a:b]
                if now and "\n" not in now and now not in marks:
                    marks.append(now)
            if mark in new and mark not in marks:
                marks.append(mark)
            if marks != [mark]:
                changed += 1
        for text in marks:
            if (text, entry["t"]) not in seen:
                seen.add((text, entry["t"]))
                fresh.append({"m": text, "t": entry["t"]})
    return fresh, changed


# The signs and numbers a mushaf sets at the end of an ayah or over a word.
AYAH_SIGNS = re.compile("[۝۞؀-؅ۖ-ۭ﴾﴿0-9۰-۹٠-٩-①-⑳]")


def completes_ayah_words(mushaf: "Mushaf", text: str, start: int, end: int, put: str) -> bool:
    """The change makes three words of the mushaf where there were none: a
    quotation typed bare, whose slip hid it from the shield."""
    if skeleton_words(text[start:end]) == skeleton_words(put):
        return False
    left = text[max(0, start - 70):start]
    new = left + put + text[end:end + 70]
    words = [(s, e, skeleton(t)) for s, e, t in tokens(new) if is_word_char(t[0]) and skeleton(t)]
    changed = {i for i, (s, e, _) in enumerate(words) if s < len(left) + len(put) and len(left) < e}
    return any(changed & {i, i + 1, i + 2} and (words[i][2], words[i + 1][2], words[i + 2][2]) in mushaf.trigrams
               for i in range(len(words) - 2))


class Shield:
    """What must not be touched in one text."""

    def __init__(self, mushaf: Mushaf, text: str, layout: str | None, skip_kinds: str = ""):
        self.text = text
        self.words = mushaf.protected(text, layout)
        self.ends = {e for _, e, _ in self.words}
        self.begins = {s for s, _, _ in self.words}
        held = {(s, e) for s, e, _ in self.words}
        # Every word of the text, and whether it is one of the protected ones.
        self.all_words = [(s, e, (s, e) in held) for s, e, t in tokens(text) if is_word_char(t[0])]
        self.closed: list[tuple[int, int]] = []
        self.arabic: list[tuple[int, int]] = []
        if layout:
            bounds = block_bounds(text)
            if len(bounds) == len(layout):
                self.arabic = [bound for bound, kind in zip(bounds, layout) if kind == "a"]
        if layout and skip_kinds:
            bounds = block_bounds(text)
            if len(bounds) == len(layout):
                self.closed = [bound for bound, kind in zip(bounds, layout) if kind in skip_kinds]

    def refuses(self, start: int, end: int, replacement: str = "") -> str | None:
        text = self.text
        touched = text[start:end] + replacement
        if AYAH_SIGNS.search(touched) and not re.search(f"[{LETTER}]", touched):
            left, right = start, end
            while left > 0 and text[left - 1] in " \t":
                left -= 1
            while right < len(text) and text[right] in " \t":
                right += 1
            if left in self.ends or right in self.begins:
                return "belongs to a line of Arabic (an ayah's sign or number beside it)"
        for s, e, _ in self.words:
            if start < e and s < end:
                return "touches the Qur'an's or other vowelled Arabic"
        before = [run for s, e, run in self.words if e <= start and not text[e:start].strip()]
        after = [run for s, e, run in self.words if s >= end and not text[end:s].strip()]
        if before and after and before[-1] == after[0]:
            return "falls between two words of an Arabic quotation"
        # A sign, a number or a mark that closes a line of Arabic (the end of
        # an ayah) or stands between two Arabic words belongs to the Arabic.
        if start != end and (start in self.ends or end in self.begins) and AYAH_SIGNS.search(text[start:end]) \
                and not re.search(f"[{LETTER}]", text[start:end]):
            return "belongs to a line of Arabic (the ayah's sign or number written against a word)"
        if not re.search(f"[{LETTER}]", text[start:end]):
            left = next(((s, e, held) for s, e, held in reversed(self.all_words)
                         if e <= start and "\n" not in text[e:start]), None)
            right = next(((s, e, held) for s, e, held in self.all_words
                          if s >= end and "\n" not in text[end:s]), None)
            if left and left[2] and (right is None or right[2]):
                return "belongs to a line of Arabic (the mark or number that closes it)"
        return None

    def in_arabic_block(self, start: int, end: int) -> bool:
        return any(s <= start and end <= e for s, e in self.arabic)

    def is_closed(self, start: int, end: int) -> bool:
        return any(s <= start and end <= e for s, e in self.closed)


# --------------------------------------------------------------------------
# Tidying: spacing around marks, the same on every Urdu page

LETTER = "ء-غف-يٱ-ۓەۮۯۺ-ۼ"
MARK = "ً-ٰٟۖ-ۭؐ-ؚ"
LETTER_NAMES = "|".join(("اے", "بی", "سی", "ڈی", "ای", "ایف", "جی", "ایچ", "آئی", "جے", "کے", "ایل", "ایم", "این", "او",
                         "پی", "کیو", "آر", "ایس", "ٹی", "یو", "وی", "ڈبلیو", "ایکس", "وائی", "زیڈ"))
# "ایم۔اے", "ڈی۔جی۔خان", "ص۔ب": the ۔ of an abbreviation is not the end of a sentence.
ABBREVIATION = re.compile(
    rf"(?<![{LETTER}])(?:(?:{LETTER_NAMES})۔)+(?:{LETTER_NAMES})(?![{LETTER}{MARK}])"
    rf"|(?<![{LETTER}])(?:(?:{LETTER_NAMES})۔){{2,}}[{LETTER}]+"
    rf"|(?<![{LETTER}{MARK}])[{LETTER}]۔[{LETTER}](?![{LETTER}{MARK}])")

FIRST_PASS = [
    ("no space before a mark", re.compile(rf"(?<=[{LETTER}{MARK}])[ \t]+(?=([۔،؟])(?!\1))"), ""),
    ("doubled space", re.compile(r"(?<=[^\s|])  (?=[^\s|])"), " "),
    ("space at the end of a line", re.compile(r"(?<=[^\s|])[ \t]+(?=\n)"), ""),
    ("Latin comma", re.compile(rf"(?<=[{LETTER}{MARK}]),(?= ?[{LETTER}])"), "،"),
    ("space inside an opening bracket", re.compile(r"(?<=\()[ \t]+(?=\S)"), ""),
    ("space inside a closing bracket", re.compile(r"(?<=[^\s(])[ \t]+(?=\))"), ""),
]
SECOND_PASS = [
    ("space after ۔", re.compile(rf"(?<=۔)(?=[{LETTER}])"), " "),
    ("space after ،", re.compile(rf"(?<=،)(?=[{LETTER}])"), " "),
    ("space after ؟ or !", re.compile(rf"(?<=[؟!])(?=[{LETTER}])"), " "),
    ("space before an opening bracket", re.compile(rf"(?<=[{LETTER}{MARK}])(?=\([{LETTER}])"), " "),
    ("space after a closing bracket", re.compile(rf"(?<=[{LETTER}{MARK}]\))(?=[{LETTER}])"), " "),
]


def tidy_pass(rules, text: str, shield: Shield, counts: Counter) -> list[Edit]:
    spared = [m.span() for m in ABBREVIATION.finditer(text)] if rules is SECOND_PASS else []
    edits: dict[tuple[int, int], str] = {}
    for name, pattern, replacement in rules:
        for match in pattern.finditer(text):
            start, end = match.span()
            if (start, end) in edits or shield.is_closed(start, end) or shield.refuses(start, end):
                continue
            if name == "no space before a mark" and start in shield.ends:
                continue  # an ayah or other Arabic is followed by its mark as printed
            if any(s < start < e for s, e in spared):
                continue
            if any(s < end and start < e for s, e in edits):
                continue
            edits[(start, end)] = replacement
            counts[name] += 1
    return sorted((s, e, r) for (s, e), r in edits.items())


def tidy(text: str, layout: str | None, mushaf: Mushaf, counts: Counter) -> tuple[str, list[list[Edit]]]:
    """The text with its spacing tidied, and the edits of each pass in turn."""
    passes = []
    for rules in (FIRST_PASS, SECOND_PASS):
        edits = tidy_pass(rules, text, Shield(mushaf, text, layout, skip_kinds="atv"), counts)
        if edits:
            text = apply_edits(text, edits)
        passes.append(edits)
    return text, passes


# --------------------------------------------------------------------------
# Margin headings that were read into the middle of a sentence

# Asrar-at-Tanzil prints its headings in the margin, beside the prose. Read
# into a single column, a heading sometimes landed between two halves of a
# sentence ("... اور جب / دعا بھی تقدیر ہوتی ہے / موسیٰ علیہ السلام مصر پہنچے ...").
# The words before it then end on a word that cannot end a sentence, or the
# words after it begin with one that cannot begin one.
CANNOT_END = frozenset("کی کا کے کو سے میں پر پہ نے کہ اور یا جب اگر مگر لیکن بلکہ جو جس جن تک چونکہ کیونکہ تاکہ نیز یعنی پھر".split())
CANNOT_BEGIN = frozenset("کو کی کا کے سے میں پر نے تک".split())
SENTENCE_END = "۔؟!"
FARTHEST_MOVE = 400


def interrupts(before: str, heading: str, after: str) -> bool:
    """`heading` stands inside the sentence that runs from `before` into `after`."""
    before = before.rstrip()
    if not before or not after.strip() or len(heading) >= 120 or "\n" in heading.strip():
        return False
    if not re.match(f"[{LETTER}]", before[-1]) and not re.match(f"[{MARK}]", before[-1]):
        return False  # closed by a mark, a bracket or a quotation mark
    if not re.match(f"[{LETTER}]", after.lstrip()[:1] or " "):
        return False
    last = [form_key(t) for _, _, t in tokens(before[-40:]) if is_word_char(t[0])]
    first = [form_key(t) for _, _, t in tokens(after[:40]) if is_word_char(t[0])]
    return bool(last and last[-1] in CANNOT_END) or bool(first and first[0] in CANNOT_BEGIN)


def lifted(before: str, heading: str, after: str) -> list[str] | None:
    """The three parts with the sentence made whole and the heading moved up
    to where the sentence begins or, failing that, down to where it ends."""
    back = max(before.rfind(mark) for mark in SENTENCE_END)
    opening = before[back + 1:].lstrip() if back != -1 else before
    ends = [at for at in (after.find(mark) for mark in SENTENCE_END) if at != -1]
    forward = min(ends) + 1 if ends else None
    while forward is not None and forward < len(after) and after[forward] in SENTENCE_END + "”\"'’)":
        forward += 1
    up = len(opening) if (back != -1 or len(before) <= FARTHEST_MOVE) else None
    down = forward
    # A margin heading stands where its subject begins, so it goes above the
    # sentence it was read into when that sentence's opening can be found.
    if up is not None and up <= FARTHEST_MOVE:
        head = before[:back + 1].rstrip() if back != -1 else ""
        return ([head] if head else []) + [heading, f"{opening.rstrip()} {after.lstrip()}"]
    if down is not None and down <= FARTHEST_MOVE:
        rest = after[down:].lstrip()
        return [f"{before.rstrip()} {after[:down].lstrip()}", heading] + ([rest] if rest else [])
    return None


def lift_headings(text: str, layout: str | None, mushaf: Mushaf, known: set[str] | None = None) -> tuple[str, str | None, list[str]]:
    """The page (or, with `known` headings and no layout, a tafsir passage)
    with every interrupting heading moved out of its sentence."""
    parts = text.split("\n\n")
    kinds = list(layout) if layout is not None and len(layout) == len(parts) else None
    if kinds is None and known is None:
        return text, layout, []
    moved_headings, i = [], 0
    while i + 2 < len(parts):
        is_heading = kinds[i + 1] == "h" if kinds else parts[i + 1].strip() in known
        is_prose = (kinds[i] == "p" and kinds[i + 2] == "p") if kinds else True
        if is_heading and is_prose and interrupts(parts[i], parts[i + 1], parts[i + 2]) \
                and not mushaf.protected(parts[i + 1], None):
            new = lifted(parts[i], parts[i + 1], parts[i + 2])
            if new is not None:
                moved_headings.append(parts[i + 1].strip())
                if kinds:
                    at = new.index(parts[i + 1])
                    kinds[i:i + 3] = ["p"] * at + ["h"] + ["p"] * (len(new) - at - 1)
                parts[i:i + 3] = new
                continue
        i += 1
    return "\n\n".join(parts), ("".join(kinds) if kinds else layout), moved_headings


# --------------------------------------------------------------------------
# Slips inside Arabic quotations (owner, 21 November 2026: "correction for
# typos approved", "use mushaf as our app")

# A quotation from the Qur'an that has a slip in it is not patched letter by
# letter: its words are written as the app's own mushaf writes them
# (`quran_ayahs.json`, which is never changed). A slip in other Arabic - a
# hadith, a du'a, the kalima in a line of Urdu - takes the reader's small fix.

NOT_TEXT = {0x200B, 0x200C, 0x200F, 0xFEFF, 0x2002, 0x2003}
ARABIC_PARTICLES = frozenset("فی من ما لا ان الی علی یا ثم قد لم لن عن اذ اذا".split())
PAUSE_MARKS = set("ؕۖۗۘۙۚۛۜ")


def mushaf_word(word: str) -> str:
    """A word of the mushaf without the signs that belong to its page, not to the word."""
    return "".join(ch for ch in word if ord(ch) not in NOT_TEXT and not 0xE000 <= ord(ch) <= 0xF8FF)


class Quotations:
    """Finds which words of the mushaf a quotation is made of."""

    def __init__(self, path: Path):
        self.ayahs = json.loads(path.read_text(encoding="utf-8"))
        self.words: list[list[str]] = []
        self.frames: list[list[str]] = []
        self.trigrams: dict[tuple, set[int]] = defaultdict(set)
        self.bigrams: dict[tuple, set[int]] = defaultdict(set)
        self.single: dict[str, set[int]] = defaultdict(set)
        for n, ayah in enumerate(self.ayahs):
            words = [w for w in (mushaf_word(w) for w in ayah["textArabic"].split()) if skeleton(w)]
            frames = [skeleton(w) for w in words]
            self.words.append(words)
            self.frames.append(frames)
            for tri in zip(frames, frames[1:], frames[2:]):
                self.trigrams[tri].add(n)
            for bi in zip(frames, frames[1:]):
                self.bigrams[bi].add(n)
            for frame in frames:
                self.single[frame].add(n)
        # Each ayah's letters in one string, and where its words begin and end in it.
        self.joined = ["".join(frames) for frames in self.frames]
        self.starts, self.ends = [], []
        for frames in self.frames:
            starts, ends, at = {}, {}, 0
            for i, frame in enumerate(frames):
                starts[at] = i
                at += len(frame)
                ends[at] = i + 1
            self.starts.append(starts)
            self.ends.append(ends)

    @staticmethod
    def _frames(text: str) -> list[str]:
        return [f for f in (skeleton(t) for _, _, t in tokens(text) if is_word_char(t[0])) if f]

    def _ayah(self, text: str) -> int | None:
        frames = self._frames(text)
        votes: dict[int, int] = defaultdict(int)
        for tri in zip(frames, frames[1:], frames[2:]):
            for n in self.trigrams.get(tri, ()):
                votes[n] += 3
        for bi in zip(frames, frames[1:]):
            for n in self.bigrams.get(bi, ()):
                votes[n] += 1
        if not votes:
            return None
        best = max(votes, key=lambda n: (votes[n], -n))
        return best if votes[best] >= 3 else None

    @staticmethod
    def quoted(correct: str) -> str:
        """The Arabic in the reader's correction: what stands between
        quotation signs when there are any; otherwise the correction without
        the unvowelled Urdu words at either end of a vowelled quotation."""
        for opening, closing in (("«", "»"), ("﴿", "﴾")):
            if opening in correct and closing in correct[correct.index(opening):]:
                inner = correct[correct.index(opening) + 1:correct.index(closing, correct.index(opening))]
                if skeleton_words(inner):
                    return inner
        words = [(s, e, sum(ch in HARAKAT for ch in t)) for s, e, t in tokens(correct) if is_word_char(t[0]) and skeleton(t)]
        if not words or sum(1 for _, _, marks in words if marks >= 2) * 2 < len(words):
            return correct
        first, last = 0, len(words) - 1
        while first < last and words[first][2] == 0:
            first += 1
        while last > first and words[last][2] == 0:
            last -= 1
        return correct[words[first][0]:words[last][1]]

    def run(self, correct: str, around: str) -> tuple[int, int, int] | None:
        """(ayah, first word, one past the last) of the mushaf words that
        `correct` - the quotation with its slip mended - is made of: a run of
        whole words of one ayah whose letters are exactly these. `around` is
        the page near it, which settles a quotation found in several ayat."""
        correct = self.quoted(correct)
        wanted = "".join(self._frames(correct))
        if len(wanted) < 3:
            return None
        places = []
        for n, frames in enumerate(self.frames):
            joined = self.joined[n]
            at = joined.find(wanted)
            while at != -1:
                first = self.starts[n].get(at)
                if first is None and at and joined[at - 1] in "وفبلک":
                    # The book quotes from just after a one-letter particle the mushaf writes joined on ("وَلَمْ").
                    first = self.starts[n].get(at - 1)
                last = self.ends[n].get(at + len(wanted))
                if first is not None and last is not None:
                    places.append((n, first, last))
                at = joined.find(wanted, at + 1)
        if not places:
            return None

        def written(place) -> str:
            n, i, j = place
            return " ".join(self.words[n][i:j]).rstrip("".join(PAUSE_MARKS))

        near = self._ayah(around)
        here = [place for place in places if place[0] == near]
        if here:
            return here[0]
        # Written differently from ayah to ayah: the one written most like the correction is the one meant.
        like = correct.translate(SKELETON)
        return max(places, key=lambda place: (difflib.SequenceMatcher(None, written(place).translate(SKELETON), like, autojunk=False).ratio(), -place[0]))

    def conformed(self, original: str, correct: str, around: str) -> tuple[str | None, str]:
        """`original` with its quotation as the mushaf writes it, and where
        the quotation is from; (None, why) when that cannot be done safely."""
        found = self.run(correct, around)
        if found is None:
            return None, "the quotation was not found in the mushaf"
        n, first, last = found
        target = "".join(self.frames[n][first:last])
        words = [(s, e, t) for s, e, t in tokens(original) if is_word_char(t[0]) and skeleton(t)]
        best, span = 0.0, None
        for i in range(len(words)):
            joined = ""
            for j in range(i, len(words)):
                joined += skeleton(words[j][2])
                if len(joined) > len(target) * 1.4 + 3:
                    break
                ratio = difflib.SequenceMatcher(None, joined, target, autojunk=False).ratio()
                if ratio > best:
                    best, span = ratio, (i, j)
        if span is None or best < 0.75:
            return None, "the quotation and the ayah are too unlike"
        i, j = span
        # A little word of Arabic left standing beside the quotation, which the
        # reader's correction did not keep, means the quotation was not taken whole.
        kept = set(self._frames(correct))
        for beside in (words[i - 1][2] if i else "", words[j + 1][2] if j + 1 < len(words) else ""):
            if form_key(beside) in ARABIC_PARTICLES and skeleton(beside) not in kept:
                return None, "a word of the quotation would be left outside it"
        quoted = original[words[i][0]:words[j][1]]
        vowelled = sum(ch in HARAKAT for ch in quoted) >= j - i + 1
        if vowelled and [skeleton(t) for _, _, t in words[i:j + 1]] == self.frames[n][first:last]:
            return None, "the quotation already has the mushaf's letters and spacing"
        if j == i and not vowelled:
            return None, "one bare word (a name or a reference, not a quotation)"
        if j - i == 1 and not vowelled and "".join(skeleton(t) for _, _, t in words[i:j + 1]) != target:
            return None, "two bare words whose letters are not the mushaf's (a term in the author's own words)"
        # What is mended is a slip: letters wrong or missing, words run together
        # or split. A whole word of the mushaf that the book does not have, or
        # a word of the book that the mushaf does not, is the book's own
        # wording and is left for the owner.
        mine = [skeleton(t) for _, _, t in words[i:j + 1]]
        theirs = self.frames[n][first:last]
        book, mushaf_letters = "".join(mine), "".join(theirs)
        if distance(book, mushaf_letters) > max(2, len(mushaf_letters) // 12):
            return None, "the book's words differ from the mushaf's by more than a slip"
        matched_book, matched_mushaf = set(), set()
        for block in difflib.SequenceMatcher(None, book, mushaf_letters, autojunk=False).get_matching_blocks():
            matched_book.update(range(block.a, block.a + block.size))
            matched_mushaf.update(range(block.b, block.b + block.size))
        for letters, frames, matched in ((book, mine, matched_book), (mushaf_letters, theirs, matched_mushaf)):
            at = 0
            for frame in frames:
                if len(frame) >= 2 and not any(k in matched for k in range(at, at + len(frame))):
                    return None, "a whole word differs between the book and the mushaf"
                at += len(frame)
        fresh = self.words[n][first:last]
        fresh[-1] = fresh[-1].rstrip("".join(PAUSE_MARKS))
        ayah = self.ayahs[n]
        return original[:words[i][0]] + " ".join(fresh) + original[words[j][1]:], f"{ayah['surahNumber']}:{ayah['ayahNumber']}"


def skeleton_words(text: str) -> str:
    return "".join(skeleton(t) for _, _, t in tokens(text) if is_word_char(t[0]))


def arabic_fix(finding: dict, text: str, at: int, quotations: Quotations, decided: bool = False) -> tuple[str | None, str]:
    """What to put where a finding would change Arabic: only what the owner
    approved for that very finding. Anything else that looks like a slip is
    put on the list for approval (arabic-awaiting-approval.json) and left."""
    fid = finding.get("id")
    approved = APPROVED.get(fid)
    if approved is not None and approved["was"] == finding["original"]:
        return approved["now"], approved["how"]
    put, how = arabic_proposal(finding, text, at, quotations, decided)
    if put is None:
        return None, how
    if fid:
        AWAITING[fid] = {"id": fid, "book": finding.get("bookID"), "page": finding.get("page"), "how": how,
                         "was": finding["original"], "now": put}
    return None, "waiting for the owner's approval"


def arabic_proposal(finding: dict, text: str, at: int, quotations: Quotations, decided: bool = False) -> tuple[str | None, str]:
    """What could be put for a finding the shield refused or the reader filed as
    Arabic: (replacement, how), or (None, why it stays as it is)."""
    original, proposed = finding["original"], finding.get("suggested")
    if not proposed or any(word in proposed and word not in original for word in NOTE_WORDS):
        return None, "no replacement words"
    category = finding.get("category", "").lower()
    marks = sum(ch in HARAKAT for ch in original)
    filed = "quran" in category or "arabic" in category or bool(finding.get("localQuranReference"))
    around = text[max(0, at - 160):at] + proposed + text[at + len(original):at + len(original) + 160]
    if filed or marks >= 3:
        fresh, where = quotations.conformed(original, proposed, around)
        if fresh is not None and fresh != original:
            return fresh, f"mushaf {where}"
        if "already" in where:
            return None, "the words are the mushaf's already; only signs around them would change"
        if filed and not (finding["confidence"] in SURE and form_key(original) == form_key(proposed)):
            return None, where
    arabic = filed or marks >= 3
    if not arabic and decided:
        return proposed, "the reader's fix"
    # In Arabic the reader's own fix is taken only where no letter and no
    # number changes: words parted or joined, a vowel or a mark put right.
    same_letters = skeleton_words(original) == skeleton_words(proposed) and digits_of(original) == digits_of(proposed)
    old_letters, new_letters = form_key(original), form_key(proposed)
    small = old_letters == new_letters or distance(old_letters, new_letters) <= 2
    if finding["confidence"] in SURE and (same_letters if arabic else small):
        return proposed, "the reader's fix"
    return None, "not a plain slip"


# --------------------------------------------------------------------------
# The build

# Which pages each Urdu tafsir under an ayah was cut from: (prefix, suffix, edition).
TAFSIR = (("asrar-", "-ur", "asrar-at-tanzil-ur"), ("tafaseer-parah-", "", "akram-ut-tafaseer-ur"))


def seed_layout(raw: bytes):
    sys.path.insert(0, str(HERE.parent))
    from seed_io import CANDIDATES
    text = raw.decode("utf-8")
    data = json.loads(text)
    for layout in CANDIDATES:
        if layout.render(data) == text:
            return data, layout
    raise SystemExit("a seed file is not written in any known JSON layout; refusing to rewrite it")


def protected_survive(mushaf: Mushaf, where: str, old: str, old_layout: str | None, new: str,
                      mended: tuple = ()) -> None:
    """The Qur'an's Arabic must come through untouched: every protected word
    of the old text must still be in the new one, in order. `mended` are the
    places where an approved slip in a quotation was put right."""
    at = 0
    for s, e, _ in mushaf.protected(old, old_layout):
        if any(ms <= e and s <= me for ms, me, _ in mended):
            continue
        found = new.find(old[s:e], at)
        if found == -1:
            raise SystemExit(f"{where}: a protected Arabic word was lost ({old[s:e]}); nothing written")
        at = found + e - s


def build(write: bool) -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    OUT.mkdir(parents=True, exist_ok=True)
    raw = base_file("book_pages.json").read_bytes()
    if hashlib.sha256(raw).hexdigest() != BASE_SHA256:
        raise SystemExit("the BASE book_pages.json is not the file the register is anchored to")
    pages, pages_layout = seed_layout(raw)
    base_text = {(row["bookID"], row["page"]): (row["text"], row.get("layout")) for row in pages}
    index = {(row["bookID"], row["page"]): row for row in pages}
    findings = read_json(REGISTER / "findings.json")
    urdu_books = {book["id"] for book in read_json(REGISTER / "inventory.json")["books"]}
    decisions = json.loads((HERE / "decisions.json").read_text(encoding="utf-8")) if (HERE / "decisions.json").exists() else {}
    mushaf = Mushaf(base_file("quran_ayahs.json"))
    quotations = Quotations(base_file("quran_ayahs.json"))
    links, links_layout = seed_layout(base_file("book_links.json").read_bytes())

    ledger: dict[str, dict] = {}
    wanted: dict[tuple[str, int], list[dict]] = defaultdict(list)
    for finding in findings:
        fid = finding["id"]
        row = index.get((finding["bookID"], finding["page"]))
        if row is None:
            ledger[fid] = {"status": "error", "why": "no such page"}
            continue
        text = row["text"]
        if hashlib.sha256(text.encode("utf-8")).hexdigest() != finding["sourceTextSha256"]:
            ledger[fid] = {"status": "error", "why": "page text is not the text the finding was read from"}
            continue
        verdict, replacement, why = classify(finding, decisions)
        if verdict not in ("apply", "arabic"):
            ledger[fid] = {"status": verdict, "why": why}
            continue
        original = finding["original"]
        first = finding["offsetUtf16"]
        if text[first:first + len(original)] != original:
            ledger[fid] = {"status": "error", "why": "the words are not at the offset given"}
            continue
        mends = verdict == "arabic"
        if mends:
            replacement, how = arabic_fix(finding, text, first, quotations)
            if replacement is None:
                ledger[fid] = {"status": "hold", "why": f"Arabic quotation: {how}"}
                continue
            why = "arabic"
        places = occurrences(text, original)
        if len(places) > 1:
            alone = [at for at in places if stands_alone(text, at, original)]
            decision = decisions.get(fid) or {}
            if "occurrences" in decision:
                places = [places[i] for i in decision["occurrences"] if i < len(places)]
            elif alone:
                places = alone
            else:
                places = [first]
        wanted[(finding["bookID"], finding["page"])].append({
            "id": fid, "places": places, "original": original, "replacement": replacement,
            "rank": RANK.get(why, 5), "why": why,
            "inWord": len(places) == 1 and not stands_alone(text, places[0], original),
            "finding": finding, "mends": mends, "how": how if mends else "",
        })

    shown: list[dict] = []
    finding_edits: dict[tuple[str, int], list[Edit]] = {}
    mended: dict[tuple[str, int], set[Edit]] = defaultdict(set)
    arabic_log: list[dict] = []
    links_changed = 0
    for key, items in wanted.items():
        row = index[key]
        text = row["text"]
        shield = Shield(mushaf, text, row.get("layout"))
        accepted: list[tuple[int, int, str, str]] = []

        def clash(start: int, end: int, replacement: str) -> str | None:
            for s, e, r, other in accepted:
                if (s, e, r) == (start, end, replacement):
                    continue
                if start == end and s == e:
                    if start == s:
                        return other
                elif start < e and s < end:
                    return other
            return None

        for item in sorted(items, key=lambda it: (it["rank"], -len(it["original"]), it["id"])):
            atoms = atomic_edits(item["original"], item["replacement"])
            done, notes = 0, []
            for at in item["places"]:
                placed = [(at + s, at + e, r) for s, e, r in atoms]
                mends, how, put = item["mends"], item["how"], item["replacement"]
                why_not = None if mends else next((w for w in (shield.refuses(s, e, r) for s, e, r in placed) if w), None)
                if not mends:
                    unseen = None
                    if any(shield.in_arabic_block(s, e) for s, e, _ in placed):
                        unseen = "inside a block of Arabic"
                    elif any(completes_ayah_words(mushaf, text, s, e, r) for s, e, r in placed):
                        unseen = "words of the Qur'an, typed bare"
                    if unseen:
                        await_owner(item["finding"], unseen, put)
                        notes.append(f"Arabic: {unseen} (waiting for the owner's approval)")
                        continue
                if why_not:
                    # Arabic stands in the way. A slip in it may be put right
                    # (the Qur'an's as the mushaf has it); anything else is refused.
                    put, how = arabic_fix(item["finding"], text, at, quotations, decided=item["why"] == "decision")
                    if put is None:
                        notes.append(f"{why_not} ({how})")
                        continue
                    placed = [(at + s, at + e, r) for s, e, r in atomic_edits(item["original"], put)]
                    mends = True
                other = next((o for o in (clash(*edit) for edit in placed) if o), None)
                if other:
                    notes.append(f"gives way to {other}")
                    continue
                for edit in placed:
                    if not any((s, e, r) == edit for s, e, r, _ in accepted):
                        accepted.append((*edit, item["id"]))
                if mends:
                    mended[key].update(placed)
                    arabic_log.append({"id": item["id"], "book": key[0], "page": key[1], "how": how,
                                       "was": item["original"], "now": put})
                done += 1
            if done:
                ledger[item["id"]] = {"status": "applied", "why": item["why"], "places": done,
                                      **({"skipped": notes} if notes else {}),
                                      **({"inWord": True} if item["inWord"] else {})}
            else:
                status = "protected" if any("Arabic" in n for n in notes) else "superseded"
                ledger[item["id"]] = {"status": status, "why": "; ".join(sorted(set(notes)))}
        if not accepted:
            continue
        ordered = sorted({(s, e, r) for s, e, r, _ in accepted}, key=lambda edit: (edit[0], edit[1]))
        corrected = apply_edits(text, ordered)

        spans: dict[str, list[int]] = {}
        for s_, e_, _, fid_ in accepted:
            span = spans.setdefault(fid_, [s_, e_])
            span[0], span[1] = min(span[0], s_), max(span[1], e_)
        for fid_, (lo, hi) in spans.items():
            a_, b_ = max(0, lo - 45), min(len(text), hi + 45)
            while a_ > 0 and moved(ordered, a_, False) is None:
                a_ -= 1
            while b_ < len(text) and moved(ordered, b_, True) is None:
                b_ += 1
            shown.append({"id": fid_, "book": key[0], "page": key[1], "was": text[a_:b_],
                          "now": corrected[moved(ordered, a_, True):moved(ordered, b_, b_ > hi)]})
        if corrected == text:
            continue
        relayout(row, text, corrected, ordered)
        row["text"] = corrected
        finding_edits[key] = ordered
        entries = links["books"].get(key[0], {}).get(str(key[1]))
        if entries:
            links["books"][key[0]][str(key[1])], n = remap_entries(entries, text, corrected, ordered)
            links_changed += n

    # Every Urdu page is tidied the same way.
    tidied: Counter = Counter()
    pages_tidied = 0
    for row in pages:
        if row["bookID"] not in urdu_books or not row["text"]:
            continue
        key = (row["bookID"], row["page"])
        text = row["text"]
        new, passes = tidy(text, row.get("layout"), mushaf, tidied)
        if new == text:
            continue
        entries = links["books"].get(key[0], {}).get(str(key[1]))
        stage = text
        for edits in passes:
            if not edits:
                continue
            after = apply_edits(stage, edits)
            if entries:
                entries, n = remap_entries(entries, stage, after, edits)
                links_changed += n
            stage = after
        if entries:
            links["books"][key[0]][str(key[1])] = entries
        row["text"] = new
        pages_tidied += 1

    # Asrar-at-Tanzil's margin headings come out of the sentences they were read into.
    headings_moved: dict[str, set[str]] = defaultdict(set)
    for row in pages:
        if not (row["bookID"].startswith("asrar-") and row["bookID"].endswith("-ur")) or row.get("layout") is None:
            continue
        text, layout, moved_here = lift_headings(row["text"], row["layout"], mushaf)
        if moved_here:
            if "blocks" in row:
                row["blocks"] += text.count("\n\n") - row["text"].count("\n\n")
            row["text"], row["layout"] = text, layout
            headings_moved[row["bookID"]].update(moved_here)

    # No page says how its text was made (the owner, 21 November 2026). The two
    # keys stay because the phones' importers require them; the values are plain.
    for row in pages:
        row["reviewState"] = PAGE_STATE
        row["validator"] = ""

    changed_pages = 0
    for row in pages:
        key = (row["bookID"], row["page"])
        old, old_layout = base_text[key]
        if row["text"] != old:
            changed_pages += 1
            protected_survive(mushaf, f"{key}", old, old_layout, row["text"], tuple(mended.get(key, ())))
            if row.get("layout") is not None and len(row["layout"]) != row["text"].count("\n\n") + 1:
                raise SystemExit(f"{key}: the layout no longer has one letter per part; nothing written")
    lost = [(book, page, entry["m"]) for book, by_page in links["books"].items() for page, entries in by_page.items()
            for entry in entries if (book, int(page)) in index and entry["m"] not in index[(book, int(page))]["text"]]

    tafsir_rows, tafsir_layout, tafsir_summary = carry_to_tafsir(base_text, finding_edits, mushaf, headings_moved, mended)

    status = Counter(entry["status"] for entry in ledger.values())
    reviewed = read_json(REGISTER / "progress.json")
    summary = {
        "registerUpdatedAt": reviewed.get("updatedAt"),
        "registerPagesInspected": reviewed.get("pageEntriesInspected"),
        "registerPagesTotal": reviewed.get("totalUrduPages"),
        "findings": len(findings),
        "status": dict(status),
        "pagesCorrectedFromFindings": len(finding_edits),
        "editsFromFindings": sum(len(edits) for edits in finding_edits.values()),
        "pagesTidied": pages_tidied,
        "headingsMovedOutOfSentences": sum(len(v) for v in headings_moved.values()),
        "tidied": dict(tidied),
        "pagesChanged": changed_pages,
        "bookLinksRemapped": links_changed,
        "bookLinksNotOnTheirPage": len(lost),
        "arabicSlipsMended": len(arabic_log),
        "arabicFindingsMended": len({entry["id"] for entry in arabic_log}),
        "arabicAwaitingApproval": len(AWAITING),
        "tafsir": tafsir_summary,
        "written": write,
    }
    (OUT / "ledger.json").write_text(json.dumps(ledger, ensure_ascii=False, indent=1), encoding="utf-8")
    (OUT / "applied-edits.json").write_text(json.dumps(shown, ensure_ascii=False, indent=1), encoding="utf-8")
    (OUT / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    review = [dict(finding, ledger=ledger[finding["id"]]) for finding in findings
              if ledger[finding["id"]]["status"] != "applied"]
    (OUT / "not-applied.json").write_text(json.dumps(review, ensure_ascii=False, indent=1), encoding="utf-8")
    (OUT / "arabic-awaiting-approval.json").write_text(
        json.dumps(sorted(AWAITING.values(), key=lambda entry: entry["id"]), ensure_ascii=False, indent=1), encoding="utf-8")
    (OUT / "links-lost.json").write_text(json.dumps(lost, ensure_ascii=False, indent=1), encoding="utf-8")
    # Kept in the repository: verify_arabic.py allows exactly these words to have changed.
    (HERE / "arabic_typos.json").write_text(json.dumps(sorted(arabic_log, key=lambda entry: entry["id"]), ensure_ascii=False, indent=1) + "\n",
                                            encoding="utf-8", newline="\n")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if write:
        (SEED / "book_pages.json").write_text(pages_layout.render(pages), encoding="utf-8", newline="")
        (SEED / "book_links.json").write_text(links_layout.render(links), encoding="utf-8", newline="")
        (SEED / "quran_tafsir.json").write_text(tafsir_layout.render(tafsir_rows), encoding="utf-8", newline="")
        print(f"wrote book_pages.json, book_links.json and quran_tafsir.json in {SEED}")
    return 0


def carry_to_tafsir(base_text: dict, finding_edits: dict, mushaf: Mushaf, headings_moved: dict, mended: dict):
    """The Urdu tafsir under an ayah holds the same passages as the pages.
    Each correction is found there by the words around it and made there too."""
    rows, layout = seed_layout(base_file("quran_tafsir.json").read_bytes())
    by_edition: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        by_edition[row["editionID"]].append(row)
    row_edits: dict[int, set[Edit]] = defaultdict(set)
    row_mended: dict[int, set[Edit]] = defaultdict(set)
    carried = missing = unsure = 0
    holding: dict[str, dict[str, set[int]]] = {edition: defaultdict(set) for _, _, edition in TAFSIR}
    for edition, index in holding.items():
        for n, row in enumerate(by_edition[edition]):
            for word in set(row["text"].split()):
                index[word].add(n)
    for (book, page), edits in sorted(finding_edits.items()):
        target = next(((edition, book[len(prefix):len(book) - len(suffix)] if suffix else None)
                       for prefix, suffix, edition in TAFSIR
                       if book.startswith(prefix) and book.endswith(suffix)), None)
        if target is None:
            continue
        edition, surah = target
        pool = [row for row in by_edition[edition] if surah is None or str(row["surahNumber"]) == surah]
        text = base_text[(book, page)][0]
        clusters: list[list[Edit]] = []
        for edit in edits:
            if clusters and edit[0] - clusters[-1][-1][1] < 24:
                clusters[-1].append(edit)
            else:
                clusters.append([edit])
        for cluster in clusters:
            lo, hi = cluster[0][0], cluster[-1][1]
            placed = False
            for reach in (32, 16, 8):
                a, b = max(0, lo - reach), min(len(text), hi + reach)
                window = text[a:b]
                # A word wholly inside the window is a whole word of any passage holding the window.
                inner = window.split()[1:-1]
                if inner:
                    sets = sorted((holding[edition].get(word, set()) for word in set(inner)), key=len)[:6]
                    candidates = [by_edition[edition][n] for n in sorted(set.intersection(*(set(x) for x in sets)))]
                    if surah is not None:
                        candidates = [row for row in candidates if str(row["surahNumber"]) == surah]
                else:
                    candidates = pool
                hits = [(row, at) for row in candidates for at in occurrences(row["text"], window)]
                if not hits:
                    continue
                if len(hits) > 1 and reach < 32:
                    unsure += 1
                else:
                    for row, at in hits:
                        for s, e, r in cluster:
                            row_edits[id(row)].add((at + s - a, at + e - a, r))
                            if (s, e, r) in mended.get((book, page), ()):
                                row_mended[id(row)].add((at + s - a, at + e - a, r))
                    carried += 1
                placed = True
                break
            if not placed:
                missing += 1
    tidied: Counter = Counter()
    changed = headings = 0
    editions = {edition for _, _, edition in TAFSIR}
    for row in rows:
        if row["editionID"] not in editions:
            continue
        old = row["text"]
        new = old
        kept: list[Edit] = []
        for edit in sorted(row_edits.get(id(row), ()), key=lambda edit: (edit[0], edit[1])):
            if kept and (edit[0] < kept[-1][1] or (edit[0] == edit[1] == kept[-1][0] == kept[-1][1])):
                continue
            kept.append(edit)
        if kept:
            shield = Shield(mushaf, old, None)
            kept = [edit for edit in kept if edit in row_mended[id(row)] or not shield.refuses(edit[0], edit[1])]
            new = apply_edits(old, kept)
        new, _ = tidy(new, None, mushaf, tidied)
        known = headings_moved.get(f"asrar-{row['surahNumber']}-ur") if row["editionID"] == "asrar-at-tanzil-ur" else None
        if known:
            new, _, moved_here = lift_headings(new, None, mushaf, known)
            headings += len(moved_here)
        if new != old:
            protected_survive(mushaf, f"tafsir {row['editionID']} {row['surahNumber']}:{row['ayahStart']}", old, None, new,
                              tuple(row_mended[id(row)]))
            row["text"] = new
            changed += 1
    return rows, layout, {"correctionsCarried": carried, "notInAnAyahPassage": missing, "ambiguousLeft": unsure,
                          "rowsChanged": changed, "headingsMovedOutOfSentences": headings, "tidied": dict(tidied)}


if __name__ == "__main__":
    raise SystemExit(build("--write" in sys.argv))
