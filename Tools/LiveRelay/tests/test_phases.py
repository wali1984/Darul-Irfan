"""The room outside the stages (owner, 11 November 2026): the room sat
silent for an hour while every screen said "Playing Bayan", and the Bayan
after the Zikr stayed on the Shajra. The picker says what the room is doing:
nothing playing ("waiting"), a Bayan before the Zikr ("bayan"), a Bayan after
it ("bayan-after") - never a Bayan in the Tahajjud, and never in the Zikr."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "relay"))
from audio_picker import AFTER_SHAJRA, BAYAN, BAYAN_AFTER, WAITING, Picker  # noqa: E402

TALK = ["آج ہم بات کریں گے اس کے بارے میں", "کسی اور تحقیق کی ضرورت نہیں ہے", "دین کی بات جاتی ہے کرنے کی"]
ZIKR = ["ایک ایک ایک ایک", "اووووووووو", ""]


class Room:
    def __init__(self, stage=None, tahajjud=False):
        self.stage, self.given = stage, []
        self.p = Picker(self.give, lambda: self.stage, inline=True)
        self.p.tahajjud = tahajjud

    def give(self, stage, why):
        if stage:
            self.given.append(stage)
            self.stage = stage

    def second(self, words=None):
        """One second of the room: sound read as `words`, or silence (None)."""
        p = self.p
        p.clock += 1.0
        if words is not None:
            p.last_voice = p.last_sound = p.clock
            p.decide(p._current(), words, "", p.clock)
        if self.stage != p.seen_stage:
            p.seen_stage, p.stage_at = self.stage, p.clock
        p._phase()


def test_silence_before_the_zikr_is_waiting_not_a_bayan():
    room = Room()
    for _ in range(25):
        room.second()
    assert room.given == [WAITING]


def test_a_bayan_before_the_zikr_then_its_end():
    room = Room()
    for i in range(30):
        room.second(TALK[i % 3])
    assert room.given == [BAYAN]
    for _ in range(45):  # a pause in the Bayan is not its end
        room.second()
    assert room.given == [BAYAN]
    for _ in range(20):
        room.second()
    assert room.given == [BAYAN, WAITING]


def test_a_long_bayan_never_flips_to_waiting():
    # bayan-2: its words read as talk while the room's floor rose under them.
    room = Room()
    for i in range(300):
        room.p.clock += 1.0
        room.p.decide(None, TALK[i % 3], "", room.p.clock)  # read as talk, never "voice" over the floor
        room.p.last_sound = room.p.clock
        room.p._phase()
    assert room.given == [BAYAN]


def test_the_zikr_sound_is_never_a_bayan():
    room = Room("latifa-3")
    for i in range(120):
        room.second(ZIKR[i % 3])
    assert room.given == []


def test_the_bayan_after_the_zikr_follows_the_shajra():
    room = Room("shajra")
    room.second()
    for i in range(int(AFTER_SHAJRA) + 5):
        room.second(TALK[i % 3])
    assert room.given == [BAYAN_AFTER]
    # The picker's order sees the Bayan after the Zikr as the Shajra: no stage after it.
    assert room.p._current() == "shajra"


def test_the_shajra_itself_is_not_the_bayan_after():
    room = Room("shajra")
    for i in range(int(AFTER_SHAJRA) - 5):
        room.second(TALK[i % 3])
    assert room.given == []


def test_the_tahajjud_has_no_bayan():
    room = Room(tahajjud=True)
    for i in range(40):
        room.second(TALK[i % 3])
    assert BAYAN not in room.given
    for _ in range(35):  # quiet, and nothing read for 30 s
        room.second()
    assert room.given == [WAITING]


def test_a_phase_is_no_stage_to_the_order():
    for stage in (WAITING, BAYAN):
        room = Room(stage)
        assert room.p._current() is None
        assert room.p._listened(None, "سوانا اللہ وال حمد", "سوحان الله الحمد اکبر", 10.0) == "tasbih"


def test_a_muraqaba_call_after_the_7th_latifa_is_the_first_muraqaba():
    # 11 November: Raabta went uncalled, the Ahadiyat call was refused as
    # Raabta's, and every Muraqaba after it with it.
    room = Room("latifa-7")
    assert room.p._settle("اللہ اللہ وقت وقت یہ دیلت", "raabta", 1.2, 10.0, "full")
    assert room.given == ["ahadiyat"]
    # A Latifa's call there is still Raabta's (the return to the 1st Latifa).
    room = Room("latifa-7")
    assert room.p._settle("پہلا لطیفہ", "raabta", 1.0, 10.0, "full")
    assert room.given == ["raabta"]


def test_the_tahajjud_joined_late_starts_from_the_zikr_sound():
    # 11 November: joined muted after the 1st Latifa's call; the first thing
    # heard was the Zikr's own sound, then the 2nd Latifa's call, posted as
    # the 1st until a host typed "2nd".
    p = Room(WAITING, tahajjud=True).p
    assert [p.decide(None, ZIKR[i % 2], "", 100.0 + i) for i in range(10)] == [None] * 8 + ["latifa-1"] * 2
    assert p._listened(None, "دوسرا لطیفہ", "", 10.0) == "latifa-2"
    # The Zikr's sound never starts the Daily Zikr (a bayan may come first).
    p = Room(WAITING).p
    assert {p.decide(None, ZIKR[i % 2], "", 100.0 + i) for i in range(10)} == {None}


def test_the_return_to_the_1st_latifa_keeps_the_order_past_the_lataif():
    # 11 November Tahajjud: a host typed "1st latifa" after the 7th; the
    # Ahadiyat call was then refused as the 2nd Latifa's.
    room = Room("latifa-7")
    assert room.p._current() == "latifa-7"
    room.stage = "latifa-1"
    assert room.p._current() == "latifa-7"
    assert room.p._settle("انا انا مراک ویادیات", "raabta", 1.7, 10.0, "full")
    assert room.given == ["ahadiyat"]
    room = Room("latifa-1")  # the Zikr's first 1st Latifa is just that
    assert room.p._current() == "latifa-1"


def test_the_stream_picture_drawn_ahead(tmp_path):
    from stage_picture import SHAJRA_FRAMES, StagePicture
    picture = StagePicture("https://example.invalid/broadcast", "https://platform.invalid", "our-sheikh", tmp_path / "stage.png")
    picture.ready_dir.mkdir()
    assert picture.ready("latifa-3") is None  # not drawn: the live page is captured instead
    (picture.ready_dir / "latifa-3.png").write_bytes(b"three")
    (picture.ready_dir / "none.png").write_bytes(b"none")
    for k in range(SHAJRA_FRAMES):
        (picture.ready_dir / f"shajra-{k}.png").write_bytes(f"shajra {k}".encode())
    assert picture.ready("latifa-3") == b"three"
    assert picture.ready(None) == b"none"
    assert picture.ready("shajra", 0.0) == b"shajra 0"
    assert picture.ready("shajra", 600.0) == f"shajra {SHAJRA_FRAMES - 1}".encode()  # the last lines, held
    names = [name for name, _ in picture._ready_items()]
    assert names[:4] == ["none", "waiting", "bayan", "tasbih"] and f"shajra-{SHAJRA_FRAMES - 1}" in names
