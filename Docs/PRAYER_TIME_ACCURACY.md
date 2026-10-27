# Prayer-time accuracy

Requirement (2026-10-27): times must be exactly right for the place, with no
exceptions. This records how that was checked, what was wrong, and what is
pinned by tests.

## How it was checked

`Tools/PrayerAccuracy/` (run `npm install` there first):

- `grid.mjs` computes 16 cities x 6 dates with **adhan-js 4.4.3**, the same
  algorithm and parameters as the app's adhan-swift, and compares each time
  with the **Aladhan API** (an independent implementation).
- `precise.py` (needs `pip install ephem tzdata`) compares the same grid with
  a **VSOP87 ephemeris**: geometric Fajr/Isha angles, -0.833 degree
  sunrise/sunset, Hanafi shadow = 2 x object + noon shadow.
- `highlat.mjs` reproduces the app's high-latitude handling.

Cities: Dar-ul-Irfan (Munara), Lahore, Karachi, New York, Houston, Toronto,
Vancouver, London, Oslo, Makkah, Dubai, Cairo, Jakarta, Sydney, Auckland,
Quito. Dates: mid-winter, the US and EU daylight-saving changes, the
solstices, and the US fall-back.

## Result

Where the sky gives an answer, the engine agrees with the ephemeris within
**0.5 minutes** for Fajr, sunrise, Maghrib and Isha, and about **1 minute**
for Asr. Dhuhr is consistently +1 minute: a deliberate safety margin in
each method's definition, so Dhuhr is never announced before the sun has
passed the meridian. London (Moonsighting Committee) shows Dhuhr +5 and
Maghrib +3, and Dubai its Awqaf offsets; those are the authorities' own
published adjustments.

## What was wrong, now fixed

| Defect | Size | Fix |
|---|---|---|
| Umm al-Qura Isha in Ramadan | 30 min early | Isha = Maghrib + 120 min in Ramadan (Umm al-Qura calendar), the Saudi rule the library leaves to the app |
| High-latitude limit applied even on nights with real twilight | up to 84 min (Vancouver, June: Fajr 04:00 vs true 02:36; Oslo, March: 60 min; Oslo, January: 8 min) | Under "Automatic", Fajr/Isha come from the astronomy whenever the sun reaches the angle (with 0.5 degree margin); the recommended rule decides only nights it never does (e.g. London in June). An explicitly chosen rule is honoured as the library applies it |
| One method (Karachi) for every country | Fajr/Isha 15-30 min off the local convention outside South Asia | Method chosen from the place's country at onboarding; Today offers it to existing users once; method, Asr school and place are shown under the times |
| Manual city with no time zone fell back to the phone's zone | wrong by the zone difference | Such results are no longer offered |

## Pinned by tests

`DarulIrfanTests/PrayerAccuracyTests.swift`: Dar-ul-Irfan winter/summer, New
York on its DST day, Sydney, Vancouver midsummer, Oslo winter/spring, London
midsummer fallback, Umm al-Qura Ramadan, the country table, and legacy place
decoding. Tolerance is two minutes.
