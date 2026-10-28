# Narration and amd batch jobs

Copies of the scripts that run on amd (`wali@10.10.100.100`, RTX 5080). The live
copies are on amd; these are kept here so the pipeline is reviewable.

- `gpu_queue.sh` (amd: `/mnt/sata1tb/di-queue/`): one GPU job at a time with a
  watchdog (Xid, 300 W cap, driver, 88 C). A `HALTED` file holds it.
- `tts_run.sh` + `tts_quran.py` (amd: `/mnt/sata1tb/di-tts/`): OmniVoice
  (k2-fsa, Apache-2.0) narration of Akram-ut-Tarajum (Urdu, English),
  Asrar-at-Tanzil English, and the per-ayah tafsir. One MP3 per ayah or per
  tafsir passage, so playback starts and stops on ayah ends. Arabic Qur'an
  quotations in tafsir are not voiced. Voices are modelled on everyayah.com
  recordings of Shamshad Ali Khan (Urdu) and Ibrahim Walk (English); the owner
  confirmed use. The apps always show that credit while narration plays.
- `tts_pilot.py`, `check_pilot.py`: the pilot and its Whisper intelligibility
  check (2026-10-28: Urdu median 95% word match, English 100%).
- `whisper_bayans.py`, `whisper_setup.sh`: bayan transcription (audio decoded
  with ffmpeg; faster-whisper's PyAV decoder needs a release with no wheel here).

Audio is served by the Worker at `/v1/audio/quran/<edition>/<kind>/<SSSAAA[-EEE]>.mp3`
from R2 `audio/quran/`, with `/v1/audio/quran/manifest` listing what exists.
