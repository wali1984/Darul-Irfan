"""The relay's audio picker: names the Zikr's stage from the room's sound.

The Zikr runs in one fixed order (owner, 2026-11-06): the opening Tasbih,
the seven Latifas, Raabta, the Muraqabat, then the Shajra, which the leader
reads - mostly hummed - after the last Muraqaba. Between stages the room is
quiet; each stage is called out loud. So the picker:

  1. hears a call: a loud stretch of voice after a quiet spell (20 s; 5 s
     during the opening recitations, which run straight into the 1st Latifa);
  2. reads it with a small Whisper model 2, 3 and 4 seconds after it began
     (a call is a word or two, so most read in the first 2 s), then once
     more from a longer clip; the first reading that settles it wins;
  3. a reading with the word Latifa (however garbled) takes the next stage
     in the order; a Muraqaba's name, which comes through well, takes that
     Muraqaba, forwards only;
  4. after the last Muraqaba, takes the next long stretch of voice for the
     Shajra.

The stage it starts from is the platform's current one, so a tap in the app
or a host's typed cue keeps it in step. Typed cues are the backup.
"""

from __future__ import annotations

import re
import threading
from collections import deque

import numpy as np

RATE = 16_000
FRAME = RATE // 10  # 100 ms

ORDER = ["tasbih", "latifa-1", "latifa-2", "latifa-3", "latifa-4", "latifa-5", "latifa-6", "latifa-7",
         "raabta", "ahadiyat", "maiyyat", "aqrabiyyat", "sair-kaaba", "rauza-athar", "masjid-nabawi", "shajra"]
LAST_MURAQABA = "masjid-nabawi"

LOUD_DB = 40.0        # voice is at least this loud (100 ms RMS, 16-bit scale)...
ABOVE_FLOOR_DB = 20.0  # ...and this far above the room's own quiet (a mic's hum)
QUIET_BEFORE = 20.0   # seconds of quiet that make the next voice a call
QUIET_IN_OPENING = 5.0  # ...while the opening recitations run (no long quiet before the 1st Latifa)
CALL_SECONDS = 0.6    # voice within the first 4 s of a call (a call is a word or two)
QUICK_CALL_SECONDS = 0.5  # ...or within its first 2 s, to read it at once
QUICK_READS = (2.0, 3.0, 4.0)  # seconds after a call began: read what has been said so far
SHAJRA_SECONDS = 20.0  # a stretch of voice this long after the last Muraqaba
FIRST_QUIET = 12.0    # quiet after a 1st Latifa read before any stage (not a bayan's word)
TASBIH_SECONDS = 5.0   # voice this long before any stage: maybe the opening Tasbih
CLIP_SECONDS = 11.5  # the last reading: the call and the ayah after it
OPENING = ("tasbih", "istighfar", "shahadah", "taawwudh", "basmalah")
JOBS = 4              # readings waiting for the worker thread at most; the oldest goes when a fifth comes
STALE_SECONDS = 30.0  # a reading whose clip is this old is skipped: the stage has moved on by then

# Words a call names, as Whisper writes them (seen in a recorded session) or
# as the app's own matcher has them. Only names, never Latifa numbers alone:
# Whisper garbles those, so the order carries the Latifas.
NAMES = [
    ("ahadiyat", r"احد[یي]ت|عدید|احضیت|ا?حدیت"),
    ("maiyyat", r"مع[یي]ت|مائ[یي]ت|ما[یي]ت|مائی ?ا[یي]ت"),  # "مائی ایت" 11 Nov
    ("aqrabiyyat", r"اقرب|قرب[یيا]|[کق]ر[بم]ی?ت|نحن|نحب|حب.?ل.?ن?و.?ر[یي]د|وا?ر[یي]د"),  # "او کربیت" 10 Nov
    ("sair-kaaba", r"سیر.?کعب|سرکب|سرکا|ارکا|کعبہ|کا بات|لب[یي]ک|لبار|سر[یي]? ?کا?ب"),  # "سری کابا" 10 Nov
    ("rauza-athar", r"روض|روز[یاےہ]|اطہر|اثر|[رن]وزی?ں ا|اتر[اے]ر|روزہ? ?ا?[طت]ا?ہ?ر"),  # "نوزیں اترار", "روز اطار" 10 Nov
    ("masjid-nabawi", r"مسجد|مشک|ماشی|نبوی|مس\S{0,4} ?نب[یيو]"),  # "مستین نبی" 10 Nov
    ("raabta", r"رابط|رابطہ"),
]


def level_db(frame: np.ndarray) -> float:
    return float(20 * np.log10(np.sqrt(np.mean(frame.astype(np.float32) ** 2)) + 1))


def named_stage(text: str) -> str | None:
    """The stage a call's words clearly name, if any."""
    for stage, pattern in NAMES:
        if re.search(pattern, text):
            return stage
    return None


# The word Latifa as Whisper writes it ("تک فا", "لدي فب", "لاتی فار", "اتیفا",
# "تکتا", "لطيفا", "لیتیفتا", "نتیف", "تِفتا"): "فا"/"فب" ending a word, not "فی" ("خفی", "کافی"), not
# "فائدہ", not "استغفار" (an opening recitation).
LATIFA_WORD = r"(?<!غ)ف[اب]\S?(?=\s|$)|ل[یاِ]?[تط][یي]?ف|تیف|تِ?فتا|تکتا|تفا"
# The opening recitations always come first, in this order (owner
# 2026-11-06: "tasbih always goes in order when the Zikr starts, before the
# 1st Latifa"). They are Arabic, so they are read as Arabic: "سبحان الله"
# comes through there where the Urdu reading garbles it ("سوحانا اللہ").
RECITATION_WORDS = [
    # 2026-11-10 Daily Zikr: the Arabic reading of the opening Tasbih came as
    # "سوحان الله و الحمد لله و لا ..." (و for ب) and the stage never moved.
    ("tasbih", r"س[بو]?ح[اـ]?ن|سبحن|سوان ال"),
    # As read on 10 November: "اسقاف الله ربي", "اصفلار", "اشادر لا اللہ اوشاد",
    # "اوز بالام", "مسم اللہ رخمان".
    ("istighfar", r"ستغفر|استغفار|استغف|اسقاف ال|صفلار|سفلار|استفن|[اأ]سف ل?ن?رب|رب[يی] من ك|رب[یي]م ا?ن ?کول"),
    ("shahadah", r"[أا]شهد|شهد [أا]ن|[أا]?شاد[رن]? |اوشاد|شادن"),
    ("taawwudh", r"[أا]عوذ|عوذ ب|[أا]وز بال|عوز بال"),
    ("basmalah", r"بسم|مسم ال|ر[حخ]مان"),
]
# The Tasbih before any stage needs more than "سبحان اللہ" (a bayan says it):
# its next words too ("والحمد لله", "الله اكبر").
TASBIH_MORE = r"حمد|[اأ]كبر|اکبر|لا ?[إا]له|ایلہ|لا ?حول|حول ب|قوات|قوة|عظيم|عظیم|مكب|مکب"
# (Tahajjud 10 November: "سبحان الله … لا إله … لا حول بنقوات" - the third
# Kalima - with no "الحمد" read.)
# The opening heard as a run: three different recitations within OPENING_WINDOW,
# one of them the Tasbih, Istighfar or Shahadah, is the Zikr's opening even when
# no single reading was clear and even though recitation reads as talk (the
# Tahajjud's opening was refused as talk). A bayan quotes one at a time.
OPENING_RUN = 3
RECITE_EVERY = 8.0  # seconds between readings of the opening's voice
# Listening (10 November 2026): the Daily Zikr's leader kept the mic open, the
# room's Zikr was heard the whole time, no quiet ever came before a call, and
# no call was read - every stage came from a host's typed cue, a minute or
# more late. Now the last few seconds are read every LISTEN_EVERY whenever
# there is voice, whoever leads and however loud the room is: a call shows
# as its words, the Zikr itself reads as nothing or one word over and over.
LISTEN_EVERY = 1.0  # a 5 s window every second: a call is read whole in several windows
LISTEN_SECONDS = 5.0
STAGE_GAP = 40.0  # a Latifa or Muraqaba lasts minutes: no new one this soon after the last stage
RETURN_GAP = 10.0  # the return to the 1st Latifa lasts moments: the Ahadiyat call came 31 s after it (10 November)
OPENING_WINDOW = 45.0  # the opening recitations follow each other within seconds
# A bayan is talk without a break; the Zikr between its calls reads as nothing
# or one word over and over. A stage heard is believed only when the
# readings of the TALK_BEFORE seconds before it (up to TALK_SKIP before it:
# the call itself is talk) were mostly not talk: a bayan about the Lataif
# says "پہلا لطیفہ" and "بسم اللہ" (the 2nd bayan recording, 10 November).
TALK_BEFORE = 30.0
TALK_SKIP = 6.0
TALK_MOST = 0.4
# What the room is doing outside the stages (owner, 11 November: the room sat
# silent for an hour while every screen said "Playing Bayan", and the Bayan
# after the Zikr stayed on the Shajra): nothing playing, a Bayan before the
# Zikr, a Bayan after it. Stages on the platform like any other; to the
# picker the first two are "no stage yet" and the last is "the Shajra".
WAITING, BAYAN, BAYAN_AFTER = "waiting", "bayan", "bayan-after"
PHASE_WINDOW = 30.0      # the readings a phase is judged on: the last 30 s
PHASE_TALK = 0.6         # a Bayan: most of them talk...
PHASE_READINGS = 10      # ...and at least this many (a reading a second while there is sound)
WAITING_QUIET = 20.0     # before the Zikr, this long without a sound: nothing is playing
BAYAN_QUIET = 60.0       # a Bayan's pause is not its end
AFTER_SHAJRA = 90.0      # the Bayan after the Zikr: talk 90 s after the Shajra began (its dua comes first)
PHASE_GAP = 20.0         # a phase changes at most this often
# "لطیفہ قلب" (the 1st) as read on 10 November: "لدی فائقان", "نتفعقال", "فيقال".
LATIFA_ONE = r"ف[ائیي]{1,2}ق[اہ]?[لن]|فعقال"


# A Latifa's number, when it comes through ("شوطحنا" = چوتھا, "اوانچوان" =
# پانچواں): it puts the order right if a call was missed or one too many
# was taken. Only ever forwards, and never more than two past the step.
NUMBERS = [(1, r"پہلا"), (2, r"دوسر|نسول"), (3, r"تیسر"), (4, r"چوتھ|[شجچ]و ?[تط]ح|جو ?تل"),
           (5, r"پانچ|انچوا|بان ?جو|باہن ?جو|بانجر"), (6, r"چھ[ٹڑ]"), (7, r"ساتو|سا ?تنل")]
# (10 November: "نسولہ تیفا" = دوسرا, "جو تل دیفا" = چوتھا, "بان جو نا دیفا" =
# پانچواں, "سا تنل دیفا" = ساتواں.)


def latifa_number(text: str) -> int | None:
    for number, pattern in NUMBERS:
        if re.search(pattern, text):
            return number
    return None


def is_call(text: str, step: str | None) -> bool:
    """Whether the words read are the call for `step`. A Latifa call is
    "<number> Latifa", and the word Latifa survives even when the number
    does not; a cough or a passing word ("اتھا", "دیکھانا") has no such word.
    A Muraqaba or the Shajra comes with an ayah or the chain of names:
    several different words (a model stuck on one word is not a call)."""
    if step and (step.startswith("latifa-") or step == "raabta"):
        return bool(re.search(LATIFA_WORD, text))
    words = text.split()
    return len(words) >= 3 and len(set(words)) * 2 > len(words)


def zikr_sound(text: str) -> bool:
    """Whether a reading is the Zikr's own sound, not a call or a recitation:
    one word over and over ("ایک ایک ایک ایک") or one drawn-out sound
    ("اوووووو"), as the 1st Latifa read on 11 November."""
    words = text.split()
    if len(words) >= 4 and len(set(words)) == 1:
        return True
    return 0 < len(words) <= 2 and any(re.search(r"(.)\1{5,}", word) for word in words)


ZIKR_SPAN = 8.0  # the Zikr's sound heard this far apart (within ZIKR_WINDOW) starts the 1st Latifa
ZIKR_WINDOW = 40.0


def is_talk(text: str) -> bool:
    """Whether a reading is speech (a bayan, a call) rather than the Zikr's
    sound, which reads as nothing or one or two words over and over."""
    words = text.split()
    return len(words) >= 3 and len(set(words)) >= 3


def ahead(stage: str, current: str | None) -> bool:
    """Whether `stage` comes after `current` in the order. One step goes
    back: after the 7th Latifa the Zikr returns to the 1st, then the
    Muraqabat (owner, 9 and 11 November: "7th Latifa, 1st Latifa, Muraqabat")."""
    if current not in ORDER:
        return True
    if current == "latifa-7" and stage == "latifa-1":
        return True
    return stage in ORDER and ORDER.index(stage) > ORDER.index(current)


def next_stage(current: str | None) -> str | None:
    if current is None:
        return "latifa-1"
    if current in ("istighfar", "shahadah", "taawwudh", "basmalah"):
        return "latifa-1"  # the opening recitations, before the first Latifa
    if current not in ORDER:
        return None  # a custom stage or the dua: no step from there
    if current == "latifa-7":
        return "latifa-1"  # the return to the 1st Latifa, before the Muraqabat
    index = ORDER.index(current)
    return ORDER[index + 1] if index + 1 < len(ORDER) else None


class Picker:
    """Feed 16 kHz mono int16 audio; `on_stage(stage, why)` is called from
    the feeding thread (steps) or the one worker thread (readings)."""

    def __init__(self, on_stage, current_stage, model_name: str = "base", read_calls: bool = True,
                 inline: bool = False) -> None:
        self.on_stage = on_stage
        self.current_stage = current_stage  # () -> the platform's stage id or None
        self.model_name = model_name
        self.read_calls = read_calls
        self.inline = inline  # tests: read calls on the feeding thread
        self.reads: list[tuple[float, str | None, float, float, str]] = []  # (read at, step, voice, call began, how)
        self.settled: set[float] = set()  # calls already settled (by when they began)
        self.model = None
        self.audio = deque(maxlen=int(40 * RATE / FRAME))  # 100 ms frames, last 40 s
        self.levels = deque(maxlen=int(40 * 10))
        self.history = deque(maxlen=1200)  # the last 2 minutes' levels, for the room's quiet
        self.floor = 0.0
        self.pending = np.zeros(0, dtype=np.int16)
        self.clock = 0.0           # seconds of audio fed
        self.quiet_since = 0.0     # start of the current quiet spell
        self.voice_run = 0.0       # seconds of near-continuous voice
        self.voice_start: float | None = None
        self.last_voice = 0.0  # a call needs a quiet spell heard first, not a cold start
        self.call_at: float | None = None  # a call being heard
        self.call_quick = False  # whether its first 2 s were checked
        self.last_call = -1e9  # when the last call that gave a stage began
        self.shajra_given = False
        self.tasbih_given = False
        self.last_tasbih_try = -1e9
        self.first_call: tuple[float, str] | None = None  # a Latifa call read before any stage, waiting for the quiet after it
        self.last_listen = -1e9
        self.seen_stage: str | None = None  # the stage as last seen, and since when (any source: heard, typed, tapped)
        self.stage_at = -1e9
        self.recited: list[tuple[float, int]] = []  # opening recitations heard before any stage: (clock, index)
        self.zikr_heard: list[float] = []  # the Zikr's own sound heard before any Latifa (Tahajjud): clocks
        self.lataif_done = False  # the 7th Latifa reached: a 1st Latifa after it is the return, not a new start
        self.heard: deque = deque(maxlen=120)  # (clock, whether the reading was talk), the listener's last readings
        # The Tahajjud Zikr has no bayan and no speech: it starts with the
        # Tasbihat and runs Lataif to the end (owner, 2026-11-10). Set by the
        # relay for each session; then nothing heard is refused as talk and
        # the first recitation or Latifa call starts the stages.
        self.tahajjud = False
        self.phase_at = -1e9  # when a phase (waiting, a Bayan) was last given
        self.last_sound = 0.0  # the last frame above LOUD_DB, whatever the room's floor
        self.lock = threading.Lock()
        # Readings run on one worker thread (the server has two cores; a
        # thread per reading piled up behind one lock on 6 November), from a
        # short queue: (generation, the clip's clock, what to run, its
        # arguments). The generation steps on reset(), so a reading queued
        # for the last session is skipped when its turn comes.
        self.generation = 0
        self.jobs: deque = deque(maxlen=JOBS)
        self.jobs_ready = threading.Condition()
        self.worker: threading.Thread | None = None
        self.dropped = 0  # readings pushed out of the queue by newer ones
        self.skipped = 0  # readings skipped as stale when their turn came

    def _current(self) -> str | None:
        """The platform's stage as the order sees it: before the Zikr (nothing
        yet, or a phase) no stage; the Bayan after it, the Shajra."""
        stage = self.current_stage()
        if stage in (WAITING, BAYAN):
            return None
        if stage == "latifa-7":
            self.lataif_done = True
        if stage == "latifa-1" and self.lataif_done:
            # The return to the 1st Latifa after the 7th (heard, or typed
            # "1st latifa"): it holds Raabta's place in the order, and the
            # next call is the first Muraqaba's (Tahajjud 11 November: the
            # Ahadiyat call was refused as the 2nd Latifa's).
            return "raabta"
        return "shajra" if stage == BAYAN_AFTER else stage

    def _phase(self) -> None:
        """Once a second: the room's phase outside the stages, from its sound
        (silence) and the listener's readings (talk). Never a Bayan in the
        Tahajjud, which has none."""
        raw = self.current_stage()
        if self.clock - self.phase_at < PHASE_GAP:
            return
        recent = [talk for t, talk in list(self.heard) if self.clock - t <= PHASE_WINDOW]  # a copy: the worker adds to it
        talking = len(recent) >= PHASE_READINGS and sum(recent) / len(recent) >= PHASE_TALK
        # Silence by the level alone: a long Bayan lifts the room's "quiet"
        # floor until its own words stop counting as voice (bayan-2: it
        # flipped between Bayan and waiting every 20 s while talk went on).
        quiet = self.clock - self.last_sound
        if raw in (None, WAITING, BAYAN):
            if raw != BAYAN and talking and not self.tahajjud:
                phase, why = BAYAN, f"talk in {sum(recent)} of {len(recent)} readings before the Zikr"
            elif raw != WAITING and not recent and quiet >= (BAYAN_QUIET if raw == BAYAN else WAITING_QUIET):
                phase, why = WAITING, f"no sound for {quiet:.0f} s before the Zikr"
            else:
                return
        elif raw == "shajra" and talking and not self.tahajjud and self.clock - self.stage_at >= AFTER_SHAJRA:
            phase, why = BAYAN_AFTER, f"talk in {sum(recent)} of {len(recent)} readings after the Shajra"
        else:
            return
        self.phase_at = self.clock
        self._give(phase, why)

    def reset(self) -> None:
        """A new session: forget the last one's calls, and skip its readings."""
        self.generation += 1
        self.phase_at = -1e9
        with self.jobs_ready:
            self.jobs.clear()
        self.reads.clear()
        self.settled.clear()
        self.call_at = None
        self.last_call = -1e9
        self.shajra_given = self.tasbih_given = False
        self.last_tasbih_try = -1e9
        self.first_call = None
        self.last_listen = -1e9
        self.seen_stage, self.stage_at = None, -1e9
        self.recited = []
        self.zikr_heard = []
        self.lataif_done = False
        self.heard.clear()

    def _queue(self, fn, *args) -> None:  # noqa: ANN001
        """A reading for the worker thread (inline: run here, on the feeding
        thread - the tests and replay_picker). JOBS wait at most: the oldest
        goes when another comes, since a backlog that long means the machine
        cannot keep up and the latest call is the one that matters."""
        job = (self.generation, self.clock, fn, args)
        if self.inline:
            self._run(job)
            return
        with self.jobs_ready:
            if len(self.jobs) == self.jobs.maxlen:
                self.dropped += 1
            self.jobs.append(job)
            self.jobs_ready.notify()
        if self.worker is None or not self.worker.is_alive():
            # A worker that died takes every later reading with it: start another.
            self.worker = threading.Thread(target=self._work, daemon=True)
            self.worker.start()

    def _work(self) -> None:
        while True:
            with self.jobs_ready:
                while not self.jobs:
                    self.jobs_ready.wait()
                job = self.jobs.popleft()
            self._run(job)

    def _run(self, job: tuple) -> None:
        generation, at, fn, args = job
        if generation != self.generation or self.clock - at > STALE_SECONDS:
            self.skipped += 1  # a new session, or a call long over: a reading now would name a stage that has passed
            return
        try:
            fn(*args)
        except Exception as error:  # noqa: BLE001 - one bad reading must not end all readings
            try:
                self.on_stage(None, f"reading failed: {error!r}")
            except Exception:  # noqa: BLE001
                pass

    def feed(self, samples: np.ndarray) -> None:
        self.pending = np.concatenate([self.pending, samples])
        while len(self.pending) >= FRAME:
            frame, self.pending = self.pending[:FRAME], self.pending[FRAME:]
            self._frame(frame)

    def _frame(self, frame: np.ndarray) -> None:
        self.clock += 0.1
        db = level_db(frame)
        self.history.append(db)
        if len(self.history) % 10 == 0:
            self.floor = float(np.percentile(self.history, 20))
        loud = db > max(LOUD_DB, self.floor + ABOVE_FLOOR_DB)
        if db > LOUD_DB:
            self.last_sound = self.clock
        self.audio.append(frame)
        self.levels.append(loud)
        stage = self._current()
        if stage != self.seen_stage:
            self.seen_stage, self.stage_at = stage, self.clock
        if round(self.clock * 10) % 10 == 0:
            self._phase()
        if (self.read_calls and self.clock - self.last_listen >= LISTEN_EVERY - 1e-6
                and len(self.audio) >= LISTEN_SECONDS * 10
                and max(list(self.history)[-int(LISTEN_SECONDS * 10):]) > LOUD_DB):
            self.last_listen = self.clock
            self._queue(self._listen, np.concatenate(list(self.audio)[-int(LISTEN_SECONDS * 10):]), self.clock)
        if loud:
            if self.clock - self.last_voice > 1.5:
                self.voice_start = self.clock
                quiet = QUIET_IN_OPENING if stage is None or stage in OPENING else QUIET_BEFORE
                if self.clock - self.last_voice > quiet and self.call_at is None:
                    self.call_at, self.call_quick = self.clock, False  # voice after a quiet spell: maybe a call
            self.last_voice = self.clock
        elif self.clock - self.last_voice > 1.5:
            self.voice_start = None
        run = self.clock - self.voice_start if self.voice_start is not None else 0.0

        opening = (stage is None and not self.tasbih_given) or (stage in OPENING and stage != "basmalah")
        if opening and run >= TASBIH_SECONDS and self.clock - self.last_tasbih_try > RECITE_EVERY:
            # Voice before any stage: the opening Tasbih, or a bayan before
            # the Zikr (the 9:15 PST room opens with one); during the opening,
            # the next recitation. Read it as Arabic; only the recitation's
            # own words move the stage, and only forwards in their order.
            self.last_tasbih_try = self.clock  # the listener reads the opening (10 November)
        if self.first_call is not None and self.clock - self.first_call[0] >= FIRST_QUIET + 4:
            # A Latifa call read before any stage counts once the room has
            # gone quiet after it, as it does in the Zikr; a bayan before
            # the Zikr talks on.
            (at, first), self.first_call = self.first_call, None
            if self._current() is None and self.read_calls:
                # What was said after the call: the Zikr's quiet reads as
                # nothing (or one word over and over), a bayan as sentences.
                clip = np.concatenate(list(self.audio)[-int(FIRST_QUIET * 10):])
                self._queue(self._after_first, clip, at, first)
        if stage == LAST_MURAQABA and not self.shajra_given and run >= SHAJRA_SECONDS:
            self.shajra_given = True
            self._give("shajra", f"{run:.0f} s of voice after the last Muraqaba")

        for read in [r for r in self.reads if self.clock >= r[0]]:
            self.reads.remove(read)
            if read[4] == "quick":  # what has been said since the call began
                clip = np.concatenate(list(self.audio)[-int((self.clock - read[3] + 0.5) * 10):])
            elif read[4] == "recite":  # the last few seconds of the opening
                clip = np.concatenate(list(self.audio)[-int(RECITE_EVERY * 10):])
            else:
                clip = np.concatenate(list(self.audio)[-int((CLIP_SECONDS + 0.5) * 10):])
            self._queue(self._read, clip, *read[1:])

        if self.call_at is not None:
            since = self.clock - self.call_at
            if since >= 2.0 and not self.call_quick:
                self.call_quick = True
                heard = sum(1 for value in list(self.levels)[-20:] if value) / 10
                if heard >= QUICK_CALL_SECONDS:  # a word or two already: read it now
                    at, self.call_at = self.call_at, None
                    self._call(at, heard, quick=True)
            elif since >= 4.0:
                heard = sum(1 for value in list(self.levels)[-40:] if value) / 10
                at, self.call_at = self.call_at, None
                if heard >= CALL_SECONDS:
                    self._call(at, heard, quick=False)

    def _call(self, at: float, heard: float, quick: bool) -> None:
        if at - self.last_call <= (RETURN_GAP if self._current() == "raabta" else 45):
            return  # a stage was given moments ago: this is the ayah after its call
        step = next_stage(self._current())
        if not self.read_calls:
            if step:
                self.last_call = at
                self._give(step, "a call, next in the order")
            return
        for after in QUICK_READS if quick else (4.0,):
            self.reads.append((at + after, step, heard, at, "quick"))
        self.reads.append((at + CLIP_SECONDS, step, heard, at, "full"))  # once the ayah after it has been said too

    def _read(self, clip: np.ndarray, step: str | None, heard: float, at: float, how: str) -> None:
        """Reads a call: quickly, what has been said so far; last, from up to
        three windows of a longer clip (a small model can read the same
        words as nothing, or as something else, from half a second away).
        The first reading that settles the call wins."""
        # The last reading tries the clip as encoded quickly, then the way
        # Whisper was trained (padded to 30 s: slower, and on some calls it
        # reads a garbled word the quick way misses), from two places.
        windows = ((clip, False), (clip, True), (clip[RATE // 2:], True)) if how == "full" else ((clip, False),)
        texts = []
        generation = self.generation
        for window, padded in windows:
            with self.lock:  # one reading at a time, whichever thread runs it
                if at in self.settled:
                    return
                try:
                    text = self.transcribe(window, padded, "ar" if how == "recite" else "ur")
                except Exception as error:  # noqa: BLE001 - the typed cues still carry the stage
                    self.on_stage(None, f"could not read the call: {error}")
                    return
                if generation != self.generation:
                    return  # a new session while this was read: the last one's call
                texts.append(text)
                if self._settle(text, step, heard, at, how):
                    self.settled.add(at)
                    return
        if how == "full":
            self.on_stage(None, f"not a call ({' / '.join(t[:25] for t in texts if t) or 'no words'}; {heard:.1f} s)")
        elif how == "recite":
            # What the opening's Arabic reading heard: the evidence for tuning
            # the Tasbihat (never once recognised by 8 November).
            self.on_stage(None, f"recite read: {(texts[0] if texts else '')[:60] or 'no words'}")

    def _listen(self, clip: np.ndarray, at: float) -> None:
        """The last few seconds, read whatever the room sounds like: an opening
        recitation, a Latifa's call, a Muraqaba's name. Only ever forwards in
        the order, and never a new Latifa or Muraqaba within STAGE_GAP of the
        last stage (whoever set it)."""
        generation = self.generation
        with self.lock:
            current = self._current()
            opening = current is None or current in OPENING
            try:
                urdu = self.transcribe(clip)
                arabic = self.transcribe(clip, language="ar") if opening else ""
            except Exception as error:  # noqa: BLE001 - the typed cues still carry the stage
                self.on_stage(None, f"could not listen: {error}")
                return
            if generation != self.generation or self._current() != current:
                return  # a new session, or the stage moved while this was read
            stage = self.decide(current, urdu, arabic, at)
            if stage:
                self.last_call = at
                if stage in OPENING:
                    self.tasbih_given = True
                self._give(stage, f"heard ({(arabic or urdu)[:40]}{' / ' + urdu[:30] if arabic else ''})")

    def decide(self, current: str | None, urdu: str, arabic: str, at: float) -> str | None:
        """The stage a reading moves to, if any: its words (_listened), and
        never in the middle of talk - except the opening's next recitation
        or the 1st Latifa once the opening is on the stage (it is talk)."""
        self.heard.append((at, is_talk(urdu)))
        stage = self._listened(current, urdu, arabic, at)
        opening = stage in OPENING + ("latifa-1",) and (current in OPENING or (current is None and self.opening_run(at, window=60.0)))
        if stage and not opening and not self.tahajjud and self.talk_before(at) >= TALK_MOST:
            self.on_stage(None, f"not taken: {stage} heard in the middle of talk ({urdu[:40]})")
            return None
        return stage

    def opening_run(self, at: float, window: float = OPENING_WINDOW) -> bool:
        heard = {i for t, i in self.recited if at - t <= window}
        return len(heard) >= OPENING_RUN and min(heard) <= 2

    def talk_before(self, at: float) -> float:
        """The share of the listener's readings that were talk, from
        TALK_BEFORE to TALK_SKIP seconds before `at` (0 when nothing was
        heard: the quiet before the Zikr is not a bayan)."""
        window = [talk for t, talk in self.heard if at - TALK_BEFORE <= t <= at - TALK_SKIP]
        return sum(window) / len(window) if window else 0.0

    def _listened(self, current: str | None, urdu: str, arabic: str, at: float) -> str | None:
        both = f"{urdu} {arabic}"
        since = at - self.stage_at
        if current is None or current in OPENING:
            after = -1 if current is None else OPENING.index(current)
            for index, (recitation, pattern) in enumerate(RECITATION_WORDS):
                if index <= after or not re.search(pattern, both):
                    continue
                if current is None and self.tahajjud:
                    return recitation  # no bayan before the Tahajjud: its first recitation is the Zikr
                if current is None:
                    # Before any stage only the Zikr's own opening starts it: the
                    # Tasbih with its next words, or the Istighfar or Shahadah
                    # right after a Tasbih. A bayan opens with "اعوذ باللہ ...
                    # بسم اللہ" and says "سبحان اللہ" (the 2nd bayan recording
                    # read as the 1st Latifa that way), so those never start it.
                    tasbih_before = any(i == 0 for t, i in self.recited if at - t <= OPENING_WINDOW)
                    self.recited = [(t, i) for t, i in self.recited if at - t <= 60.0] + [(at, index)]
                    if self.opening_run(at):
                        return recitation
                    if index == 0 and not re.search(TASBIH_MORE, both):
                        continue
                    if index > 0 and not (index <= 2 and tasbih_before):
                        continue
                return recitation
            # The 1st Latifa's call ends the opening. Before any stage (the
            # opening missed) only after a recitation in the minute before it,
            # and - like every stage heard - not in the middle of talk.
            # The call is a word or two ("پہلا لطیفہ"); a recitation reads as many
            # words, one of which can look like Latifa ("افال" in "ولا حول ولا قوۃ",
            # Tahajjud 10 November) - so never from a long reading.
            if (re.search(LATIFA_WORD, urdu) or re.search(LATIFA_ONE, both) or latifa_number(urdu)) and not is_talk(urdu):
                if current is not None or self.tahajjud or self.opening_run(at, window=60.0):
                    # Its number, when it comes through, outranks the order:
                    # the first call heard can be the 2nd's ("دوسرا لطیفہ",
                    # Tahajjud 11 November, when the room was joined late).
                    number = latifa_number(urdu)
                    return f"latifa-{number}" if number and number <= 3 else "latifa-1"
            if self.tahajjud and zikr_sound(urdu) and not re.search(LATIFA_WORD, both):
                # The Tahajjud has no bayan: the Zikr's own sound, heard twice
                # some seconds apart, means the 1st Latifa is on (its call
                # missed: on 11 November the room was joined muted after it).
                self.zikr_heard = [t for t in self.zikr_heard if at - t <= ZIKR_WINDOW] + [at]
                if at - self.zikr_heard[0] >= ZIKR_SPAN:
                    return "latifa-1"
            return None
        if since < (RETURN_GAP if current == "raabta" else STAGE_GAP):
            return None
        if current.startswith("latifa-") and current != "latifa-7":
            if re.search(LATIFA_WORD, urdu) or latifa_number(urdu):
                step = next_stage(current)
                number = latifa_number(urdu)
                if number and ahead(f"latifa-{number}", current) and number <= int(step[7:]) + 2:
                    step = f"latifa-{number}"
                return step
            return None
        if current == "latifa-7" and re.search(LATIFA_WORD, urdu) and latifa_number(urdu) in (None, 1):
            return "latifa-1"  # the return to the 1st Latifa ("پہلا لطیفہ"), before the Muraqabat
        if current in ORDER and ORDER.index(current) >= ORDER.index("latifa-6"):
            named = named_stage(urdu)
            if named and ahead(named, current) and ORDER.index(named) <= ORDER.index(current) + 2:
                return named
        return None

    def _after_first(self, clip: np.ndarray, at: float, first: str) -> None:
        generation = self.generation
        with self.lock:
            try:
                words = self.transcribe(clip).split()
            except Exception as error:  # noqa: BLE001 - the typed cues still carry the stage
                self.on_stage(None, f"could not read after the call: {error}")
                return
            if self._current() is not None or generation != self.generation:
                return
            if len(set(words)) <= 2:
                self.last_call = at
                self._give(first, f"a call, then quiet ({self.clock - at:.0f} s after it began)")
            else:
                self.on_stage(None, f"not a call: speech went on after it ({' '.join(words[:6])}; a bayan)")

    def _settle(self, text: str, step: str | None, heard: float, at: float, how: str) -> bool:
        if step == "recite":
            current = self._current()
            # Before any stage only the Tasbih can begin it; then each
            # recitation in turn (one may be missed, never gone back to).
            after = -1 if current is None else (OPENING.index(current) if current in OPENING else 99)
            for index, (recitation, pattern) in enumerate(RECITATION_WORDS):
                if after < index <= after + 2 and (current is not None or recitation == "tasbih") and re.search(pattern, text):
                    self.tasbih_given = True
                    self._give(recitation, f"the opening recitation ({text[:40]})")
                    return True
            return False
        current = self._current()
        returning = step == "latifa-1" and current == "latifa-7"
        if step in ORDER and current in ORDER and ORDER.index(step) <= ORDER.index(current) and not returning:
            return True  # the stage moved on meanwhile (a tap, a typed cue): nothing to do
        when = f"{self.clock - at:.1f} s after it began, {heard:.1f} s of voice"
        named = named_stage(text)
        # A name is believed once the Latifas are nearly done, a stage or two
        # ahead at most and never back: before that, "نحن" or "اثر" is just a
        # word in a recitation.
        if named and not (current in ORDER and ORDER.index(current) >= ORDER.index("latifa-6")
                          and (step not in ORDER or ORDER.index(named) <= ORDER.index(step) + 1)):
            named = None
        if named and ahead(named, current):
            self.last_call = at
            self._give(named, f"the call named it ({text[:40]}; {when})")
            return True
        if (step == "raabta" or returning) and not is_call(text, step) and is_call(text, "ahadiyat"):
            # Raabta passes in seconds and is often not called: a Muraqaba's
            # call (an ayah, no "Latifa") after the 7th Latifa is the first
            # Muraqaba's (11 November: missed, then every Muraqaba after it).
            step = "ahadiyat"
        if step and is_call(text, step):
            number = latifa_number(text) if step.startswith("latifa-") else None
            if number and ahead(f"latifa-{number}", current) and number <= int(step[7:]) + 2:
                step = f"latifa-{number}"  # its number came through: it outranks the order
            if current is None:
                self.first_call = (at, step)  # before any stage: wait for the quiet that follows a call
                return True
            self.last_call = at
            self._give(step, f"a call, next in the order ({text[:40]}; {when})")
            return True
        return False

    def transcribe(self, clip: np.ndarray, padded: bool = False, language: str = "ur") -> str:
        """The words in a clip. Whisper's encoder is built for 30 s and costs
        the same for any clip padded to it (about 5 s a reading on the relay
        server); a call is a few seconds, so only the clip's own length (and
        a second more) is encoded: 4-6 times faster, and it reads the calls
        as well. Greedy at temperature 0: the same call always reads the
        same way."""
        if self.model is None:
            from faster_whisper import WhisperModel
            self.model = WhisperModel(self.model_name, device="cpu", compute_type="int8", cpu_threads=2)
            tokenizer = self.model.hf_tokenizer
            self.prompts = {code: tokenizer.encode(f"<|startoftranscript|><|{code}|><|transcribe|><|notimestamps|>",
                                                   add_special_tokens=False).ids for code in ("ur", "ar")}
            self.end_token = tokenizer.token_to_id("<|endoftext|>")
        if padded:
            segments, _ = self.model.transcribe(clip.astype(np.float32) / 32768, language=language, beam_size=1,
                                                temperature=0.0, vad_filter=False, condition_on_previous_text=False)
            return " ".join(segment.text.strip() for segment in segments).strip()
        import ctranslate2
        features = self.model.feature_extractor(clip.astype(np.float32) / 32768)
        frames = min(3000, len(clip) // 160 + 100)
        if features.shape[1] >= frames:
            features = features[:, :frames]
        else:
            features = np.pad(features, ((0, 0), (0, frames - features.shape[1])), constant_values=float(features.min()))
        encoded = self.model.model.encode(ctranslate2.StorageView.from_array(np.ascontiguousarray(features[None], dtype=np.float32)),
                                          to_cpu=False)
        result = self.model.model.generate(encoded, [self.prompts[language]], beam_size=1, max_length=48, suppress_blank=True)
        tokens = [token for token in result[0].sequences_ids[0] if token < self.end_token]
        return self.model.hf_tokenizer.decode(tokens).strip()

    def _give(self, stage: str, why: str) -> None:
        self.on_stage(stage, why)
