#!/usr/bin/env python3
"""Give every narrator's biography its English and its Urdu.

The narrator store came with the scholars' appraisals in Arabic only, 16,422 of
them filed under the English key, English facts written letter for letter from
the Arabic ("al-Syql", "Abu Arwى") and the Arabic columns standing in for Urdu.
This writes, for every narrator:

  appraisals   each one as scholarArabic / scholar / scholarUrdu and
               textArabic / textEnglish / textUrdu; rows with no words are dropped
  facts        cities, profession, byname, madhhab, description and generation in
               English and in Urdu (citiesUrdu, professionUrdu, ...)
  names        the name, lineage, kunya and affiliations in English with their
               vowels (the store wrote unknown names without them: "al-Hakm",
               "Smak") and in Urdu spelling (nameUrdu, lineageUrdu, kunyaUrdu,
               affiliationsUrdu)

The wording comes from `narrator_translations.json.gz` (one entry per distinct
Arabic text, keyed as below), so the same Arabic always reads the same way.

    python Tools/Hadith/apply_narrator_translations.py            # report only
    python Tools/Hadith/apply_narrator_translations.py --write    # update the iOS seed

Only the iOS seed is written; the release sync copies it to the other platforms.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path

IOS_ROOT = Path(__file__).resolve().parents[2]
SEED = IOS_ROOT / "DarulIrfanApp/Resources/SeedData/hadith_narrators.json"
TABLE = Path(__file__).resolve().parent / "narrator_translations.json.gz"

ARABIC = re.compile("[؀-ۿ]")
LETTER = re.compile("[ء-يٱ-ۓ]")      # a word, not only punctuation
HARAKAT = re.compile("[ً-ْـ]")


def key(kind: str, text: str, field: str = "") -> str:
    return kind + "-" + hashlib.sha1((field + "\x00" + text).encode("utf-8")).hexdigest()[:16]


def parts(value: str | None) -> list[str]:
    """A fact column holds several values joined by the Arabic comma."""
    return [p.strip() for p in re.split(r"\s*[،,]\s*", value or "") if p.strip()]


# Names that truly end in alif maqsura keep it in Urdu (یحییٰ، موسیٰ). Every
# other final ى in the store is the Egyptian way of writing a final ي (الرازى).
ALIF_MAQSURA = {
    "يحيى", "موسى", "عيسى", "مصطفى", "المصطفى", "مرتضى", "المرتضى", "مجتبى", "ليلى", "سلمى", "سعدى",
    "المثنى", "مثنى", "الأعلى", "يعلى", "المعلى", "معلى", "أروى", "أوفى", "أبزى", "بشرى", "الأعشى",
    "الكبرى", "الصغرى", "الوسطى", "حبى", "رضوى", "نجوى",
}
URDU_LETTERS = str.maketrans({
    "ي": "ی", "ك": "ک", "ة": "ہ", "ه": "ہ", "أ": "ا", "إ": "ا", "ٱ": "ا", "ى": "ی",
})


def urdu_name(arabic: str | None) -> str | None:
    """An Arabic name in Urdu spelling: Urdu letters, no vowel marks."""
    if not arabic:
        return None
    words = []
    for word in HARAKAT.sub("", arabic).split():
        core = word.strip("،,.:؛()[]")
        if core in ALIF_MAQSURA and core.endswith("ى"):
            word = word.replace(core, core[:-1] + "یٰ")
        words.append(word.translate(URDU_LETTERS))
    return " ".join(words) or None


ORDINAL_FIX = re.compile(r"^(\d+)(st|nd|rd|th)$")


def english_ordinal(value: str | None) -> str | None:
    match = ORDINAL_FIX.match(value or "")
    if not match:
        return value
    n = int(match.group(1))
    suffix = "th" if 10 <= n % 100 <= 20 else {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
    return f"{n}{suffix}"


def unique(values: list[str]) -> list[str]:
    seen, out = set(), []
    for v in values:
        if v and v.casefold() not in seen:
            seen.add(v.casefold())
            out.append(v)
    return out


class Table:
    def __init__(self, rows: dict[str, list[str]]):
        self.rows = rows
        self.missing: Counter = Counter()

    def get(self, kind: str, text: str, field: str = "") -> tuple[str | None, str | None]:
        row = self.rows.get(key(kind, text, field))
        if row is None:
            self.missing[kind] += 1
            return None, None
        urdu = row[1]
        if kind != "appr":
            urdu = urdu.replace("ة", "ہ")          # a name's ta marbuta, as Urdu writes it
        return row[0], urdu

    def fact(self, value: str | None, field: str) -> tuple[str | None, str | None]:
        english, urdu = [], []
        for p in parts(value):
            en, ur = self.get("fact", p, field)
            if en is None:
                return None, None
            english.append(en)
            urdu.append(ur)
        if not english:
            return None, None
        return ", ".join(unique(english)), "، ".join(unique(urdu))

    def names(self, value: str | None, whole: bool) -> tuple[str | None, str | None]:
        english, urdu = [], []
        for p in ([value.strip()] if whole else parts(value)):
            en, ur = self.get("name", p)
            if en is None:
                return None, None
            english.append(en)
            urdu.append(ur)
        if not english:
            return None, None
        return ", ".join(english), "، ".join(urdu)


def clean_label(label: str) -> str:
    return label.strip().rstrip(":،,. ").strip()


def apply(narrators: list[dict], table: Table) -> Counter:
    stats: Counter = Counter()
    for n in narrators:
        # Names, in English and in Urdu. A name the table lacks keeps the
        # store's English and takes its Urdu spelling by rule.
        for english, arabic, urdu, whole in (("nameEnglish", "nameArabic", "nameUrdu", True),
                                             ("lineageEnglish", "lineageArabic", "lineageUrdu", True),
                                             ("kunya", "kunyaArabic", "kunyaUrdu", False),
                                             ("affiliations", "affiliationsArabic", "affiliationsUrdu", False)):
            if not n.get(arabic):
                continue
            en, ur = table.names(n[arabic], whole)
            if en:
                n[english], n[urdu] = en, ur
                stats["names"] += 1
            else:
                n[urdu] = "، ".join(urdu_name(p) for p in ([n[arabic]] if whole else parts(n[arabic])))
                if n.get(english):
                    n[english] = n[english].replace("`", "'")      # one mark for the 'ayn everywhere
                stats["names spelt by rule"] += 1
        # Facts, in both languages.
        for field, english, arabic, urdu in (("city", "cities", "citiesArabic", "citiesUrdu"),
                                             ("profession", "profession", "professionArabic", "professionUrdu"),
                                             ("byname", "byname", "bynameArabic", "bynameUrdu"),
                                             ("madhhab", "madhhab", "madhhabArabic", "madhhabUrdu"),
                                             ("description", "descriptionEnglish", "descriptionArabic", "descriptionUrdu")):
            if n.get(arabic):
                en, ur = table.fact(n[arabic], field)
                if en:
                    n[english], n[urdu] = en, ur
                    stats["facts"] += 1
                elif n.get(english):
                    n[english] = n[english].replace("`", "'")
        if n.get("generationArabic"):
            n["generation"] = english_ordinal(n.get("generation"))
            _, ur = table.fact(n["generationArabic"], "generation")
            if ur:
                n["generationUrdu"] = ur
        # Appraisals: one shape, three languages.
        rebuilt = []
        for a in n.get("appraisals") or []:
            arabic = (a.get("textArabic") or "").strip()
            if not arabic and ARABIC.search(a.get("textEnglish") or ""):
                arabic = a["textEnglish"].strip()          # filed under the English key
            if not LETTER.search(arabic):
                stats["appraisals without words dropped"] += 1
                continue
            label = (a.get("scholarArabic") or "").strip()
            if not label and ARABIC.search(a.get("scholar") or ""):
                label = a["scholar"].strip()
            row = {}
            if LETTER.search(label):
                en, ur = table.get("label", label)
                row["scholarArabic"] = clean_label(label)
                if en:
                    row["scholar"], row["scholarUrdu"] = en, ur
            row["textArabic"] = arabic
            en, ur = table.get("appr", arabic)
            if en:
                row["textEnglish"], row["textUrdu"] = en, ur
                stats["appraisals translated"] += 1
            else:
                stats["appraisals left in Arabic"] += 1
            rebuilt.append(row)
        if "appraisals" in n:
            n["appraisals"] = rebuilt
        n["needsUrdu"] = False
        n.pop("urduSource", None)
        n.pop("urduReviewState", None)
    return stats


def audit(narrators: list[dict]) -> Counter:
    """What a reader could still see in the wrong script."""
    found: Counter = Counter()
    english = ("nameEnglish", "lineageEnglish", "kunya", "byname", "profession", "madhhab", "cities",
               "affiliations", "generation", "descriptionEnglish", "gradeEnglish")
    urdu = ("nameUrdu", "lineageUrdu", "kunyaUrdu", "bynameUrdu", "professionUrdu", "madhhabUrdu", "citiesUrdu",
            "affiliationsUrdu", "generationUrdu", "descriptionUrdu", "gradeUrdu")
    for n in narrators:
        for k in english:
            if n.get(k) and ARABIC.search(str(n[k])):
                found[f"Arabic script in {k}"] += 1
        for k in urdu:
            if n.get(k) and re.search("[يكىة]", str(n[k])):
                found[f"Arabic-only letters in {k}"] += 1
        for k, source in zip(urdu, ("nameArabic", "lineageArabic", "kunyaArabic", "bynameArabic", "professionArabic",
                                    "madhhabArabic", "citiesArabic", "affiliationsArabic", "generationArabic",
                                    "descriptionArabic", "gradeEnglish")):
            if n.get(source) and not n.get(k):
                found[f"no {k}"] += 1
        for a in n.get("appraisals") or []:
            if not a.get("textEnglish"):
                found["appraisal without English"] += 1
            elif ARABIC.search(a["textEnglish"]):
                found["Arabic script in an appraisal's English"] += 1
            if not a.get("textUrdu"):
                found["appraisal without Urdu"] += 1
            if a.get("scholarArabic") and not a.get("scholar"):
                found["scholar label without English"] += 1
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    narrators = json.loads(SEED.read_text(encoding="utf-8"))
    table = Table(json.loads(gzip.decompress(TABLE.read_bytes()).decode("utf-8")))
    stats = apply(narrators, table)
    for name, count in sorted(stats.items()):
        print(f"{count:>7}  {name}")
    for kind, count in sorted(table.missing.items()):
        print(f"{count:>7}  lookups with no entry in the table ({kind})")
    found = audit(narrators)
    for name, count in sorted(found.items()):
        print(f"{count:>7}  STILL: {name}")
    if args.write:
        SEED.write_text(json.dumps(narrators, ensure_ascii=False, separators=(",", ":")), encoding="utf-8", newline="")
        print(f"wrote {SEED} ({SEED.stat().st_size / 1e6:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
