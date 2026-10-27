"""Builds each topic's Qur'an and hadith references into topics.json.

Hadith come from the chapters Imam an-Nawawi arranged by theme in Riyad
as-Salihin, plus named narrations from al-Bukhari, an-Nawawi's Forty and the
Forty Hadith Qudsi, each confirmed by a phrase in its text so a renumbered
source cannot slip in the wrong narration. A Riyad narration whose wording is
found in Sahih al-Bukhari or Sahih Muslim is cited from there instead, because
those two carry an Urdu translation in the app and Riyad does not.

Ayat are the curated list below, every reference checked against the surah's
real length.

usage: build_topic_references.py [--write]
"""
from __future__ import annotations

import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SEED = ROOT / "DarulIrfanApp" / "Resources" / "SeedData"
MIRRORS = [
    ROOT.parent / "DarulIrfanAndroid/app/src/main/assets/seed",
    ROOT.parent / "DarulIrfanHarmony/entry/src/main/resources/rawfile/seed",
    ROOT.parent / "DarulIrfanWeb/content",
]

# Riyad as-Salihin chapters, by the start of their English title.
RIYAD = {
    "tawhid": [],
    "zikr": ["The Excellence of the Remembrance of Allah", "Remembrance of Allah in all Conditions",
             "Remembrance of Allah in the Morning and in the Evening", "Supplication before going to Bed"],
    "sabr": ["Patience and Perseverance", "Endurance of Afflictions"],
    "shukr": ["The Obligation of Gratitude", "The Desirability of Prostrating out of Gratitude",
              "Excellence of a Grateful Rich Man"],
    "tawakkul": ["Firm Belief and Perfect Reliance on Allah"],
    "tawbah": ["Repentance"],
    "dua": ["Issues regarding Supplications", "The Excellence of Supplicating in one's Absence",
            "Some Verdicts Pertaining to Supplications"],
    "salah": ["The Excellence of As-Salat (The Prayer)", "Excellence of the Morning (Fajr) and 'Asr Prayers",
              "The Excellence of Performing Salat (Prayers) in Congregation",
              "Strict Orders for Observance of Obligatory Salat", "Excellence of Standing in Prayer at Night"],
    "love-prophet": ["The Obligation of Supplicating Allah to Exalt His Mention",
                     "Observing the Sunnah and the manners of its obedience"],
    "tasawwuf": ["Sincerity and Significance of Intentions", "Watchfulness", "Piety",
                 "Leading an Abstemious Life and refraining from the Doubtful"],
    "mercy": ["Hope in Allah's Mercy"],
    "hope": ["Excellence of Good Hopes", "Combining Hope and Fear (of Allah)",
             "Supplication when one is disappointed about his Life"],
    "guidance": ["Calling to right guidance and forbidding depravity", "Uprightness and Steadfastness",
                 "Prohibition of heresies in religion"],
    "reflection": ["Remembrance of Death and Restraint of Wishes", "Excellence of Weeping out of Fear from Allah"],
    "knowledge": ["Virtues of Knowledge which is Learnt and Taught for the sake of Allah"],
    "decree": [],
    "baiat": [],
    "nearness": ["Signs of Allah's love for His slaves", "Excellence and Etiquette of Sincere love for the sake of Allah"],
    "company-prophet": ["Visiting the Pious Persons, loving them and adoption of their company",
                        "Etiquette of Attending company and sitting with Companions"],
    "parents-family": ["Kind Treatment towards Parents", "Prohibition of Disobeying Parents",
                       "Excellence in doing Good to the Friends of Parents", "Sustentation of the Members of the Family"],
}

# Named narrations: (canonical id, a phrase its English text must contain).
NAMED = {
    "tawhid": [("nawawi40|2|2", "testify"), ("nawawi40|8|8", "none worthy of worship except Allah")],
    "decree": [("nawawi40|2|2", "qadar"), ("nawawi40|4|4", "four matters"),
               ("nawawi40|19|19", "pens have been lifted")],
    "baiat": [],
    "nearness": [("nawawi40|38|38", "draw near")],
    "tasawwuf": [("nawawi40|2|2", "Ihsan"), ("nawawi40|6|6", "heart")],
    "guidance": [("nawawi40|21|21", "be steadfast")],
    "mercy": [],
    "hope": [],
    "love-prophet": [],
}

# Bukhari chapters, by a phrase in their English title.
BUKHARI_CHAPTERS = {
    "tawhid": ["inviting his followers to Tauhid"],
    "baiat": ["How do the people give the Bai'a to the Imam", "The Bai'a given by women",
              "When they gave their Bai'a (pledge) to you", "When believing women come to you to give you the Bai'a"],
    "decree": [],
}

# Narrations found by a phrase in their English text: (book, phrase).
BY_PHRASE = {
    "tawhid": [("muslim", "died knowing (fully well) that there is no god but Allah")],
    "love-prophet": [("bukhari", "loves me more than his father")],
    "mercy": [("qudsi40", "My mercy prevails over My wrath")],
    "hope": [("qudsi40", "I am as My servant thinks I am")],
    "nearness": [("qudsi40", "draws near to Me"), ("qudsi40", "comes to Me walking")],
}

# Whole books of Sahih al-Bukhari (its own numbering), with the title each
# must carry: Divine Will (Al-Qadar) and the Oneness of Allah (Tawhid).
BUKHARI_BOOKS = {
    "decree": [(82, "Qadar")],
    "tawhid": [(97, "Tawheed")],
}

# Curated ayat for each topic. Ranges are inclusive.
AYAT = {
    "tawhid": ["112:1-4", "2:255", "2:163", "3:18", "20:14", "21:22", "42:11", "6:102-103", "57:3", "59:22-24", "7:180", "3:26"],
    "zikr": ["13:28", "2:152", "33:41-42", "29:45", "3:190-191", "7:205", "62:10", "63:9", "73:8", "18:28"],
    "sabr": ["2:153", "2:155-157", "3:200", "39:10", "16:127", "103:1-3", "2:45", "8:46", "31:17", "11:115"],
    "shukr": ["14:7", "2:152", "31:12", "16:114", "39:66", "27:40", "34:13", "76:3"],
    "tawakkul": ["65:3", "3:159", "8:2", "9:51", "14:12", "33:3", "25:58", "3:173"],
    "tawbah": ["39:53", "66:8", "4:110", "25:70", "2:222", "11:3", "3:135-136", "24:31", "4:17"],
    "dua": ["2:186", "40:60", "7:55", "27:62", "2:201", "25:74", "3:8", "7:23", "17:24", "14:40-41"],
    "salah": ["2:45", "29:45", "20:14", "2:238", "4:103", "23:1-2", "17:78", "11:114", "62:9"],
    "love-prophet": ["3:31", "33:56", "9:128", "21:107", "33:21", "68:4", "4:80", "33:6", "9:24"],
    "tasawwuf": ["91:7-10", "87:14-15", "26:88-89", "13:28", "62:2", "79:40-41", "50:16", "29:69"],
    "mercy": ["7:156", "39:53", "6:54", "21:107", "40:7", "15:56", "2:218", "12:87"],
    "hope": ["94:5-6", "65:7", "12:87", "39:53", "2:286", "93:3-5", "65:2-3", "2:214", "3:139"],
    "guidance": ["1:6-7", "2:2", "6:125", "28:56", "29:69", "17:9", "42:52", "39:23", "2:38"],
    "reflection": ["3:190-191", "2:164", "30:21", "47:24", "38:29", "59:21", "88:17-20", "45:13", "51:20-21", "41:53"],
    "knowledge": ["20:114", "58:11", "39:9", "96:1-5", "35:28", "16:43", "2:269"],
    "decree": ["54:49", "57:22-23", "9:51", "64:11", "25:2", "6:59", "2:216", "87:2-3"],
    "baiat": ["48:10", "48:18", "60:12", "9:111", "5:35", "9:119", "18:28", "4:59"],
    "nearness": ["2:186", "50:16", "96:19", "56:88-89", "5:35", "17:57", "56:10-11", "57:4", "58:7"],
    "company-prophet": ["9:119", "18:28", "4:69", "25:27-29", "43:67", "48:29", "9:100", "6:52", "31:15"],
    "parents-family": ["17:23-24", "31:14-15", "46:15", "4:36", "66:6", "25:74", "2:83", "29:8", "14:41"],
}

# Urdu search terms, so related library items and bayans are found in Urdu too.
URDU_TERMS = {
    "tawhid": ["توحید", "وحدانیت"], "zikr": ["ذکر", "ذکر الٰہی"], "sabr": ["صبر"], "shukr": ["شکر"],
    "tawakkul": ["توکل"], "tawbah": ["توبہ", "استغفار"], "dua": ["دعا"], "salah": ["نماز"],
    "love-prophet": ["عشق رسول", "محبت رسول"], "tasawwuf": ["تصوف", "تزکیہ"], "mercy": ["رحمت"],
    "hope": ["امید"], "guidance": ["ہدایت"], "reflection": ["تفکر", "غور و فکر"], "knowledge": ["علم"],
    "decree": ["تقدیر"], "baiat": ["بیعت", "سلسلہ"], "nearness": ["قرب الٰہی"],
    "company-prophet": ["صحبت", "صالحین"], "parents-family": ["والدین", "خاندان"],
}

DIACRITICS = re.compile(r"[ؐ-ًؚ-ٰٟۖ-ۭـ]")


def normalise(text: str) -> list[str]:
    text = DIACRITICS.sub("", text or "")
    text = re.sub(r"[أإآا]", "ا", text).replace("ى", "ي").replace("ة", "ه")
    return re.findall(r"[ء-ي]+", text)


def shingles(words: list[str], n: int = 5) -> set[tuple[str, ...]]:
    return {tuple(words[i:i + n]) for i in range(len(words) - n + 1)}


def load(book: str) -> list[dict]:
    return json.loads((SEED / f"hadith_{book}.json").read_text(encoding="utf-8"))


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    write = "--write" in sys.argv
    topics = json.loads((SEED / "topics.json").read_text(encoding="utf-8"))
    surahs = {s["id"]: s["ayahCount"] for s in json.loads((SEED / "quran_surahs.json").read_text(encoding="utf-8"))}
    books = {name: load(name) for name in ("riyadussalihin", "bukhari", "muslim", "nawawi40", "qudsi40")}
    by_id = {h["canonicalID"]: h for rows in books.values() for h in rows}
    catalogue = json.loads((SEED / "hadith_books.json").read_text(encoding="utf-8"))
    catalogue = catalogue if isinstance(catalogue, list) else catalogue["books"]
    bukhari_sections = {s["number"]: s["titleEnglish"] for b in catalogue if b["id"] == "bukhari" for s in b.get("sections", [])}

    # Shingle index over the two Sahihs that carry Urdu.
    index: dict[tuple[str, ...], set[str]] = defaultdict(set)
    for name in ("bukhari", "muslim"):
        for h in books[name]:
            if h.get("text_ur"):
                for shingle in shingles(normalise(h.get("text_ar", ""))):
                    index[shingle].add(h["canonicalID"])

    def with_urdu(riyad: dict) -> str:
        """The Bukhari or Muslim narration with this wording, or the Riyad one."""
        words = normalise(riyad.get("text_ar", ""))[8:]  # past the narrator's name
        own = shingles(words)
        if len(own) < 6:
            return riyad["canonicalID"]
        votes = Counter(candidate for shingle in own for candidate in index.get(shingle, ()))
        if not votes:
            return riyad["canonicalID"]
        best, hits = votes.most_common(1)[0]
        return best if hits / len(own) >= 0.6 else riyad["canonicalID"]

    problems = []
    for topic in topics:
        tid = topic["id"]
        refs: list[str] = []

        for prefix in RIYAD.get(tid, []):
            chapter = [h for h in books["riyadussalihin"]
                       if (h.get("chapterTitleEnglish") or "").removeprefix("Chapter: ").startswith(prefix)]
            if not chapter:
                problems.append(f"{tid}: no Riyad chapter '{prefix}'")
            refs += [with_urdu(h) for h in chapter]
        for phrase in BUKHARI_CHAPTERS.get(tid, []):
            chapter = [h["canonicalID"] for h in books["bukhari"] if phrase.lower() in (h.get("chapterTitleEnglish") or "").lower()]
            if not chapter:
                problems.append(f"{tid}: no Bukhari chapter '{phrase}'")
            refs += chapter
        for canonical, phrase in NAMED.get(tid, []):
            text = (by_id.get(canonical) or {}).get("text_en") or ""
            if phrase.lower() not in text.lower():
                problems.append(f"{tid}: {canonical} lacks '{phrase}'")
                continue
            refs.append(canonical)
        for book, phrase in BY_PHRASE.get(tid, []):
            match = next((h["canonicalID"] for h in books[book] if phrase.lower() in (h.get("text_en") or "").lower()), None)
            if match is None:
                problems.append(f"{tid}: no {book} narration with '{phrase}'")
                continue
            refs.append(match)

        for number, word in BUKHARI_BOOKS.get(tid, []):
            if word.lower() not in bukhari_sections.get(number, "").lower():
                problems.append(f"{tid}: Bukhari book {number} is '{bukhari_sections.get(number)}', not {word}")
                continue
            refs += [h["canonicalID"] for h in books["bukhari"] if h.get("sourceBook") == number]

        seen: set[str] = set()
        hadith = [r for r in refs if not (r in seen or seen.add(r))]

        ayat = []
        for ref in AYAT[tid]:
            surah, verses = ref.split(":")
            first, _, last = verses.partition("-")
            if int(surah) not in surahs or not (1 <= int(first) <= int(last or first) <= surahs[int(surah)]):
                problems.append(f"{tid}: ayah reference {ref} is out of range")
                continue
            ayat.append(ref)

        terms = topic["searchTerms"] + [t for t in URDU_TERMS.get(tid, []) if t not in topic["searchTerms"]]
        from_sahih = sum(1 for r in hadith if r.split("|")[0] in ("bukhari", "muslim"))
        print(f"{tid:16} ayat {len(ayat):2}  hadith {len(hadith):3}  (Bukhari/Muslim with Urdu {from_sahih})")
        topic["ayahRefs"] = ayat
        topic["hadithRefs"] = hadith
        topic["searchTerms"] = terms

    for problem in problems:
        print("PROBLEM", problem)
    if write and not problems:
        text = json.dumps(topics, ensure_ascii=False, indent=2) + "\n"
        for folder in [SEED, *MIRRORS]:
            if folder.exists():
                (folder / "topics.json").write_text(text, encoding="utf-8", newline="\n")
                print("wrote", folder / "topics.json")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
