"""Cut the English Asrar-at-Tanzil commentary at the ayat it turns to.

The rows were built (October 2026) under the ayat of the Silsila's
english-tafseer.com sections, six to twenty ayat each, and a short surah is
one row: in the reader the commentary showed at a section's first ayah only,
a whole surah under its first (owner, 29 October 2026: "english tafseer
doesn't align or show in each ayat"). The printed commentary itself is
headed ayah by ayah with the ayah's own words in the book's translation
("Those who believe in the unseen" for 2:3, "Who has made the earth your
carpet" for 2:22), so a section is cut at the heading that turns to a later
ayah of it. A heading quoting an ayah ahead of the commentary is not a cut
when what follows still quotes the ayat before it (the rule the Akram-ut-
Tafaseer cutting follows); a section with no such heading stays whole.

The first section of a few surahs opens with the book's introduction to the
surah ("AL-BAQARAH (THE COW)", "Salient Features", an overview). It is not
commentary on the ayat (owner, the same day), so it is taken out of the
reader's rows; the printed volume in the Library keeps it.

Reads and writes the iOS seed (quran_tafsir.json); Tools/Release/sync_seeds.py
copies it to the other platforms. Run after any rebuild of the English rows.

    python Tools/Library/split_asrar_english.py [--write]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path

SEED = Path(__file__).resolve().parents[2] / "DarulIrfanApp" / "Resources" / "SeedData"
EDITION = "asrar-at-tanzil-en"
INTRO = re.compile(r"^salient features$", re.IGNORECASE)
CROSS_REFERENCE = re.compile(r"\(\s*\d{1,3}\s*:\s*\d{1,3}\s*\)")
HEADING_LENGTH = 220
COMMON = {
    "the", "and", "of", "to", "a", "in", "is", "that", "it", "for", "on", "as", "with", "be", "they", "you",
    "he", "his", "their", "them", "we", "our", "us", "are", "was", "were", "not", "this", "which", "who",
    "whom", "from", "by", "or", "an", "at", "so", "have", "has", "had", "will", "shall", "do", "does", "did",
    "but", "if", "then", "there", "what", "all", "any", "no", "nor", "may", "those", "these", "my", "me",
    "your", "him", "her", "she", "its", "into", "upon", "unto", "been", "when", "one", "say", "said", "indeed",
    "verily", "surely", "allah", "lord", "rabb",
}


def words(text: str) -> list[str]:
    text = "".join(c for c in unicodedata.normalize("NFKD", text) if not unicodedata.combining(c))
    text = re.sub(r"(?<![a-z0-9])0(?=\s|[a-z])", "o", text.lower())   # the OCR's "0 mankind!"
    return [w for w in re.findall(r"[a-z]+", text) if w not in COMMON and len(w) > 2]


def heading_ayah(paragraph: str, translations: dict[int, set[str]]) -> int | None:
    """The ayah of the section a short heading quotes: most of its words are
    that ayah's, and clearly more of them than any other's. A heading that
    joins the start of one ayah to the end of the next ("And if you doubt...
    for those who do not believe", 2:23-24) belongs to the first."""
    if len(paragraph) > HEADING_LENGTH or CROSS_REFERENCE.search(paragraph):
        return None
    quoted = set(words(paragraph))
    if len(quoted) < 2:
        return None
    scores = sorted(((len(quoted & own) / len(quoted), ayah) for ayah, own in translations.items()), reverse=True)
    best, ayah = scores[0]
    runner = scores[1][0] if len(scores) > 1 else 0.0
    if best >= 0.8 and best - runner >= 0.25:
        return ayah
    pairs = sorted(((len(quoted & (own | translations[ayah + 1])) / len(quoted), ayah)
                    for ayah, own in translations.items() if ayah + 1 in translations), reverse=True)
    if pairs and pairs[0][0] >= 0.9 and pairs[0][0] - best >= 0.25 and (len(pairs) < 2 or pairs[0][0] - pairs[1][0] >= 0.25):
        return pairs[0][1]
    return None


BASMALA = re.compile(r"^in the name of allah", re.IGNORECASE)


def introduction_end(paragraphs: list[str], headed: set[int]) -> int | None:
    """Where the book's introduction to the surah ends, when a surah's first
    row opens with one ("Salient Features" among its first paragraphs): after
    its title lines and its overview, at the first short heading, the Basmala,
    or a heading on an ayah."""
    marker = next((i for i, p in enumerate(paragraphs[:4]) if INTRO.match(p.strip())), None)
    if marker is None:
        return None
    seen_overview = False
    for index in range(marker + 1, len(paragraphs)):
        paragraph = paragraphs[index].strip()
        if index in headed or BASMALA.match(paragraph) or (len(paragraph) <= 100 and seen_overview):
            return index
        seen_overview = seen_overview or len(paragraph) > 100
    return None


def split(row: dict, translations: dict[int, set[str]], report: dict) -> list[dict]:
    paragraphs = [p for p in re.split(r"\n\s*\n", row["text"]) if p.strip()]
    first, last = row["ayahStart"], row["ayahEnd"]
    own = {ayah: translations[ayah] for ayah in range(first, last + 1) if ayah in translations}
    headings = [(index, ayah) for index, p in enumerate(paragraphs)
                if (ayah := heading_ayah(p.strip(), own)) is not None]

    # The book's introduction to the surah, before its commentary on the ayat.
    cut = introduction_end(paragraphs, {index for index, _ in headings}) if first == 1 else None
    introduction = cut is not None
    if introduction:
        report["introductions"].append(f"{row['surahNumber']}: {sum(len(p) for p in paragraphs[:cut])} chars "
                                       f"({' / '.join(p.strip()[:30] for p in paragraphs[:cut])})")
        paragraphs = paragraphs[cut:]
        headings = [(index - cut, ayah) for index, ayah in headings if index >= cut]

    cuts, current = [], first
    for position, (index, ayah) in enumerate(headings):
        if ayah <= current or index == 0:
            continue
        later = headings[position + 1:]
        behind = sum(1 for _, other in later if other < ayah)
        onward = 1 + sum(1 for _, other in later if other >= ayah)
        if behind > onward:
            continue
        cuts.append((index, ayah))
        current = ayah
    if not cuts and not introduction:
        return [row]   # left exactly as it was

    parts, start, ayah_from = [], 0, first
    for index, ayah in cuts:
        parts.append((ayah_from, ayah - 1, paragraphs[start:index]))
        start, ayah_from = index, ayah
    parts.append((ayah_from, last, paragraphs[start:]))
    out = []
    for ayah_from, ayah_to, chunk in parts:
        out.append(dict(row, ayahStart=ayah_from, ayahEnd=ayah_to, text="\n\n".join(p.strip() for p in chunk)))
    report["cuts"] += len(cuts)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--write", action="store_true", help="write the iOS seed")
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")

    path = SEED / "quran_tafsir.json"
    tafsir = json.loads(path.read_text(encoding="utf-8"))
    translations: dict[int, dict[int, set[str]]] = {}
    for item in json.loads((SEED / "quran_translations.json").read_text(encoding="utf-8")):
        if item["editionID"] == EDITION and item.get("text"):
            translations.setdefault(item["surahNumber"], {})[item["ayahNumber"]] = set(words(item["text"]))

    report = {"introductions": [], "cuts": 0}
    rows, out = [r for r in tafsir if r["editionID"] == EDITION], []
    for row in rows:
        out.extend(split(row, translations.get(row["surahNumber"], {}), report))

    # Nothing lost or moved across ayat: the same ayat covered, the same words
    # kept (bar the introductions), no empty row.
    def covered(items):
        return {(r["surahNumber"], a) for r in items for a in range(r["ayahStart"], r["ayahEnd"] + 1)}

    def letters(items):
        return re.sub(r"\s+", "", "".join(r["text"] for r in items))

    assert covered(out) == covered(rows), "the ayat covered changed"
    assert all(r["text"].strip() for r in out), "an empty row"
    removed = sum(int(line.split(": ")[1].split(" ")[0]) for line in report["introductions"])
    assert len(letters(rows)) - len(letters(out)) <= removed, "text was lost"

    single = sum(1 for r in out if r["ayahStart"] == r["ayahEnd"])
    print(f"rows {len(rows)} -> {len(out)}; cuts {report['cuts']}; rows on one ayah {single}")
    print("introductions taken out:", *report["introductions"], sep="\n  ")
    if args.write:
        rest = [r for r in tafsir if r["editionID"] != EDITION]
        merged = sorted(rest + out, key=lambda r: (r["editionID"], r["surahNumber"], r["ayahStart"]))
        with path.open("w", encoding="utf-8", newline="\n") as handle:
            json.dump(merged, handle, ensure_ascii=False, indent=1)
            handle.write("\n")
        print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
