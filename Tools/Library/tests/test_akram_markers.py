"""akram_markers renumbers only quotation markers that the mushaf settles."""

import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from akram_markers import renumber_markers  # noqa: E402

SEED = HERE.parents[2] / "DarulIrfanApp" / "Resources" / "SeedData"
AYAHS = json.loads((SEED / "quran_ayahs.json").read_text(encoding="utf-8"))
ARABIC = {(a["surahNumber"], a["ayahNumber"]): a["textArabic"] for a in AYAHS}


def row(surah, start, end, text):
    return {"editionID": "akram-ut-tafaseer-ur", "surahNumber": surah, "ayahStart": start,
            "ayahEnd": end, "text": text}


class AkramMarkersTest(unittest.TestCase):
    def renumber(self, r):
        rows, _ = renumber_markers([r], AYAHS)
        return rows[0]["text"]

    def test_fatiha_markers_follow_the_mushaf_and_the_translation_keeps_its_own(self):
        arabic = " ".join(f"{ARABIC[(1, k)]} ﴿{m}﴾" for k, m in zip(range(2, 8), "۲۲۳۴۶۷"))
        translation = "تمام خوبیاں اللہ کے لئے ہیں ﴿۱﴾ بڑے مہربان ﴿۲﴾"
        text = self.renumber(row(1, 1, 7, arabic + "\n\n" + translation))
        self.assertEqual([m for m in text if m in "۰۱۲۳۴۵۶۷۸۹"], list("۲۳۴۵۶۷۱۲"))

    def test_only_digits_change(self):
        text = f"فرمایا: {ARABIC[(80, 5)]} ﴿۳﴾ {ARABIC[(80, 6)]} ﴿۴﴾"
        fixed = self.renumber(row(80, 1, 42, text))
        self.assertEqual(fixed, text.replace("۳", "۵").replace("۴", "۶"))

    def test_marker_printed_inside_an_ayah_is_left_alone(self):
        # 40:9 printed with a marker after "رحمته" and another at its end.
        words = ARABIC[(40, 9)].split()
        cut = next(i for i, w in enumerate(words) if w.startswith("رَحِمْتَه")) + 1
        text = " ".join(words[:cut]) + " ﴿۹﴾ " + " ".join(words[cut:]) + " ﴿۵﴾"
        self.assertEqual(self.renumber(row(40, 1, 9, text)), text)

    def test_a_cross_reference_keeps_its_number(self):
        # 2:178's ending quoted under Surah 5.
        tail = " ".join(ARABIC[(2, 178)].split()[-6:])
        text = f"تو فرمایا: {tail} ﴿۱۷۸﴾"
        self.assertEqual(self.renumber(row(5, 94, 96, text)), text)


if __name__ == "__main__":
    unittest.main()
