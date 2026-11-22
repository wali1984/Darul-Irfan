# TestFlight tester notes

Paste-ready text for App Store Connect, plus the briefing testers should get.
Check each line against the build being released before it is pasted.

## Beta app description (App Store Connect)

> Darul Irfan is the official companion of Silsila Naqshbandia Owaisiah. It
> gives you prayer times and the azan, the complete Quran with translation and
> tafsir, a large hadith library, daily dua and zikr, and the Silsila's books
> and lectures. Everything core works offline. An account is optional and used
> only for Halqahs, which include live meetings with chat. Prayer times and
> Qibla are calculated on your own device. When Weather is on, your chosen
> city's approximate location goes to our weather service, and a nearby-masjid
> search, made only when you ask, sends your chosen place's location.

## What to test

Ask testers to spend time on these, in this order:

1. **Prayer times and the azan.** Are the times right for your city? Turn on
   reminders, and turn on the full azan. Does it arrive at the right moment,
   at a sensible volume, and can you stop it? Fajr should use its own call.
   "Send a test reminder" is in the notification settings, with the iqamah
   reminders.
2. **The Quran and tafsir.** Open several surahs, long (2, 4, 7) and short
   (112, 114). Switch between English and Urdu, translation and tafsir: the
   text should change straight away and stay chosen in the next surah. Every
   ayah's Tafsir button opens Akram-ut-Tafaseer or Asrar-at-Tanzil.
3. **Today.** Today's Light, My Day tasks and reminders, the focus timer,
   Continue, and Weather: turning Weather off in the location settings should
   remove it.
4. **Daily Zikr and Tahajjud Zikr.** The schedule should be in your own time;
   during a session Join Daily Zikr opens it inside the app.
5. **Hadith, books and lectures.** Search, open a narrator, read a book's
   text and open its PDF, play a lecture and lock the phone - audio should
   continue.
6. **Offline.** Aeroplane mode: prayer times, Quran, hadith and book text
   should all still work.
7. **Urdu and right-to-left.** Urdu text right-aligned, letters joined, never
   clipped; English text left-aligned; numbers as 0-9 in both languages.
8. **Halqahs.** Sign in with Apple or enter an invitation code, read the posts,
   join a meeting and use its chat. Admins: add someone by email and by phone,
   make a second admin, publish a post, remove a stage message. Last of all,
   try "Delete my account".

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
