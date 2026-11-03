# November 2026 narration fixes (amd: /mnt/sata1tb/di-voices/nov-fixes)

Owner, 2026-11-02: hiss still heard in Urdu and Arabic; Urdu sounds like AI in
places, with wrong pauses and pronunciations; in "recitation + translation",
some ayat are cut or carry a little of the next ayah's voice.

Measurement (read only):
- `hiss2.py`, `hiss3.py`: pause/noise floor, 6-9 kHz "sizzle" against the voice
  band, noise bursts (breaths) of 80 ms or more, on/off steps into digital silence.
- `pron_scan.py`: repeated Whisper disagreements over the stored transcripts, and pace.
- `whisper_words.py` + `pause_detect.py`: word-timed Whisper; pauses measured by
  energy between words (Whisper stretches words over pauses), mid-phrase pauses,
  clause ends read without a pause, pace while speaking.
- `cuts_build.py`, `align_surahs.py`, `cut_check.py`: where the reciter's ayah
  timings fall against the audio; Whisper alignment for surahs whose table does
  not fit the recording; Whisper check of each ayah clip, old table vs new.

Making:
- `tts_higgs_v3.py`: clause pauses from punctuation and Urdu grammar, cleaned
  reference clip, slowest-sensible take, `pronounce_v3.json`, recitation inside
  tafsir level-matched and faded. Writes to its own folder only.
- `narration_finish_v3.py`: high shelf + de-esser for the hot band, breath
  ducking, pause expander, soft ends.
- `pron_bench.py`: does a vowel mark make Whisper hear the written word.
- `ab_setup.py`, `ab_score.py`, `vox_ur.py`: the fixed-sample comparison.
- `nov_queue.sh` + `remake_slice.sh`: the remake through the GPU queue's lock and
  watchdog, in 12 slices, each checked by `verify_narration.py` (now with
  NARRATION_ROOT / VERIFY_DIR) and remade up to 3 times.
- `tafsir_check.py`: exact-text check for tafsir with the Qari's recitation taken out (not yet reliable).
- `ayah_cuts_apply.py`: writes the measured ayah windows into a copy of
  quran_word_timings.json for a content release (not run).

Nothing here uploads, touches the manifest, PUBLISH or HOLD_UPLOAD.
