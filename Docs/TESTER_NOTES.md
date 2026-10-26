# TestFlight tester notes — 1.9.7 (43)

Paste-ready text for App Store Connect, plus the briefing testers should get.
Keep the "already known" list current: a tester reporting a known gap costs
everyone time, and it reads as though the app is less finished than it is.

## Beta app description (App Store Connect)

> Darul Irfan is the official companion of Silsila Naqshbandia Owaisiah. It
> gives you prayer times and the azan, the complete Quran with translation and
> tafsir, a large hadith library, daily dua and zikr, and the silsila's books
> and lectures. Everything core works offline, and prayer times are calculated
> on your own device — your location is never sent anywhere.

## What to test

Ask testers to spend time on these, in this order:

1. **Prayer times and the azan.** Are the times right for your city? Turn on
   reminders, and turn on the full azan. Does it arrive at the right moment,
   at a sensible volume, and can you stop it? Fajr should use its own call.
2. **The Quran.** Open several surahs, including long ones (2, 4, 7) and short
   ones (112, 114). Try the recitation and check the highlighted word keeps up
   with the reciter. Switch between translation and tafsir views.
3. **Hadith.** Open a few collections, search inside one and across all of
   them, tap a narrator's name for the biography, and tap a verse quotation to
   see whether it opens the Quran at the right place.
4. **Books and lectures.** Open a book's text and read a few pages. Play a
   lecture, then lock the phone — audio should continue.
5. **Offline.** Turn on aeroplane mode and use the app. Prayer times, Quran,
   hadith and book text should all still work.
6. **Urdu and right-to-left.** If you read Urdu, check that Urdu text is
   right-aligned, in the Nastaliq face, and never clipped.
7. **Reinstall.** Delete and reinstall; your content should come back and the
   app should not be slow to start.

## Already known — please do not report these

- **Urdu tafsir is largely missing.** Asrar-at-Tanzil Urdu and
  Akram-ut-Tafaseer Urdu are not yet in the app; the English Asrar tafsir is
  complete for all 114 surahs. This is being worked on and is a content task,
  not a bug.
- **Two verses have no Asrar English translation** (23:38 and 80:41). The
  authoritative source's own text is wrong at those two places, so they are
  deliberately left blank rather than guessed at.
- **Some Asrar commentary is shorter than the printed original.** About a fifth
  of it is not in yet.
- **Book text is machine-read from scans and is not proofread.** Quality varies
  by book; some pages are rough and some embedded Arabic quotations are
  garbled. Never treat text inside a book as a reliable Quran or hadith quote.
- **A small number of hadith have a missing Arabic character**, shown as a
  replacement mark. This came from the source corpus we received and cannot be
  repaired from it.
- **The azan does not play in the web version unless the site is open**, which
  is a browser limitation, not a bug. The iPhone app is unaffected.

## Worth reporting

Anything else, especially: a prayer time that looks wrong for your city (say
which city), a crash or a blank screen, Arabic or Urdu that is clipped or
shown in the wrong script, audio that will not play or stop, and anything that
is slow enough to be annoying.

For a wrong prayer time, include the city and what time you expected — that is
almost always enough to find the cause.

## Internal vs external

Internal testers (App Store Connect users on the team) get the build with no
review. External testers need Beta App Review first, which wants the
description above, a contact email and the "what to test" notes.
