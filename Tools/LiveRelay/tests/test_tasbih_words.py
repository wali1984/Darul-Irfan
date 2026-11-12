"""The opening Tasbih is recognised in the Arabic reading, also as heard on
10 November 2026 ("سوحان" for "سبحان")."""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "relay"))
from audio_picker import RECITATION_WORDS  # noqa: E402

TASBIH = dict(RECITATION_WORDS)["tasbih"]


def test_tasbih_as_read_on_10_november():
    assert re.search(TASBIH, "سوحان الله و الحمد لله و لا لا لا")
    assert re.search(TASBIH, "سبحان الله والحمد لله")


def test_not_other_words():
    assert not re.search(TASBIH, "استغفر الله ربي من كل ذنب")
    assert not re.search(TASBIH, "بسم الله الرحمن الرحيم")


def test_tasbih_as_read_on_12_november():
    # The ب and the ح lost: "اوان اللہ والحندر اللہ" (Daily Zikr, 12 November).
    from audio_picker import TASBIH_MORE
    for heard in ("اوان اللہ والحندر اللہ وا", "اجوان اللہ والحندر اللہ و", "وان الله و الحندر الله و رب"):
        assert re.search(TASBIH, heard), heard
        assert re.search(TASBIH_MORE, heard), heard


def test_a_bayan_naming_hazrat_awan_is_not_the_tasbih():
    assert not re.search(TASBIH, "حضرت امیر محمد اکرم اعوان رحمۃ اللہ علیہ نے فرمایا")
