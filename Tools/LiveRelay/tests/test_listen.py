"""The listener's decisions on readings heard in the Daily Zikr of
10 November 2026 (the leader's mic open the whole time, no quiet before any
call): the opening recitations, each Latifa's call as Whisper wrote it, the
Muraqaba names, and the Zikr's own sound, which must never move the stage."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "relay"))
from audio_picker import STAGE_GAP, Picker  # noqa: E402


def picker(stage=None, since=1000.0):
    p = Picker(lambda s, w: None, lambda: stage, inline=True)
    p.stage_at = -since
    return p


ZIKR_SOUND = ["ایک ایک ایک ایک ایک ایک", "او او او او او", "اووووووووو", "ایسا ایسا ایسا", "اوش مجھے اوش مجھے",
              "اٹھا", "اوچھا اوچھا", "دیکھتے ہیں", ""]


def test_the_opening_in_order():
    p = picker(None)
    assert p._listened(None, "سوانا اللہ وال حمد", "سوحان الله الحمد", 10.0) == "tasbih"
    p = picker("tasbih")
    assert p._listened("tasbih", "اشادہ اللہ اللہ اوشاد", "فلا ربي من قلز", 20.0) == "shahadah"
    p = picker("shahadah")
    assert p._listened("shahadah", "اوز بالام نجاتہ", "أهوز باللام نجاته", 25.0) == "taawwudh"
    p = picker("taawwudh")
    assert p._listened("taawwudh", "مسم اللہ رخمان", "مسم الله رخماني", 28.0) == "basmalah"
    p = picker("basmalah")
    assert p._listened("basmalah", "فکال", "فاقل", 32.0) == "latifa-1"


BAYAN = ["آج ہم بات کریں گے اس کے بارے میں", "کسی اور تحقیق کی ضرورت نہیں ہے", "دین کی بات جاتی ہے کرنے کی",
         "ہمارے پاس خیر کا راستہ ہے", "اس میں اللہ کی رحمت ہے اور"]


def in_a_bayan(p, current, until):
    """A bayan's talk read every second up to `until`."""
    for second in range(int(until) - 40, int(until)):
        p.decide(current, BAYAN[second % len(BAYAN)], "", float(second))


def test_a_bayan_never_moves_the_stage():
    p = picker(None)
    assert p.decide(None, "سبحان اللہ کیا بات ہے", "سبحان الله", 10.0) is None  # "سبحان اللہ" alone
    # The 2nd bayan recording: its opening, then the Lataif named, in the middle of talk.
    p = picker(None)
    in_a_bayan(p, None, 100)
    assert p.decide(None, "اما با اد فاوز و ان لا ہی", "فعوز بالله من الشيطان", 100.0) is None
    assert p.decide(None, "بسم اللہ الرحمن الرحیم", "بسم الله الرحمن الرحيم", 103.0) is None
    in_a_bayan(p, None, 150)
    assert p.decide(None, "اپتلا ایس میں بہلا لطيفا جو", "", 150.0) is None
    # Even if a stage got on: a Latifa named in talk does not move it.
    p = picker("latifa-1")
    in_a_bayan(p, "latifa-1", 300)
    assert p.decide("latifa-1", "تو پر چتے اللہ اللہ تیفے سے بندہ", "", 300.0) is None


def test_a_call_after_the_zikr_sound_is_taken():
    p = picker("latifa-3")
    for second in range(260, 300):
        p.decide("latifa-3", ZIKR_SOUND[second % len(ZIKR_SOUND)], "", float(second))
    assert p.decide("latifa-3", "جو تل دیفا", "", 300.0) == "latifa-4"


def test_each_latifa_call_as_read():
    calls = {"latifa-1": "نسولہ تیفا", "latifa-2": "یہ جب انہوں نے ایک دیفا", "latifa-3": "جو تل دیفا",
             "latifa-4": "بانجونا دیفا", "latifa-5": "چھٹھا لطيفا", "latifa-6": "ساتون ادیفا"}
    expected = {"latifa-1": "latifa-2", "latifa-2": "latifa-3", "latifa-3": "latifa-4",
                "latifa-4": "latifa-5", "latifa-5": "latifa-6", "latifa-6": "latifa-7"}
    for current, text in calls.items():
        assert picker(current)._listened(current, text, "", 1000.0) == expected[current], current


def test_a_number_puts_a_missed_latifa_right():
    assert picker("latifa-3")._listened("latifa-3", "بان جو نا دیفا", "", 1000.0) == "latifa-5"


def test_muraqaba_names():
    assert picker("latifa-7")._listened("latifa-7", "اللہ رکھ میں احدیت", "", 1000.0) == "ahadiyat"
    assert picker("ahadiyat")._listened("ahadiyat", "مائیت", "", 1000.0) == "maiyyat"
    assert picker("maiyyat")._listened("maiyyat", "و کرمیت۔", "", 1000.0) == "aqrabiyyat"


def test_the_zikr_itself_never_moves_the_stage():
    for current in (None, "basmalah", "latifa-1", "latifa-4", "latifa-7", "ahadiyat", "maiyyat"):
        for text in ZIKR_SOUND:
            assert picker(current)._listened(current, text, text, 1000.0) is None, (current, text)


def test_no_new_stage_right_after_the_last():
    p = picker("latifa-2", since=STAGE_GAP - 5)
    assert p._listened("latifa-2", "جو تل دیفا", "", 0.0) is None


def test_after_the_7th_the_return_to_the_1st_is_shown():
    # Owner, 11 November: "7th Latifa, 1st Latifa, Muraqabat" is the order.
    assert picker("latifa-7")._listened("latifa-7", "اعلار کی فا", "", 1000.0) == "latifa-1"


def test_a_latifa_look_alike_inside_a_recitation_is_not_the_call():
    # Tahajjud 10 November: "ولا حول ولا قوۃ" read with "افال" in it, 22 s before the call.
    p = picker("tasbih")
    assert p._listened("tasbih", "افال ان لا ایک لحظ ان لا بلا ایک لحظ ان لا بكت", "لا خلال لا يبلاحظه الله ولا يحاول", 31.0) is None
    assert p._listened("basmalah", "بلو لطيفا", "بللطفة", 55.0) == "latifa-1"


def test_the_tahajjud_starts_on_its_first_recitation():
    p = picker(None)
    p.tahajjud = True
    assert p.decide(None, "سبحان الله اگر حوض ان لا اگر", "سبحان الله و لحوض الله", 28.0) == "tasbih"
