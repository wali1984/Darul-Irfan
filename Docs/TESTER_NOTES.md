# TestFlight tester notes — 1.11.1

Paste-ready text for App Store Connect, plus the briefing testers should get.
Keep the "already known" list current: a tester reporting a known gap costs
everyone time, and it reads as though the app is less finished than it is.

## Beta app description (App Store Connect)

> Darul Irfan is the official companion of Silsila Naqshbandia Owaisiah. It
> gives you prayer times and the azan, the complete Quran with translation and
> tafsir, a large hadith library, daily dua and zikr, and the silsila's books
> and lectures. Everything core works offline, and prayer times are calculated
> on your own device — your location is never sent anywhere.

## Owner's checklist for 1.11.1

What changed after the first 1.11.0 build, then the full 1.11.0 list.

**From your 1.11.0 feedback**
1. Urdu letters join everywhere (Quran tafsir, books, hadith). Urdu now uses
   the iPhone's standard lettering. If your phone has Apple's Nastaliq,
   Settings -> Appearance shows "Urdu in Nastaliq" - try it, and tell us if
   the letters still break with it on.
2. Full para tafseer (Library or "Read the full commentary"): lines joined
   into paragraphs, headings in green, Quranic quotations set apart in the
   Quran font, contents pages folded ("Contents page"), a sentence cut by the
   page continues on the same page. Asrar Urdu two-column pages show the
   Arabic first, then its Urdu.
3. Tafsir button on every ayah: opens Akram-ut-Tafaseer or Asrar-ut-Tanzil,
   in Urdu or English, for that ayah alone; the printed volume is one tap away.
4. Daily Zikr is 9:15 PM Pakistan time: 12:15 PM in New York until 1 November,
   11:15 AM after. The button reads "Join Daily Zikr".
5. Tahajjud Zikr shows one hour before Fajr at Dar-ul-Irfan (Pakistan time),
   marked as to be confirmed. The exact time is one number to change.
6. Community admins: in a group, Group admin -> "Members, admins and
   invitations": add by email (they join when they sign in with Apple under
   it), add by phone (a code you send by text or WhatsApp), code only, member
   or admin of that group; make or unmake admins; remove people; withdraw
   unused codes. Admins are now admins of their own groups only.

**From 1.11.0**

**The ten reported issues**
1. Urdu tafsir: open a surah, Tafsir, Urdu - Akram-ut-Tafaseer shows verse by
   verse, and "Read the full commentary" opens the printed volume at the surah.
2. Akram 1:1: Urdu reads cleanly in Nastaliq (no "noon noon", no OCR notes).
3. English Asrar translation and tafsir are left-aligned.
4. EN/UR switch in the reader changes the text straight away, and stays
   chosen when you move to the next surah.
5. Urdu shows Urdu and English shows English, across the app.
6. Zikr -> Method of Zikr opens the text (never "being prepared").
7. The live section is called "Daily Zikr" everywhere.
8. Zikr schedule: After Isha and Tahajjud show "Your time" in the phone's own
   time zone, with Pakistan time beside it.
9. Community -> Private groups explains how groups work.
10. About has no Acknowledgements (licences are in Settings -> Licences).

**Also in this release**
- Prayer times: check your city against your masjid; the method suggested at
  onboarding matches your country; the place and method show under the times;
  iqamah reminders and "Send a test reminder" in notification settings.
- Ayah of the Day (Today): Silsila translation (Akram-ut-Tarajum) in your
  language, full reference, tafsir excerpt, and "Open in the Quran".
- Today: quick tools, My Day (tasks with prayer-relative reminders, notes,
  focus timer, fasting), Continue reading, Understand something today.
- Daily Zikr is watched inside the app; no outside app or platform is named.
- Sign-in appears only in Community -> Private groups; nothing else asks.

**Community groups**
- Community -> Private groups -> Sign in with Apple -> **Share My Email**
  (wajidmahmood@hotmail.com): you should see "Super admin" and every group.
- In a group: post an announcement (paste works), save as draft and publish,
  add a zikr time (shown in your time zone, with a reminder), schedule a
  meeting, start community zikr with a live video link.
- Group notifications: with notifications on, a published post arrives as a
  push to that group's members only.
- Items that wait on an outside service say **"integration in progress"**
  instead of failing (video meetings and joining the zikr together, posts
  forwarded from WhatsApp, Daily Zikr starting here automatically). Each label
  disappears by itself once that service is connected on the server - no app
  update needed.

## What to test

Ask testers to spend time on these, in this order:

1. **Prayer times and the azan.** Are the times right for your city? Turn on
   reminders, and turn on the full azan. Does it arrive at the right moment,
   at a sensible volume, and can you stop it? Fajr should use its own call.
2. **The Quran and tafsir.** Open several surahs, long (2, 4, 7) and short
   (112, 114). Switch between English and Urdu, translation and tafsir. Urdu
   tafsir (Akram-ut-Tafaseer) now appears verse by verse.
3. **Today.** Ayah of the Day, My Day tasks and reminders, the focus timer.
4. **Daily Zikr.** The schedule should be in your own time; during a session
   it plays inside the app.
5. **Hadith, books and lectures.** Search, open a narrator, read a book's
   text, play a lecture and lock the phone - audio should continue.
6. **Offline.** Aeroplane mode: prayer times, Quran, hadith and book text
   should all still work.
7. **Urdu and right-to-left.** Urdu text right-aligned, letters joined, never
   clipped; English text left-aligned.
8. **Private groups** (members with an invitation code only). Admins: add
   someone by email and by phone, and make a second admin.

## Already known — please do not report these

- **"Integration in progress"** next to video meetings, joining the zikr
  together, WhatsApp-forwarded posts and the automatic Daily Zikr broadcast:
  those services are being connected and the labels go away when they are.
- **Akram-ut-Tafaseer stops at surah 91** (Ash-Shams). Parah 30 part 2
  (surahs 92-114) is still being converted from the scan.
- **Asrar-at-Tanzil Urdu opens as the printed volume, not verse by verse**:
  its scan corrupts the Quranic Arabic, so we will not split it by verse.
- **Two verses have no Asrar English translation** (23:38 and 80:41); the
  source text is wrong there, so they are left blank rather than guessed.
- **Some Asrar commentary is shorter than the printed original.**
- **Book text is machine-read from scans and is not proofread.** Never treat
  text inside a book as a reliable Quran or hadith quote.
- **A small number of hadith have a missing Arabic character**, from the
  source corpus.
- **The 251 Al-Murshid magazine issues have no text yet**; they have never
  been scanned.
- **The 33 Akram-ut-Tarajum library entries have no separate text**; the
  translation itself is complete in the Quran reader.

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
