"""Build per-ayah Akram-ut-Tafaseer (Urdu) rows from the parah page text.

`ingest_tafsir_pages.py` shipped Akram-ut-Tafaseer as 30 page-structured parah
volumes and deliberately did not key it per ayah, because the OCR pipeline's own
`verse_refs` were wrong. That left the Quran reader with no Urdu commentary at
all. This tool keys it from a different, much stronger signal: the book's own
printed section headings,

    سورۃ البقرہ رکوع 18 آیات 148 تا 152

which open every section and are typeset large enough to survive OCR. Nothing is
inferred from the OCR'd Arabic or from a pipeline guess.

A heading is believed only when it is consistent with everything around it:

  * its surah resolves by name, and lies inside the parah's juz span;
  * its range lies inside the surah and inside the juz;
  * it moves forward from the previous accepted heading in the same volume.

A section's text runs from its heading to the next accepted heading. Its range
is then taken from the *next* heading, not from its own label, so a heading the
OCR missed widens the range instead of attributing its text to the wrong ayat:
`2:21-25` followed directly by `2:30-34` yields `2:21-29`. A section is dropped,
not guessed, when the boundary after it cannot be confirmed (a jump to a surah
that does not start at ayah 1, or a skipped surah).

Inside a section, the commentary quotes each ayah before explaining it. Where a
quotation matches one ayah of the section's range in the bundled mushaf - by
letter trigrams, with a clear margin over every other ayah - the section is
split there, so commentary sits under the ayah it explains. The same match
replaces a whole-ayah quotation with the mushaf's text and corrects its ﴿n﴾
marker; a fragment is never rewritten.

Also emits `tafsir_volumes.json`: for every surah, where its Urdu commentary
begins in each volume, so the reader can open the full printed text at the
right page for ayat the sections do not cover.

Writes the four platform seeds; reads only seed files.
"""

from __future__ import annotations

import argparse
import bisect
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1].parent
SEED_DIRS = [
    ROOT / "DarulIrfanApp" / "Resources" / "SeedData",
    ROOT.parent / "DarulIrfanAndroid" / "app" / "src" / "main" / "assets" / "seed",
    ROOT.parent / "DarulIrfanHarmony" / "entry" / "src" / "main" / "resources" / "rawfile" / "seed",
    ROOT.parent / "DarulIrfanWeb" / "content",
]
EDITION = "akram-ut-tafaseer-ur"
SOURCE_URL = "https://www.naqshbandiaowaisiah.org/akram-ut-tafaseer"
# The reader crashed on a 662 KB block in v1.6.9. Rows stay well below that.
MAX_ROW_BYTES = 40 * 1024

# Standard juz starts (surah, ayah); the IndoPak parah divisions the book uses.
JUZ_START = [
    (1, 1), (2, 142), (2, 253), (3, 93), (4, 24), (4, 148), (5, 82), (6, 111),
    (7, 88), (8, 41), (9, 93), (11, 6), (12, 53), (15, 1), (17, 1), (18, 75),
    (21, 1), (23, 1), (25, 21), (27, 56), (29, 46), (33, 31), (36, 28), (39, 32),
    (41, 47), (46, 1), (51, 31), (58, 1), (67, 1), (78, 1),
]

# Volumes whose scan stops short of the juz. Parah 30 was supplied as
# "QuranTafseer-Para-30-part1" and ends with Ash-Shams; 92-114 are not in the
# OCR drop at all, so the reader offers Asrar-at-Tanzil for them instead.
VOLUME_END = {30: (91, 15)}

DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")
URDU_DIGITS = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")
NUM = r"([0-9۰-۹٠-٩]{1,3})"
HEADING = re.compile(
    r"سور[ةۃهہ]\s+(.{1,22}?)\s+(?:[رد][کگ]وع\s*[0-9۰-۹]+\s+)?آیا?ت\s*"
    + NUM + r"\s*(?:تا|سے|-|–|—)\s*" + NUM
)
# Spelling the OCR or the book uses that the mushaf names do not cover.
NAME_ALIASES = {
    "بنیاسرائیل": 17, "بنیاسراءیل": 17, "اسراء": 17, "جاثیہ": 45, "جاشیہ": 45,
    "کہف": 18, "کھف": 18, "کلمف": 18, "کعف": 18, "ص": 38, "سجدہ": 32, "السجدہ": 32,
    "انبیا": 21, "انبیاء": 21, "اعبیاء": 21, "عمران": 3, "آلعمران": 3, "مومن": 40,
    "مومنون": 23, "حمالسجدہ": 41, "حمٓالسجدہ": 41, "فصلت": 41, "دہر": 76,
    "یسن": 36, "یٰسین": 36, "یس": 36, "صفت": 37, "صٰفّٰت": 37, "صُّفّت": 37,
    "ذریت": 51, "ذاریات": 51, "نزعت": 79, "نازعات": 79, "لقمن": 31, "لقمان": 31,
    "قلم": 68, "مؤمن": 40, "غافر": 40, "شوری": 42, "شوریٰ": 42, "فاطر": 35,
    "سبا": 34, "سباء": 34, "طہ": 20, "طٰہٰ": 20, "حج": 22, "نور": 24, "فرقان": 25,
    "شعراء": 26, "نمل": 27, "قصص": 28, "عنکبوت": 29, "روم": 30, "احزاب": 33,
    "زمر": 39, "زخرف": 43, "دخان": 44, "احقاف": 46, "محمد": 47, "فتح": 48,
    "حجرات": 49, "ق": 50, "طور": 52, "نجم": 53, "قمر": 54, "رحمن": 55, "رحمٰن": 55,
    "واقعہ": 56, "حدید": 57, "مجادلہ": 58, "حشر": 59, "ممتحنہ": 60, "صف": 61,
    "جمعہ": 62, "منافقون": 63, "تغابن": 64, "طلاق": 65, "تحریم": 66, "ملک": 67,
    "حاقہ": 69, "معارج": 70, "نوح": 71, "جن": 72, "مزمل": 73, "مدثر": 74,
    "قیامہ": 75, "قیامۃ": 75, "مرسلت": 77, "مرسلات": 77, "نبا": 78, "نباء": 78,
}

ARABIC_LETTER = re.compile(r"[ء-يٱ-ۓۺ-ۿ]")
HARAKA = re.compile(r"[ً-ٰٟۖ-ۭ]")
# An Arabic run (letters carrying harakat) optionally closed by an ornate marker.
QUOTE = re.compile(
    r"((?:[ء-ٰٟ-ۓۖ-ۭۺ-ۿ]+[  ]+){2,}"
    r"[ء-ٰٟ-ۓۖ-ۭۺ-ۿ]+)"
    r"(\s*﴿\s*[0-9۰-۹٠-٩]{1,3}\s*﴾)?"
)
TOC_MARK = "فہرست"
OCR_NOTE = re.compile(r"\n*OCR\s*نوٹ[\s\S]*$")
# The OCR repeatedly read the ﷺ ligature as a wrong honorific; in every case
# found it stands where the Prophet is named.
BAD_HONORIFIC = re.compile(r"\s*\n?\s*(?:رَحْمَةُ اللہِ عَلَیْہِ السَّلَامِ|رحمۃ اللہ علیہ السلام)\s*\n?\s*")
REPEAT_RUN = re.compile(r"(?<!\S)(\S{1,4})(?:\s+\1){2,}(?!\S)")
KEEP_REPEATS = {"اللہ", "الله", "حق", "ہو", "ھو", "-", "۔", "."}


def norm_name(text: str) -> str:
    text = HARAKA.sub("", text).replace("ـ", "")
    text = text.translate(str.maketrans({"ة": "ہ", "ۃ": "ہ", "ه": "ہ", "ھ": "ہ", "ي": "ی",
                                         "ى": "ی", "ك": "ک", "أ": "ا", "إ": "ا", "ٱ": "ا"}))
    text = re.sub(r"\s+", "", text)
    return text[2:] if text.startswith("ال") else text


def norm_arabic(text: str) -> str:
    text = HARAKA.sub("", text).replace("ـ", "")
    text = text.translate(str.maketrans({"أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ى": "ي",
                                         "ی": "ي", "ة": "ه", "ۃ": "ه", "ہ": "ه", "ک": "ك",
                                         "ؤ": "و", "ئ": "ي"}))
    return "".join(ARABIC_LETTER.findall(text))


def trigrams(text: str) -> set[str]:
    return {text[i:i + 3] for i in range(max(0, len(text) - 2))}


def load(seed: Path, name: str):
    with (seed / f"{name}.json").open(encoding="utf-8") as handle:
        return json.load(handle)


def juz_end(juz: int, counts: dict[int, int]) -> tuple[int, int]:
    """Last (surah, ayah) of a 1-based juz."""
    if juz == 30:
        return (114, counts[114])
    surah, ayah = JUZ_START[juz]
    return (surah, ayah - 1) if ayah > 1 else (surah - 1, counts[surah - 1])


def clean(text: str) -> str:
    text = OCR_NOTE.sub("", text)
    text = BAD_HONORIFIC.sub(" ﷺ ", text)

    def collapse(match: re.Match) -> str:
        return match.group(0) if match.group(1) in KEEP_REPEATS else match.group(1)

    text = REPEAT_RUN.sub(collapse, text)
    return re.sub(r"[ \t]+\n", "\n", text).strip()


class Mushaf:
    """The bundled mushaf, indexed for finding which ayah a quotation is from."""

    def __init__(self, ayahs: list[dict]):
        self.text = {(a["surahNumber"], a["ayahNumber"]): a["textArabic"] for a in ayahs}
        self.grams = {key: trigrams(norm_arabic(value)) for key, value in self.text.items()}
        self.index: dict[str, list[tuple[int, int]]] = defaultdict(list)
        for key, grams in self.grams.items():
            for gram in grams:
                self.index[gram].append(key)

    def best(self, quote: str, first: tuple[int, int], last: tuple[int, int]):
        """((surah, ayah), jaccard) of the one ayah between `first` and `last` a
        quotation comes from, or None when no ayah stands clearly above the
        rest. Containment, not similarity, decides: a quotation is usually a
        fragment of its ayah."""
        grams = trigrams(norm_arabic(quote))
        if len(grams) < 10:
            return None
        shared: dict[tuple[int, int], int] = defaultdict(int)
        for gram in grams:
            for key in self.index.get(gram, ()):
                if first <= key <= last:
                    shared[key] += 1
        if not shared:
            return None
        ranked = sorted(shared.items(), key=lambda item: item[1], reverse=True)
        key, count = ranked[0]
        containment = count / len(grams)
        runner = ranked[1][1] / len(grams) if len(ranked) > 1 else 0.0
        if containment < 0.7 or containment - runner < 0.15:
            return None
        return key, count / len(grams | self.grams[key])


def is_contents_page(text: str) -> bool:
    return TOC_MARK in text or len(HEADING.findall(text)) >= 3


def volume_text(pages: list[dict]) -> tuple[str, list[tuple[int, int]]]:
    """One volume as a single text, with (offset, printed page) marks."""
    parts, marks, offset = [], [], 0
    for page in pages:
        if is_contents_page(page["text"]):
            continue
        body = page["text"].strip()
        if not body:
            continue
        marks.append((offset, page["page"]))
        parts.append(body)
        offset += len(body) + 2
    return "\n\n".join(parts), marks


def page_at(marks: list[tuple[int, int]], position: int) -> int:
    page = marks[0][1]
    for offset, number in marks:
        if offset > position:
            break
        page = number
    return page


def anchors_for(text: str, first, last, names, counts, mushaf: Mushaf):
    """Points in a volume where commentary on a known ayah begins, in reading
    order and moving only forward: [(position, (surah, ayah), kind)]."""
    found = []
    for match in HEADING.finditer(text):
        surah = names.get(norm_name(match.group(1)))
        if surah is None:
            continue
        start = int(match.group(2).translate(DIGITS))
        end = int(match.group(3).translate(DIGITS))
        if 1 <= start <= end <= counts[surah] and first <= (surah, start) and (surah, end) <= last:
            found.append((match.start(), (surah, start), "heading"))
    for match in QUOTE.finditer(text):
        quote = match.group(1)
        if len(HARAKA.findall(quote)) < 4:
            continue  # unvowelled: Urdu prose, not a quotation
        hit = mushaf.best(quote, first, last)
        if hit:
            found.append((match.start(), hit[0], "quote"))
    found.sort()
    if not found:
        return []

    # Longest run that never moves backwards through the mushaf. A stray
    # match - a phrase that recurs in a later surah, a misread heading - is a
    # step back, so it falls out here instead of being trusted.
    parent = [-1] * len(found)
    keys: list[tuple[int, int]] = []
    tails: list[int] = []
    for i, (_, key, _) in enumerate(found):
        slot = bisect.bisect_right(keys, key)
        if slot > 0:
            parent[i] = tails[slot - 1]
        if slot == len(keys):
            keys.append(key)
            tails.append(i)
        else:
            keys[slot] = key
            tails[slot] = i
    chain, cursor = [], tails[-1]
    while cursor != -1:
        chain.append(found[cursor])
        cursor = parent[cursor]
    chain.reverse()
    return chain


def section_start(text: str, floor: int, position: int, ayah: int, kind: str) -> int:
    """Where commentary on `ayah` begins, given the anchor at `position`.

    A section opens with its translation, which closes ayah `ayah` with the
    marker ﴿n﴾. When that marker sits shortly before the quotation, the
    section starts at the paragraph holding it, so the translation travels
    with its commentary instead of trailing the previous ayah's."""
    if kind == "heading":
        return position
    window_from = max(floor, position - 4000)
    best = None
    for form in (f"﴿{ayah}﴾", f"﴿{str(ayah).translate(URDU_DIGITS)}﴾"):
        spot = text.rfind(form, window_from, position)
        if spot != -1 and (best is None or spot < best):
            best = spot
    anchor = best if best is not None else position
    paragraph = text.rfind("\n", floor, anchor)
    return paragraph + 1 if paragraph != -1 else max(floor, anchor)


def correct_quotations(text: str, first, last, mushaf: Mushaf) -> tuple[str, int]:
    """Replace whole-ayah quotations (those closed by a ﴿n﴾ marker) with the
    mushaf's own text and number. Fragments are left exactly as printed."""
    out, cursor, count = [], 0, 0
    for match in QUOTE.finditer(text):
        if not match.group(2) or len(HARAKA.findall(match.group(1))) < 4:
            continue
        hit = mushaf.best(match.group(1), first, last)
        if not hit or hit[1] < 0.6:
            continue
        key = hit[0]
        out.append(text[cursor:match.start()])
        out.append(mushaf.text[key] + f" ﴿{str(key[1]).translate(URDU_DIGITS)}﴾")
        cursor = match.end()
        count += 1
    out.append(text[cursor:])
    return "".join(out), count


MARKER = re.compile(r"﴿\s*([0-9۰-۹٠-٩]{1,3})\s*﴾")


def opening_length(text: str) -> int:
    """Length of a section's opening: its heading, the Arabic of its ayat and
    their numbered translation, which come before any commentary. A section
    is never cut inside it, or the next part would start mid-verse."""
    offset = 0
    for line in text.splitlines():
        stripped = line.strip()
        vowelled = len(HARAKA.findall(stripped)) >= len(stripped) * 0.12
        if stripped and not (vowelled or MARKER.search(stripped) or len(stripped) < 120
                             or HEADING.search(stripped)):
            break
        offset += len(line) + 1
    return offset


def translation_runs(text: str):
    """The book's section openings: Urdu translation in which consecutive
    ayat close with consecutive markers ﴿n﴾ ﴿n+1﴾ ... Returns
    [(run_start, run_end, first_ayah, last_ayah)]. A lone marker is not a run;
    whole-ayah Arabic quotations in the commentary also carry markers, so a
    run must read as Urdu (few vowel marks) between its markers."""
    markers = [(m.start(), m.end(), int(m.group(1).translate(DIGITS))) for m in MARKER.finditer(text)]
    runs, i = [], 0
    while i < len(markers):
        j = i
        while (j + 1 < len(markers)
               and markers[j + 1][2] == markers[j][2] + 1
               and markers[j + 1][0] - markers[j][1] < 900):
            between = text[markers[j][1]:markers[j + 1][0]]
            if len(HARAKA.findall(between)) > len(between) * 0.05:
                break  # vowelled: Arabic quotation, not translation
            j += 1
        if j > i:
            begin = text.rfind("\n", 0, max(0, markers[i][0] - 700))
            # The run's first ayah's translation starts after the previous
            # marker or paragraph break, whichever is nearer.
            previous_marker = markers[i - 1][1] if i > 0 else 0
            paragraph = text.rfind("\n", 0, markers[i][0])
            begin = max(previous_marker, paragraph + 1 if paragraph != -1 else 0)
            runs.append((begin, markers[j][1], markers[i][2], markers[j][2]))
            i = j + 1
        else:
            i += 1
    return runs


def build(seed: Path, report: dict):
    surahs = load(seed, "quran_surahs")
    counts = {s["id"]: s["ayahCount"] for s in surahs}
    names = {}
    for surah in surahs:
        for name in (surah["nameArabic"], surah.get("nameUrdu") or ""):
            if name:
                names[norm_name(name)] = surah["id"]
    names.update({norm_name(k): v for k, v in NAME_ALIASES.items()})
    mushaf = Mushaf(load(seed, "quran_ayahs"))

    all_pages = load(seed, "book_pages")
    by_book = defaultdict(list)
    for page in all_pages:
        if page["bookID"].startswith("tafaseer-parah-"):
            by_book[page["bookID"]].append(page)

    rows, volumes = [], defaultdict(list)
    dropped = replaced = sections_total = split_parts = fallback_rows = 0
    for juz in range(1, 31):
        book = f"tafaseer-parah-{juz}"
        pages = sorted(by_book.get(book, []), key=lambda p: p["page"])
        if not pages:
            report["missingVolumes"].append(book)
            continue
        first, last = JUZ_START[juz - 1], VOLUME_END.get(juz) or juz_end(juz, counts)
        text, marks = volume_text(pages)
        chain = anchors_for(text, first, last, names, counts, mushaf)
        quote_anchors = [(p, key) for p, key, kind in chain if kind == "quote"]

        # A section opening is believed when two independent signals agree:
        # the Urdu translation's own numbering, and Arabic within the opening
        # that the mushaf places in that same run of ayat. The Arabic says
        # which surah; the numbering says where the section starts.
        sections = []  # (begin, surah, first_ayah)
        for position, key, kind in chain:
            if kind == "heading":
                sections.append((position, key[0], key[1]))
        for begin, end, a, b in translation_runs(text):
            window = [key for p, key in quote_anchors if begin - 4000 <= p <= end + 2500]
            surahs_here = {s for s, ayah in window if a <= ayah <= b}
            if len(surahs_here) != 1:
                continue
            surah = surahs_here.pop()
            if not (first <= (surah, a) <= last) or b > counts[surah]:
                continue
            # Start at the Arabic block that precedes the translation, when
            # there is one: vowelled lines right before it are the section's
            # own ayat, and belong with it.
            start = begin
            probe = text.rfind("\n\n", 0, begin)
            while probe > 0 and begin - probe < 4000:
                block = text[probe:start]
                if len(HARAKA.findall(block)) < len(block) * 0.12:
                    break
                start = probe + 2
                probe = text.rfind("\n\n", 0, probe)
            sections.append((start, surah, a))
        sections.sort()

        # Keep the forward-moving sections only, one per starting ayah.
        ordered = []
        for section in sections:
            if ordered and (section[1], section[2]) <= (ordered[-1][1], ordered[-1][2]):
                continue
            ordered.append(section)
        sections_total += len(ordered)

        seen = set()
        for position, surah, _ in ordered:
            if surah not in seen:
                seen.add(surah)
                volumes[surah].append({"edition": EDITION, "bookID": book, "page": page_at(marks, position)})
        for surah in range(first[0], last[0] + 1):
            if surah not in seen:
                volumes[surah].append({"edition": EDITION, "bookID": book, "page": pages[0]["page"]})

        # Strong rows first; the spans they take are recorded so the
        # quotation fallback below only works where they left nothing.
        spans: list[tuple[int, int]] = []
        volume_rows: list[dict] = []
        for i, (begin, surah, ayah) in enumerate(ordered):
            following = ordered[i + 1] if i + 1 < len(ordered) else None
            if following is None:
                if last[0] != surah:
                    dropped += 1
                    continue
                stop, finish = last[1], len(text)
            elif following[1] == surah:
                stop, finish = following[2] - 1, following[0]
            elif following[1] == surah + 1 and following[2] == 1:
                stop, finish = counts[surah], following[0]
            else:
                dropped += 1
                continue
            if stop < ayah:
                continue
            spans.append((begin, finish))
            body, count = correct_quotations(clean(text[begin:finish]), (surah, ayah), (surah, stop), mushaf)
            replaced += count
            body = body.strip()
            if len(body) < 40:
                continue

            # Over budget: split where the commentary turns to a later ayah of
            # the section, judged by its quotation, past the opening.
            parts = [(ayah, body)]
            if len(body.encode()) > MAX_ROW_BYTES:
                cuts = []
                opening_end = opening_length(body)
                for match in QUOTE.finditer(body):
                    if match.start() <= opening_end or len(HARAKA.findall(match.group(1))) < 4:
                        continue
                    hit = mushaf.best(match.group(1), (surah, ayah), (surah, stop))
                    if hit and hit[0][1] > (cuts[-1][1] if cuts else ayah):
                        paragraph = body.rfind("\n", 0, match.start())
                        cuts.append((paragraph + 1 if paragraph != -1 else match.start(), hit[0][1]))
                if cuts:
                    parts, cursor, current = [], 0, ayah
                    for cut, next_ayah in cuts:
                        if cut <= cursor:
                            continue
                        parts.append((current, body[cursor:cut]))
                        cursor, current = cut, next_ayah
                    parts.append((current, body[cursor:]))
                    split_parts += len(parts) - 1
            for index, (part_ayah, part) in enumerate(parts):
                part_end = parts[index + 1][0] - 1 if index + 1 < len(parts) else stop
                if part.strip():
                    volume_rows.append({"editionID": EDITION, "surahNumber": surah, "ayahStart": part_ayah,
                                        "ayahEnd": part_end, "text": part.strip(), "sourceUrl": SOURCE_URL})

        # Fallback where no section opening was confirmed - a whole volume
        # whose openings the scan lost (parah 3), or a stretch before the first
        # one. Commentary on an ayah begins where the author quotes it, so the
        # quotation anchors cut the text there, but only outside the strong
        # rows' spans and only onto ayat no strong row already holds.
        covered = {(r["surahNumber"], a) for r in volume_rows for a in range(r["ayahStart"], r["ayahEnd"] + 1)}

        def shadowed(position: int) -> bool:
            return any(b <= position < f for b, f in spans)

        weak = []
        for position, key, kind in chain:
            if kind != "quote" or shadowed(position) or key in covered:
                continue
            if weak and key <= weak[-1][1]:
                continue
            weak.append((position, key))
        boundaries = sorted(
            [(position, key, "weak") for position, key in weak]
            + [(begin, (surah, ayah), "strong") for begin, surah, ayah in ordered]
        )
        for i, (position, (surah, ayah), kind) in enumerate(boundaries):
            if kind != "weak":
                continue
            following = boundaries[i + 1] if i + 1 < len(boundaries) else None
            if following is None:
                if last[0] != surah:
                    dropped += 1
                    continue
                stop, finish = last[1], len(text)
            elif following[1][0] == surah:
                stop, finish = following[1][1] - 1, following[0]
            elif following[1][0] == surah + 1 and following[1][1] <= 3:
                stop, finish = counts[surah], following[0]
            else:
                dropped += 1
                continue
            # Never onto an ayah a strong row holds.
            for candidate in range(ayah, stop + 1):
                if (surah, candidate) in covered:
                    stop = candidate - 1
                    break
            if stop < ayah:
                continue
            begin = section_start(text, max(0, boundaries[i - 1][0] + 1) if i else 0, position, ayah, "quote")
            body, count = correct_quotations(clean(text[begin:finish]), (surah, ayah), (surah, stop), mushaf)
            replaced += count
            body = body.strip()
            if len(body) >= 40:
                volume_rows.append({"editionID": EDITION, "surahNumber": surah, "ayahStart": ayah,
                                    "ayahEnd": stop, "text": body, "sourceUrl": SOURCE_URL})
                fallback_rows += 1
        rows.extend(volume_rows)
    report["sections"] = sections_total
    report["oversizeSplits"] = split_parts
    report["fallbackRows"] = fallback_rows

    # A row over the size budget is cut at its last paragraph break under the
    # budget and marked as continuing; the full text stays one tap away in the
    # volume. Reported, so the count is visible rather than silent.
    final = []
    for row in rows:
        if len(row["text"].encode()) <= MAX_ROW_BYTES:
            final.append(row)
        else:
            report["oversize"].append(f"{row['surahNumber']}:{row['ayahStart']}-{row['ayahEnd']}")
            row = dict(row)
            row["text"] = row["text"].encode()[:MAX_ROW_BYTES].decode("utf-8", "ignore")
            cut = row["text"].rfind("\n")
            row["text"] = row["text"][:cut].rstrip() + "\n\n…"
            final.append(row)

    # One row per (surah, ayahStart): keep the first, which is the section's own.
    unique, keys = [], set()
    for row in final:
        key = (row["surahNumber"], row["ayahStart"])
        if key in keys:
            continue
        keys.add(key)
        unique.append(row)

    # Asrar-at-Tanzil ships one volume per surah and language, opening at its
    # first page.
    asrar_pages = defaultdict(list)
    for page in load(seed, "book_pages"):
        if page["bookID"].startswith("asrar-"):
            asrar_pages[page["bookID"]].append(page["page"])
    for surah in range(1, 115):
        for language in ("ur", "en"):
            book = f"asrar-{surah}-{language}"
            if asrar_pages.get(book):
                volumes[surah].append({"edition": f"asrar-at-tanzil-{language}", "bookID": book,
                                       "page": min(asrar_pages[book])})

    covered = set()
    for row in unique:
        for ayah in range(row["ayahStart"], row["ayahEnd"] + 1):
            covered.add((row["surahNumber"], ayah))
    report.update({
        "rows": len(unique),
        "ayatCovered": len(covered),
        "surahsTouched": len({r["surahNumber"] for r in unique}),
        "sectionsDropped": dropped,
        "quotationsReplacedWithMushaf": replaced,
    })
    return unique, {str(k): v for k, v in sorted(volumes.items())}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--write", action="store_true", help="write the four platform seeds")
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")

    primary = SEED_DIRS[0]
    report = {"missingVolumes": [], "oversize": []}
    rows, volumes = build(primary, report)
    print(json.dumps(report, ensure_ascii=False, indent=1)[:4000])
    if not args.write:
        return 0

    tafsir = [r for r in load(primary, "quran_tafsir") if r["editionID"] != EDITION] + rows
    tafsir.sort(key=lambda r: (r["editionID"], r["surahNumber"], r["ayahStart"]))
    editions = load(primary, "quran_editions")
    for edition in editions:
        if edition["id"] == EDITION:
            edition["reviewState"] = "testFlightApproved"
    payloads = {
        "quran_tafsir": tafsir,
        "quran_editions": editions,
        "tafsir_volumes": {"generatedBy": "Tools/Library/segment_akram_tafaseer.py",
                           "surahs": volumes},
    }
    for seed in SEED_DIRS:
        for name, payload in payloads.items():
            path = seed / f"{name}.json"
            with path.open("w", encoding="utf-8", newline="\n") as handle:
                json.dump(payload, handle, ensure_ascii=False, indent=1)
                handle.write("\n")
        print(f"wrote {seed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
