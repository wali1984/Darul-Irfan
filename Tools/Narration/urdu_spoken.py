#!/usr/bin/env python3
"""How the narrator speaks text that is not read letter for letter as written.

Shared by the narrator (tts_higgs_ur.py) and the check (verify_narration.py),
so the check expects exactly what the voice was asked to say.
"""

from __future__ import annotations

import re

# Honorifics printed as one symbol are read out in full.
HONORIFICS = {
    "ﷺ": " صلی اللہ علیہ وآلہ وسلم ", "ؐ": " صلی اللہ علیہ وآلہ وسلم ",
    "ؓ": " رضی اللہ عنہ ", "ؒ": " رحمۃ اللہ علیہ ", "ؑ": " علیہ السلام ", "ﷻ": " جل جلالہ ",
}
# The disjointed letters that open some surahs (الم، یس، حٰمٓ) are read as
# the letters' names, as they are recited - never as a word ("یس" is not
# "yes", "الم" is not "pain").
MUQATTAAT = {
    "الم": "الف، لام، میم", "المص": "الف، لام، میم، صاد", "الر": "الف، لام، را", "المر": "الف، لام، میم، را",
    "کہیعص": "کاف، ہا، یا، عین، صاد", "طہ": "طا، ہا", "طسم": "طا، سین، میم", "طس": "طا، سین",
    "یس": "یا، سین", "ص": "صاد", "حم": "حا، میم", "عسق": "عین، سین، قاف", "ق": "قاف", "ن": "نون",
}
# The ayat that open with them (42:2 is عسق).
LETTER_AYAT = {(2, 1), (3, 1), (7, 1), (10, 1), (11, 1), (12, 1), (13, 1), (14, 1), (15, 1), (19, 1), (20, 1), (26, 1),
               (27, 1), (28, 1), (29, 1), (30, 1), (31, 1), (32, 1), (36, 1), (38, 1), (40, 1), (41, 1), (42, 1), (42, 2),
               (43, 1), (44, 1), (45, 1), (46, 1), (50, 1), (68, 1)}
OPENING_LETTERS = re.compile(r"^\s*([\u0621-\u06D3\u064B-\u0670\u06D6-\u06ED]{1,9}?)\s*(۔|$|\s)")


# A number printed in words and again in digits ("سو(100)دانے", "اُنیس (19
# فرشتے)") is read once, in words: the voice read both ("سو سو دانے", 2:261).
BRACKETED_DIGITS = re.compile(r"\(\s*[0-9\u0660-\u0669\u06F0-\u06F9]+\s*\)")
DIGITS_OPENING_NOTE = re.compile(r"\(\s*[0-9\u0660-\u0669\u06F0-\u06F9]+\s+")


def drop_digits(text: str) -> str:
    """Leave out the digits that repeat a number already written in words."""
    return DIGITS_OPENING_NOTE.sub("(", BRACKETED_DIGITS.sub(" ", text))


def spell_letters(text: str) -> str:
    """An opening of disjointed letters, spoken as the letters' names."""
    match = OPENING_LETTERS.match(text)
    if not match:
        return text
    letters = re.sub(r"[\u064B-\u0670\u06D6-\u06ED]", "", match.group(1)).replace("ھ", "ہ")
    spoken = MUQATTAAT.get(letters)
    return f"{spoken}۔ {text[match.end():].strip()}".strip() if spoken else text


def spoken(text: str, surah: int, ayah: int) -> str:
    """What the voice is asked to say for an ayah's translation: honorifics
    in full and the disjointed letters by name (pause and vowel marks aside)."""
    if (surah, ayah) in LETTER_AYAT:
        text = spell_letters(text)
    for symbol, words in HONORIFICS.items():
        text = text.replace(symbol, words)
    return " ".join(text.split())
