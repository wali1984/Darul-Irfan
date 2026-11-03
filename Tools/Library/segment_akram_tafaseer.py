"""Build per-ayah Akram-ut-Tafaseer (Urdu) rows from the parah page text.

`ingest_tafsir_pages.py` shipped Akram-ut-Tafaseer as 30 page-structured parah
volumes and deliberately did not key it per ayah, because the OCR pipeline's own
`verse_refs` were wrong. This tool keys it from signals the book itself prints.

Every section of the book opens the same way: the ruku heading

    سورۃ البقرہ رکوع 18 آیات 148 تا 152

the Arabic of those ayat, and the Sheikh's Urdu translation of them, each ayah
closed by its number ﴿n﴾. The commentary on those ayat follows, up to the next
section's opening. The openings are found five ways, and the heaviest set of
them that agrees with the order of the mushaf is believed:

  * the translation itself: it is the Akram-ut-Tarajum translation, so every
    ayah's Urdu is located in the volume by its letters. This is the strongest
    signal (the OCR reads plain Urdu well), and it names the surah outright;
  * the printed heading, when the OCR kept it;
  * a run of consecutive markers ﴿n﴾ ﴿n+1﴾ closing Urdu text, whose surah is
    taken from the translation or the Arabic quoted around it (markers after
    the commentary's Arabic quotations are not used: the OCR misreads them);
  * a surah's title box (سورۃ آل عمران مدنی), which opens a new surah;
  * in parah 3, which prints another translation without ayah numbers, the
    "خلاصہ تفسیر و معارف" line that closes each section's translation, keyed
    by the first ayah the commentary after it quotes.

The openings then cut each volume into consecutive rows, so every page of the
commentary lands in exactly one row: nothing between two openings is dropped,
text before a volume's first recognised opening goes to the volume's first
ayah, and a row never runs past the end of its surah. A row's range runs to
the ayah before the next opening, so an opening the OCR missed widens a range
instead of attributing text to the wrong ayat.

Inside a section the commentary quotes each ayah before explaining it. A row
over the size budget is split where the commentary turns to a later ayah of
its range, judged by the quoted Arabic matched against the bundled mushaf
(letter trigrams, with a clear margin over every other ayah). The same match
replaces Qur'anic quotations with the mushaf's own text: whole ayat closed by
﴿n﴾, and fragments whose letters are clearly a passage of one ayah of the row.

Stretches re-cut by eye, after all of the above, are in SECTION_CORRECTIONS:
only their row boundaries move.

Parahs follow the IndoPak divisions the book is printed in (para 4 opens at
3:92, para 14 at 15:2, ...), not the Madani ones.

Also emits `tafsir_volumes.json`: for every surah, the page where its
commentary begins in each volume (the parah's title page for a surah carried
over from the previous parah), so the reader can open the full printed text;
for Parah 30 part 2, which has no text in the app yet, the PDF page of each
surah's printed heading.

Reads only seed files. Writes quran_tafsir.json and tafsir_volumes.json to the
seed folders named by --targets (all four platforms by default).
"""

from __future__ import annotations

import argparse
import difflib
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
TARGETS = {"ios": 0, "android": 1, "harmony": 2, "web": 3}
EDITION = "akram-ut-tafaseer-ur"
TRANSLATION_EDITION = "akram-ut-tarajum-ur"
SOURCE_URL = "https://www.naqshbandiaowaisiah.org/akram-ut-tafaseer"
# The reader crashed on a 662 KB block in v1.6.9. A row over this budget is
# split where its commentary turns to a later ayah. A section that cannot be
# split that way stays whole: cutting it at a paragraph would file the rest of
# an ayah's commentary under the next ayah. The content gate's hard ceiling
# (check_content.py) is 96 KB.
MAX_ROW_BYTES = 40 * 1024
HARD_ROW_BYTES = 96 * 1024

# Where each printed parah begins (surah, ayah): the IndoPak divisions the
# Silsila prints Akram-ut-Tarajum and Akram-ut-Tafaseer in. They differ from
# the Madani juz starts at 3:92, 5:83, 9:94, 15:2, 27:60, 29:45 and 36:22.
PARAH_START = [
    (1, 1), (2, 142), (2, 253), (3, 92), (4, 24), (4, 148), (5, 83), (6, 111),
    (7, 88), (8, 41), (9, 94), (11, 6), (12, 53), (15, 2), (17, 1), (18, 75),
    (21, 1), (23, 1), (25, 21), (27, 60), (29, 45), (33, 31), (36, 22), (39, 32),
    (41, 47), (46, 1), (51, 31), (58, 1), (67, 1), (78, 1),
]
JUZ_START = PARAH_START  # the name older checks import

# Volumes whose scan stops short of the parah. Parah 30 was supplied as
# "QuranTafseer-Para-30-part1" and ends with Ash-Shams; part 2 (92-114) has no
# text in the app yet, so those surahs have no rows.
VOLUME_END = {30: (91, 15)}

# Parah 30 part 2 ("QuranTafseer-Para-30-part2.pdf", library item
# tafaseer-parah-30-part-2) has no text pages yet, so its volume links are the
# PDF pages on which each surah's heading is printed ("سورۃ اللیل رکوع 1 آیات
# 1 تا 21"), read from the scan on 2026-10-29. The book's contents page puts
# At-Takathur on page 153; its heading is printed on page 154 (PDF page 155).
PART_TWO_BOOK = "tafaseer-parah-30-part-2"
PART_TWO_STARTS = {
    92: 20, 93: 42, 94: 57, 95: 79, 96: 86, 97: 119, 98: 125, 99: 141, 100: 146,
    101: 150, 102: 155, 103: 169, 104: 175, 105: 180, 106: 186, 107: 191, 108: 200,
    109: 204, 110: 211, 111: 218, 112: 224, 113: 235, 114: 242,
}

DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")
URDU_DIGITS = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")
NUM = r"([0-9۰-۹٠-٩]{1,3})"
HEADING = re.compile(
    r"سور[ةۃهہ]\s+(.{1,22}?)\s+(?:[رد][کگ]وع\s*[0-9۰-۹]+\s+)?آیا?ت\s*"
    + NUM + r"\s*(?:تا|سے|-|–|—)\s*" + NUM
)
# The same heading printed without "سورۃ" ("النساء رکوع 5 آیات 26-33"), on a
# line of its own.
HEADING_BARE = re.compile(
    r"(?m)^[ \t]*(\S{2,14}(?: \S{2,14})?)\s+[رد][کگ]وع\s*[0-9۰-۹]+\s+آیا?ت\s*"
    + NUM + r"\s*(?:تا|سے|-|–|—)\s*" + NUM
)


def iter_headings(text: str):
    """(start, end, surah name, first ayah, last ayah) of each printed heading."""
    seen = set()
    for pattern in (HEADING, HEADING_BARE):
        for match in pattern.finditer(text):
            if match.start() in seen:
                continue
            seen.add(match.start())
            yield (match.start(), match.end(), match.group(1),
                   int(match.group(2).translate(DIGITS)), int(match.group(3).translate(DIGITS)))


def has_heading(text: str) -> bool:
    return bool(HEADING.search(text) or HEADING_BARE.search(text))


# The line that follows a section's translation.
SUMMARY = re.compile(r"(?m)^[ \t]*(?:خلاصہ تفسیر و معارف|خلاصہ رکوع|خلاصۂ رکوع)[ \t]*$")
# A surah's title box, as parah 3 prints it: "سورۃ آل عمران مدنی".
TITLE_BOX = re.compile(r"(?m)^[ \t]*سور[ةۃهہ]\s+([^\n]{1,24}?)\s+(?:مکی|مدنی|مکیہ|مدنیہ)[ \t]*$")
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
HARAKA = re.compile(r"[ً-ٰٟۖ-ۭ]")
# An Arabic run (letters carrying harakat) optionally closed by an ornate marker.
QUOTE = re.compile(
    r"((?:[ء-ٰٟ-ۓۖ-ۭۺ-ۿ]+[  ]+){2,}"
    r"[ء-ٰٟ-ۓۖ-ۭۺ-ۿ]+)"
    r"(\s*﴿\s*[0-9۰-۹٠-٩]{1,3}\s*﴾)?"
)
MARKER = re.compile(r"﴿\s*([0-9۰-۹٠-٩]{1,3})\s*﴾")
MARKER_AFTER = re.compile(r"[ \t]*﴿\s*([0-9۰-۹٠-٩]{1,3})\s*﴾")
ASCII_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")
WHOLE_QURAN = ((1, 1), (114, 6))
OCR_NOTE = re.compile(r"\n*OCR\s*نوٹ[\s\S]*$")
# The OCR repeatedly read the ﷺ ligature as a wrong honorific; in every case
# found it stands where the Prophet is named.
BAD_HONORIFIC = re.compile(r"\s*\n?\s*(?:رَحْمَةُ اللہِ عَلَیْہِ السَّلَامِ|رحمۃ اللہ علیہ السلام)\s*\n?\s*")
REPEAT_RUN = re.compile(r"(?<!\S)(\S{1,4})(?:\s+\1){2,}(?!\S)")
KEEP_REPEATS = {"اللہ", "الله", "حق", "ہو", "ھو", "-", "۔", "."}
# OCR misreadings of the book's punctuation: the Devanagari danda and the CJK
# full stop for the Urdu full stop, the ayah-end roundel after a Qur'anic
# quotation read as ©, ⓘ, ⊕ or ⊗, and a closing ornate bracket read as ⟩.
PUNCT_FIXES = [
    (re.compile(r"[।。]"), "۔"),
    (re.compile(r"[ \t]*[©ⓘ⊕⊗][ \t]*"), " "),
    (re.compile(r"﴿([0-9۰-۹٠-٩]{1,3})⟩"), r"﴿\1﴾"),
]
# A line holding nothing but a number: the OCR's reading of the small numbers
# and roundels printed beside quotations, never text.
LONE_NUMBER = re.compile(r"(?m)^[ \t]*\(?[0-9۰-۹٠-٩]{1,3}\)?[ \t]*$\n?")
# The back cover carries the publisher's advertisement for Asrar-ul-Ma'arif
# and the bookshop's address; it is not commentary.
BACK_COVER = ("چھ جلدوں", "اسرار المعارف")
URDU_ONLY = set("ٹڈڑںےۓھہکیگپچژ")
PAUSE_TOKEN = re.compile(r"[\u06d6-\u06dc\u06df-\u06ed\u200c-\u200f\ue000-\uf8ff]+")
# The OCR's readings of the ayah-end ornament itself: 1 to 22 (1,370 of the
# review's 1,404 wrong markers; 1 x317, 15 x313).
ORNAMENT_READINGS = set(range(1, 23))
CITATION_PUNCT = re.compile(r"[:()\[\]﴿﴾،؛]")
# Opening words of the author's preface printed in every volume.
PREFACE = ("اکثر احباب سوچتے", "پیش لفظ", "عرض ناشر", "عرضِ ناشر")


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


def parah_end(parah: int, counts: dict[int, int]) -> tuple[int, int]:
    """Last (surah, ayah) of a 1-based parah."""
    if parah in VOLUME_END:
        return VOLUME_END[parah]
    if parah == 30:
        return (114, counts[114])
    surah, ayah = PARAH_START[parah]
    return (surah, ayah - 1) if ayah > 1 else (surah - 1, counts[surah - 1])


def next_key(key: tuple[int, int], counts: dict[int, int]) -> tuple[int, int]:
    surah, ayah = key
    return (surah, ayah + 1) if ayah < counts[surah] else (surah + 1, 1)


def clean(text: str) -> str:
    text = BAD_HONORIFIC.sub(" ﷺ ", text)
    for pattern, replacement in PUNCT_FIXES:
        text = pattern.sub(replacement, text)
    text = LONE_NUMBER.sub("", text)

    def collapse(match: re.Match) -> str:
        return match.group(0) if match.group(1) in KEEP_REPEATS else match.group(1)

    text = REPEAT_RUN.sub(collapse, text)
    text = re.sub(r"[ \t]{2,}", " ", text)
    text = re.sub(r"[ \t]+\n", "\n", text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


# ---------------------------------------------------------------------------
# The mushaf, for Qur'anic quotations
# ---------------------------------------------------------------------------

class Mushaf:
    """The bundled mushaf, indexed for finding which ayah a quotation is from."""

    def __init__(self, ayahs: list[dict]):
        self.text = {(a["surahNumber"], a["ayahNumber"]): a["textArabic"] for a in ayahs}
        self.grams = {key: trigrams(norm_arabic(value)) for key, value in self.text.items()}
        self.index: dict[str, list[tuple[int, int]]] = defaultdict(list)
        for key, grams in self.grams.items():
            for gram in grams:
                self.index[gram].append(key)
        self._words: dict[tuple[int, int], list[tuple[int, int, str]]] = {}
        self._by_first: dict[str, list[tuple[tuple[int, int], int]]] | None = None

    def matches(self, letters: list[str]) -> list[tuple[tuple[int, int], int, int]]:
        """(ayah, word index, how many words agree) for every place an ayah
        has the first of `letters`, read on word by word, letters exactly."""
        if self._by_first is None:
            self._by_first = defaultdict(list)
            for key in self.text:
                for index, (_, _, word) in enumerate(self.words(key)):
                    self._by_first[word].append((key, index))
        found = []
        for key, index in self._by_first.get(letters[0], ()):
            words = self.words(key)
            count = 0
            while count < len(letters) and index + count < len(words) and words[index + count][2] == letters[count]:
                count += 1
            found.append((key, index, count))
        return found

    def span_text(self, key: tuple[int, int], index: int, length: int) -> str:
        """The mushaf's own words for `length` words of an ayah from `index`,
        exactly as it writes them (its invisible marks too, so a quotation
        already in its words is left untouched)."""
        words = self.words(key)
        return self.text[key][words[index][0]:words[index + length - 1][1]]

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

    def words(self, key: tuple[int, int]) -> list[tuple[int, int, str]]:
        """(start, end, letters) of each word of an ayah that has letters;
        waqf signs and other marks are not words."""
        if key not in self._words:
            found = []
            # A pause mark joined to the next word ("اَجْرٍ ؕاِنْ") still ends a
            # word; a zero-width space before a vowel mark ("عَوْرَة\u200bٌ")
            # does not.
            for match in re.finditer(r"(?:[^\s\u200b\u06d6-\u06dc\u06de\u06e9]|\u200b(?=[\u064b-\u065f\u0670]))+",
                                     self.text[key]):
                letters = norm_arabic(match.group(0))
                if letters:
                    found.append((match.start(), match.end(), letters))
            self._words[key] = found
        return self._words[key]

    def candidates(self, letters: str, first: tuple[int, int], last: tuple[int, int]):
        """Ayat between `first` and `last` holding at least 60% of the
        fragment's letter trigrams. The informative trigrams (found in 1 to
        400 ayat) find them, so an OCR-mangled trigram, rare by nature, does
        not decide; all trigrams confirm."""
        grams = trigrams(letters)
        if not grams:
            return []
        informative = [g for g in grams if 0 < len(self.index.get(g, ())) <= 400]
        if len(informative) < 3:
            informative = [g for g in grams if self.index.get(g)]
        if not informative:
            return []
        votes: dict[tuple[int, int], int] = defaultdict(int)
        for gram in informative:
            for key in self.index.get(gram, ()):
                if first <= key <= last:
                    votes[key] += 1
        need = 0.5 * len(informative)
        return [key for key, count in votes.items()
                if count >= need and len(grams & self.grams[key]) / len(grams) >= 0.6]

    def passages(self, fragment: str, first: tuple[int, int], last: tuple[int, int], min_letters: int = 12):
        """Every reading of a vowelled fragment as a passage of one ayah
        between `first` and `last`: [(similarity, key, the mushaf's words)],
        best first.

        The passage has as many words as the fragment (a particle the OCR set
        apart, "وَ اَمَّمُوا", counts with its word), and its first and last
        words must be the fragment's: a quotation is never lengthened by a
        word it did not quote, and a word the OCR mangled past recognition at
        either end leaves the fragment as printed."""
        letters = norm_arabic(fragment)
        if len(letters) < min_letters:
            return []
        tokens = []
        for token in fragment.split():
            token_letters = norm_arabic(token)
            if not token_letters:
                continue
            if tokens and len(tokens[-1]) == 1:
                tokens[-1] += token_letters  # a lone particle joins its word
            else:
                tokens.append(token_letters)
        if len(tokens) < 2:
            return []

        def similar(a: str, b: str) -> float:
            return difflib.SequenceMatcher(None, a, b, autojunk=False).ratio()

        results = []
        for key in self.candidates(letters, first, last):
            words = self.words(key)
            best = None
            # As many words as the fragment; one more or fewer only where the
            # OCR joined or split words in the middle ("الْبِرَّحَتَّى"), and
            # only when that reads clearly better.
            for length, handicap in ((len(tokens), 0.0), (len(tokens) + 1, 0.02), (len(tokens) - 1, 0.02)):
                if length < 2:
                    continue
                for i in range(0, len(words) - length + 1):
                    span = words[i:i + length]
                    first_word, last_word = span[0][2], span[-1][2]
                    first_ok = similar(tokens[0], first_word) >= 0.7
                    last_ok = similar(tokens[-1], last_word) >= 0.7
                    if length == len(tokens) - 1 and len(tokens) >= 3:
                        # a word the OCR split at an edge ("لَوْ مُّهَا")
                        first_ok = first_ok or similar(tokens[0] + tokens[1], first_word) >= 0.7
                        last_ok = last_ok or similar(tokens[-2] + tokens[-1], last_word) >= 0.7
                    if not (first_ok and last_ok):
                        continue
                    ratio = similar(letters, "".join(w[2] for w in span))
                    if best is None or ratio - handicap > best[0]:
                        best = (ratio - handicap, i, length, ratio)
            if best:
                _, i, length, ratio = best
                start, end = words[i][0], words[i + length - 1][1]
                results.append((ratio, key, self.text[key][start:end]))
        results.sort(key=lambda r: (-r[0], r[1]))
        return results

    def passage(self, fragment: str, first: tuple[int, int], last: tuple[int, int]):
        """The exact words of the mushaf a vowelled fragment quotes, when its
        letters are clearly a passage of one ayah between `first` and `last`:
        (key, mushaf text, similarity), or None."""
        results = self.passages(fragment, first, last)
        if not results:
            return None
        ratio, key, text = results[0]
        if ratio < 0.85:
            return None
        for other_ratio, other_key, other_text in results[1:]:
            if other_text != text and ratio - other_ratio < 0.05:
                return None  # two different passages fit equally well
        return key, text, ratio

    def identify(self, fragment: str, first: tuple[int, int], last: tuple[int, int]):
        """(the mushaf's words, every ayah that has them, similarity) for a
        quotation read against the whole Qur'an, the row's own ayat preferred
        on a tie; None when no single passage stands out."""
        results = self.passages(fragment, WHOLE_QURAN[0], WHOLE_QURAN[1])
        if not results:
            return None
        top = results[0][0]
        if top < 0.85:
            return None
        best = [r for r in results if top - r[0] < 0.005]
        own = [r for r in best if first <= r[1] <= last]
        ratio, key, text = (own or best)[0]
        if top < 0.995:   # an exact reading is not made doubtful by a near-identical phrase
            for other_ratio, other_key, other_text in results:
                if other_text != text and top - other_ratio < 0.05:
                    if norm_arabic(other_text) != norm_arabic(text):
                        return None  # two different passages fit equally well
        keys = sorted({k for r_, k, t in results if norm_arabic(t) == norm_arabic(text) and top - r_ < 0.005})
        return text, keys, ratio


def quranic_runs(text: str):
    """(start, end) of each run of three or more Qur'anic words: voweled
    Arabic (Urdu prose carries a vowel mark only now and then), as the
    reader's page formatter decides."""
    tokens = [(m.start(), m.end(), m.group(0)) for m in re.finditer(r"\S+", text)]

    def quranic(word: str) -> bool:
        if not ARABIC_LETTER.search(word) or CITATION_PUNCT.search(word):
            return False
        vowels = len(HARAKA.findall(word))
        return vowels >= 2 or (vowels >= 1 and not (set(word) & URDU_ONLY))

    def pause(word: str) -> bool:
        # a pause mark (or a directional mark) standing as its own token
        return bool(PAUSE_TOKEN.fullmatch(word))

    def joined(a: int, b: int) -> bool:
        return "\n\n" not in text[tokens[a][1]:tokens[b][0]]

    runs, i = [], 0
    while i < len(tokens):
        if not quranic(tokens[i][2]):
            i += 1
            continue
        j, count = i, 1
        while True:
            k = j + 1
            while k < len(tokens) and pause(tokens[k][2]) and joined(k - 1, k):
                k += 1
            if k < len(tokens) and quranic(tokens[k][2]) and joined(k - 1, k):
                j, count = k, count + 1
            else:
                break
        if count >= 3:
            runs.append((tokens[i][0], tokens[j][1]))
        i = j + 1
    return runs


def correct_quotations(text: str, first, last, mushaf: Mushaf) -> tuple[str, int]:
    """Replace quotations of the row's own ayat that are closed by a ﴿n﴾
    marker with the mushaf's own text and number: the whole ayah when the
    quotation is (nearly) the whole ayah, else the mushaf's words for the
    part it quotes."""
    out, cursor, count = [], 0, 0
    for match in QUOTE.finditer(text):
        if not match.group(2) or len(HARAKA.findall(match.group(1))) < 4:
            continue
        quote = match.group(1)
        hit = mushaf.best(quote, first, last)
        if not hit or hit[1] < 0.6:
            continue
        key = hit[0]
        if len(norm_arabic(quote)) >= 0.8 * len(norm_arabic(mushaf.text[key])):
            replacement = mushaf.text[key]
        else:
            part = mushaf.passage(quote, key, key)
            if not part:
                continue
            replacement = part[1]
        out.append(text[cursor:match.start()])
        out.append(replacement + f" ﴿{str(key[1]).translate(URDU_DIGITS)}﴾")
        cursor = match.end()
        count += 1
    out.append(text[cursor:])
    return "".join(out), count


def correct_fragments(text: str, first, last, mushaf: Mushaf) -> tuple[str, int]:
    """Replace a quoted fragment of an ayah of the row with the mushaf's own
    words for it. Only a fragment whose letters are at least 85% the same as
    one passage of one ayah of the row's range is touched; a citation of an
    ayah outside the row, or a quotation the OCR mangled past recognition, is
    left exactly as printed."""
    out, cursor, count = [], 0, 0
    for start, end in quranic_runs(text):
        fragment = text[start:end]
        if MARKER.search(fragment):
            continue  # a whole ayah with its number: correct_quotations' job
        hit = mushaf.passage(fragment, first, last)
        if not hit:
            continue
        _, replacement, _ = hit
        if replacement == fragment or len(letter_words(replacement)) < len(letter_words(fragment)):
            continue
        out.append(text[cursor:start])
        out.append(replacement)
        cursor = end
        count += 1
    out.append(text[cursor:])
    return "".join(out), count


def letter_words(fragment: str) -> list[tuple[int, int, str]]:
    """(start, end, letters) of each word of a fragment; a lone particle the
    OCR set apart ("وَ اَمَّمُوا") joins its word, as passages() reads them."""
    words: list[tuple[int, int, str]] = []
    for match in re.finditer(r"\S+", fragment):
        letters = norm_arabic(match.group(0))
        if not letters:
            continue
        if words and len(words[-1][2]) == 1:
            start, _, joined = words[-1]
            words[-1] = (start, match.end(), joined + letters)
        else:
            words.append((match.start(), match.end(), letters))
    return words


def correct_by_letters(text: str, first, last, mushaf: Mushaf) -> tuple[str, int]:
    """Give a quotation the mushaf's words where its letters are exactly the
    mushaf's, word for word: the OCR read the letters right and a vowel wrong
    ("مُلْكُ يَوْمِ الدِّيْنِ" for 1:4), or ran a quotation on into the Urdu
    after it. Short quotations count too, since every letter must agree; from
    each word the longest such stretch is taken. It is replaced only when it
    has one reading in the Qur'an, or one among the row's own ayat, so no
    vowel is guessed; a word the OCR mangled ends the stretch and stays as
    printed."""
    out, cursor, count = [], 0, 0
    for start, end in quranic_runs(text):
        words = letter_words(text[start:end])
        index = 0
        while index < len(words) - 1:
            found = mushaf.matches([w[2] for w in words[index:]])
            longest = max((n for _, _, n in found), default=0)
            replacement = None
            if longest >= 2:
                readings: dict[str, list[tuple[int, int]]] = defaultdict(list)
                for key, at, n in found:
                    if n >= longest:
                        readings[mushaf.span_text(key, at, longest)].append(key)
                own = [t for t, keys in readings.items() if any(first <= key <= last for key in keys)]
                replacement = next(iter(readings)) if len(readings) == 1 else own[0] if len(own) == 1 else None
            if replacement is None:
                index += 1
                continue
            a, b = start + words[index][0], start + words[index + longest - 1][1]
            if text[a:b] != replacement:
                out.append(text[cursor:a])
                out.append(replacement)
                cursor = b
                count += 1
            index += longest
    out.append(text[cursor:])
    return "".join(out), count


def correct_citations(text: str, first, last, mushaf: Mushaf, row: str, report: dict) -> tuple[str, dict]:
    """Every Qur'anic run of a row, the cross-references to other surahs
    included (TAFSIR-002), read against the whole Qur'an. A run that one
    passage clearly matches (if need be without a stray word at an edge)
    takes the mushaf's words; the ayah-end marker after it (TAFSIR-007) takes
    that ayah's number. When the words stand in several ayat, the marker keeps
    a printed number that is one of them, else takes the one ayah of the row
    (or within three ayat of it) among them. Anything else stays as printed
    and is listed in the report."""
    counts = defaultdict(int)
    out, cursor = [], 0
    for start, end in quranic_runs(text):
        if start < cursor:
            continue
        fragment = text[start:end]
        marker = MARKER_AFTER.match(text, end)
        found = mushaf.identify(fragment, first, last)
        # A shorter reading would lose printed words: "اَعُوْذُ بِاللّٰہِ مِنَ
        # الشَّیْطٰنِ الرَّجِیْمِ" must not become 16:98's words alone. Only the part
        # that matches may take the mushaf's words, below.
        if found and len(letter_words(found[0])) < len(letter_words(fragment)):
            found = None
        span = (start, end)
        if not found:
            tokens = list(re.finditer(r"\S+", fragment))
            for drop_first, drop_last in ((0, 1), (1, 0), (1, 1)):
                if len(tokens) - drop_first - drop_last < 3:
                    continue
                a, b = tokens[drop_first].start(), tokens[len(tokens) - 1 - drop_last].end()
                found = mushaf.identify(fragment[a:b], first, last)
                if found and len(letter_words(found[0])) < len(letter_words(fragment[a:b])):
                    found = None
                if found:
                    span = (start + a, start + b)
                    counts["edgeTrimmed"] += 1
                    break
        if found and found[0] != text[span[0]:span[1]]:
            out.append(text[cursor:span[0]])
            out.append(found[0])
            cursor = span[1]
            counts["quotations"] += 1
            if not any(first <= k <= last for k in found[1]):
                counts["crossReferences"] += 1
        if not marker:
            continue
        printed = int(marker.group(1).translate(ASCII_DIGITS))
        if not found:
            report["citationMarkersUnidentified"].append(
                {"row": row, "marker": printed, "quotation": fragment[-80:]})
            continue
        keys = found[1]
        own = [k for k in keys if first <= k <= last]
        near = [k for k in keys if k[0] == first[0] and first[1] - 3 <= k[1] <= last[1] + 3]
        numbers = {k[1] for k in keys}
        if len(keys) == 1:
            number = keys[0][1]
        elif printed in numbers and printed not in ORNAMENT_READINGS:
            number = printed
        elif len(own) == 1:
            number = own[0][1]
            counts["markersByRow"] += 1
        elif len(near) == 1:
            number = near[0][1]
            counts["markersByRow"] += 1
        elif printed in numbers:
            number = printed
        else:
            report["citationMarkersAmbiguous"].append(
                {"row": row, "marker": printed, "ayat": [f"{a}:{b}" for a, b in keys[:8]],
                 "quotation": fragment[-80:]})
            continue
        if number != printed:
            out.append(text[cursor:marker.start()])
            out.append(f" ﴿{str(number).translate(URDU_DIGITS)}﴾")
            cursor = marker.end()
            counts["markers"] += 1
    out.append(text[cursor:])
    return "".join(out), counts


# ---------------------------------------------------------------------------
# The translation, for section openings
# ---------------------------------------------------------------------------

FOLD = str.maketrans({"ي": "ی", "ى": "ی", "ك": "ک", "ه": "ہ", "ھ": "ہ", "ة": "ہ", "ۃ": "ہ",
                      "ۂ": "ہ", "ۓ": "ے", "ؤ": "و", "أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا",
                      "ئ": "ی", "ء": ""})
URDU_LETTER = re.compile(r"[ء-غف-يٱ-ۓۺ-ۿ]")
GRAM = 6


def fold_letters(text: str) -> tuple[str, list[int]]:
    """The letters of an Urdu text with vowel marks dropped and the spellings
    the OCR mixes folded together, and each letter's offset in `text`."""
    letters, offsets = [], []
    for offset, char in enumerate(text):
        if HARAKA.match(char) or char == "ـ":
            continue
        char = char.translate(FOLD)
        if char and URDU_LETTER.match(char):
            letters.append(char)
            offsets.append(offset)
    return "".join(letters), offsets


class TranslationIndex:
    """Finds where an ayah's Akram-ut-Tarajum translation is printed in a volume."""

    def __init__(self, text: str):
        self.text = text
        self.letters, self.offsets = fold_letters(text)
        self.grams: dict[str, list[int]] = defaultdict(list)
        for i in range(len(self.letters) - GRAM + 1):
            self.grams[self.letters[i:i + GRAM]].append(i)

    def locate(self, translation: str):
        """(score, start, end) in text offsets of the best placement, where
        score is the share of the translation's letter 6-grams found in order
        there; None for a translation too short to place."""
        letters, _ = fold_letters(translation)
        count = len(letters) - GRAM + 1
        if count < 8:
            return None
        votes: dict[int, set[int]] = defaultdict(set)
        diagonals: dict[int, list[int]] = defaultdict(list)
        for offset in range(count):
            hits = self.grams.get(letters[offset:offset + GRAM])
            if not hits or len(hits) > 40:
                continue
            for hit in hits:
                bucket = (hit - offset) // 16
                votes[bucket].add(offset)
                diagonals[bucket].append(hit - offset)
        if not votes:
            return None
        best, best_bucket = 0, None
        for bucket in votes:
            joined = votes[bucket] | votes.get(bucket - 1, set()) | votes.get(bucket + 1, set())
            if len(joined) > best:
                best, best_bucket = len(joined), bucket
        spread = sorted(diagonals[best_bucket] + diagonals.get(best_bucket - 1, [])
                        + diagonals.get(best_bucket + 1, []))
        diagonal = spread[len(spread) // 2]
        first_letter = max(0, min(len(self.offsets) - 1, diagonal))
        last_letter = max(0, min(len(self.offsets) - 1, diagonal + len(letters) - 1))
        return best / count, self.offsets[first_letter], self.offsets[last_letter] + 1


def snap_to_line(text: str, position: int) -> int:
    """A located translation starts within some letters of where it was
    found (a different wording, an OCR slip). A section opens a paragraph or
    at least a line: move to one when only a few words separate the two, and
    never leave a cut inside a word."""
    if position <= 0 or text[position - 1] == "\n":
        return position
    paragraph = text.find("\n\n", position, position + 160)
    if paragraph != -1 and re.search(r"(?:[۔؟!]|آمین)\s*$", text[position:paragraph]):
        while paragraph < len(text) and text[paragraph] == "\n":
            paragraph += 1
        return paragraph
    after = text.find("\n", position, position + 80)
    if after != -1 and len(fold_letters(text[position:after])[0]) <= 24:
        while after < len(text) and text[after] == "\n":
            after += 1
        return after
    before = text.rfind("\n", max(0, position - 80), position)
    if before != -1 and len(fold_letters(text[before:position])[0]) <= 24:
        return before + 1
    while 0 < position < len(text) and not text[position - 1].isspace():
        position -= 1
    return position


def weighted_chain(items, key_of, weight_of):
    """Heaviest subsequence of `items` (already in reading order) whose keys
    never move backwards through the mushaf."""
    keys = sorted({key_of(item) for item in items})
    rank = {key: i for i, key in enumerate(keys)}
    tree = [(0.0, -1)] * (len(keys) + 1)  # Fenwick tree of (best weight, item index)

    def query(i):
        best = (0.0, -1)
        while i > 0:
            if tree[i][0] > best[0]:
                best = tree[i]
            i -= i & -i
        return best

    def update(i, value):
        while i <= len(keys):
            if value[0] > tree[i][0]:
                tree[i] = value
            i += i & -i

    parent, total = [-1] * len(items), [0.0] * len(items)
    for index, item in enumerate(items):
        position = rank[key_of(item)] + 1
        best, previous = query(position)  # keys <= this one
        total[index] = best + weight_of(item)
        parent[index] = previous
        update(position, (total[index], index))
    if not items:
        return []
    cursor = max(range(len(items)), key=lambda i: total[i])
    chain = []
    while cursor != -1:
        chain.append(items[cursor])
        cursor = parent[cursor]
    return chain[::-1]


# ---------------------------------------------------------------------------
# One volume
# ---------------------------------------------------------------------------

def is_back_cover(text: str) -> bool:
    return all(mark in text for mark in BACK_COVER)


def is_title_page(text: str) -> bool:
    """The page that opens a parah: it starts with its name, "پارہ 4 لن تنالوا",
    and often carries the first heading and ayat too."""
    return text.strip()[:12].startswith(("پارہ", "پاره", "پارد", "پار ه"))


def is_contents_page(text: str) -> bool:
    head = text[:160]
    return any(mark in head for mark in ("فہرست", "نمبر شمار", "صفحہ نمبر", "مندرجات", "مفخخ"))


def page_at(marks: list[tuple[int, int]], position: int) -> int:
    page = marks[0][1]
    for offset, number in marks:
        if offset > position:
            break
        page = number
    return page


def translation_runs(text: str):
    """The book's section openings: Urdu translation in which consecutive
    ayat close with consecutive markers ﴿n﴾ ﴿n+1﴾ ... Returns
    [(run_start, run_end, first_ayah, last_ayah)]. A lone marker is not a run.

    A translation marker closes Urdu. The commentary's markers close the
    Arabic it quotes, and the OCR misreads those numbers freely (﴿۱۵﴾ after
    79:19), so they never make a run."""
    every = [(m.start(), m.end(), int(m.group(1).translate(DIGITS))) for m in MARKER.finditer(text)]

    def closes_urdu(start: int) -> bool:
        before = text[max(0, start - 60):start]
        letters = len(ARABIC_LETTER.findall(before))
        return letters > 0 and len(HARAKA.findall(before)) <= letters * 0.25

    urdu = [closes_urdu(m[0]) for m in every]
    markers = [(m, n) for n, m in enumerate(every) if urdu[n]]
    runs, i = [], 0
    while i < len(markers):
        j = i
        while (j + 1 < len(markers)
               and markers[j + 1][0][2] == markers[j][0][2] + 1
               and markers[j + 1][0][0] - markers[j][0][1] < 900):
            between = text[markers[j][0][1]:markers[j + 1][0][0]]
            if len(HARAKA.findall(between)) > len(between) * 0.05:
                break  # vowelled: Arabic quotation, not translation
            j += 1
        if j > i:
            first, n = markers[i]
            previous_marker = every[n - 1][1] if n > 0 else 0
            paragraph = text.rfind("\n", 0, first[0])
            begin = max(previous_marker, paragraph + 1 if paragraph != -1 else 0)
            # Translation printed straight after the section's Arabic, across a
            # page break, begins where the Arabic block's last ayah closes: a
            # block of several numbered ayat, followed by one unbroken
            # sentence (a commentary quotation is one ayah, and the commentary
            # after it runs on in sentences).
            block = n >= 2 and not urdu[n - 2] and every[n - 1][0] - every[n - 2][1] < 800
            if n > 0 and not urdu[n - 1] and block and begin > previous_marker:
                gap = text[previous_marker:first[0]]
                if (len(gap) < 900 and len(HARAKA.findall(gap)) <= len(gap) * 0.05
                        and not re.search(r"[۔؟!।.]", gap)):
                    begin = previous_marker
                    while begin < len(text) and text[begin].isspace():
                        begin += 1
            runs.append((begin, markers[j][0][1], first[2], markers[j][0][2]))
            i = j + 1
        else:
            i += 1
    return runs


def opening_length(text: str) -> int:
    """Length of a section's opening: its heading, the Arabic of its ayat and
    their numbered translation, which come before any commentary. A section
    is never cut inside it, or the next part would start mid-verse."""
    offset = 0
    for line in text.splitlines():
        stripped = line.strip()
        vowelled = len(HARAKA.findall(stripped)) >= len(stripped) * 0.12
        if stripped and not (vowelled or MARKER.search(stripped) or len(stripped) < 120
                             or has_heading(stripped)):
            break
        offset += len(line) + 1
    return offset


class Volume:
    """One parah volume's commentary as a single text, cut into sections."""

    def __init__(self, parah, pages, first, last, counts, names, mushaf, translations, report):
        self.parah, self.first, self.last = parah, first, last
        self.counts, self.names, self.mushaf = counts, names, mushaf
        self.translations, self.report = translations, report
        self.book = f"tafaseer-parah-{parah}"
        self.all_pages = pages
        self.pages = [p for p in pages if p["text"].strip() and not is_back_cover(p["text"])]
        skipped = [p["page"] for p in pages if is_back_cover(p["text"])]
        if skipped:
            report["backCoverPages"].append(f"{self.book}#{','.join(map(str, skipped))}")

    def ayat(self):
        key = self.first
        while key <= self.last:
            yield key
            key = next_key(key, self.counts)

    def in_range(self, key) -> bool:
        return self.first <= key <= self.last

    # -- text ------------------------------------------------------------

    def join(self, pages):
        parts, marks, offset = [], [], 0
        for page in pages:
            body = OCR_NOTE.sub("", page["text"]).strip()
            if not body:
                continue
            marks.append((offset, page["page"]))
            parts.append(body)
            offset += len(body) + 2
        return "\n\n".join(parts), marks

    def find_content_start(self):
        """Index into self.pages of the first page of commentary: the parah's
        title page, or the page where its first ayat are printed. The cover,
        imprint, preface and contents come before it and are not commentary;
        in parah 1 a preface also follows the contents."""
        front = [i for i, p in enumerate(self.pages[:40]) if is_contents_page(p["text"])]
        after = front[-1] + 1 if front else 0
        text, marks = self.join(self.pages[after:])
        index = TranslationIndex(text)
        opening_ayat = list(self.ayat())[:6]
        candidates = []
        for key in opening_ayat:
            hit = index.locate(self.translations.get(key, ""))
            if hit and hit[0] >= 0.5:
                candidates.append(hit[1])
        candidates += [begin for begin, _, a, _ in translation_runs(text)
                       if (self.first[0], a) in opening_ayat[:4]]
        for h_start, _, name, a, _ in iter_headings(text):
            if (self.names.get(norm_name(name)), a) in opening_ayat[:4]:
                candidates.append(h_start)
        if not candidates:
            self.report["noContentStart"].append(self.book)
            return after
        page = page_at(marks, min(candidates))
        start = next(i for i, p in enumerate(self.pages) if p["page"] == page)
        if start > after + 6:
            # Parah 3 prints a translation of its own, without ayah numbers,
            # so its first ayat cannot be located. Its commentary starts
            # straight after the contents.
            start = after
            while start < len(self.pages) and any(mark in self.pages[start]["text"][:300] for mark in PREFACE):
                start += 1
        if start > after and is_title_page(self.pages[start - 1]["text"]):
            start -= 1
        return start

    # -- openings ----------------------------------------------------------

    def translation_blocks(self, index):
        """Each printed translation block: [(start, end, first_key, last_key, weight)]."""
        hits = []
        for key in self.ayat():
            hit = index.locate(self.translations.get(key, ""))
            if hit and hit[0] >= 0.5:
                hits.append((hit[1], hit[2], key, hit[0]))
        hits = sorted((snap_to_line(index.text, start), end, key, score) for start, end, key, score in hits)
        chain = weighted_chain(hits, key_of=lambda h: h[2], weight_of=lambda h: h[3])
        blocks = []
        for start, end, key, score in chain:
            if blocks:
                b_start, b_end, b_first, b_last, b_weight = blocks[-1]
                if key == (b_last[0], b_last[1] + 1) and start - b_end < 350:
                    blocks[-1] = (b_start, max(b_end, end), b_first, key, b_weight + score)
                    continue
            blocks.append((start, end, key, key, score))
        return blocks

    def surah_from_evidence(self, begin, end, a, b, evidence):
        """The one surah in which ayat a..b were translated or quoted around
        a marker run, or None."""
        found = {key[0] for position, key in evidence
                 if begin - 4000 <= position <= end + 2500 and a <= key[1] <= b}
        return found.pop() if len(found) == 1 else None

    def openings(self, text):
        index = TranslationIndex(text)
        blocks = self.translation_blocks(index)
        quotes = []
        for match in QUOTE.finditer(text):
            if len(HARAKA.findall(match.group(1))) < 4:
                continue
            hit = self.mushaf.best(match.group(1), self.first, self.last)
            if hit:
                quotes.append((match.start(), hit[0]))
        for start, end in quranic_runs(text):
            hit = self.mushaf.best(text[start:end], self.first, self.last)
            if hit:
                quotes.append((start, hit[0]))
        quotes.sort()
        evidence = quotes + [(b[0], key) for b in blocks for key in (b[2], b[3])]

        # (position, first key, weight, kind, end of the opening, its last key)
        candidates = []
        for start, end, first_key, last_key, weight in blocks:
            candidates.append((start, first_key, 1.0 + weight, "translation", end, last_key))
        for h_start, h_end, name, a, b in iter_headings(text):
            surah = self.names.get(norm_name(name))
            if surah is None:
                continue
            # The heading's first ayah places it; its last is only a hint, and
            # the OCR misreads it more often (۶ as ۶۲).
            if 1 <= a <= self.counts[surah] and self.in_range((surah, a)):
                last_key = max((surah, a), min((surah, min(b, self.counts[surah])), self.last))
                candidates.append((h_start, (surah, a), 1.5, "heading", h_end, last_key))
        for match in TITLE_BOX.finditer(text):
            surah = self.names.get(norm_name(match.group(1)))
            if surah is not None and self.in_range((surah, 1)):
                candidates.append((match.start(), (surah, 1), 2.0, "title", match.end(), (surah, 1)))
        # "خلاصہ تفسیر و معارف" / "خلاصہ رکوع" closes a section's translation.
        # Parah 3 prints its translation without ayah numbers, so this line is
        # its only mark of where a section begins; the ayah is the first one
        # the commentary after it quotes, and the section starts where that
        # ayah's translation does, just before the line.
        for match in SUMMARY.finditer(text):
            after = [key for position, key in quotes if match.end() <= position < match.end() + 6000]
            if not after:
                continue
            key = after[0]
            window_start = max(0, match.start() - 6000)
            local = TranslationIndex(text[window_start:match.start()])
            hit = local.locate(self.translations.get(key, ""))
            if not hit or hit[0] < 0.12:
                continue
            start = snap_to_line(text, window_start + hit[1])
            candidates.append((start, key, 1.2, "summary", match.end(), key))
        for begin, end, a, b in translation_runs(text):
            surah = self.surah_from_evidence(begin, end, a, b, evidence)
            if surah is not None:
                if b <= self.counts[surah] and self.in_range((surah, a)):
                    candidates.append((begin, (surah, a), 0.5 + 0.5 * (b - a + 1), "markers", end, (surah, b)))
                continue
            # No translation or quotation names the surah: offer the run to
            # every surah of the volume it fits, lightly; the mushaf order
            # decides which one, if any, it belongs to.
            for surah in range(self.first[0], self.last[0] + 1):
                if b <= self.counts[surah] and self.in_range((surah, a)) and self.in_range((surah, b)):
                    candidates.append((begin, (surah, a), 0.3 * (b - a + 1), "markers", end, (surah, b)))
        candidates.sort()
        chain = weighted_chain(candidates, key_of=lambda c: c[1], weight_of=lambda c: c[2])

        # The same ayah can be claimed at several places: its real opening,
        # and a quotation in the commentary before it whose number the OCR
        # misread (﴿۱﴾ for ﴿۴۲﴾). The strongest claim is the opening; an
        # earlier one is kept only when it is the heading just above it.
        grouped = []
        for candidate in chain:
            if grouped and grouped[-1][-1][1] == candidate[1]:
                grouped[-1].append(candidate)
            else:
                grouped.append([candidate])
        chain = []
        for group in grouped:
            strongest = max(group, key=lambda c: c[2])
            heading = [c for c in group if c[3] in ("heading", "title") and strongest[0] - 4000 <= c[0] < strongest[0]]
            chain.extend(heading[:1] + [strongest])

        # Signals for one opening agree in place: a heading, the marker run
        # and the located translation of the same ayat. An opening that lies
        # inside, or within an ayah's translation after, the previous one's
        # heading and translation, and continues its ayat, is the same
        # opening: commentary never starts that close. The earliest position
        # wins.
        openings = []
        for position, key, weight, kind, end, last_key in chain:
            if openings:
                current = openings[-1]
                # A misread number (﴿۳۲﴾ for ﴿۳۴﴾) breaks a marker run in two;
                # the halves still sit in one block of translation.
                reach = (current[4][0], current[4][1] + 3)
                if position < current[3] + 600 and current[4][0] == key[0] and key <= reach:
                    current[3] = max(current[3], end)
                    current[4] = max(current[4], last_key)
                    continue
            openings.append([position, key, kind, end, last_key])
        self.report["openingKinds"][self.book] = dict(sorted(
            {kind: sum(1 for o in openings if o[2] == kind) for kind in {o[2] for o in openings}}.items()))
        return openings, quotes

    def surah_page_start(self, position, floor):
        """Where a surah begins whose first ayat could not be located: the
        page the OCR read badly (a few lines in Arabic letters, or nearly
        empty) that holds them, when the first located ayah is at the top of
        the next page or on such a page itself."""
        index = max(i for i, (offset, _) in enumerate(self.marks) if offset <= position)
        page_start = self.marks[index][0]
        page_end = self.marks[index + 1][0] if index + 1 < len(self.marks) else len(self.text)
        if page_end - page_start < 700:
            return max(floor + 1, page_start)
        if position - page_start < 400 and index > 0:
            previous_start = self.marks[index - 1][0]
            if page_start - previous_start < 700:
                return max(floor + 1, previous_start)
            return max(floor + 1, page_start)
        return position

    def widen_opening(self, text, floor, position, key, quotes):
        """Move an opening back over the section's own heading and the Arabic
        block of its ayat printed just before the translation."""
        start = position
        probe = text.rfind("\n\n", floor, start)
        while probe > floor and start - probe < 4000:
            block = text[probe:start]
            if len(HARAKA.findall(block)) < len(block) * 0.12 and not has_heading(block):
                break
            # The block must not be quoting the previous section's ayat.
            if any(probe <= p < start and k < key for p, k in quotes):
                break
            start = probe + 2
            probe = text.rfind("\n\n", floor, probe)
        return start

    # -- rows --------------------------------------------------------------

    def build(self):
        start = self.find_content_start()
        content = self.pages[start:]
        self.title_page = content[0]["page"] if content and is_title_page(content[0]["text"]) else None
        text, marks = self.join(content)
        self.text, self.marks = text, marks
        openings, quotes = self.openings(text)

        # A new surah's opening heading is often a page the OCR left blank; its
        # muqatta'at ayah is too short to locate. A section that begins a new
        # surah within its first ayat begins it at ayah 1.
        previous = None
        for opening in openings:
            surah, ayah = opening[1]
            if previous is not None and surah != previous[1][0] and 1 < ayah <= 8:
                opening[1] = (surah, 1)
                opening[0] = self.surah_page_start(opening[0], previous[0])
            previous = opening
        # Drop keys a fix-up made equal.
        unique = []
        for opening in openings:
            if unique and unique[-1][1] >= opening[1]:
                continue
            unique.append(opening)
        openings = unique

        floor = 0
        for opening in openings:
            widened = self.widen_opening(text, floor, snap_to_line(text, opening[0]), opening[1], quotes)
            opening[0] = max(floor, widened)
            floor = opening[0] + 1

        # A section holding next to nothing - a heading, or a muqatta'at ayah
        # with its marker - is the start of the section after it.
        merged = []
        for i, opening in enumerate(openings):
            if merged:
                previous = merged[-1]
                body = text[previous[0]:opening[0]]
                if len(fold_letters(body)[0]) < 40 and opening[1][0] == previous[1][0]:
                    continue  # the previous opening's key now covers this section
            merged.append(opening)
        openings = merged

        # The volume's first ayah owns everything before the first opening.
        if not openings or openings[0][1] != self.first:
            openings.insert(0, [0, self.first, "volume-start", 0, self.first])
        else:
            lead = text[:openings[0][0]]
            if len(fold_letters(lead)[0]) >= 120:
                openings[0][0] = 0
        self.openings_final = openings

        sections = []
        for i, (position, key, kind, _, _) in enumerate(openings):
            following = openings[i + 1] if i + 1 < len(openings) else None
            surah, ayah = key
            if following is None:
                if surah != self.last[0]:
                    self.report["unresolvedSurahOpenings"].append(f"{self.book}: after {surah}:{ayah} to volume end {self.last}")
                stop = self.last[1] if surah == self.last[0] else self.counts[surah]
                finish = len(text)
            else:
                f_surah, f_ayah = following[1]
                finish = following[0]
                if f_surah == surah:
                    stop = f_ayah - 1
                else:
                    stop = self.counts[surah]
                    if (f_surah, f_ayah) != (surah + 1, 1):
                        self.report["unresolvedSurahOpenings"].append(
                            f"{self.book}: {surah}:{ayah} is followed by {f_surah}:{f_ayah}")
            sections.append((position, finish, surah, ayah, stop, kind))
        return sections

    def rows(self):
        sections = self.build()
        text = self.text
        out = []
        for position, finish, surah, ayah, stop, kind in sections:
            raw = text[position:finish]
            body = clean(raw)
            body, whole = correct_quotations(body, (surah, ayah), (surah, stop), self.mushaf)
            body, parts_fixed = correct_fragments(body, (surah, ayah), (surah, stop), self.mushaf)
            # First over the whole section (its markers are listed only after
            # the second pass, row by row, below).
            body, cited = correct_citations(body, (surah, ayah), (surah, stop), self.mushaf,
                                            f"{surah}:{ayah}-{stop}", defaultdict(list))
            self.report["quotationsReplacedWithMushaf"] += whole
            self.report["fragmentsReplacedWithMushaf"] += parts_fixed
            self.report["citationsReplacedWithMushaf"] += cited["quotations"]
            self.report["crossReferencesReplacedWithMushaf"] += cited["crossReferences"]
            self.report["markersRenumbered"] += cited["markers"]
            self.report["markersRenumberedByRow"] += cited["markersByRow"]
            self.report["citationsMatchedWithoutAnEdgeWord"] += cited["edgeTrimmed"]
            body = body.strip()
            if len(fold_letters(body)[0]) < 20:
                if body:
                    self.report["tinySections"].append(f"{surah}:{ayah}-{stop} {body[:60]!r}")
                continue
            for part_ayah, part_end, part in self.split(body, surah, ayah, stop):
                part, settled = correct_citations(part, (surah, part_ayah), (surah, part_end), self.mushaf,
                                                  f"{surah}:{part_ayah}-{part_end}", self.report)
                self.report["markersRenumbered"] += settled["markers"]
                self.report["markersRenumberedByRow"] += settled["markersByRow"]
                out.append({"editionID": EDITION, "surahNumber": surah, "ayahStart": part_ayah,
                            "ayahEnd": part_end, "text": part, "sourceUrl": SOURCE_URL})
        return out

    def split(self, body, surah, ayah, stop):
        """A section over budget is cut where its commentary turns to a later
        ayah of its range, judged by the Arabic it quotes; never inside its
        opening (heading, Arabic and translation)."""
        if len(body.encode()) <= MAX_ROW_BYTES or stop == ayah:
            parts = [(ayah, body)]
        else:
            cuts = []
            opening_end = opening_length(body)
            spans = [(m.start(), m.group(1)) for m in QUOTE.finditer(body)
                     if len(HARAKA.findall(m.group(1))) >= 4]
            spans += [(s, body[s:e]) for s, e in quranic_runs(body)]
            spans.sort()
            hits = []
            for start, quote in spans:
                if start <= opening_end:
                    continue
                hit = self.mushaf.best(quote, (surah, ayah), (surah, stop))
                if hit:
                    hits.append((start, hit[0][1], len(quote)))
            for index, (start, quoted, size) in enumerate(hits):
                if quoted <= (cuts[-1][1] if cuts else ayah):
                    continue
                # A quotation ahead of the commentary - a heading that takes the
                # section's last ayah as its theme before the commentary on the
                # first (2:21-29 opens on 2:29) - is not where the commentary
                # turns to that ayah: what follows it still quotes the ayat
                # before. Such a cut would file their commentary under it.
                behind = sum(other_size for _, other, other_size in hits[index + 1:] if other < quoted)
                onward = size + sum(other_size for _, other, other_size in hits[index + 1:] if other >= quoted)
                if behind > onward:
                    continue
                paragraph = body.rfind("\n", 0, start)
                cut = paragraph + 1 if paragraph != -1 else snap_to_line(body, start)
                # A short heading over the quotation ("آیت الکرسی") goes with it.
                above = body.rfind("\n\n", 0, max(0, cut - 2))
                heading = body[above + 2:cut].strip() if above != -1 else ""
                if heading and len(heading) < 80 and not heading.endswith(("۔", "؟", "!", ".")):
                    cut = above + 2
                cuts.append((cut, quoted))
            parts, cursor, current = [], 0, ayah
            for cut, next_ayah in cuts:
                if cut <= cursor:
                    continue
                parts.append((current, body[cursor:cut]))
                cursor, current = cut, next_ayah
            parts.append((current, body[cursor:]))
            self.report["oversizeSplits"] += len(parts) - 1
        result = []
        for index, (part_ayah, part) in enumerate(parts):
            part_end = parts[index + 1][0] - 1 if index + 1 < len(parts) else stop
            part = part.strip()
            if not part:
                continue
            size = len(part.encode())
            if size > MAX_ROW_BYTES:
                self.report["overBudgetRows"].append(f"{surah}:{part_ayah}-{part_end} {size // 1024} KB")
            if size > HARD_ROW_BYTES:
                self.report["overHardLimit"].append(f"{surah}:{part_ayah}-{part_end} {size // 1024} KB")
            result.append((part_ayah, part_end, part))
        return result

    def start_pages(self):
        """Where each surah's commentary begins in this volume."""
        pages = {}
        for position, key, kind, _, _ in self.openings_final:
            surah, ayah = key
            if surah in pages:
                continue
            if key == self.first and self.title_page is not None:
                pages[surah] = self.title_page
            elif key == self.first:
                pages[surah] = self.marks[0][1]
            else:
                pages[surah] = page_at(self.marks, position)
        return pages


# ---------------------------------------------------------------------------
# Cuts read by eye
# ---------------------------------------------------------------------------

# Where the book's section structure was read by a person (November 2026) and
# the automatic cut filed commentary under a later ayah. Each entry names the
# rows a stretch of a surah becomes: (first ayah, last ayah, where the row
# starts). The rows the cutter made for that stretch are joined and cut again at
# these places, so only row boundaries move; no word changes. A "|" marks the
# cut inside text quoted to make the place unique; without one the row starts
# at the quoted text. A stretch that no longer fits (a re-read changed its
# words) stops the build, so a cut is never guessed.
SECTION_CORRECTIONS = [
    # The volume glosses 2:35-39 first (it closes: this is the plain translation), then comments on 2:35-36; the commentary on 2:37 opens at this quotation.
    (2, [
        (35, 36, None),
        (37, 38, 'فَتَلَقّٰٓى اٰدَمُ مِنْ رَّبِّهٖ كَلِمٰتٍ آدم'),
    ]),
    # The commentary quotes 2:194 and 2:195 before this first quotation of 2:196.
    (2, [
        (193, 195, None),
        (196, 196, 'وَاَتِمُّوا الْحَجَّ وَالْعُمْرَةَ لِلّٰهِؕ احسان '),
    ]),
    # Section opening 2:261-266; the commentary on 2:261-262 runs up to this first quotation of 2:263.
    (2, [
        (261, 262, None),
        (263, 266, 'قَوْلٌ مَّعْرُوْفٌ وَّمَغْفِرَةٌ خَيْرٌ مِّنْ صَدَقَةٍ يَّتْبَعُهَاۤ اَذًى ؕ ایس'),
    ]),
    # Section opening 2:280-283; the commentary on 2:280-282 runs up to this heading over 2:283.
    (2, [
        (280, 282, None),
        (283, 283, 'رہن کی صورت استفادہ جائز '),
    ]),
    # Printed sections 3:1-4, 3:5-9 and 3:10-11, each its Arabic, translation and commentary; the commentary quotes each ayah at these places.
    (3, [
        (1, 4, None),
        (5, 6, 'اِنَّ اللّٰهَ لَا يَخْفٰى عَلَيْهِ شَىْءٌ فِى الْاَرْضِ وَلَا فِى السَّمَآءِ ؕ﴿'),
        (7, 7, 'هُوَ الَّذِىْۤ اَنْزَلَ عَلَيْكَ الْكِتٰبَ اے'),
        (8, 9, 'نفرت کرنے لگتا ہے۔\n\n|دلوں کے ٹیڑھے پن کا علاج'),
        (10, 10, ' حشر فرمائے۔ آمین!\n\n|اِنَّ الَّذِيْنَ كَفَرُوْ'),
        (11, 11, 'یندھن بننا پڑے گا۔\n\n|تاریخ سے عبرت حاصل کرو'),
    ]),
    # Section opening 3:65-71 was cut in three, its commentary filed under 3:71-72; 3:72-74 opens a section of its own.
    (3, [
        (65, 67, None),
        (68, 70, 'اِنَّ اَوْلَى النَّاسِ بِاِبْرٰهِيْمَ لَـلَّذِيْنَ اتَّ'),
        (71, 71, 'ہ وہ خود گواہ ہیں۔\n\n|يٰۤـاَهْلَ الْكِتٰبِ لِمَ'),
        (72, 74, 'وَقَالَتْ طَّآئِفَةٌ مِّن'),
    ]),
    # The commentary on 3:78 runs up to this heading over 3:79.
    (3, [
        (78, 78, None),
        (79, 79, 'کسی نبی نے اپنی بندگی کی '),
    ]),
    # Section opening 3:83-91; the commentary on 3:83-86 runs up to this first quotation of 3:87.
    (3, [
        (83, 86, None),
        (87, 87, 'دعوے دار بن بیٹھے۔\n\n|اُولٰٓٮِٕكَ جَزَآؤُهُمْ '),
    ]),
    # The commentary on 3:135 runs up to this first quotation of 3:136.
    (3, [
        (135, 135, None),
        (136, 139, 'اُولٰٓٮِٕكَ جَزَآؤُهُمْ مَّغْفِرَةٌ مِّنْ رَّبِّهِمْ ا'),
    ]),
    # Printed heading 5:20-26; the commentary on 5:20-22 runs up to this first quotation of 5:23.
    (5, [
        (20, 22, None),
        (23, 26, 'لئے قوت دے دیتا ہے۔ |قَالَ رَجُلٰنِ مِنَ الَّذ'),
    ]),
    # The commentary on 5:61-62 runs up to this quotation of 5:63.
    (5, [
        (60, 62, None),
        (63, 63, 'لَوْلَا يَنْهٰٮهُمُ الرَّ'),
    ]),
    # Printed heading 5:116-120; the commentary on 5:116-119 runs up to this first quotation of 5:120.
    (5, [
        (116, 119, None),
        (120, 120, 'یں پہنچ جایا جائے۔\n\n|لِلّٰهِ مُلْكُ السَّمٰوٰت'),
    ]),
    # Printed heading 9:25-29; the account of Hunayn on 9:25 runs on to this quotation of 9:26, and 9:26's to this quotation of 9:27. Both old cuts fell mid-sentence.
    (9, [
        (25, 25, None),
        (26, 26, 'ثُمَّ اَنْزَلَ اللّٰهُ سَكِيْنَـتَهٗ عَلٰى رَسُوْلِهٖ ج'),
        (27, 27, 'ثُمَّ يَتُوْبُ اللّٰهُ مِنْۢ بَعْدِ ذٰلِكَ عَلَى مَنْ يَّشَآءُ ا'),
    ]),
    # The commentary on 11:1 runs up to this first quotation of 11:2.
    (11, [
        (1, 1, None),
        (2, 2, 'تو فرمایا یاد رکھو اللّٰه'),
    ]),
    # The rest of the section's translation and the commentary on 21:76 run up to this first quotation of 21:77.
    (21, [
        (75, 76, None),
        (77, 77, 'فرمایا: وَنَصَرْنٰهُ مِنَ'),
    ]),
    # ------------------------------------------------------------------------
    # Row boundaries reviewed one by one, November 2026. Each cut that follows
    # moved to where the commentary turns to its ayah: the ayah's first quotation
    # (with the words that lead in to it), a sentence's end, or the section's
    # heading and translation that had been left at the end of the row before.
    # A rule for this was tried and rejected: by the review about one cut in six
    # needed a person (a quotation's first words shared with another ayah, a gloss
    # before the Arabic, a heading the OCR lost), so the places are listed here.
    #
    # Left as printed: 96:3-5, because the volume reprints 96:1-5 there. Surahs 63,
    # 64, 67, 79 and 81 keep their older rows (see the recovery notes), so no cut
    # is listed for them.
    (2, [
        (1, 1, None),
        (2, 2, 'خلاصہ تفسیر وم'),
    ]),
    (2, [
        (17, 17, None),
        (18, 18, 'ان کا حال تو ی'),
    ]),
    (2, [
        (25, 25, None),
        (26, 26, 'امثالِ قرآنی:\n'),
    ]),
    (2, [
        (27, 27, None),
        (28, 28, 'كَيْفَ تَكْفُرُوْنَ بِاللّٰهِ لو'),
    ]),
    (2, [
        (31, 31, None),
        (32, 32, 'قَالُوْا سُبْح'),
    ]),
    (2, [
        (42, 42, None),
        (43, 43, 'وَاَقِيْمُوا ا'),
        (44, 44, 'اَتَاْمُرُوْنَ'),
    ]),
    (2, [
        (47, 47, None),
        (48, 48, 'پھر تمہیں یہ خ'),
    ]),
    (2, [
        (49, 49, None),
        (50, 50, 'وَاِذْ فَرَقْنَا بِكُمُ الْبَحْرَ جب ہ'),
    ]),
    (2, [
        (55, 55, None),
        (56, 56, 'فرمایا: ثُمَّ '),
    ]),
    (2, [
        (65, 65, None),
        (66, 66, 'فَجَعَلْنٰهَا '),
        (67, 67, 'وَاِذْ قَالَ م'),
        (68, 68, 'بے جا استفسار:'),
        (69, 70, 'قَالُوا ادْعُ لَنَا رَبَّكَ يُبَيِّنْ لَّنَا مَا لَوْنُهَا ط پ'),
        (71, 71, 'قَالَ اِنَّهٗ يَقُوْلُ اِنَّهَا بَقَرَةٌ لَّا ذَلُ'),
    ]),
    (2, [
        (87, 87, None),
        (88, 88, 'اور تم نے کہا:'),
    ]),
    (2, [
        (92, 93, None),
        (94, 94, 'فرمایا میرے حب'),
    ]),
    (2, [
        (102, 102, None),
        (103, 103, 'حق تو یہ تھا و'),
    ]),
    (2, [
        (105, 105, None),
        (106, 106, 'فرمایا: مَا نَ'),
        (107, 107, 'اَلَمْ تَعْلَمْ اَنَّ اللّٰهَ لَ'),
        (108, 108, 'اَمْ تُرِيْدُوْنَ اَنْ تَسْـَٔـلُوْا رَسُوْلَـكُمْ كَمَا سُٮِٕلَ مُوْسٰى مِنْ قَبْلُ ۔'),
    ]),
    (2, [
        (119, 119, None),
        (120, 120, 'یہی حال دوسری '),
    ]),
    (2, [
        (122, 123, None),
        (124, 124, 'خلیل اللہؑ کے '),
    ]),
    (2, [
        (127, 127, None),
        (128, 128, 'رَبَّنَا وَاجْعَلْنَا مُسْلِمَيْنِ لَـكَ وَ '),
        (129, 129, 'پھر وہ دعا فرم'),
    ]),
    (2, [
        (145, 145, None),
        (146, 146, 'اس لیے کہ اَلّ'),
    ]),
    (2, [
        (166, 166, None),
        (167, 167, 'پیروکار اپنے پ'),
    ]),
    (2, [
        (174, 174, None),
        (175, 175, 'فرمایا: اُولٰٓ'),
    ]),
    (2, [
        (183, 183, None),
        (184, 184, 'فرمایا: اَيَّا'),
    ]),
    (2, [
        (186, 186, None),
        (187, 187, 'فرمایا: اُحِلّ'),
    ]),
    (2, [
        (191, 191, None),
        (192, 192, 'فَاِنِ انْـتَهَوْا فَاِنَّ اللّٰهَ غَفُوْرٌ رَّحِيْمٌ\u200f ﴿١٩٢﴾ ا'),
    ]),
    (2, [
        (200, 200, None),
        (201, 202, 'وَمِنْهُمْ اور'),
    ]),
    (2, [
        (205, 205, None),
        (206, 206, 'اور پھر ان میں'),
    ]),
    (2, [
        (253, 253, None),
        (254, 254, 'يٰۤـاَيُّهَا الَّذِيْنَ اٰمَنُوْۤا اَن'),
    ]),
    (3, [
        (80, 80, None),
        (81, 81, 'وَاِذْ اَخَذَ اللّٰهُ مِيْثَاقَ النَّبِيّٖنَ لَمَا'),
    ]),
    (3, [
        (92, 92, None),
        (93, 94, 'كُلُّ الطَّعَامِ كَانَ حِلًّا لِّبَنِىْۤ اِسْرَآءِيْلَ اِلَّا مَا حَرَّمَ اِسْرَآءِيْلُ عَلٰى نَفْسِهٖ مِنْ قَبْلِ اَنْ تُنَزَّلَ التَّوْرٰٮةُ رہ'),
    ]),
    (3, [
        (106, 106, None),
        (107, 108, 'اور وَاَمَّا ا'),
    ]),
    (3, [
        (113, 113, None),
        (114, 114, 'يُؤْمِنُوْنَ ب'),
        (115, 115, 'وَمَا يَفْعَلُ'),
    ]),
    (3, [
        (121, 121, None),
        (122, 122, 'اِذْ هَمَّتْ طَّآٮِٕفَتٰنِ مِنْكُمْ اَنْ تَفْشَلَا\u2002ۙ وَاللّٰهُ وَلِيُّهُمَا ؕ وَعَلَى اللّٰهِ فَلْيَتَوَكَّلِ الْمُؤْمِنُوْنَ\u200f ﴿۱۲۲﴾ انصار '),
    ]),
    (3, [
        (149, 149, None),
        (150, 150, 'بَلِ اللّٰهُ مَوْلٰٮكُمْ ف'),
    ]),
    (3, [
        (156, 156, None),
        (157, 157, 'وَلَٮِٕنْ قُتِلْتُمْ فِىْ سَبِيْلِ اللّٰهِ اَوْ مُتُّمْ لَمَغْفِرَةٌ مِّنَ اللّٰهِ وَرَحْمَةٌ خَيْرٌ مِّمَّا يَجْمَعُوْنَ\u200f ﴿۱۵۷﴾ یہ تو'),
    ]),
    (3, [
        (168, 170, None),
        (171, 171, 'بلکہ يَسْتَبْش'),
    ]),
    (3, [
        (182, 182, None),
        (183, 184, 'اَلَّذِيْنَ قَالُوْۤا اِنَّ اللّٰهَ عَهِدَ ا'),
    ]),
    (3, [
        (191, 191, None),
        (192, 192, 'رَبَّنَاۤ اِنّ'),
    ]),
    (3, [
        (193, 193, None),
        (194, 194, 'رَبَّنَا وَاٰتِنَا مَا وَعَدتَّنَا عَلٰى رُسُلِكَ وَلَا '),
        (195, 195, 'فَاسْتَجَابَ ل'),
    ]),
    (4, [
        (19, 19, None),
        (20, 20, 'وان اردتم استب'),
    ]),
    (4, [
        (26, 26, None),
        (27, 27, 'وَاللّٰهُ يُرِيْدُ اَنْ يَّتُوْبَ عَلَيْكُمْ\ue01e اللہ'),
    ]),
    (4, [
        (29, 29, None),
        (30, 30, 'وَمَنْ يَّفْعَ'),
    ]),
    (4, [
        (35, 35, None),
        (36, 36, 'اصل بات یہ ہے '),
        (37, 37, 'اۨلَّذِيْنَ يَ'),
    ]),
    (4, [
        (39, 39, None),
        (40, 40, 'اِنَّ اللّٰهَ '),
    ]),
    (4, [
        (42, 42, None),
        (43, 43, 'النساء آیات 43'),
    ]),
    (4, [
        (50, 50, None),
        (51, 51, 'سورۃ النساء آی'),
    ]),
    (4, [
        (53, 53, None),
        (54, 54, 'اَمْ يَحْسُدُو'),
    ]),
    (4, [
        (57, 57, None),
        (58, 58, 'اِنَّ اللّٰهَ يَاْمُ'),
    ]),
    (4, [
        (59, 59, None),
        (60, 60, 'النساء آیات 60'),
        (61, 61, 'وَاِذَا قِيْلَ لَهُمْ تَعَالَوْا اِلٰى مَاۤ اَنْزَلَ اللّٰهُ ج'),
        (62, 62, 'فَكَيْفَ اِذَاۤ اَصَابَتْهُمْ مُّصِيْبَةٌ ۢ بِمَا قَدَّمَتْ اَيْدِيْهِمْ ثُمَّ جَآءُوْكَ يَحْلِفُوْنَ ا'),
    ]),
    (4, [
        (63, 63, None),
        (64, 64, 'وَمَاۤ اَرْسَل'),
    ]),
    (4, [
        (70, 70, None),
        (71, 71, 'النساء آیات 71'),
    ]),
    (4, [
        (76, 76, None),
        (77, 77, 'النساء آیات 77'),
        (78, 78, 'اَيْنَ مَا تَكُوْنُوْا يُدْرِكْكُّمُ الْمَوْتُ وَلَوْ كُنْتُمْ فِىْ بُرُوْجٍ مُّشَيَّدَةٍ تم'),
        (79, 79, 'مَاۤ اَصَابَكَ مِنْ حَسَنَةٍ فَمِنَ اللّٰهِ ز اے ا'),
    ]),
    (4, [
        (83, 83, None),
        (84, 84, 'اور فَقَاتِلْ '),
    ]),
    (4, [
        (97, 97, None),
        (98, 98, 'اِلَّا الْمُسْتَضْعَفِيْنَ مِنَ الرِّجَالِ\n\n'),
        (99, 100, 'فَاُولٰٓٮِٕكَ عَسَى اللّٰهُ اَنْ يَّعْفُوَ عَنْهُمْ ؕ وَكَانَ اللّٰهُ عَفُوًّا غَفُوْرًا\u200f ﴿۹۹﴾ تو '),
    ]),
    (4, [
        (101, 101, None),
        (102, 102, 'وَاِذَا كُنْتَ فِيْهِمْ فَاَقَمْتَ لَهُمُ الصَّلٰوةَ فَلْتَقُمْ طَآٮِٕفَةٌ مِّنْهُمْ مَّعَكَ وَلْيَاْخُذُوْۤا اَسْلِحَتَهُمْ\ue01e فرمایا '),
    ]),
    (4, [
        (105, 105, None),
        (106, 106, 'وَّاسْتَغْفِرِ'),
    ]),
    (4, [
        (107, 107, None),
        (108, 108, 'یہ تو ایسے لوگ'),
    ]),
    (4, [
        (110, 110, None),
        (111, 111, 'وَمَنْ يَّكْسِ'),
    ]),
    (4, [
        (118, 119, None),
        (120, 122, 'يَعِدُهُمْ الش'),
        (123, 123, 'لَـيْسَ بِاَمَ'),
    ]),
    (4, [
        (124, 124, None),
        (125, 125, 'وَمَنْ اَحْسَن'),
        (126, 126, 'اس لئے کہ اللہ'),
    ]),
    (4, [
        (154, 154, None),
        (155, 155, 'فَبِمَا نَقْضِ'),
    ]),
    (4, [
        (157, 157, None),
        (158, 158, 'بَلْ رَّفَعَهُ'),
        (159, 159, 'وَاِنْ مِّنْ ا'),
    ]),
    (4, [
        (160, 160, None),
        (161, 161, 'وَّاَخْذِهِمُ '),
        (162, 162, 'ایسے لوگوں کے '),
    ]),
    (4, [
        (163, 163, None),
        (164, 165, 'وَرُسُلًا قَدْ قَصَصْنٰهُمْ عَلَيْكَ مِنْ قَبْلُ وَرُسُلًا لَّمْ نَقْصُصْهُمْ عَلَيْكَ یہ تو'),
    ]),
    (4, [
        (166, 166, None),
        (167, 167, 'اِنَّ الَّذِيْ'),
    ]),
    (4, [
        (168, 168, None),
        (169, 169, 'اِلَّا طَرِيْق'),
    ]),
    (4, [
        (172, 172, None),
        (173, 173, 'فَاَمَّا الَّذِيْنَ اٰمَنُوْا وَعَمِلُوا الصّٰلِحٰتِ فَيُوَفِّيْهِمْ اُجُوْرَهُمْ وَ يَزِيْدُهُمْ مِّنْ فَضْلِهٖ آدم'),
    ]),
    (4, [
        (174, 174, None),
        (175, 175, 'فرمایا: فَاَمّ'),
    ]),
    (5, [
        (12, 12, None),
        (13, 13, 'فَبِمَا نَقْضِهِمْ مِّيْثَاقَهُمْ جب ا'),
    ]),
    (5, [
        (27, 27, None),
        (28, 29, 'لَٮِٕنْۢ بَسَطْتَّ اِلَىَّ يَدَكَ لِتَقْتُلَنِىْ مَاۤ اَنَا بِبَاسِطٍ يَّدِىَ اِلَيْكَ لِاَقْتُلَكَ تونے'),
    ]),
    (5, [
        (36, 36, None),
        (37, 37, 'يُرِيْدُوْنَ ا'),
    ]),
    (5, [
        (39, 39, None),
        (40, 40, 'اَلَمْ تَعْلَم'),
    ]),
    (5, [
        (41, 41, None),
        (42, 42, 'سَمّٰعُوْنَ لِلْكَذِبِ اَ '),
        (43, 43, 'وَكَيْفَ يُحَك'),
    ]),
    (5, [
        (46, 46, None),
        (47, 47, 'وَلْيَحْكُمْ ا'),
        (48, 48, 'وَاَنْزَلْنَاۤ اِلَيْكَ الْكِتٰبَ بِالْحَـقِّ اللہ'),
    ]),
    (5, [
        (51, 51, None),
        (52, 52, 'فَتَـرَى الَّذِيْنَ فِىْ قُلُوْبِهِمْ مَّرَضٌ آپ ا'),
    ]),
    (5, [
        (55, 55, None),
        (56, 56, 'وَمَنْ يَّتَوَ'),
    ]),
    (5, [
        (68, 68, None),
        (69, 69, 'یہ میرا وعدہ ہ'),
    ]),
    (5, [
        (73, 73, None),
        (74, 75, 'اَفَلَا يَتُوْ'),
        (76, 76, 'قُلْ اَ تَعْبُ'),
    ]),
    (5, [
        (88, 88, None),
        (89, 89, 'لَا يُؤَاخِذُك'),
    ]),
    (5, [
        (112, 113, None),
        (114, 115, 'حضرت عیسیٰؑ نے'),
    ]),
    (6, [
        (11, 11, None),
        (12, 12, 'قُلْ لِّمَنْ مَّا فِى السَّمٰوٰتِ وَالْاَرْضِ ؕ ان'),
    ]),
    (6, [
        (17, 17, None),
        (18, 18, 'الْقَاهِرُ فَو'),
    ]),
    (6, [
        (22, 24, None),
        (25, 25, 'وَمِنْهُمْ مَّ'),
    ]),
    (6, [
        (31, 31, None),
        (32, 32, 'وَمَا الْحَيٰو'),
        (33, 33, 'قَدْ نَـعْلَمُ اِنَّهٗ لَيَحْزُنُكَ فر'),
    ]),
    (6, [
        (57, 57, None),
        (58, 58, 'قُلْ لَّوْ اَن'),
    ]),
    (6, [
        (75, 75, None),
        (76, 76, 'آپؑ اپنی قوم ک'),
    ]),
    (6, [
        (78, 78, None),
        (79, 79, 'میں اس سے بری ہوں او'),
    ]),
    (6, [
        (91, 91, None),
        (92, 92, 'قرآن حکیم میں تجلیات'),
    ]),
    (6, [
        (102, 102, None),
        (103, 103, 'لَا تُدْرِكُهُ الْاَبْصَارُ\ue01a وَهُوَ يُدْرِكُ الْاَبْصَارَ اب ت'),
        (104, 104, 'آگے فرمایا قَد'),
    ]),
    (6, [
        (105, 105, None),
        (106, 106, 'یہ تو لوگوں کا'),
        (107, 107, 'اس لئے آگے بڑی'),
        (108, 108, 'وَلَا تَسُبُّوا الَّذِيْنَ يَدْعُوْنَ مِنْ دُوْنِ اللّٰهِ تَسُ'),
        (109, 109, 'وَاَقْسَمُوْا '),
        (110, 110, 'یہاں بھی وہی ب'),
    ]),
    (6, [
        (115, 115, None),
        (116, 116, 'وَاِنْ تُطِعْ '),
        (117, 117, 'اِنَّ رَبَّكَ '),
    ]),
    (6, [
        (123, 123, None),
        (124, 124, 'وَاِذَا جَآءَ'),
    ]),
    (6, [
        (125, 125, None),
        (126, 126, 'وَهٰذَا صِرَاطُ رَبِّكَ مُسْتَقِيْمًا فرمایا'),
        (127, 127, 'اور جب ان کی د'),
    ]),
    (6, [
        (128, 128, None),
        (129, 129, 'اور فرمایا: وَ'),
    ]),
    (6, [
        (130, 130, None),
        (131, 131, 'لِكَ اَنْ لَّمْ يَكُنْ رَّبُّكَ مُهْلِكَ الْقُرٰى بِظُلْمٍ وَّاَهْلُهَا غٰفِلُوْنَ﴿۱۳۱'),
        (132, 133, 'وَلِكُلٍّ دَرَجٰتٌ مِّمَّا عَمِلُوْا ؕ اور ہ'),
        (134, 135, 'اِنَّ مَا تُوْعَدُوْنَ لَاٰتٍ تم'),
    ]),
    (6, [
        (151, 151, None),
        (152, 152, 'وَلَا تَقْرَبُوْا مَالَ الْيَتِيْمِ یت'),
    ]),
    (6, [
        (158, 158, None),
        (159, 159, 'اِنَّ الَّذِيْ'),
    ]),
    (7, [
        (1, 1, None),
        (2, 2, 'فرمایا: یہ کتا'),
    ]),
    (7, [
        (3, 3, None),
        (4, 4, 'فرمایا وَكَمْ '),
    ]),
    (7, [
        (8, 8, None),
        (9, 9, 'وَمَنْ خَفَّتْ'),
    ]),
    (7, [
        (11, 11, None),
        (12, 12, 'ارشاد باری ہوا'),
        (13, 13, 'یہاں بھی ایسا '),
    ]),
    (7, [
        (24, 24, None),
        (25, 25, 'قَالَ فِيْهَا '),
    ]),
    (7, [
        (28, 28, None),
        (29, 29, 'پھر فرمایا: قُ'),
    ]),
    (7, [
        (35, 35, None),
        (36, 36, 'وَالَّذِيْنَ كَذَّبُوْا بِاٰيٰتِنَا لی'),
        (37, 37, 'فرمایا فَمَنْ '),
    ]),
    (7, [
        (38, 38, None),
        (39, 39, 'وَقَالَتْ اُوْ'),
    ]),
    (7, [
        (41, 41, None),
        (42, 42, 'جنت کے لئے کسی'),
        (43, 43, 'وَنَزَعْنَا مَا فِىْ صُدُوْرِهِمْ پہلی'),
    ]),
    (7, [
        (44, 44, None),
        (45, 45, 'یہ وہ لوگ ہیں '),
    ]),
    (7, [
        (54, 54, None),
        (55, 55, 'لہٰذا تمہیں تو'),
    ]),
    (7, [
        (56, 56, None),
        (57, 57, 'وَهُوَ الَّذِى'),
    ]),
    (7, [
        (65, 65, None),
        (66, 66, 'قَالَ الْمَلَاُ الَّذِيْنَ كَفَرُوْا مِنْ قَوْمِهٖۤ ان ک'),
    ]),
    (7, [
        (67, 68, None),
        (69, 69, 'اَوَعَجِبْتُمْ'),
        (70, 70, 'قَالُوْٓا وہ ک'),
        (71, 71, 'آپؑ نے بہت خوب'),
        (72, 72, 'فَاَنْجَيْنٰهُ وَالَّذِيْنَ مَعَهٗ بِر'),
    ]),
    (7, [
        (73, 73, None),
        (74, 74, 'وَاذْكُرُوْۤا اِذْ جَعَلَـكُمْ خُلَفَآءَ مِنْۢ بَعْدِ عَادٍ وَّبَوَّاَكُمْ فِی '),
    ]),
    (7, [
        (75, 75, None),
        (76, 76, 'قَالَ الَّذِيْ'),
        (77, 77, 'چنانچہ انہوں نے مشور'),
        (78, 79, 'اللہ کریم فرما'),
    ]),
    (7, [
        (81, 82, None),
        (83, 83, 'اور جب عذاب آ '),
    ]),
    (7, [
        (105, 105, None),
        (106, 108, 'قَالَ اِنْ كُن'),
    ]),
    (7, [
        (152, 152, None),
        (153, 153, 'فرمایا وَالَّذ'),
    ]),
    (7, [
        (154, 154, None),
        (155, 155, 'فَلَمَّاۤ اَخَ'),
        (156, 156, 'وَاكْتُبْ لَـنَا فِىْ هٰذِهِ الدُّنْيَا حَسَنَةً ی'),
        (157, 157, 'فرمایا لَّذِيْ'),
    ]),
    (7, [
        (159, 159, None),
        (160, 160, 'وَقَطَّعْنٰهُم'),
    ]),
    (7, [
        (161, 161, None),
        (162, 162, 'فَبَدَّلَ الَّذِيْنَ ظَلَمُوْا مِنْهُمْ قَوْلًا غَيْرَ الَّذِىْ قِيْلَ لَهُمْ لی'),
    ]),
    (7, [
        (163, 163, None),
        (164, 164, 'وَاِذْ قَالَتْ اُمَّةٌ مِّنْهُمْ لِمَ تَعِظُوْنَ قَوْمَاْ \u200b ۙ اۨللّٰهُ مُهْلِكُهُمْ اَوْ مُعَذِّبُهُمْ عَذَابًا شَدِيْدًا ؕ قَالُوْا مَعْذِرَةً اِلٰى رَبِّكُمْ وَلَعَلَّهُمْ يَتَّقُوْنَ\u200f ﴿۱۶۴﴾ و'),
        (165, 165, 'فَلَمَّا نَسُوْا مَا ذُكِّرُوْا بِهٖۤ اَنْجَيْنَا الَّذِيْنَ يَنْهَوْنَ عَنِ السُّوْۤءِ اب ق'),
    ]),
    (7, [
        (168, 168, None),
        (169, 169, 'لیکن ہوا کیا ف'),
        (170, 171, 'وَالَّذِيْنَ ي'),
    ]),
    (7, [
        (175, 175, None),
        (176, 176, 'وَلَوْ شِئْنَا'),
        (177, 178, 'سَآءَ مَثَلَا'),
    ]),
    (7, [
        (182, 183, None),
        (184, 184, 'اَوَلَمْ يَتَفَكَّرُوْا\u200b مَا بِصَاحِبِهِمْ مِّنْ جِنَّةٍ\u200bؕ اِن'),
    ]),
    (7, [
        (189, 189, None),
        (190, 190, 'فرمایا پھر انس'),
    ]),
    (7, [
        (191, 192, None),
        (193, 194, 'وَاِنْ تَدْعُو'),
    ]),
    (7, [
        (195, 195, None),
        (196, 197, 'آگے اس کی وجہ '),
    ]),
    (7, [
        (199, 199, None),
        (200, 200, 'وَاِمَّا يَنْز'),
        (201, 202, 'اِنَّ الَّذِيْ'),
    ]),
    (7, [
        (205, 205, None),
        (206, 206, 'فرمایا جنہیں ق'),
    ]),
    (8, [
        (3, 3, None),
        (4, 4, 'اُولٰۤٮِٕكَ هُمُ الْمُؤْمِنُوْنَ حَقًّا یہ ہ'),
    ]),
    (8, [
        (5, 5, None),
        (6, 6, 'حتیٰ کہ يُجَاد'),
        (7, 7, 'وَاِذْ يَعِدُك'),
        (8, 8, 'اور باطل کا با'),
        (9, 9, 'اِذْ تَسْتَغِي'),
    ]),
    (8, [
        (11, 11, None),
        (12, 12, 'پھر ان کی خاطر'),
        (13, 13, 'یہ سزا انہیں ا'),
    ]),
    (8, [
        (15, 16, None),
        (17, 17, 'قرآن اسی فنائے'),
    ]),
    (8, [
        (21, 21, None),
        (22, 22, 'اور اللہ کریم '),
    ]),
    (8, [
        (26, 26, None),
        (27, 27, 'تو یہاں ارشاد '),
        (28, 28, 'وَاعْلَمُوْۤا '),
    ]),
    (8, [
        (29, 29, None),
        (30, 30, 'وَاِذْ يَمْكُرُ بِكَ الَّذِيْنَ كَفَرُوْا فر'),
    ]),
    (8, [
        (32, 32, None),
        (33, 33, 'ارشاد باری ہے '),
    ]),
    (8, [
        (36, 36, None),
        (37, 37, 'لِيَمِيْزَ اللّٰهُ الْخَبِيْثَ مِنَ الطَّيِّبِ تا '),
    ]),
    (8, [
        (70, 70, None),
        (71, 71, 'وَاِنْ يُّرِيْدُوْا خِيَانَـتَكَ فَقَدْ خَانُوا اللّٰهَ مِنْ قَبْلُ فَاَمْكَنَ مِنْهُمْ ؕ او'),
    ]),
    (8, [
        (72, 72, None),
        (73, 73, 'وَالَّذِيْنَ ك'),
    ]),
    (9, [
        (3, 3, None),
        (4, 4, 'اور فرمایا اِل'),
        (5, 5, 'فَاِذَا انْسَل'),
    ]),
    (9, [
        (9, 9, None),
        (10, 10, 'لَا يَرْقُبُوْ'),
    ]),
    (9, [
        (12, 12, None),
        (13, 13, 'اَلَا تُقَاتِل'),
    ]),
    (9, [
        (21, 21, None),
        (22, 22, 'خٰلِدِيْنَ فِي'),
    ]),
    (9, [
        (23, 23, None),
        (24, 24, 'فرمایاقُلْ اے '),
    ]),
    (9, [
        (28, 28, None),
        (29, 29, 'رہی یہ بات کہ '),
    ]),
    (9, [
        (30, 30, None),
        (31, 31, 'اِتَّخَذُوْۤا اَحْبَارَهُمْ وَرُهْبَانَهُمْ اَرْبَابًا مِّنْ دُوْنِ اللّٰهِ انہو'),
    ]),
    (9, [
        (34, 34, None),
        (35, 35, 'اور اس طرح سے '),
    ]),
    (9, [
        (41, 41, None),
        (42, 42, 'اللہ کی راہ میں ایثا'),
    ]),
    (9, [
        (45, 45, None),
        (46, 46, 'وَلَوْ اَرَادُوْا الْخُـرُوْجَ ل'),
    ]),
    (9, [
        (47, 47, None),
        (48, 48, 'لَـقَدِ ابْتَغ'),
        (49, 49, 'وَمِنْهُمْ مَّنْ يَّقُوْلُ ائْذَنْ لِّىْ وَلَا تَفْتِنِّىْ ؕ ا'),
    ]),
    (9, [
        (51, 51, None),
        (52, 52, 'ان کفار سے فرم'),
    ]),
    (9, [
        (54, 54, None),
        (55, 55, 'اب رہی یہ بات '),
    ]),
    (9, [
        (65, 65, None),
        (66, 66, 'لَا تَعْتَذِرُوْا اب'),
    ]),
    (9, [
        (67, 67, None),
        (68, 68, 'جس کا نتیجہ یہ'),
    ]),
    (9, [
        (69, 69, None),
        (70, 70, 'فرمایا تم اس ب'),
    ]),
    (9, [
        (71, 71, None),
        (72, 72, 'وَعَدَ اللّٰهُ'),
    ]),
    (9, [
        (73, 73, None),
        (74, 74, 'منافقین اور کف'),
        (75, 75, 'وَمِنْهُمْ مَّنْ عَاهَدَ اللّٰهَ لَٮِٕنْ اٰتٰٮنَا مِنْ فَضْلِهٖ لَـنَصَّدَّقَنَّ وَلَنَكُوْنَنَّ مِنَ الصّٰلِحِيْنَ\u200f \u06dd یہا'),
        (76, 77, 'فرمایا فَلَمَّ'),
    ]),
    (9, [
        (81, 81, None),
        (82, 82, 'انہیں کہہ دو ف'),
    ]),
    (9, [
        (83, 83, None),
        (84, 84, 'اللہ کریم نے ف'),
    ]),
    (9, [
        (88, 88, None),
        (89, 89, 'اَعَدَّ اللّٰهُ لَهُمْ جَن'),
    ]),
    (9, [
        (91, 91, None),
        (92, 93, 'وَّلَا عَلَى ا'),
    ]),
    (9, [
        (95, 95, None),
        (96, 96, 'يَحْلِفُوْنَ ل'),
    ]),
    (9, [
        (105, 105, None),
        (106, 106, 'وَاٰخَرُوْنَ م'),
    ]),
    (9, [
        (107, 107, None),
        (108, 108, 'سو اللہ کریم ن'),
        (109, 109, 'اَفَمَنْ اَسَّ'),
    ]),
    (9, [
        (111, 111, None),
        (112, 112, 'اَلتَّاۤٮِٕبُوْنَ الْعٰبِدُوْنَ الْحٰمِدُوْنَ السّاۤٮِٕحُوْنَ الرّٰكِعُوْنَ السّٰجِدُوْنَ الْاٰمِرُوْنَ بِالْمَعْرُوْفِ وَالنَّاهُوْنَ عَنِ الْمُنْكَرِ وَالْحٰــفِظُوْنَ لِحُدُوْدِ اللّٰه ِ\u200bؕ وَ'),
    ]),
    (9, [
        (113, 113, None),
        (114, 114, 'وَمَا كَانَ اس'),
    ]),
    (9, [
        (124, 124, None),
        (125, 125, 'لیکن وَاَمَّا '),
    ]),
    (10, [
        (1, 1, None),
        (2, 2, 'اس میں کوئی کم'),
        (3, 3, 'رہی عظمتِ الٰہ'),
    ]),
    (10, [
        (6, 6, None),
        (7, 7, 'اِنَّ الَّذِيْ'),
    ]),
    (10, [
        (9, 9, None),
        (10, 10, 'کسی کو دکھ ہوگ'),
    ]),
    (10, [
        (12, 12, None),
        (13, 13, 'وَلَقَدْ اَهْل'),
        (14, 14, 'اے لوگو! جو اب'),
    ]),
    (10, [
        (18, 18, None),
        (19, 19, 'وَمَا كَانَ النَّاسُ اِلَّاۤ اُمَّةً وَّاحِدَةً فَاخْتَلَفُوْا لوگ ا'),
        (20, 20, 'وَيَقُوْلُوْنَ لَوْلَاۤ اُنْزِلَ عَلَيْهِ اٰيَةٌ مِّنْ رَّبِّهٖ فرما'),
    ]),
    (10, [
        (21, 21, None),
        (22, 22, 'مثال دیتے ہوئے'),
        (23, 23, 'فَلَمَّاۤ اَنْجٰٮهُمْ اِذَا هُمْ يَبْغُوْنَ فِی الْاَرْضِ بِغَيْرِ الْحَـقِّ ؕ يُّهَا النَّاسُ اِنَّمَا بَغْيُكُمْ عَلٰٓى اَنْفُسِكُمْ\u200bۙ مَّتَاعَ الْحَيٰوةِ الدُّنْيَا ؗ '),
    ]),
    (10, [
        (24, 24, None),
        (25, 25, 'وَاللّٰهُ يَدْعُوْۤا اِلٰى دَارِ السَّلٰمِؕ ط وہ ہ'),
    ]),
    (10, [
        (31, 31, None),
        (32, 32, 'فرمایا، فَذٰلِ'),
    ]),
    (10, [
        (37, 37, None),
        (38, 38, 'جو کتاب اتنے ع'),
    ]),
    (10, [
        (52, 52, None),
        (53, 53, 'وَيَسْتَنْۢبِـ'),
        (54, 54, 'سورة یونس رکوع'),
    ]),
    (10, [
        (57, 57, None),
        (58, 58, 'سو اے\n\nمیرے حب'),
    ]),
    (10, [
        (65, 65, None),
        (66, 66, 'اَلَاۤ اِنَّ ل'),
    ]),
    (10, [
        (68, 68, None),
        (69, 70, 'قُلْ اِنَّ الّ'),
    ]),
    (10, [
        (72, 72, None),
        (73, 73, 'فَكَذَّبُوهُ ا'),
    ]),
    (10, [
        (74, 75, None),
        (76, 77, 'فَلَهَا جَآءَ'),
    ]),
    (10, [
        (79, 80, None),
        (81, 81, 'موسیٰ نے فرمایا فَلَ'),
        (82, 82, 'اور وَيُحِقُّ '),
    ]),
    (10, [
        (94, 94, None),
        (95, 95, 'وَلَا تَكُوْنَ'),
    ]),
    (10, [
        (100, 100, None),
        (101, 101, 'فرمایا، اے میر'),
        (102, 102, 'اور یہ لوگ جو '),
    ]),
    (11, [
        (3, 3, None),
        (4, 5, 'اِلَی اللہِ مَرْجِعُكُمْ ۚ ہمیں '),
    ]),
    (11, [
        (18, 18, None),
        (19, 19, 'ظالموں پر اللہ کی لعنت ہوگ'),
        (20, 20, 'اُولٰٓٮِٕكَ لَ'),
        (21, 23, 'اُولٰٓٮِٕكَ ال'),
    ]),
    (11, [
        (28, 28, None),
        (29, 30, 'فرمایا، قَوْمِ'),
        (31, 31, 'اَقُوْلُ لَـكُ'),
    ]),
    (11, [
        (32, 32, None),
        (33, 35, 'قَالَ اِنَّمَا'),
    ]),
    (11, [
        (36, 36, None),
        (37, 37, 'فرمایا، آپ ایس'),
        (38, 38, 'نوحؑ اپنا کام '),
        (39, 39, 'فَسَوْفَ تَعْل'),
    ]),
    (11, [
        (41, 41, None),
        (42, 42, 'وَهِىَ تَجْرِى'),
    ]),
    (11, [
        (43, 43, None),
        (44, 44, 'وَقِيْلَ يَا ر'),
    ]),
    (11, [
        (50, 50, None),
        (51, 51, 'فرمایا، يٰقَوْ'),
    ]),
    (11, [
        (59, 59, None),
        (60, 60, 'وَاُتْبِعُوْا '),
        (61, 68, 'سورة محمود رکو'),
    ]),
    (11, [
        (94, 94, None),
        (95, 95, 'كَاَنْ لَّمْ ي'),
    ]),
    (11, [
        (96, 96, None),
        (97, 97, 'فَاتَّبَعُوْۤا'),
    ]),
    (11, [
        (102, 104, None),
        (105, 107, 'یَوْمَ يَأْتِ\n'),
    ]),
    (11, [
        (108, 108, None),
        (109, 109, 'فَلَا تَكُ فِى'),
    ]),
    (11, [
        (110, 111, None),
        (112, 112, 'فَاسْتَقِمْ كَمَاۤ اُمِرْتَ وَمَ'),
    ]),
    (11, [
        (116, 116, None),
        (117, 117, 'وَمَا كَانَ رَ'),
    ]),
    (11, [
        (118, 118, None),
        (119, 119, 'اللہ مَنْ رَّح'),
    ]),
    (12, [
        (8, 8, None),
        (9, 9, 'پھر مشورہ کرنے'),
    ]),
    (12, [
        (11, 11, None),
        (12, 12, 'اَرْسِلْهُ مَع'),
    ]),
    (12, [
        (14, 14, None),
        (15, 15, 'فَلَمَّا ذَهَب'),
    ]),
    (12, [
        (24, 24, None),
        (25, 25, 'وَاسْتَبَقَا ا'),
    ]),
    (12, [
        (28, 29, None),
        (30, 35, 'سورة یوسف رکوع'),
    ]),
    (12, [
        (68, 68, None),
        (69, 79, 'سورة یوسف راکو'),
    ]),
    (12, [
        (80, 80, None),
        (81, 82, 'بھائیوں سے کہا'),
    ]),
    (12, [
        (83, 85, None),
        (86, 86, 'تو انہوں نے فر'),
    ]),
    (12, [
        (87, 89, None),
        (90, 90, 'کہنے لگے، قَالُوْۤا ءَاِنَّكَ لَاَنْتَ يُوْسُفُ کہ'),
    ]),
    (13, [
        (2, 2, None),
        (3, 3, 'قدرت الہی کی ن'),
    ]),
    (13, [
        (5, 5, None),
        (6, 6, 'وَيَسْتَعْجِلُ'),
    ]),
    (13, [
        (12, 12, None),
        (13, 14, 'فرمایا، وَيُسَ'),
        (15, 15, 'وَلِلّٰهِ يَسْ'),
    ]),
    (13, [
        (33, 33, None),
        (34, 34, 'لَهُمْ عَذَابٌ فِى الْحَيٰوةِ الدُّنْيَا دُن'),
    ]),
    (13, [
        (35, 35, None),
        (36, 36, 'وَالَّذِيْنَ ا'),
    ]),
    (14, [
        (1, 1, None),
        (2, 2, 'اللّٰهِ الَّذِ'),
        (3, 4, 'فرمایا، اَلَّذ'),
        (5, 5, 'وَلَـقَدْ اَرْ'),
        (6, 6, 'وَاِذْ قَالَ م'),
        (7, 12, 'سورة ابراہیم رکوع 12'),
    ]),
    (15, [
        (27, 27, None),
        (28, 29, 'سورہ بقرہ میں '),
    ]),
    (15, [
        (32, 32, None),
        (33, 33, 'کہنے لگا: قَال'),
    ]),
    (15, [
        (42, 42, None),
        (43, 44, 'وَاِنَّ\n\nوَاِن'),
    ]),
    (16, [
        (26, 26, None),
        (27, 27, 'یہ تو اخروی ذل'),
    ]),
    (16, [
        (29, 29, None),
        (30, 30, 'وَقِيْلَ لِلَّذِيْنَ اتَّقَوْا م'),
        (31, 31, 'جَنّٰتُ عَدْنٍ'),
    ]),
    (16, [
        (44, 44, None),
        (45, 45, 'فرمایا: اَفَاَ'),
    ]),
    (16, [
        (79, 79, None),
        (80, 80, 'وَاللّٰهُ جَعَ'),
    ]),
    (16, [
        (95, 95, None),
        (96, 96, 'اور یاد رکھو: '),
    ]),
    (17, [
        (11, 22, None),
        (23, 30, 'سورۃ بنی اسراء'),
    ]),
    (17, [
        (39, 39, None),
        (40, 40, 'فرمایا: اَفَاَ'),
    ]),
    (17, [
        (61, 70, None),
        (71, 77, 'سورة بنی اسراء'),
    ]),
    (17, [
        (85, 93, None),
        (94, 100, 'سورہ بنی اسراء'),
    ]),
    (18, [
        (1, 1, None),
        (2, 3, 'قَيِّمًا لِّيُ'),
    ]),
    (18, [
        (23, 23, None),
        (24, 24, 'اِلَّاۤ اَنْ ي'),
    ]),
    (18, [
        (45, 49, None),
        (50, 53, 'سورة اللاصف رک'),
    ]),
    (18, [
        (60, 70, None),
        (71, 74, 'سورۃ الکعب رگو'),
    ]),
    (18, [
        (84, 86, None),
        (87, 87, 'انہوں نے عرض ک'),
    ]),
    (18, [
        (88, 89, None),
        (90, 92, 'حَتّٰٓى اِذَا '),
    ]),
    (18, [
        (95, 95, None),
        (96, 98, 'اٰتُوْنِىْ زُب'),
        (99, 99, 'وَتَرَكْنَا بَ'),
        (100, 100, 'جب ساری مخلوق '),
    ]),
    (19, [
        (46, 46, None),
        (47, 47, 'تو آپؑ نے فرما'),
    ]),
    (20, [
        (2, 2, None),
        (3, 3, 'اِلَّا تَذْكِر'),
    ]),
    (20, [
        (9, 9, None),
        (10, 10, 'اِذْ رَاٰ نَار'),
    ]),
    (20, [
        (12, 12, None),
        (13, 13, 'نبی ازل سے نبی'),
        (14, 14, 'سب سے بنیادی ب'),
    ]),
    (20, [
        (17, 19, None),
        (20, 21, 'فَالْقِهَا۔۔۔ '),
    ]),
    (20, [
        (25, 26, None),
        (27, 28, 'مزید عرض کی: و'),
        (29, 34, 'وَاجْعَلْ لِّى'),
    ]),
    (20, [
        (39, 39, None),
        (40, 41, 'اِذْ تَمْشِىْۤ'),
        (42, 43, 'اِذْهَبْ اَنْت'),
    ]),
    (20, [
        (48, 48, None),
        (49, 50, 'کہنے لگا: قَال'),
    ]),
    (20, [
        (58, 58, None),
        (59, 59, 'موسیٰ علیہ السلام نے'),
    ]),
    (20, [
        (64, 64, None),
        (65, 65, 'قَالُوْا يٰمُو'),
    ]),
    (20, [
        (71, 71, None),
        (72, 72, 'جادو گروں نے ج'),
    ]),
    (20, [
        (75, 75, None),
        (76, 76, 'وہاں ایسی نعمت'),
    ]),
    (20, [
        (80, 80, None),
        (81, 81, 'كُلُوْا مِنْ ط'),
    ]),
    (20, [
        (87, 87, None),
        (88, 88, 'جب سامری نے وہ'),
    ]),
    (20, [
        (90, 104, None),
        (105, 105, 'سورة ظلم رکوع '),
    ]),
    (20, [
        (122, 122, None),
        (123, 123, 'زمین پر نزول:\n'),
    ]),
    (21, [
        (4, 4, None),
        (5, 5, 'بَلْ قَالُوْۤا'),
    ]),
    (21, [
        (12, 13, None),
        (14, 15, 'وہ کہیں گے: قَ'),
    ]),
    (21, [
        (26, 26, None),
        (27, 28, 'لَا يَسْبِقُوْ'),
    ]),
    (21, [
        (49, 49, None),
        (50, 50, 'قرآن کریم کی ع'),
    ]),
    (21, [
        (58, 59, None),
        (60, 63, 'قَالُوْا سَمِع'),
    ]),
    (21, [
        (64, 64, None),
        (65, 67, 'ثُمَّ نُكِسُوْ'),
    ]),
    (21, [
        (74, 74, None),
        (75, 76, 'ان بد کاروں کی'),
    ]),
    (21, [
        (83, 83, None),
        (84, 84, 'فَاسْتَجَبْنَا'),
    ]),
    (21, [
        (87, 87, None),
        (88, 88, 'فَاسْتَجَبْنَا لَهُ '),
        (89, 90, 'اللہ کریم فرماتے ہیں'),
    ]),
    (21, [
        (91, 91, None),
        (92, 92, 'اِنَّ هٰذِهٖۤ '),
        (93, 93, 'فرمایا: وَتَقَ'),
    ]),
    (21, [
        (101, 102, None),
        (103, 103, 'لَا يَحْزُنُهُ'),
    ]),
    (21, [
        (107, 107, None),
        (108, 108, 'سوفر مایا: لوگ'),
        (109, 109, 'اگر یہ بات بھی'),
        (110, 112, 'یہ تم جانو اور'),
    ]),
    (22, [
        (19, 19, None),
        (20, 21, 'فرمایا: يُصْهَ'),
        (22, 22, 'جب وہ ارادہ کریں گے کہ کہیں ادھر'),
    ]),
    (22, [
        (34, 34, None),
        (35, 35, 'الَّذِيْنَ اِذ'),
    ]),
    (22, [
        (40, 40, None),
        (41, 41, 'فرمایا: لَّذِي'),
        (42, 42, 'فرمایا: وَإِنْ'),
    ]),
    (22, [
        (43, 43, None),
        (44, 44, 'اسی طرح وَّ اَ'),
        (45, 45, 'فرمایا: فَكَاَ'),
    ]),
    (22, [
        (46, 46, None),
        (47, 47, 'فرمایا: وَيَسْ'),
    ]),
    (22, [
        (48, 48, None),
        (49, 49, 'سورة الح رکوع '),
        (50, 50, 'فرمایا: فَالَّ'),
    ]),
    (22, [
        (54, 54, None),
        (55, 55, 'یہ کافر کا حال'),
    ]),
    (22, [
        (68, 68, None),
        (69, 69, 'فرمایا: اللّٰه'),
    ]),
    (23, [
        (2, 2, None),
        (3, 3, 'وَالَّذِيْنَ ه'),
    ]),
    (23, [
        (9, 10, None),
        (11, 11, 'الَّذِيْنَ يَر'),
    ]),
    (23, [
        (12, 12, None),
        (13, 13, 'ثُمَّ جَعَلْنٰ'),
    ]),
    (23, [
        (16, 16, None),
        (17, 17, 'فرمایا: وَلَقَ'),
        (18, 18, 'فرمایا: وَاَنْ'),
    ]),
    (23, [
        (54, 56, None),
        (57, 57, 'فرمایا: اِنَّ '),
    ]),
    (23, [
        (86, 86, None),
        (87, 87, 'سَيَقُوْلُوْنَ'),
    ]),
    (23, [
        (99, 99, None),
        (100, 100, 'لَعَلِّيَّ\n\nاَ'),
    ]),
    (24, [
        (39, 39, None),
        (40, 40, 'اَوْ كَظُلُمٰت'),
    ]),
    (24, [
        (54, 54, None),
        (55, 55, 'فرمایا: اللّٰه'),
    ]),
    (25, [
        (7, 7, None),
        (8, 8, 'یا پھر، اَوْ ي'),
    ]),
    (25, [
        (17, 17, None),
        (18, 18, 'وہ کہیں گے: قَ'),
    ]),
    (25, [
        (30, 30, None),
        (31, 31, 'فرمایا: وَكَذٰ'),
    ]),
    (25, [
        (34, 34, None),
        (35, 35, 'اور يقينا بهم '),
    ]),
    (25, [
        (62, 62, None),
        (63, 63, 'فرمایا: وَعِبَ'),
    ]),
    (26, [
        (10, 33, None),
        (34, 51, 'قَالَ قَآٮِٕل'),
        (52, 67, 'اور ہم نے موسیٰ (علیہ السلام) پر وحی ف'),
        (68, 68, 'رحمت رب العالمین بطف'),
    ]),
    (26, [
        (92, 93, None),
        (94, 97, 'فَكُبْكِبُوْا '),
    ]),
    (26, [
        (100, 101, None),
        (102, 103, 'فَلَوْ اَنَّ ل'),
    ]),
    (26, [
        (143, 144, None),
        (145, 145, 'وَمَاۤ اَسْــٔ'),
    ]),
    (26, [
        (154, 155, None),
        (156, 157, 'فرمایا: وَلَا '),
    ]),
    (26, [
        (192, 192, None),
        (193, 194, 'نَزَلَ بِهِ الرُّوْحُ الْاَمِيْنُ ﴿۱۹۳'),
    ]),
    (26, [
        (199, 201, None),
        (202, 202, 'فَيَاْتِيَهُمْ'),
        (203, 207, 'فرمایا، مجرمین'),
    ]),
    (26, [
        (208, 209, None),
        (210, 212, 'وَمَا تَنَزَّل'),
        (213, 214, 'فَلَا تَدْعُ م'),
    ]),
    (26, [
        (218, 220, None),
        (221, 221, 'هَلْ اُنَبِّئُ'),
    ]),
    (26, [
        (222, 222, None),
        (223, 223, 'يُّلْقُوْنَ ال'),
    ]),
    (26, [
        (224, 224, None),
        (225, 226, 'فرمایا: اَلَمْ'),
    ]),
    (27, [
        (1, 1, None),
        (2, 2, 'هُدًى وَّبُشْر'),
    ]),
    (27, [
        (8, 8, None),
        (9, 9, 'سوار شاد ہوا: '),
    ]),
    (27, [
        (20, 20, None),
        (21, 21, 'لَا عَلَيْهِ ب'),
    ]),
    (27, [
        (23, 23, None),
        (24, 24, 'کہنے لگا کہ یہ'),
    ]),
    (27, [
        (63, 63, None),
        (64, 64, 'فرمایا: اَمَّنْ يَّب'),
    ]),
    (27, [
        (82, 83, None),
        (84, 93, 'پُرِسْش:\n\nفرما'),
    ]),
    (28, [
        (6, 6, None),
        (7, 7, 'فرمایا: وَأَوْ'),
    ]),
    (28, [
        (29, 29, None),
        (30, 30, 'فَلَمَّاۤ اَتٰ'),
    ]),
    (28, [
        (39, 39, None),
        (40, 40, 'تکبر کا نتیجہ:'),
    ]),
    (28, [
        (41, 41, None),
        (42, 42, 'وَاَتْبَعْنٰهُ'),
    ]),
    (28, [
        (43, 43, None),
        (44, 45, 'آپ صلی اللہ علیہ وسلم کی رسالت کی دلیل:\n\nاور'),
    ]),
    (28, [
        (54, 54, None),
        (55, 55, 'فرمایا، وَاِذَ'),
    ]),
    (28, [
        (56, 56, None),
        (57, 57, 'فرمایا: وَقَال'),
    ]),
    (28, [
        (58, 58, None),
        (59, 59, 'یہ بھی مت سوچو'),
    ]),
    (29, [
        (5, 5, None),
        (6, 6, 'وہ جانتا ہے کو'),
    ]),
    (29, [
        (12, 12, None),
        (13, 13, 'فرمایا یہ دوسر'),
    ]),
    (29, [
        (46, 46, None),
        (47, 47, 'وَكَذٰلِكَ اَن'),
    ]),
    (29, [
        (63, 63, None),
        (64, 68, 'سورۃ العنبرات '),
        (69, 69, 'فرمایا: وَالَّ'),
    ]),
    (30, [
        (20, 27, None),
        (28, 28, '(اللہ) تمہارے ہی حالات میں سے تمہارے لیے ایک مثال بیان فرماتے ہیں۔\nک'),
    ]),
    (30, [
        (52, 52, None),
        (53, 53, 'وَمَاۤ اَنْتَ '),
    ]),
    (31, [
        (4, 4, None),
        (5, 5, 'اُولٰٓٮِٕكَ عَ'),
    ]),
    (31, [
        (8, 8, None),
        (9, 9, 'خٰلِدِيْنَ فِي'),
    ]),
    (31, [
        (23, 23, None),
        (24, 24, 'فرمایا، یہ تھو'),
    ]),
    (31, [
        (27, 27, None),
        (28, 28, 'اِنَّ اللّٰهَ '),
    ]),
    (31, [
        (29, 29, None),
        (30, 30, 'اور یہ اس لیے '),
        (31, 31, 'سورۃ ثمن رکوع '),
    ]),
    (33, [
        (2, 2, None),
        (3, 3, 'وَّتَوَكَّلْ ع'),
    ]),
    (33, [
        (38, 38, None),
        (39, 40, 'انبیاء علیہ ہم'),
    ]),
    (33, [
        (41, 42, None),
        (43, 43, 'هُوَ الَّذِىْ يُصَلِّىْ عَلَيْكُمْ وَمَلٰٓٮِٕكَتُهٗ لِيُخْرِجَكُمْ مِّنَ الظُّلُمٰتِ اِلَى النُّوْرِ ؕ وَكَانَ بِالْمُؤْمِنِيْنَ رَحِيْمًا\u200f ﴿۴۳﴾ وہی تو ہے جو تم پر رحمت بھیجتا ہے اور اس\n\nک'),
        (44, 45, 'فرمایا: تَحِيّ'),
    ]),
    (34, [
        (10, 10, None),
        (11, 11, 'اِنِّ الْحَمْل'),
    ]),
    (34, [
        (20, 20, None),
        (21, 21, 'پھر مزے کی بات'),
    ]),
    (34, [
        (22, 30, None),
        (31, 36, 'سورة سبارکوع 4'),
    ]),
    (34, [
        (37, 45, None),
        (46, 54, 'سورة سبار گوع '),
    ]),
    (35, [
        (6, 6, None),
        (7, 7, 'فرمایا: لَّذِي'),
    ]),
    (35, [
        (11, 11, None),
        (12, 12, 'وَمَا يَسْتَوِ'),
    ]),
    (35, [
        (14, 14, None),
        (15, 15, 'سورۃ فاطمہ رکو'),
    ]),
    (35, [
        (16, 16, None),
        (17, 17, 'ایک انسان نہیں'),
    ]),
    (35, [
        (29, 29, None),
        (30, 30, 'لِیُو فِیْہُمْ'),
    ]),
    (35, [
        (34, 34, None),
        (35, 35, 'اور ہمیں جنت م'),
    ]),
    (35, [
        (38, 38, None),
        (39, 39, 'فرمایا: الَّذِ'),
    ]),
    (36, [
        (1, 12, None),
        (13, 21, 'سورۃ بیس رکوع '),
    ]),
    (36, [
        (51, 68, None),
        (69, 83, 'فرمایا: وَمَا '),
    ]),
    (37, [
        (1, 21, None),
        (22, 22, 'جولوگ ظلم کرتے'),
        (23, 25, 'مِنْ دُونِ الل'),
    ]),
    (37, [
        (28, 29, None),
        (30, 30, 'وَمَا كَانَ لَ'),
    ]),
    (37, [
        (38, 40, None),
        (41, 43, 'اُولٰٓٮِٕكَ لَ'),
    ]),
    (37, [
        (48, 50, None),
        (51, 53, 'قَالَ قَآٮِٕل'),
    ]),
    (37, [
        (60, 62, None),
        (63, 63, 'اِنَّا جَعَلْن'),
    ]),
    (37, [
        (76, 78, None),
        (79, 81, 'فرمایا: سَلٰمٌ'),
    ]),
    (37, [
        (87, 87, None),
        (88, 94, 'فَنَظَرَ نَظْر'),
    ]),
    (37, [
        (95, 96, None),
        (97, 98, 'قَالُوا ابْنُو'),
    ]),
    (37, [
        (105, 108, None),
        (109, 111, 'سَلٰمٌ عَلٰٓى '),
    ]),
    (37, [
        (147, 148, None),
        (149, 150, 'ان سے پوچھیے: '),
    ]),
    (37, [
        (158, 160, None),
        (161, 161, 'فرمایا: فَاِنّ'),
    ]),
    (37, [
        (172, 172, None),
        (173, 174, 'وَاِنَّ جُنْدَ'),
    ]),
    (37, [
        (175, 176, None),
        (177, 179, '﴿فَإِذَا نَزَل'),
    ]),
    (38, [
        (1, 13, None),
        (14, 26, 'اس کا پھر نتیج'),
        (27, 40, 'سورة ص ارکوع 3'),
    ]),
    (38, [
        (62, 63, None),
        (64, 64, 'فرمایا: اِنَّ '),
    ]),
    (38, [
        (65, 65, None),
        (66, 66, 'رَبُّ السَّمٰو'),
    ]),
    (39, [
        (34, 34, None),
        (35, 35, 'فرمایا: لِيُكَ'),
    ]),
    (40, [
        (38, 50, None),
        (51, 60, 'يقينا بهم اپنے'),
        (61, 68, 'الله هي تو به '),
    ]),
    (40, [
        (69, 78, None),
        (79, 82, 'اللہ نے تمہارے'),
    ]),
    (41, [
        (1, 2, None),
        (3, 3, 'قرآن حکیم کی خ'),
    ]),
    (41, [
        (4, 4, None),
        (5, 5, 'حق کا انکار ان'),
    ]),
    (41, [
        (6, 6, None),
        (7, 8, 'فرمایا: الَّذِ'),
    ]),
    (41, [
        (18, 18, None),
        (19, 25, 'سورۃ خم السجدہ'),
    ]),
    (41, [
        (44, 44, None),
        (45, 46, 'سورة ختم السجد'),
    ]),
    (42, [
        (18, 18, None),
        (19, 19, 'اَللّٰهُ لَطِي'),
    ]),
    (42, [
        (37, 37, None),
        (38, 38, 'فرمایا: وَالَّ'),
    ]),
    (42, [
        (44, 44, None),
        (45, 45, 'وَتَرٰٮهُمْ يُ'),
    ]),
    (42, [
        (46, 46, None),
        (47, 47, 'کوئی اُس کی مد'),
        (48, 48, 'فَإِنْ أَعْرَض'),
    ]),
    (42, [
        (51, 51, None),
        (52, 52, 'وَ كَذٰلِكَ أَ'),
        (53, 53, 'صِرَاط الله ال'),
    ]),
    (43, [
        (1, 10, None),
        (11, 25, 'وَالَّذِىْ نَز'),
    ]),
    (44, [
        (13, 13, None),
        (14, 14, 'ثُمَّ تَوَلَّو'),
    ]),
    (44, [
        (17, 17, None),
        (18, 18, 'آپؐ نے آواز لگ'),
    ]),
    (44, [
        (20, 21, None),
        (22, 23, 'مگر وہ نہ مانے'),
    ]),
    (47, [
        (4, 4, None),
        (5, 6, 'سَيَهْدِيْهِمْ'),
    ]),
    (47, [
        (16, 16, None),
        (17, 18, 'اسی طرح ہر نیک'),
    ]),
    (48, [
        (2, 2, None),
        (3, 3, 'فرمایا: يَنْصُ'),
    ]),
    (48, [
        (12, 12, None),
        (13, 13, 'فرمایا: وَمَنْ لَّمْ'),
    ]),
    (48, [
        (19, 19, None),
        (20, 20, 'فرمایا: وَعَدَ'),
    ]),
    (48, [
        (26, 26, None),
        (27, 27, 'سورۃ الشیخ رکو'),
    ]),
    (48, [
        (28, 28, None),
        (29, 29, 'فرمایا: هُمَّه'),
    ]),
    (49, [
        (11, 11, None),
        (12, 12, 'فرمایا: يَا يٰۤـاَيّ'),
    ]),
    (49, [
        (15, 15, None),
        (16, 16, 'یہ جو تم کرتے '),
    ]),
    (49, [
        (17, 17, None),
        (18, 18, 'فرمایا: اِنَّ '),
    ]),
    (50, [
        (1, 15, None),
        (16, 29, 'سورۃ قرآن کو ع'),
        (30, 30, 'جس دن اسم دوزخ'),
    ]),
    (50, [
        (39, 39, None),
        (40, 40, 'فرمایا: وَمِنَ'),
        (41, 41, 'وَاسْتَمِعْ يَ'),
    ]),
    (50, [
        (42, 43, None),
        (44, 45, 'ہم کہیں گے تم '),
    ]),
    (51, [
        (1, 6, None),
        (7, 9, 'حساب کتاب کا دن قائم'),
        (10, 13, 'اپنی بربادی کے'),
        (14, 16, 'میرے حبیب صلی '),
        (17, 18, 'یہ لوگ وہ تھے '),
        (19, 20, 'تو عبادت پر نا'),
    ]),
    (51, [
        (21, 21, None),
        (22, 22, 'وَفِى السَّمَا'),
        (23, 23, 'فَوَرَبِّ السّ'),
        (24, 30, 'كَيَا ابْرَائِ'),
    ]),
    (52, [
        (1, 27, None),
        (28, 28, 'اِنَّا كُـنَّا مِنْ '),
    ]),
    (53, [
        (1, 1, None),
        (2, 2, 'مَا ضَلَّ صَاحِبُكُمْ وَمَا غَوٰى اللَ'),
    ]),
    (53, [
        (21, 22, None),
        (23, 23, 'اِنْ هِىَ اِلّ'),
    ]),
    (55, [
        (26, 42, None),
        (43, 78, 'فرمایا: هٰذِهٖ'),
    ]),
    (57, [
        (2, 2, None),
        (3, 3, 'فرمایا: هُوَ ا'),
    ]),
    (57, [
        (20, 25, None),
        (26, 29, 'اور يقينا بهم '),
    ]),
    (59, [
        (8, 8, None),
        (9, 9, 'فرمایا: وَالَّ'),
    ]),
    (60, [
        (1, 6, None),
        (7, 13, 'عجیب نہیں کہ ا'),
    ]),
    (62, [
        (8, 8, None),
        (9, 11, 'سورۃ الجمعہ رک'),
    ]),
    (65, [
        (7, 7, None),
        (8, 12, 'سورة الطلاق رک'),
    ]),
    (66, [
        (11, 11, None),
        (12, 12, 'فرمایا: وَمَرْ'),
    ]),
    (68, [
        (1, 1, None),
        (2, 3, 'مَاۤ اَنْتَ بِـنِعْمَةِ رَبِّكَ بِمَجْنُوْنٍ ﴿۲﴾ و'),
    ]),
    (68, [
        (19, 21, None),
        (22, 22, 'اَنِ اغْدُوْا '),
    ]),
    (68, [
        (29, 29, None),
        (30, 31, 'فرمایا: فَاَقْ'),
    ]),
    (68, [
        (39, 39, None),
        (40, 40, 'فرمایا: سَلْهُ'),
    ]),
    (68, [
        (44, 44, None),
        (45, 45, 'فرمایا: وَاُمْ'),
    ]),
    (68, [
        (46, 46, None),
        (47, 47, 'فرمایا: اَمْ ع'),
    ]),
    (68, [
        (51, 51, None),
        (52, 52, 'فرمایا، لیکن ی'),
    ]),
    (69, [
        (9, 9, None),
        (10, 10, 'فرمایا: فَعَصَ'),
    ]),
    (69, [
        (13, 13, None),
        (14, 14, 'کہ فرمایا: وَح'),
    ]),
    (69, [
        (34, 34, None),
        (35, 35, 'فرمایا، یہ غری'),
    ]),
    (70, [
        (30, 30, None),
        (31, 31, 'فرمایا، جو جائ'),
    ]),
    (70, [
        (35, 35, None),
        (36, 44, 'سورة المعارف ر'),
    ]),
    (72, [
        (4, 4, None),
        (5, 7, 'وَّاَنَّا ظَنَ'),
    ]),
    (73, [
        (16, 17, None),
        (18, 18, 'اۨلسَّمَآءُ م'),
    ]),
    (73, [
        (19, 19, None),
        (20, 20, 'سورة الحرم مل '),
    ]),
    (76, [
        (1, 1, None),
        (2, 2, 'فرمایا: اِنَّا'),
    ]),
    (76, [
        (9, 9, None),
        (10, 10, 'فرمایا: اِنَّا'),
    ]),
    (77, [
        (11, 16, None),
        (17, 17, 'سوچو کیوں تباہ'),
    ]),
    (77, [
        (20, 20, None),
        (21, 24, 'فرمایا:\nفَجَعَ'),
    ]),
    (77, [
        (29, 29, None),
        (30, 30, 'فرمایا: اِنْطَ'),
    ]),
    (77, [
        (38, 38, None),
        (39, 50, 'فرمایا: فَاِنْ'),
    ]),
    (78, [
        (1, 30, None),
        (31, 40, 'سورۃ النبا کو '),
    ]),
    (83, [
        (1, 1, None),
        (2, 2, 'الَّذِيْنَ اِذ'),
    ]),
    (83, [
        (18, 21, None),
        (22, 24, 'فرمایا: اِنَّ '),
    ]),
    (83, [
        (29, 29, None),
        (30, 32, 'فرمایا: وَاِذَ'),
    ]),
    (86, [
        (7, 7, None),
        (8, 8, 'فرمایا: اِنَّه'),
    ]),
    (86, [
        (15, 16, None),
        (17, 17, 'فرمایا: فَمَهّ'),
    ]),
    (87, [
        (18, 18, None),
        (19, 19, 'صُحُفِ اِبْرٰه'),
    ]),
    (88, [
        (11, 11, None),
        (12, 12, 'فرمایا: فِيْهَ'),
    ]),
    (89, [
        (5, 5, None),
        (6, 6, 'فرمایا: اَلَمْ'),
        (7, 8, 'اِرَمَ ذَاتِ ا'),
    ]),
    (89, [
        (9, 9, None),
        (10, 10, 'وَفِرْ عَوْنَ '),
        (11, 12, 'الَّذِيْنَ طَغ'),
    ]),
    (89, [
        (25, 26, None),
        (27, 27, 'ارشاد ہوگا،\n\nي'),
        (28, 28, 'رَبِّكِ رَاضِي'),
    ]),
    (90, [
        (11, 13, None),
        (14, 15, 'فرمایا: اَوْ ا'),
    ]),
    (91, [
        (1, 1, None),
        (2, 2, 'کائنات کی ہر چ'),
    ]),
    (91, [
        (11, 12, None),
        (13, 13, 'فَقَالَ لَهُمْ'),
        (14, 14, 'فرمایا: فَكَذَ'),
        (15, 15, 'فرمایا: وَلَا '),
    ]),
    (92, [
        (12, 13, None),
        (14, 14, 'اسی لیے فرمایا'),
    ]),
    (92, [
        (15, 17, None),
        (18, 18, 'جو یہ رشتہ نبھ'),
    ]),
    (93, [
        (1, 2, None),
        (3, 3, 'مَا وَدَّعَكَ رَبُّكَ وَمَا قَلٰىؕ\u200f ۞ '),
    ]),
    (96, [
        (6, 7, None),
        (8, 8, "اِنَّ اِلٰى رَبِّكَ الرُّجْعٰىؕ\u200f ؇ ''ی"),
    ]),
    (96, [
        (14, 14, None),
        (15, 19, 'كَلَّا لَٮِٕنْ'),
    ]),
    (102, [
        (1, 1, None),
        (2, 4, 'حَتّٰى زُرْتُمُ الْمَقَابِرَؕ\u200f \u06dd٢ یہاں'),
    ]),
    (102, [
        (5, 6, None),
        (7, 7, 'ثُمَّ لَتَرَوُ'),
    ]),
    (112, [
        (1, 3, None),
        (4, 4, 'اور: وَلَمْ يَ'),
    ]),
]


def apply_section_corrections(rows: list[dict], report: dict | None = None) -> list[dict]:
    """Re-cut the stretches in SECTION_CORRECTIONS. Rows must be Akram rows; the
    order of the words is untouched and every other row is returned as it is."""
    result = list(rows)
    for surah, wanted in SECTION_CORRECTIONS:
        first, last = wanted[0][0], wanted[-1][1]
        where = f"section correction {surah}:{first}-{last}"
        old = sorted((r for r in result if r["surahNumber"] == surah and first <= r["ayahStart"] <= last),
                     key=lambda r: r["ayahStart"])
        if not old or old[0]["ayahStart"] != first or old[-1]["ayahEnd"] != last:
            raise SystemExit(f"{where}: the rows no longer span it")
        for a, b in zip(old, old[1:]):
            if a["ayahEnd"] + 1 != b["ayahStart"]:
                raise SystemExit(f"{where}: its rows are not contiguous")
        for a, b in zip(wanted, wanted[1:]):
            if a[1] + 1 != b[0]:
                raise SystemExit(f"{where}: the new rows are not contiguous")
        joined = "\n\n".join(r["text"] for r in old)
        cuts = [0]
        for _, _, anchor in wanted[1:]:
            before, bar, after = anchor.rpartition("|")
            place = before + after
            if joined.count(place) != 1:
                raise SystemExit(f"{where}: {anchor!r} is found {joined.count(place)} times")
            cuts.append(joined.index(place) + (len(before) if bar else 0))
        if cuts != sorted(cuts):
            raise SystemExit(f"{where}: the cuts are out of order")
        parts = [joined[a:b].strip() for a, b in zip(cuts, cuts[1:] + [len(joined)])]
        template = old[0]
        new = [{**template, "ayahStart": a, "ayahEnd": b, "text": part}
               for (a, b, _), part in zip(wanted, parts)]
        if "".join("".join(p.split()) for p in parts) != "".join("".join(r["text"].split()) for r in old):
            raise SystemExit(f"{where}: the words changed")
        gone = {id(r) for r in old}
        result = [r for r in result if id(r) not in gone] + new
        if report is not None:
            report["sectionCorrections"] = report.get("sectionCorrections", 0) + 1
    result.sort(key=lambda r: (r["surahNumber"], r["ayahStart"]))
    return result


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
    translations = {(r["surahNumber"], r["ayahNumber"]): r["text"]
                    for r in load(seed, "quran_translations") if r["editionID"] == TRANSLATION_EDITION}

    all_pages = load(seed, "book_pages")
    by_book = defaultdict(list)
    asrar_pages = defaultdict(list)
    for page in all_pages:
        if page["bookID"].startswith("tafaseer-parah-"):
            by_book[page["bookID"]].append(page)
        elif page["bookID"].startswith("asrar-"):
            asrar_pages[page["bookID"]].append(page["page"])

    for name in ("backCoverPages", "noContentStart", "unresolvedSurahOpenings", "tinySections",
                 "overBudgetRows", "overHardLimit", "missingVolumes"):
        report.setdefault(name, [])
    report.setdefault("openingKinds", {})
    for name in ("quotationsReplacedWithMushaf", "fragmentsReplacedWithMushaf", "oversizeSplits",
                 "citationsReplacedWithMushaf", "crossReferencesReplacedWithMushaf", "markersRenumbered",
                 "markersRenumberedByRow", "citationsMatchedWithoutAnEdgeWord", "quotationsMatchedByLetters"):
        report.setdefault(name, 0)
    for name in ("citationMarkersUnidentified", "citationMarkersAmbiguous"):
        report.setdefault(name, [])

    rows, volumes = [], defaultdict(list)
    for parah in range(1, 31):
        book = f"tafaseer-parah-{parah}"
        pages = sorted(by_book.get(book, []), key=lambda p: p["page"])
        if not pages:
            report["missingVolumes"].append(book)
            continue
        first, last = PARAH_START[parah - 1], parah_end(parah, counts)
        volume = Volume(parah, pages, first, last, counts, names, mushaf, translations, report)
        rows.extend(volume.rows())
        for surah, page in sorted(volume.start_pages().items()):
            volumes[surah].append({"edition": EDITION, "bookID": book, "page": page})
    # Parah 30 part 2 (92-114): its start pages were read off the printed
    # volume, but a link is only written once the book has pages, so the
    # reader never opens an empty book.
    if by_book.get(PART_TWO_BOOK):
        # Read by Claude in November 2026, so it is cut per ayah like the rest.
        pages = sorted(by_book[PART_TWO_BOOK], key=lambda p: p["page"])
        part_two = Volume(30, pages, (92, 1), (114, counts[114]), counts, names, mushaf, translations, report)
        part_two.book = PART_TWO_BOOK
        rows.extend(part_two.rows())
        for surah, page in sorted(PART_TWO_STARTS.items()):
            volumes[surah].append({"edition": EDITION, "bookID": PART_TWO_BOOK, "page": page})
    else:
        report["partTwoLinksWithheld"] = f"{PART_TWO_BOOK} has no pages yet: no links for surahs 92-114"

    # Asrar-at-Tanzil ships one volume per surah and language, opening at its
    # first page.
    for surah in range(1, 115):
        for language in ("ur", "en"):
            book = f"asrar-{surah}-{language}"
            if asrar_pages.get(book):
                volumes[surah].append({"edition": f"asrar-at-tanzil-{language}", "bookID": book,
                                       "page": min(asrar_pages[book])})

    # What the corrections above left as the OCR read it, where its letters
    # are still exactly the mushaf's (correct_by_letters).
    for row in rows:
        row["text"], fixed = correct_by_letters(row["text"], (row["surahNumber"], row["ayahStart"]),
                                                (row["surahNumber"], row["ayahEnd"]), mushaf)
        report["quotationsMatchedByLetters"] += fixed

    # Last, so a row's words do not depend on where it was re-cut.
    rows = apply_section_corrections(rows, report)
    rows.sort(key=lambda r: (r["surahNumber"], r["ayahStart"]))
    keys = [(r["surahNumber"], r["ayahStart"]) for r in rows]
    if len(keys) != len(set(keys)):
        raise SystemExit("duplicate (surah, ayahStart) rows: the segmentation is broken")
    covered = {(r["surahNumber"], a) for r in rows for a in range(r["ayahStart"], r["ayahEnd"] + 1)}
    report.update({
        "rows": len(rows),
        "ayatCovered": len(covered),
        "surahsTouched": len({r["surahNumber"] for r in rows}),
        "largestRowBytes": max(len(r["text"].encode()) for r in rows),
        "commentaryUnderLaterAyah": misfiled(rows, mushaf),
    })
    return rows, {str(k): v for k, v in sorted(volumes.items())}


def misfiled(rows: list[dict], mushaf: Mushaf) -> list[str]:
    """Rows whose commentary quotes three or more of the ayat just before
    their own: the sign of a section cut in the wrong place, the commentary
    on its earlier ayat filed under a later one (2:29 once held 2:21-28's).
    Listed for a person to check; nothing is moved.

    The ayat after the row are searched too. A section's opening quotes them,
    and a formula closing one ("اِنَّ اللّٰهَ غَفُوْرٌ رَّحِيْمٌ") would otherwise be
    counted against the earlier ayah that closes the same way. A cut that
    separates only one or two earlier ayat is not caught by this count."""
    found = []
    for row in rows:
        surah, start, end, text = row["surahNumber"], row["ayahStart"], row["ayahEnd"], row["text"]
        quotes = [m.group(1) for m in QUOTE.finditer(text) if len(HARAKA.findall(m.group(1))) >= 4]
        quotes += [text[s:e] for s, e in quranic_runs(text)]
        earlier = set()
        for quote in quotes:
            hit = mushaf.best(quote, (surah, max(1, start - 30)), (surah, end + 40))
            if hit and hit[0][1] < start:
                earlier.add(hit[0][1])
        if len(earlier) >= 3:
            found.append(f"{surah}:{start}-{end}")
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--write", action="store_true", help="write the seeds named by --targets")
    parser.add_argument("--targets", default="ios,android,harmony,web",
                        help="comma-separated seed folders to write: ios, android, harmony, web")
    parser.add_argument("--report", help="also save the full build report as JSON here")
    parser.add_argument("--requote", action="store_true",
                        help="only give the Akram rows already in the iOS seed the mushaf's words where their letters "
                             "are exactly the mushaf's (correct_by_letters), without cutting them again")
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")

    primary = SEED_DIRS[0]
    if args.requote:
        mushaf = Mushaf(load(primary, "quran_ayahs"))
        tafsir = load(primary, "quran_tafsir")
        fixed = 0
        for row in tafsir:
            if row["editionID"] == EDITION:
                row["text"], count = correct_by_letters(row["text"], (row["surahNumber"], row["ayahStart"]),
                                                        (row["surahNumber"], row["ayahEnd"]), mushaf)
                fixed += count
        print(f"quotations given the mushaf's words by their letters: {fixed}")
        if args.write:
            for target in args.targets.split(","):
                path = SEED_DIRS[TARGETS[target.strip()]] / "quran_tafsir.json"
                with path.open("w", encoding="utf-8", newline="\n") as handle:
                    json.dump(tafsir, handle, ensure_ascii=False, indent=1)
                    handle.write("\n")
                print(f"wrote {path}")
        return 0
    report: dict = {}
    rows, volumes = build(primary, report)
    summary = {k: (v if not isinstance(v, list) or len(v) <= 12 else v[:12] + [f"... {len(v)} in all"])
               for k, v in report.items()}
    print(json.dumps(summary, ensure_ascii=False, indent=1))
    if args.report:
        Path(args.report).write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    if report["overHardLimit"]:
        print("rows over the content gate's hard limit; not writing", file=sys.stderr)
        return 1
    if not args.write:
        return 0

    tafsir = [r for r in load(primary, "quran_tafsir") if r["editionID"] != EDITION] + rows
    tafsir.sort(key=lambda r: (r["editionID"], r["surahNumber"], r["ayahStart"]))
    payloads = {
        "quran_tafsir": tafsir,
        "tafsir_volumes": {"generatedBy": "Tools/Library/segment_akram_tafaseer.py", "surahs": volumes},
    }
    for target in args.targets.split(","):
        seed = SEED_DIRS[TARGETS[target.strip()]]
        for name, payload in payloads.items():
            path = seed / f"{name}.json"
            with path.open("w", encoding="utf-8", newline="\n") as handle:
                json.dump(payload, handle, ensure_ascii=False, indent=1)
                handle.write("\n")
        print(f"wrote {seed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
