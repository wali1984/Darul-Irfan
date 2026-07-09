# Notification audio

iOS custom notification sounds must be **Linear PCM / IMA4 / uLaw / aLaw** in a
`.caf`, `.wav`, or `.aiff` container and **shorter than 30 seconds** — longer or
unsupported files silently fall back to the system default sound.

## Files

- `prayer-chime.wav` — app-original 6 s bell chime (generated, no rights issues).
  Used by the "Azan Clip" alert style until a licensed azan recording is added.

## Adding a real short Azan clip

`NotificationScheduler` looks for **`azan-short.caf`** in the app bundle first
and falls back to `prayer-chime.wav`, then to the default sound. To ship a real
azan excerpt (e.g. the takbir, ~15–25 s), obtain a licensed/permitted recording
and convert it on macOS:

```sh
afconvert azan-excerpt.m4a azan-short.caf -d ima4 -f caff -v
```

Drop `azan-short.caf` into this folder and add it to the app target (XcodeGen
picks up the folder automatically on regeneration).

Full-length azan playback inside the app (not notifications) can use a normal
MP3/M4A added here and played via `AudioPlayerService` — the 30 s limit only
applies to notification sounds.
