# Sayings of the Sheikh from Al-Murshid TV (Today "Aqwal-e-Sheikh" card)

Date: 2026-11-03 to 2026-11-04. Branch: claude/amd-content. Manifest unchanged (56).

## What changed

`aqwal_e_sheikh.json` (English) and `aqwal_urdu.json` (Urdu) used to be two different lists: 13 English passages from website articles and 6 Urdu sayings from the website. Both files now hold the same 200 sayings, taken word for word from the Al-Murshid TV Q&A programmes (2014-05 to 2018-01). Each saying has the same id in the same position in both files, so `DailySelector.pick` (index = (epochDay + 337) % count) gives the same saying in both languages on the same day.

- id: `aqwal-almurshid-tv-ep<NNN>-<date>-<start seconds>`
- attribution: the Sheikh by the owner's date rule, then "Al-Murshid TV, Episode N, YYYY-MM-DD, mm:ss". In Urdu the numbers are wrapped in LRI/PDI.
- sourceUrl: the episode on YouTube at the saying's second (`&t=<s>s`).
- The schema is unchanged.
- Tests updated for the new count (200), the YouTube source and the bundled day's pick: iOS `TodayNoorLocalizationTests`, Android `TodayNoorLocalizationTest` and `DailySelectorTest`. Both tests now also assert that the English and Urdu ids are identical.

## Source and method

1. **Audio.** All 210 `alMurshidQA` episodes in `media_items.json` were downloaded from YouTube with yt-dlp on amd (`/mnt/sata1tb/di-almurshid`). None failed. That is 122 h of audio.
2. **Transcription.** The same faster-whisper large-v3 model and settings as the 800 bayans (`whisper_almurshid.py`, a copy of `whisper_bayans.py`). It ran as job `almurshid-whisper` in `gpu_queue.sh`, after the November narration queue: 210/210, 6.75 GPU h, 1.2% of segments flagged. The transcripts went through `transcript-pipeline/pipeline.py` (the paths can now be overridden with DI_TRANSCRIPTS/DI_OUT/DI_WORK) into `transcript-pipeline/out-almurshid/`, and `validate.py` passed. They are not shown in the app.
3. **Candidates.** 21 reader agents read every transcript in full, about 10 episodes each, and proposed 501 contiguous, verbatim stretches of the Sheikh's own answers. They left out presenter questions and interjections, callers and guests, politics, sects, fiqh rulings about a questioner's personal case, named living people, and any unverified Arabic.
4. **Review pass 1** (six independent reviewers, each stretch read with 2 minutes of context either side). They checked speaker, verbatim, standalone sense, safety, Arabic, spelling fixes and English. Result: 375 keep, 126 drop. Seven more were removed as replays: ep087/090/091 re-air parts of ep066/071/072, and ep161 repeats ep157.
5. **Second, independent transcription.** Each candidate's exact span was cut with ffmpeg and transcribed again with a different model, faster-whisper large-v2, on the clip only (job `almurshid-clips` in `gpu_queue.sh`, queued behind the narration remake).
6. **Review pass 2** (five independent reviewers). They compared both transcriptions word by word. A correction was applied only where the second model supports it, or where it is a pure spelling fix of the same sounds. The reviewers settled the final Urdu, translated it again from scratch, and gave a final faithful English. Result: 305 confirmed, 62 "listen first", 3 dropped.
7. **Selection.** The 200 in the app are all confirmed:
   - all 95 rated 5, plus 105 rated 4, preferring 65 words or fewer and at most two per episode;
   - 139 episodes are represented;
   - 117 have at least one confirmed spelling correction.

   Excluded on purpose:
   - ep215 (2018-01-04), a replayed lifetime interview of Hazrat Ameer Muhammad Akram Awan (RA). The date rule would credit it to Hazrat Ameer Abdul Qadeer Awan (MZA), so it was left out rather than credited by date.
   - ep168 at 27:39, which uses the terms ظلی/بروزی.

No Arabic appears in any saying except ordinary Urdu usage (اللہ، الٰہی، الحمدللہ، رب العالمین، حقوق العباد، ایمان بالغیب). The one candidate with a Qur'an line was not selected.

## Attribution

- 199 sayings: Hazrat Ameer Muhammad Akram Awan (RA), recorded 2014-05 to 2017-12.
- 1 saying: Hazrat Ameer Abdul Qadeer Awan (MZA), ep216 (2018-01-08), his jalsa address after the passing.

## Doubts for the owner

- **How the sayings were checked.** No person has listened yet. "Listening" here means two different Whisper models agreeing on the exact clip, plus two rounds of reader review. Every saying has its clip in `outputs/darul-design-review/sayings-almurshid/` (index.html, sayings.csv/json, clips/) so the owner can listen.
- **Episode dates.** The catalogue dates of some episodes look like upload dates, not recording dates:
  - ep37/38 are about Eid-ul-Adha, ep40/41 about Muharram, and ep134-136 about Ramadan.
  - ep200 appears twice in the catalogue (2017-09-22 and a re-air dated 2017-12-21).
  - Al-Murshid TV episodes 214 (funeral special) and 217/218 (interviews with Hazrat Ameer Abdul Qadeer Awan about his late father) gave no sayings, except one in ep218 that was not selected.
- **The catalogue `speaker` label** credits all 210 episodes to Hazrat Ameer Muhammad Akram Awan (RA), but ep216-218 are Hazrat Ameer Abdul Qadeer Awan (MZA). ep008 is a speech by a different, unnamed speaker, and ep112 is a recorded khitab, not a Q&A.
- **Reserve sayings.** 62 are listed in the review folder as "listen first". Each needs one word settled by ear, named in the row, and none of them is in the app.
