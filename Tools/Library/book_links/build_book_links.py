#!/usr/bin/env python3
"""Find, on every page of the Library's books, the words that open something:

  an ayah      a reference such as "(البقرہ: 255)", "سورۃ النور آیت نمبر ۳۱" or "(24:31)",
               and the words of an ayah where a page quotes it
  a narration  the Arabic of a hadith where a page quotes it
  a narrator   the name of a Companion or an imam of hadith ("حضرت ابو ہریرہ")

and write them as `book_links.json`: for each book and printed page a list of
{"m": the words exactly as the page shows them, "t": target}. The apps find each
`m` in the page's text again, literally, and make it tappable (see BookLinks.swift).

The pages are read as the apps lay them out (dump_blocks.mjs writes that), so
every `m` is text the reader actually sees. Before a page's list is written,
the apps' matcher is run over it here: a name or reference that would also catch
other words on the page is left out rather than risk a wrong link.

    node dump_blocks.mjs <book-format.js> <book_pages.json> blocks.jsonl
    python build_book_links.py <SeedData dir> blocks.jsonl book_links.json [--no-hadith]
"""
from __future__ import annotations

import json
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

# --------------------------------------------------------------------- text

ALEFS = set("اأإآٱٲٳ")
YEHS = {c: "ي" for c in "يیىےۓېۍ"}
KAFS = {c: "ك" for c in "كکڪ"}
HEHS = {c: "ه" for c in "هہھةۃۂەۀ"}
WAWS = {c: "و" for c in "وؤۇۆ"}
FOLD = {**YEHS, **KAFS, **HEHS, **WAWS}


def skel(word: str) -> str:
    """The consonant frame of an Arabic word: no vowel marks, no alif, one
    form for each letter that Arabic, Urdu and the mushaf write differently."""
    out = []
    for ch in word:
        if ch in ALEFS or ch in "ءئـ":                # a hamza's seat differs between scripts; tatweel is not a letter
            continue
        if ch in FOLD:
            out.append(FOLD[ch])
            continue
        if "ء" <= ch <= "ي" or "ٱ" <= ch <= "ۓ":
            out.append(ch)
    return "".join(out)


DIGITS = {**{chr(0x06F0 + i): str(i) for i in range(10)}, **{chr(0x0660 + i): str(i) for i in range(10)}}
NUM = r"[0-9۰-۹٠-٩]{1,3}"


def number(text: str) -> int:
    return int("".join(DIGITS.get(c, c) for c in text))


def tokens(line: str) -> list[tuple[int, int, str]]:
    return [(m.start(), m.end(), m.group(0)) for m in re.finditer(r"\S+", line)]


def frames(words: list[str]) -> list[tuple[str, int, int]]:
    """(frame, first word, last word) for each word that has letters. A "و"
    or a "یا" standing alone joins the word after it, as the mushaf writes
    them ("یٰمُوْسٰی")."""
    out: list[tuple[str, int, int]] = []
    carry, lead = None, ""
    for n, word in enumerate(words):
        s = skel(word)
        if not s:
            continue
        if s in ("و", "ي") and carry is None:
            carry, lead = n, s
            continue
        if carry is not None:
            out.append((lead + s, carry, n))
            carry = None
        else:
            out.append((s, n, n))
    if carry is not None:
        out.append((lead, carry, carry))
    return out


# -------------------------------------------------------------------- Qur'an

class Quran:
    def __init__(self, seed: Path):
        ayahs = json.loads((seed / "quran_ayahs.json").read_text(encoding="utf-8"))
        surahs = json.loads((seed / "quran_surahs.json").read_text(encoding="utf-8"))
        self.count = {s["id"]: s["ayahCount"] for s in surahs}
        self.stream: list[str] = []
        self.where: list[tuple[int, int]] = []
        for a in ayahs:
            for s, _, _ in frames(a["textArabic"].split()):
                self.stream.append(s)
                self.where.append((a["surahNumber"], a["ayahNumber"]))
        self.index: dict[tuple[str, str, str], list[int]] = defaultdict(list)
        for i in range(len(self.stream) - 2):
            self.index[(self.stream[i], self.stream[i + 1], self.stream[i + 2])].append(i)
        self.names: dict[str, int] = {}
        for s in surahs:
            self.add_name(s["nameArabic"], s["id"])
        for number_, aliases in SURAH_ALIASES.items():
            for alias in aliases:
                self.add_name(alias, number_)

    def add_name(self, name: str, surah: int) -> None:
        key = skel(name.replace(" ", ""))
        if key:
            self.names.setdefault(key, surah)
            if key.startswith("ل") and len(key) > 3:
                self.names.setdefault(key[1:], surah)

    def surah(self, name: str) -> int | None:
        name = re.sub(r"^\s*سور[ۃةہه]\s*", "", name.strip())
        key = skel(name.replace(" ", ""))
        if not key:
            return None
        return self.names.get(key) or self.names.get("ل" + key) or (self.names.get(key[1:]) if key.startswith("ل") else None)

    def valid(self, surah: int, ayah: int) -> bool:
        return surah in self.count and 1 <= ayah <= self.count[surah]

    def spans(self, sk: list[str], least: int) -> list[tuple[int, int, list[int]]]:
        """Runs of `sk` that are the mushaf's own words in order: (start, length,
        positions in the mushaf where that run stands)."""
        out, j, n, total = [], 0, len(sk), len(self.stream)
        while j <= n - 3:
            best, at = 0, []
            for pos in self.index.get((sk[j], sk[j + 1], sk[j + 2]), ()):
                length = 3
                while j + length < n and pos + length < total and self.stream[pos + length] == sk[j + length]:
                    length += 1
                if length > best:
                    best, at = length, [pos]
                elif length == best:
                    at.append(pos)
            if best >= least:
                out.append((j, best, at))
                j += best
            else:
                j += 1
        return out


# Names the books use for a surah beside the mushaf's own.
SURAH_ALIASES = {
    1: ["الفاتحہ", "فاتحہ", "الحمد"], 9: ["التوبہ", "توبہ", "براءۃ", "برأۃ"], 17: ["بنی اسرائیل", "بنی اسرائیل", "الاسراء", "اسراء"],
    32: ["السجدہ", "الم سجدہ", "الم السجدہ"], 35: ["فاطر", "الملائکہ"], 40: ["المؤمن", "المومن", "غافر"],
    41: ["حم السجدہ", "حٰم السجدہ", "فصلت", "حم سجدہ"], 47: ["محمد", "القتال"], 67: ["الملک", "تبارک"], 76: ["الدہر", "الدھر", "الانسان"],
    78: ["النبا", "عم"], 94: ["الم نشرح", "الانشراح", "الشرح", "انشراح"], 96: ["العلق", "اقرا", "اقرأ"], 98: ["البینہ", "لم یکن"],
    99: ["الزلزال", "الزلزلہ", "زلزال"], 106: ["قریش", "القریش"], 108: ["الکوثر"], 110: ["النصر"], 111: ["اللہب", "تبت", "المسد"],
    112: ["الاخلاص", "اخلاص"], 36: ["یٰسین", "یسین", "یس"], 20: ["طہ", "طٰہٰ"], 38: ["ص", "صٓ"], 50: ["ق", "قٓ"], 68: ["القلم", "ن", "نٓ"],
    5: ["المائدہ", "مائدہ"], 2: ["البقرہ", "البقرۃ", "بقرہ"], 3: ["آل عمران", "ال عمران"], 4: ["النساء", "النسآء", "النسآ", "نساء"],
    33: ["الاحزاب"], 24: ["النور"], 49: ["الحجرات"], 55: ["الرحمٰن", "الرحمن"], 21: ["الانبیاء", "الانبیآء"], 26: ["الشعراء", "الشعرآء"],
    37: ["الصافات", "الصّٰفٰت", "الصفت"], 42: ["الشوریٰ", "الشوری"], 53: ["النجم"], 57: ["الحدید"], 63: ["المنافقون", "المنٰفقون"],
    23: ["المؤمنون", "المومنون"], 87: ["الاعلیٰ", "الاعلی"], 92: ["اللیل"], 93: ["الضحیٰ", "الضحی"], 13: ["الرعد"], 11: ["ھود", "ہود"],
}

# The first ayah of each of the thirty parts (surah, ayah).
JUZ = [(1, 1), (2, 142), (2, 253), (3, 93), (4, 24), (4, 148), (5, 82), (6, 111), (7, 88), (8, 41), (9, 93), (11, 6),
       (12, 53), (15, 1), (17, 1), (18, 75), (21, 1), (23, 1), (25, 21), (27, 56), (29, 46), (33, 31), (36, 28),
       (39, 32), (41, 47), (46, 1), (51, 31), (58, 1), (67, 1), (78, 1), (115, 1)]


def book_scope(book: str):
    """Where a tafsir volume's own ayat lie: a predicate on (surah, ayah)."""
    m = re.fullmatch(r"asrar-(\d+)-(?:en|ur)", book)
    if m:
        surah = int(m.group(1))
        return lambda s, a: s == surah
    m = re.fullmatch(r"tafaseer-parah-(\d+)(?:-part-\d+)?", book)
    if m:
        part = int(m.group(1))
        low, high = JUZ[part - 1], JUZ[part]
        return lambda s, a: low <= (s, a) < high
    return None


REF_NAME = re.compile(
    r"[\(\[（﴿]\s*(?:سور[ۃةہه]\s*)?(?P<name>[؀-ۿ][؀-ۿ\s]{0,24}?)\s*[:：،,\-]?\s*"
    r"(?:آیت\s*(?:نمبر)?\s*[:：]?\s*)?(?P<a>" + NUM + r")(?:\s*(?:[-–،,]|تا)\s*(?P<b>" + NUM + r"))?\s*[\)\]）﴾]")
REF_SURAH = re.compile(
    r"سور[ۃةہه]\s+(?P<name>[؀-ۿ]+(?:\s+[؀-ۿ]+)?)\s*(?:،|:|کی|,)?\s*\(?\s*آیت\s*(?:نمبر)?\s*[:：]?\s*"
    r"(?P<a>" + NUM + r")(?:\s*(?:[-–]|تا)\s*(?P<b>" + NUM + r"))?\)?")
REF_NUMBERS = re.compile(
    r"[\(\[]\s*(?P<word>(?:القرآن الکریم|القرآن|قرآن|Al-?Qur'?an|Qur'?an)\s*[:،,]?\s*)?(?P<s>" + NUM + r")\s*[:：]\s*"
    r"(?P<a>" + NUM + r")(?:\s*[-–]\s*(?P<b>" + NUM + r"))?\s*[\)\]]")


AYAH_MARK = re.compile(r"﴿\s*(" + NUM + r")\s*﴾")


def target(surah: int, first: int, last: int | None = None) -> str:
    return f"q:{surah}:{first}-{last}" if last and last > first else f"q:{surah}:{first}"


# ------------------------------------------------------------------ narrators

HONOUR_BEFORE = ["حضرت سیدنا", "حضرت سیدہ", "حضرت", "سیدنا", "سیّدنا", "سیدہ", "سیّدہ", "امیرالمومنین", "امیر المومنین",
                 "امیر المؤمنین", "ام المومنین", "ام المؤمنین", "اُمّ المؤمنین", "خلیفہ"]
HONOUR_AFTER = ["ؓ", " ؓ", " رضی اللہ عنہ", " رضی اللہ تعالیٰ عنہ", " رضی اللہ عنہا", " رضی اللہ تعالیٰ عنہا",
                " کرم اللہ وجہہ", " کرّم اللہ وجہہ"]
# What may follow a single name for it to be that person and not the start of
# another name ("حضرت علی ہجویری", "حضرت عمر بن عبدالعزیز").
AFTER_NAME = {"نے", "کو", "کا", "کی", "کے", "سے", "پر", "میں", "اور", "بھی", "تک", "ہی", "تو", "و", "یا", "کہ", "رضی", "کرم", "کرّم",
              "فرماتے", "فرماتی", "فرمایا", "کہتے", "کہتی", "روایت", "بیان", "ہیں", "تھے", "تھیں", "جیسے", "جیسی", "خود", "جب", "اس", "ان",
              "المرتضیٰ", "مرتضیٰ", "صدیق", "صدیقہ", "فاروق", "غنی", "ذوالنورین"}

# narrator id -> (names that stand on their own, names that need an honorific beside them)
PEOPLE: dict[int, tuple[list[str], list[str]]] = {
    4945: (["ابوبکر صدیق", "ابو بکر صدیق", "صدیق اکبر", "صدیقِ اکبر", "ابوبکر الصدیق"], ["ابوبکر", "ابو بکر"]),
    5913: (["عمر فاروق", "فاروق اعظم", "فاروقِ اعظم", "عمر بن خطاب", "عمر بن الخطاب", "عمرِ فاروق"], ["عمر"]),
    5543: (["عثمان غنی", "عثمانِ غنی", "عثمان بن عفان", "عثمان ذوالنورین"], ["عثمان"]),
    5722: (["علی المرتضیٰ", "علی مرتضیٰ", "علی بن ابی طالب", "علی ابن ابی طالب"], ["علی"]),
    4049: (["عائشہ صدیقہ", "عائشۃ الصدیقہ", "عائشہ الصدیقہ", "عائشۃ الصدیقۃ", "عائشہ بنت ابی بکر"], ["عائشہ"]),
    4883: (["عبداللہ بن عباس", "عبد اللہ بن عباس", "عبداللہ ابن عباس", "ابن عباس", "ابنِ عباس"], []),
    4396: (["ابو ہریرہ", "ابوہریرہ", "ابوہریرۃ", "ابو ہریرۃ", "ابو ھریرہ"], []),
    720: (["انس بن مالک"], ["انس"]),
    4967: (["عبداللہ بن عمر", "عبد اللہ بن عمر", "عبداللہ ابن عمر", "ابن عمر", "ابنِ عمر"], []),
    5079: (["عبداللہ بن مسعود", "عبد اللہ بن مسعود", "عبداللہ ابن مسعود", "ابن مسعود", "ابنِ مسعود"], []),
    2069: (["جابر بن عبداللہ", "جابر بن عبد اللہ"], ["جابر"]),
    3260: (["ابو سعید خدری", "ابوسعید خدری", "ابو سعید الخدری", "ابوسعید الخدری"], []),
    7547: (["معاذ بن جبل"], ["معاذ"]),
    2187: (["ابوذر غفاری", "ابو ذر غفاری", "ابوذر الغفاری"], ["ابوذر", "ابو ذر"]),
    3476: (["سلمان فارسی", "سلمان الفارسی"], ["سلمان"]),
    5021: (["ابو موسیٰ اشعری", "ابوموسیٰ اشعری", "ابو موسی اشعری", "ابوموسیٰ الاشعری"], []),
    7570: (["امیر معاویہ", "معاویہ بن ابی سفیان"], ["معاویہ"]),
    50207: (["خدیجۃ الکبریٰ", "خدیجہ الکبریٰ", "خدیجۃ الکبری"], ["خدیجہ"]),
    6388: (["فاطمۃ الزہرا", "فاطمہ الزہرا", "فاطمۃ الزہراء", "فاطمہ الزہراء", "فاطمہ زہرا"], ["فاطمہ"]),
    1281: (["امام حسن", "حسن بن علی"], ["حسن"]),
    1336: (["امام حسین", "حسین بن علی"], ["حسین"]),
    2457: ([], ["حفصہ"]),
    2324: (["حذیفہ بن یمان", "حذیفہ بن الیمان"], ["حذیفہ"]),
    1963: (["بلال حبشی", "بلال بن رباح"], ["بلال"]),
    4180: (["عباس بن عبدالمطلب", "عباس بن عبد المطلب"], ["عباس"]),
    2650: (["ابو ایوب انصاری", "ابوایوب انصاری", "ابو ایوب الانصاری"], []),
    2630: (["خالد بن ولید", "خالد بن الولید"], []),
    3131: (["زید بن ثابت"], []),
    31696: (["مصعب بن عمیر"], []),
    3232: (["سعد بن ابی وقاص"], []),
    4697: (["عبداللہ بن زبیر", "عبد اللہ بن زبیر", "ابن زبیر"], []),
    6271: (["ابو درداء", "ابودرداء", "ابو الدرداء", "ابوالدرداء"], []),
    396: (["ابی بن کعب", "اُبی بن کعب"], []),
    4461: (["عبدالرحمٰن بن عوف", "عبدالرحمن بن عوف", "عبد الرحمٰن بن عوف"], []),
    4018: (["طلحہ بن عبیداللہ", "طلحہ بن عبید اللہ"], ["طلحہ"]),
    1427: (["زبیر بن عوام", "زبیر بن العوام"], ["زبیر"]),
    4106: (["ابو عبیدہ بن جراح", "ابوعبیدہ بن جراح", "ابو عبیدہ بن الجراح"], ["ابوعبیدہ", "ابو عبیدہ"]),
    5860: (["عمار بن یاسر"], []),
    3964: (["صہیب رومی"], ["صہیب"]),
    532: (["اسامہ بن زید"], []),
    8101: (["ام سلمہ", "اُم سلمہ", "امِ سلمہ"], []),
    553: (["اسماء بنت ابی بکر", "اسماء بنت ابوبکر"], []),
    1157: (["براء بن عازب"], []),
    6086: (["عمرو بن عاص", "عمرو بن العاص"], []),
    4980: (["عبداللہ بن عمرو", "عبد اللہ بن عمرو"], []),
    1665: (["مغیرہ بن شعبہ"], []),
    5575: (["عدی بن حاتم"], []),
    2955: (["ام حبیبہ", "اُم حبیبہ"], []),
    3929: (["ابو امامہ", "ابوامامہ"], []),
    3642: (["سمرہ بن جندب"], []),
    3672: (["سہل بن سعد"], []),
    1239: (["حسن بصری"], []),
    3299: (["سعید بن مسیب", "سعید بن المسیب", "سعید ابن مسیب"], []),
    3436: (["سفیان ثوری"], []),
    4716: (["عبداللہ بن مبارک", "عبد اللہ بن مبارک", "عبداللہ ابن مبارک"], []),
    6659: (["امام مالک", "مالک بن انس"], []),
    6805: (["امام شافعی"], []),
    488: (["امام احمد بن حنبل", "احمد بن حنبل", "امام احمد"], []),
    6817: (["امام بخاری"], []),
    7457: (["امام مسلم"], []),
    30371: (["امام ترمذی"], []),
    3567: (["امام ابو داؤد", "امام ابوداؤد", "امام ابو داود", "امام ابوداود"], []),
    9880: (["امام نسائی"], []),
    31013: (["امام ابن ماجہ", "امام ابنِ ماجہ"], []),
    1734: (["امام ابو حنیفہ", "امام ابوحنیفہ", "امام اعظم ابو حنیفہ", "امام اعظم ابوحنیفہ"], []),
    2163: (["امام جعفر صادق", "جعفر صادق"], []),
    5974: (["عمر بن عبدالعزیز", "عمر بن عبد العزیز"], []),
    7016: (["ابن سیرین", "ابنِ سیرین", "محمد بن سیرین"], []),
    6715: (["امام مجاہد"], []),
    11092: (["اویس قرنی"], []),
}
# Words after a whole name that make it someone else.
NOT_FOLLOWED = {"امام احمد": ["رضا", "سرہندی", "علی", "یار"], "امام حسن": ["بصری", "عسکری"]}
# "حضرت حسن" alone is as often Hasan of Basra: these need رضی اللہ عنہ beside them.
NEEDS_SALUTATION = {"حسن"}
ARABIC_LETTER = re.compile("[ء-يٱ-ۓًٰ-ْ]")


def name_finder():
    whole, single = {}, {}
    for narrator, (names, lone) in PEOPLE.items():
        for name in names:
            whole[name] = narrator
        for name in lone:
            single[name] = narrator
    alternatives = sorted(set(whole) | set(single), key=len, reverse=True)
    pattern = re.compile("|".join(re.escape(a) for a in alternatives))
    return whole, single, pattern


WHOLE, SINGLE, NAME = name_finder()
BEFORE = re.compile("(?:" + "|".join(re.escape(h) for h in sorted(HONOUR_BEFORE, key=len, reverse=True)) + r")\s+$")
AFTER = re.compile("^(?:" + "|".join(re.escape(h) for h in sorted(HONOUR_AFTER, key=len, reverse=True)) + ")")


def names_in(text: str) -> list[tuple[int, int, int]]:
    """(start, end, narrator id) for each name in `text` that is surely that person."""
    found = []
    for m in NAME.finditer(text):
        start, end, name = m.start(), m.end(), m.group(0)
        if start and ARABIC_LETTER.match(text[start - 1]):
            continue                                            # inside a longer word
        rest = text[end:]
        if rest and ARABIC_LETTER.match(rest[0]):
            continue
        following = re.match(r"\s*([؀-ۿ]+)", rest)
        nxt = following.group(1) if following else ""
        if nxt in ("بن", "ابن", "بنت", "ابنِ"):
            continue                                            # the start of a longer name
        if name in WHOLE:
            if nxt in NOT_FOLLOWED.get(name, ()):
                continue
            if text[:start].rstrip().endswith(("بن", "ابن", "بنت", "ابنِ")) and not name.startswith(("ابن", "ام ", "اُم")):
                continue                                        # "فلاں بن عمر فاروق": another man's father
            found.append((start, end, WHOLE[name]))
            continue
        before = BEFORE.search(text[:start])
        after = AFTER.match(rest)
        if not before and not after:
            continue
        if text[:start].rstrip().endswith(("بن", "ابن", "بنت")):
            continue
        if after:
            found.append((start, end + len(after.group(0)), SINGLE[name]) if not before else
                         (before.start(), end + len(after.group(0)), SINGLE[name]))
        elif name not in NEEDS_SALUTATION and (not nxt or nxt in AFTER_NAME):
            found.append((before.start(), end, SINGLE[name]))
    return found


# --------------------------------------------------------------------- hadith

class Hadith:
    """Every narration's Arabic as one stream of word frames, to find a quotation in."""
    ORDER = ["bukhari", "muslim", "abudawud", "tirmidhi", "nasai", "ibnmajah", "malik", "ahmad", "darimi", "mishkat",
             "riyadussalihin", "adab", "shamail", "nawawi40", "qudsi40", "bulugh", "hisn", "virtues", "ibnkhuzayma",
             "ibnhibban", "hakim", "daraqutni", "nasaikubra", "bayhaqi", "abdurrazzaq", "ibnabishayba"]
    TRANSLATED = 18          # ORDER[:18] are the collections the app has in English or Urdu

    def __init__(self, seed: Path):
        import numpy as np
        self.np = np
        words: list[str] = []
        owner: list[int] = []
        self.ids: list[str] = []
        self.rank: list[int] = []
        vocabulary: dict[str, int] = {}
        for rank, book in enumerate(self.ORDER):
            path = seed / f"hadith_{book}.json"
            if not path.exists():
                continue
            for entry in json.loads(path.read_text(encoding="utf-8")):
                text = entry.get("text_ar") or " ".join(s.get("text", "") for s in entry.get("arabicSegments") or [])
                if not text:
                    continue
                number_ = len(self.ids)
                self.ids.append(entry["canonicalID"])
                self.rank.append(rank)
                for s, _, _ in frames(text.split()):
                    words.append(vocabulary.setdefault(s, len(vocabulary)))
                    owner.append(number_)
        self.vocabulary = vocabulary
        self.words = np.array(words, dtype=np.int64)
        self.owner = np.array(owner, dtype=np.int32)
        w = self.words.astype(np.uint64)
        prime = np.uint64(self.PRIME)
        with np.errstate(over="ignore"):
            grams = ((w[:-3] * prime + w[1:-2]) * prime + w[2:-1]) * prime + w[3:]     # wraps at 2**64
        order = np.argsort(grams, kind="stable")
        self.grams, self.positions = grams[order], order

    PRIME = 1000003

    def gram(self, a: int, b: int, c: int, d: int) -> int:
        mask, h = (1 << 64) - 1, a
        for word in (b, c, d):
            h = (h * self.PRIME + word) & mask
        return h

    def best(self, sk: list[str], least: int = 5):
        """The longest run of `sk` found inside one narration: (start, length,
        canonical id of the first collection in ORDER that has it)."""
        np = self.np
        codes = [self.vocabulary.get(w, -1) for w in sk]
        best, best_score = (0, 0, None), -1
        j, n = 0, len(codes)
        while j <= n - 4:
            if min(codes[j:j + 4]) < 0:
                j += 1
                continue
            g = np.uint64(self.gram(*codes[j:j + 4]))
            lo, hi = int(np.searchsorted(self.grams, g, "left")), int(np.searchsorted(self.grams, g, "right"))
            top, top_score, where = 0, -1, None
            for pos in self.positions[lo:min(hi, lo + 400)]:
                pos = int(pos)
                if [int(x) for x in self.words[pos:pos + 4]] != codes[j:j + 4]:
                    continue
                length, owner = 4, self.owner[pos]
                while (j + length < n and pos + length < len(self.words) and self.owner[pos + length] == owner
                       and int(self.words[pos + length]) == codes[j + length]):
                    length += 1
                rank = self.rank[owner]
                score = length - (0 if rank < self.TRANSLATED else 2)
                if score > top_score or (score == top_score and where is not None and rank < self.rank[where]):
                    top, top_score, where = length, score, int(owner)
            if top >= least and top_score > best_score:
                best, best_score = (j, top, self.ids[where]), top_score
            j += max(1, top - 2) if top >= least else 1
        return best if best[2] else None


# Words every chain and salutation shares: a quotation must have more than these to be a narration.
FORMULA = {skel(w) for w in """صلي الله عليه وسلم واله وآله وعلي وصحبه رضي عنه عنها عنهما عنهم تعالي عن قال قالت قالوا وقال فقال
    رسول النبي نبي ان انه سمعت يقول حدثنا اخبرنا حدثني اخبرني بن ابن بنت ابي ابو ابا ام عليهم عليهما السلام عبد رحمه رحمة
    والسلام عليكم ورحمة وبركاته""".split()}


# ---------------------------------------------------------------------- pages

def client_pieces(text: str, links: list[dict]) -> list[tuple[int, int, int]]:
    """The apps' matcher: (start, end, index of the link) for every tappable range."""
    taken: list[tuple[int, int, int]] = []
    for index in sorted(range(len(links)), key=lambda i: -len(links[i]["m"])):
        needle = links[index]["m"]
        at = text.find(needle)
        while at != -1:
            end = at + len(needle)
            if not any(a < end and at < b for a, b, _ in taken):
                taken.append((at, end, index))
            at = text.find(needle, end)
    return sorted(taken)


def build(seed: Path, blocks: Path, with_hadith: bool) -> tuple[dict, Counter]:
    quran = Quran(seed)
    hadith = Hadith(seed) if with_hadith else None
    stats: Counter = Counter()
    pages = [json.loads(line) for line in blocks.read_text(encoding="utf-8").splitlines() if line.strip()]

    # A book whose bare "(2: 101)" are volume and page of another work, not surah and ayah.
    bare = defaultdict(lambda: [0, 0])
    for page in pages:
        for el in page["els"]:
            for m in REF_NUMBERS.finditer(el["t"]):
                if not m.group("word"):
                    s, a = number(m.group("s")), number(m.group("a"))
                    bare[page["b"]][0 if quran.valid(s, a) or quran.valid(a, s) else 1] += 1
    numeric_books = {book for book, (good, bad) in bare.items() if good and bad <= 0.15 * (good + bad)}

    books: dict[str, dict[str, list[dict]]] = {}
    for page in pages:
        book, scope = page["b"], book_scope(page["b"])
        own = re.fullmatch(r"asrar-(\d+)-(?:en|ur)", book)
        own_surah = int(own.group(1)) if own else None
        wanted: dict[tuple[int, int, int], str] = {}             # (element, start, end) -> target
        cited: set[tuple[int, int]] = set()

        def want(el_index: int, start: int, end: int, t: str, kind: str) -> None:
            if end - start < 4 or "\n" in page["els"][el_index]["t"][start:end]:
                return
            if any(e == el_index and a < end and start < b for (e, a, b) in wanted):
                return
            wanted[(el_index, start, end)] = t
            stats[kind] += 1

        # 1. references
        for i, el in enumerate(page["els"]):
            text = el["t"]
            for m in REF_SURAH.finditer(text):
                surah = quran.surah(m.group("name"))
                if surah is None and " " in m.group("name"):
                    surah = quran.surah(m.group("name").split()[0])
                a = number(m.group("a"))
                b = number(m.group("b")) if m.group("b") else None
                if surah and quran.valid(surah, a):
                    cited.add((surah, a))
                    want(i, m.start(), m.end(), target(surah, a, b if b and quran.valid(surah, b) else None), "reference by name")
            for m in REF_NAME.finditer(text):
                if len(skel(m.group("name"))) < 2:
                    continue                                     # "(ص ۲۵)" is a page, not Surah Sad
                surah = quran.surah(m.group("name"))
                a = number(m.group("a"))
                b = number(m.group("b")) if m.group("b") else None
                if surah and quran.valid(surah, a):
                    cited.add((surah, a))
                    want(i, m.start(), m.end(), target(surah, a, b if b and quran.valid(surah, b) else None), "reference by name")
            for m in REF_NUMBERS.finditer(text):
                if not m.group("word") and book not in numeric_books:
                    continue
                s, a = number(m.group("s")), number(m.group("a"))
                b = number(m.group("b")) if m.group("b") else None
                if not quran.valid(s, a) and quran.valid(a, s) and not b:
                    s, a = a, s                                  # written ayah first
                if quran.valid(s, a):
                    cited.add((s, a))
                    want(i, m.start(), m.end(), target(s, a, b if b and quran.valid(s, b) else None), "reference by number")

        # 2. quotations: the mushaf first, then the collections of hadith
        for i, el in enumerate(page["els"]):
            flagged = el["k"] == "quran" or (el["k"] == "run" and el.get("q"))
            offset = 0
            for line in el["t"].split("\n"):
                toks = tokens(line)
                framed = frames([t for _, _, t in toks])
                sk = [f for f, _, _ in framed]
                used = [False] * len(sk)
                # Words of the mushaf are never a narration, linked or not.
                for start, length, _ in quran.spans(sk, 3):
                    for k in range(start, start + length):
                        used[k] = True
                for start, length, positions in quran.spans(sk, 4 if not flagged else 3):
                    letters = sum(len(f) for f in sk[start:start + length])
                    if length == 3 and letters < 12:
                        continue
                    if length < 5 and not flagged and letters < 16:
                        continue
                    places = []
                    for pos in positions:
                        s1, a1 = quran.where[pos]
                        s2, a2 = quran.where[pos + length - 1]
                        if (s1, a1, a2 if s2 == s1 else a1) not in places:
                            places.append((s1, a1, a2 if s2 == s1 else a1))
                    chosen = None
                    if len(places) == 1:
                        chosen = places[0]
                    else:
                        near = [p for p in places if any((p[0], a) in cited for a in range(p[1], p[2] + 1))]
                        inside = [p for p in places if scope and scope(p[0], p[1])]
                        if len(near) == 1:
                            chosen = near[0]
                        elif len(inside) >= 1:
                            chosen = inside[0]
                        elif len(places) <= 3 or len({p[0] for p in places}) == 1:
                            chosen = places[0]                   # a refrain: its first place in the surah
                    if not chosen:
                        stats["quotation found in many ayat, left plain"] += 1
                        continue
                    first, last = framed[start][1], framed[start + length - 1][2]
                    want(i, offset + toks[first][0], offset + toks[last][1], target(*chosen), "ayah quoted")
                if own_surah and flagged and sk and not any(e == i and offset <= a < offset + len(line) for (e, a, b) in wanted):
                    marks = AYAH_MARK.findall(line)
                    if len(marks) == 1 and line.rstrip().endswith("﴾") and quran.valid(own_surah, number(marks[0])):
                        body = line[:line.rindex("﴿")].rstrip()
                        if len(body.split()) >= 2:
                            start_at = len(line) - len(line.lstrip())
                            want(i, offset + start_at, offset + len(body), target(own_surah, number(marks[0])), "ayah by its number")
                if hadith and el["k"] in ("arabic", "run", "quran"):
                    # the longest stretch of words the mushaf does not claim
                    stretch, current = [], []
                    for k, u in enumerate(used):
                        if u:
                            current = []
                        else:
                            current.append(k)
                            if len(current) > len(stretch):
                                stretch = current[:]
                    if len(stretch) >= 5:
                        base = stretch[0]
                        found = hadith.best(sk[base:base + len(stretch)])
                        if found:
                            start, length, canonical = found
                            body = [w for w in sk[base + start:base + start + length] if w not in FORMULA]
                            if len(body) >= 4 and sum(map(len, body)) >= 18:
                                first, last = framed[base + start][1], framed[base + start + length - 1][2]
                                want(i, offset + toks[first][0], offset + toks[last][1], "h:" + canonical, "narration quoted")
                offset += len(line) + 1

        # 3. names
        for i, el in enumerate(page["els"]):
            if el["k"] == "quran" or el["k"] == "arabic" or (el["k"] == "run" and el.get("q")):
                continue
            for start, end, narrator in names_in(el["t"]):
                want(i, start, end, f"n:{narrator}", "narrator named")

        if not wanted:
            continue
        # One target for one wording on a page, then what the apps would link.
        links: list[dict] = []
        by_words: dict[str, str] = {}
        for (i, start, end), t in sorted(wanted.items()):
            m = page["els"][i]["t"][start:end]
            if m not in by_words:
                by_words[m] = t
                links.append({"m": m, "t": t})
        while True:
            wrong = set()
            for i, el in enumerate(page["els"]):
                for start, end, index in client_pieces(el["t"], links):
                    if wanted.get((i, start, end)) != links[index]["t"]:
                        wrong.add(index)
            if not wrong:
                break
            stats["left out: would catch other words"] += len(wrong)
            links = [link for index, link in enumerate(links) if index not in wrong]
        if links:
            books.setdefault(book, {})[str(page["p"])] = links
            stats["pages with links"] += 1
            stats["links"] += len(links)
    return {"version": 1, "books": books}, stats


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    seed, blocks, out = Path(args[0]), Path(args[1]), Path(args[2])
    result, stats = build(seed, blocks, "--no-hadith" not in sys.argv)
    out.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")), encoding="utf-8", newline="")
    for name, count in sorted(stats.items()):
        print(f"{count:>8}  {name}")
    print(f"{len(result['books'])} books; {out} is {out.stat().st_size / 1e6:.2f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
