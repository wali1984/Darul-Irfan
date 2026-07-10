# Notification & azan audio

iOS custom notification sounds must be **Linear PCM / IMA4 / uLaw / aLaw** in a
`.caf`, `.wav`, or `.aiff` container and **shorter than 30 seconds** — longer or
unsupported files silently fall back to the system default sound. The 30 s limit
applies only to notification sounds; in-app playback (`AVAudioPlayer`) can use
normal MP3/M4A files.

## Files

### `azan-short.caf` — notification clip (opening takbirs)

- 18.0 s, Linear PCM (`pcm_s16le`), 44.1 kHz mono, ~1.51 MB. Used by
  `NotificationScheduler` for the "Azan Clip" alert style and previewed in
  Notification Settings.
- Cut from the first phrase group (the opening takbirs, ending on the natural
  pause at ~16 s) of the recording below, with a 2.5 s fade-out.
- **Source:** "Beautiful adhan" — Wikimedia Commons,
  <https://commons.wikimedia.org/wiki/File:Beautiful_adhan.ogg>
  (file: <https://upload.wikimedia.org/wikipedia/commons/b/b0/Beautiful_adhan.ogg>)
- **Author:** Adam-synagda (own work, uploaded 2022-04-29)
- **License:** **CC0 1.0 Universal** (public domain dedication) — verified on the
  Commons file page and via the Commons API extmetadata on 2026-07-10.
  No attribution required; credited anyway in More → About → Acknowledgements.

### `azan-full.mp3` — complete azan for in-app playback

- 2 min 34 s, MP3 96 kbps, 44.1 kHz mono, ~1.76 MB. Playable from
  Notification Settings ("Play Full Azan").
- The complete, unedited azan from the same recording as `azan-short.caf`
  (format conversion only — no content edits).
- **Source / Author / License:** same as above ("Beautiful adhan",
  Adam-synagda, **CC0 1.0**).

### `azan-fajr-full.mp3` — Fajr azan for in-app playback

- 4 min 8 s, MP3 80 kbps, 44.1 kHz mono, ~2.36 MB. Playable from
  Notification Settings ("Play Fajr Azan"). A live congregation recording
  (mosque ambience is audible), shipped unedited.
- **Source:** "Eid al-Fitr Fajr azan at Malmö Mosque - 19 August 2012" —
  Wikimedia Commons,
  <https://commons.wikimedia.org/wiki/File:Eid_al-Fitr_Fajr_azan_at_Malm%C3%B6_Mosque_-_19_August_2012.webm>
- **Author:** Islamic Center Malmö
- **License:** **CC BY 3.0 Unported** — verified on the Commons file page on
  2026-07-10. **Attribution is required** and is shown in More → About →
  Acknowledgements (author, source link, license, and a note that the audio
  was extracted from the original video and converted).

### `prayer-chime.wav` — fallback chime

- App-original 6 s bell chime (generated, no rights issues). Retained as the
  fallback for the "Azan Clip" alert style if `azan-short.caf` is ever removed
  from the bundle.

## Replacing the short azan clip

`NotificationScheduler` looks for **`azan-short.caf`** in the app bundle first
and falls back to `prayer-chime.wav`, then to the default sound — keep the
exact filename. To swap in a different licensed recording, trim to the opening
takbirs (~15–25 s, must stay under 30 s) and convert on macOS:

```sh
afconvert azan-excerpt.m4a azan-short.caf -d ima4 -f caff -v
```

(IMA4 is ~4x smaller than the Linear PCM used now; both are valid.) Or with
ffmpeg, adjusting the trim/fade to end on a natural phrase boundary:

```sh
ffmpeg -i input -t 18 -af "afade=t=out:st=15.5:d=2.5" \
  -ar 44100 -ac 1 -c:a pcm_s16le -f caf azan-short.caf
```

Drop the file into this folder and regenerate the project (XcodeGen picks up
the folder automatically). Update the license records above and the
Acknowledgements screen whenever a recording changes.
