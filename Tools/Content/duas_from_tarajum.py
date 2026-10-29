"""Give every Qur'anic dua the Silsila's own translation.

The duas were first bundled with the Pickthall (English) and Jalandhry (Urdu)
translations, which the app no longer carries: every Qur'an translation must be
Akram-ut-Tarajum. This rewrites translationEnglish / translationUrdu of each
dua in duas.json from quran_translations.json (akram-ut-tarajum-en / -ur) for
the dua's source range, the way silsila_translations_only.py does it for the
Ayah of the Day, and marks the rows permissionConfirmed like the other Silsila
content.

A dua whose Arabic is a whole ayah (or whole ayat) gets the whole translation.
Akram-ut-Tarajum is stored per ayah, so a dua whose Arabic is only part of an
ayah cannot be given "the matching part" automatically: the script stops and
names it, so that translation is chosen by a person rather than guessed.

Re-run it whenever the Akram-ut-Tarajum text changes (corrections against the
printed book), so the Duas screen never drifts from the Qur'an reader.

    python Tools/Content/duas_from_tarajum.py
"""

from __future__ import annotations

import json
import re
import sys

from seed_io import SEED, dump, load

EDITIONS = {"translationEnglish": "akram-ut-tarajum-en", "translationUrdu": "akram-ut-tarajum-ur"}
SOURCE = re.compile(r"^Quran (\d+):(\d+)(?:-(\d+))?$")


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    duas, layout = load("duas.json")
    ayahs = {(row["surahNumber"], row["ayahNumber"]): row["textArabic"]
             for row in json.loads((SEED / "quran_ayahs.json").read_text(encoding="utf-8"))}
    text = {(row["editionID"], row["surahNumber"], row["ayahNumber"]): row["text"]
            for row in json.loads((SEED / "quran_translations.json").read_text(encoding="utf-8"))
            if row["editionID"] in EDITIONS.values()}

    changed = 0
    for dua in duas:
        match = SOURCE.match(dua["source"])
        if not match:
            raise SystemExit(f"{dua['id']}: source {dua['source']!r} is not 'Quran s:a' or 'Quran s:a-b'")
        surah, first = int(match.group(1)), int(match.group(2))
        last = int(match.group(3) or first)
        verses = range(first, last + 1)

        whole = " ".join(ayahs[(surah, ayah)] for ayah in verses)
        if dua["arabic"] != whole:
            raise SystemExit(f"{dua['id']}: the Arabic is not the whole of {dua['source']}; "
                             "choose the matching part of the translation by hand")

        before = (dua.get("translationEnglish"), dua.get("translationUrdu"), dua.get("rightsStatus"))
        for field, edition in EDITIONS.items():
            parts = [text.get((edition, surah, ayah), "").strip() for ayah in verses]
            if not all(parts):
                raise SystemExit(f"{dua['id']}: {edition} has no text for part of {dua['source']}")
            dua[field] = " ".join(parts)
        dua["rightsStatus"] = "permissionConfirmed"
        changed += before != (dua["translationEnglish"], dua["translationUrdu"], dua["rightsStatus"])

    dump("duas.json", duas, layout)
    print(f"duas.json: {len(duas)} duas, {changed} changed, all from Akram-ut-Tarajum")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
