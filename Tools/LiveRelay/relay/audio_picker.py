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
    ("maiyyat", r"مع[یي]ت|مائ[یي]ت|ما[یي]ت"),
    ("aqrabiyyat", r"اقرب|قرب[یيا]|نحن|نحب|حب.?ل.?ن?و.?ر[یي]د|وا?ر[یي]د"),
    ("sair-kaaba", r"سیر.?کعب|سرکب|سرکا|ارکا|کعبہ|کا بات|لب[یي]ک|لبار"),
    ("rauza-athar", r"روض|روز[یاے]|اطہر|اثر"),
    ("masjid-nabawi", r"مسجد|مشک|ماشی|نبوی"),
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
    ("tasbih", r"سبح[اـ]?ن|سبحن"),
    ("istighfar", r"ستغفر|استغفار"),
    ("shahadah", r"[أا]شهد|شهد [أا]ن"),
    ("taawwudh", r"[أا]عوذ|عوذ ب"),
    ("basmalah", r"بسم"),
]
RECITE_EVERY = 8.0  # seconds between readings of the opening's voice


# A Latifa's number, when it comes through ("شوطحنا" = چوتھا, "اوانچوان" =
# پانچواں): it puts the order right if a call was missed or one too many
# was taken. Only ever forwards, and never more than two past the step.
NUMBERS = [(1, r"پہلا"), (2, r"دوسر"), (3, r"تیسر"), (4, r"چوتھ|[شجچ]و ?[تط]ح"), (5, r"پانچ|انچوا"),
           (6, r"چھٹ"), (7, r"ساتو")]


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


def ahead(stage: str, current: str | None) -> bool:
    """Whether `stage` comes after `current` in the order."""
    if current not in ORDER:
        return True
    return stage in ORDER and ORDER.index(stage) > ORDER.index(current)


def next_stage(current: str | None) -> str | None:
    if current is None:
        return "latifa-1"
    if current in ("istighfar", "shahadah", "taawwudh", "basmalah"):
        return "latifa-1"  # the opening recitations, before the first Latifa
    if current not in ORDER:
        return None  # a custom stage or the dua: no step from there
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

    def reset(self) -> None:
        """A new session: forget the last one's calls, and skip its readings."""
        self.generation += 1
        with self.jobs_ready:
            self.jobs.clear()
        self.reads.clear()
        self.settled.clear()
        self.call_at = None
        self.last_call = -1e9
        self.shajra_given = self.tasbih_given = False
        self.last_tasbih_try = -1e9
        self.first_call = None

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
        self.audio.append(frame)
        self.levels.append(loud)
        stage = self.current_stage()
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
            self.last_tasbih_try = self.clock
            if self.read_calls:
                self.reads.append((self.clock, "recite", run, self.clock, "recite"))
        if self.first_call is not None and self.clock - self.first_call[0] >= FIRST_QUIET + 4:
            # A Latifa call read before any stage counts once the room has
            # gone quiet after it, as it does in the Zikr; a bayan before
            # the Zikr talks on.
            (at, first), self.first_call = self.first_call, None
            if self.current_stage() is None and self.read_calls:
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
        if at - self.last_call <= 45:
            return  # a stage was given moments ago: this is the ayah after its call
        step = next_stage(self.current_stage())
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

    def _after_first(self, clip: np.ndarray, at: float, first: str) -> None:
        generation = self.generation
        with self.lock:
            try:
                words = self.transcribe(clip).split()
            except Exception as error:  # noqa: BLE001 - the typed cues still carry the stage
                self.on_stage(None, f"could not read after the call: {error}")
                return
            if self.current_stage() is not None or generation != self.generation:
                return
            if len(set(words)) <= 2:
                self.last_call = at
                self._give(first, f"a call, then quiet ({self.clock - at:.0f} s after it began)")
            else:
                self.on_stage(None, f"not a call: speech went on after it ({' '.join(words[:6])}; a bayan)")

    def _settle(self, text: str, step: str | None, heard: float, at: float, how: str) -> bool:
        if step == "recite":
            current = self.current_stage()
            # Before any stage only the Tasbih can begin it; then each
            # recitation in turn (one may be missed, never gone back to).
            after = -1 if current is None else (OPENING.index(current) if current in OPENING else 99)
            for index, (recitation, pattern) in enumerate(RECITATION_WORDS):
                if after < index <= after + 2 and (current is not None or recitation == "tasbih") and re.search(pattern, text):
                    self.tasbih_given = True
                    self._give(recitation, f"the opening recitation ({text[:40]})")
                    return True
            return False
        current = self.current_stage()
        if step in ORDER and current in ORDER and ORDER.index(step) <= ORDER.index(current):
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
            self.model = WhisperModel(self.model_name, device="cpu", compute_type="int8", cpu_threads=1)
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
