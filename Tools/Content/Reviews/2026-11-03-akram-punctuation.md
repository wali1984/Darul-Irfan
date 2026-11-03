# Akram-ut-Tafaseer: rows that end without punctuation, checked against the print (2026-11-03)

Owner's instruction: fix the 113 Akram-ut-Tafaseer rows that have no punctuation, for the next release.

## Which rows these are

The figure 113 came from the row-boundary review of 2026-11-02 (`Tools/Library/segment_akram_tafaseer.py`
SECTION_CORRECTIONS work). After that review was written, its check counted the rows of edition
`akram-ut-tafaseer-ur` that **end** without closing punctuation. It counted every row that has a next row
in the same surah, leaving out the kept surahs 63, 64, 67, 79 and 81, whose text does not match:

    (?:[۔؟!:.)\]﴾۞]|آمین)[\s‏﻿۝]*$

On the seed at the start of this task (`quran_tafsir.json` at c050914) the check gives exactly **113** rows.
These rows are not unpunctuated throughout. Their bodies carry ۔ and ، as normal, and only the end of
each row is open. For each row the "tail" was the text after its last ۔ ؟ or !, and that is the part checked.

## How each row was checked

- **Scans:** the printed volumes are `QuranTafseer-Para-N.pdf` (and `-30-part1`, `-30-part2`) on amd,
  `/mnt/sata1tb/Darul Irfan/Akram-ut-Tafaseer — Quran Urdu tafsir/`. They were copied read-only for this work.
  A page number in `book_pages.json` (`tafaseer-parah-N`) is the same as its PDF page number.
- **Finding the page:** each tail's start and end were found by matching 5-word runs of letters against
  the `book_pages.json` text of the expected parah. Five hints were wrong (16:95, 24:39, 24:54, 2:103,
  4:142) and 89:27 had none, so the reviewers found those pages by eye.
- **Reading:** five reviewers worked in parallel on 23, 23, 23, 23 and 21 rows. Each rendered bands of
  the page at 300 dpi with PyMuPDF and read by eye the tail, plus what the book prints straight after its
  last word. Each reported the printed punctuation that the tail lacked, inserting characters only.
- **Second check:** two more reviewers, given neither the first verdicts nor the first images, re-read
  41 rows (36%). These were all 16 flagged rows (any change, doubt or word difference, plus 2:130, 12:13,
  10:68 and 9:51) and 25 others drawn at random (seed 20261103).
  - On 7:105 and 42:32 the second check agreed.
  - On 2:103 the second checker could not read the faint line. I read it myself at 1:242: the print
    has "…وَهُوَ اَرْحَمُ الرّٰحِمِيْنَ ۔" at the end of the paragraph, before the next ruku heading on 243.
  - Every other row agreed: the second check found no punctuation missing.

## Result

| | Rows |
|---|---|
| Rows found by the check | 113 |
| Punctuated as printed | 3 |
| Unchanged: the print has no mark there | 110 |
| Unchanged: page not found or not readable | 0 |

The three changes, all of them inserted characters only:

- **2:103-103 (vol 1 p. 242):** ` ۔` added after the closing quotation فَاللّٰهُ خَيْرٌ حٰفِظًا وَّهُوَ اَرْحَمُ الرّٰحِمِيْنَ.
  The Arabic and its U+200F are untouched; the stop is its own token, as elsewhere in the file after U+200F.
- **7:105-105 (vol 9 p. 45):** `۔ ` added between …بَنِىْۤ اِسْرَآءِيْلَ and the Urdu "بنی اسرائیل کو میرے ساتھ بھیج دو".
  The book prints ﴿۱۰۵﴾ ۔ at that point. The row has no ayah marker there, and none was added. The book
  prints nothing after "بھیج دو", which runs straight into قَالَ.
- **42:32-32 (vol 25 p. 70):** `:` added at the end of "وہ تو ایسا قادر ہے کہ". The print has "کہ: اِنْ يَّشَاْ".

Why the other 110 are unchanged: the book itself has no stop where the row ends. In most of them the
row ends mid-sentence, and the printed sentence runs on into the next row's text, usually a quotation
of the next ayah, or words such as "اور تم نے کہا:" or "فرمایا:". A few are something else:

- **☆ lines:** 5:50, 5:56, 5:77 and 5:78-82 end on decorative ☆ lines.
- **Verse or a closing formula:** 2:235 and 3:185 end on couplets printed without stops, and 4:142-147
  and 6:110 end on the centred closing formula.
- **Ayah marker:** 3:145-147 and 4:173 end at an ayah marker with nothing after it.
- **Sub-heading:** 4:45 is a sub-heading line.
- **Mark already present:** 2:105, 24:39 and 83:18-21 already end with ، and 83:1 with :, exactly as printed.
- **Paragraph ends without a stop:** 12:13 is the one place where a paragraph ends unpunctuated in the
  book itself, after "کیوں کھا جائے گا".

Doubtful places were left alone. Gaps after "محال ہے" (10:68) and "کامیاب فرما" (9:51) carry no mark when zoomed.

## Verification

- **Changed rows:** a script compared the seed before and after (HEAD c050914). Exactly 3 rows changed,
  and every field other than `text` is the same. In each changed row:
  - the old text is a subsequence of the new;
  - only ۔ : and spaces were inserted;
  - the sequence of letters and digits is identical, with all punctuation and whitespace removed;
  - the words are identical once ۔ and : are removed.
- **Untouched content:** no Arabic letter, diacritic or ﴿…﴾ marker changed.
- **File layout:** written with `Tools/Content/seed_io.py`, so the file keeps its layout and the git diff
  is three lines.
- **Recount:** the same end-of-row check now counts 111 rows. Only 2:103 and 42:32 end differently;
  7:105's change is inside the row.
- **Android:** `a-content/app/src/main/assets/seed/quran_tafsir.json` equalled the iOS file before the
  change, was copied, and `cmp` shows it identical.
- **Gates:** `check_content.py` PASS (6,236 ayat, 163,476 narrations). `hadith_gate.py` PASS (26
  collections, only the existing narrator-biography warnings). The manifest stays at 56.

## Left for later (not changed in this task, because words must not change here)

- **2:130-141:** the row ends in back-cover text that is not part of the tafsir: "OUR CONTACT / WEBSITES:
  www.owaisiah.com … darulirfan@gmail.com", after the calligraphy plate عَلَّمَ الْاِنْسَانَ مَا لَمْ يَعْلَمْ on 1:318.
  The book's own text ends on 1:317 with ۔. This text should be removed from the row.
- **7:56-56:** the print reads "…واپس آجاؤ، وہ بڑا کریم ہے۔ وَهُوَ الَّذِىْ". The row lacks the word "ہے". Once
  it is restored, the printed ۔ goes after it.

OCR word errors seen by the reviewers. The row is on the left, the print on the right, and none was changed:

| Row | Row text | Print |
|---|---|---|
| 6:110-110 | دَعْوٰٮهُمْ (closing formula, Arabic) | دَعْوٰنَا |
| 7:56-56 | وہ بڑا کریم | وہ بڑا کریم ہے۔ |
| 7:159-159 | مِنْ قَوْمِ مُوْسٰٓى (Qur'an quotation) | وَمِنْ قَوْمِ مُوْسٰٓى |
| 11:13-13 | وحی والہی | وحیِ الٰہی |
| 19:46-46 | سنگ کرنے | سنگسار کرنے |
| 26:192-192 | پر دردگارِ | پروردگارِ |
| 26:192-192 | (missing) | headings "تفسیر ومعارف" and "عظمتِ قرآن:" between ﴿۲۲۷﴾ and فرمایا |
| 27:8-8 | تکہیانی | نگہبانی |
| 29:63-63 | امین | آمین |
| 34:10-10 | (missing) | heading "ایجادات:" before فرمایا |
| 34:10-10 | الْحَرِيْدَ (Arabic) | الْحَدِيْدَ; ﴿۱۰﴾ also missing |
| 34:9-9 | ayah markers ۱۹ and ۲۰ missing; Arabic garbled by OCR | |
| 35:34-34 | اجرا پنی | اجر اپنی |
| 89:27-27 | يَا يٰۤاَيَّتُهَا | يٰۤاَيَّتُهَا; ﴿۲۷﴾ missing |
| 89:27-27 | از جعج الی | ارْجِعِىْۤ اِلٰى |
| 20:17-19 | يُمُوّنُوا بَارِي تَعَالَى نَى فَرَمَايَا (before the tail) | یٰمُوْسٰی ﴿۱۹﴾ باری تعالیٰ نے فرمایا |
| 3:106-106, 7:8-8 | ayah marker after تَكْفُرُوْنَ / الْمُفْلِحُوْنَ missing | ﴿۱۰۶﴾ / ﴿۸﴾ printed |

Oddities found in the print itself were left as printed: "قیات" in 7:172, and "برباد ہوتی۔ ہے" just
before the 8:21 tail.

## All 113 rows

| Row | Printed page (vol:PDF p.) | Result | Second check |
|---|---|---|---|
| 2:21-22 | 1:63, 1:64 | unchanged: no mark in print | - |
| 2:31-31 | 1:86 | unchanged: no mark in print | - |
| 2:87-87 | 1:210 | unchanged: no mark in print | - |
| 2:103-103 | 1:242, 1:243 | punctuated | could not read the faint line; checked by eye by the lead: ۔ printed |
| 2:105-105 | 1:251 | unchanged: no mark in print | - |
| 2:130-141 | 1:317, 1:318 | unchanged: no mark in print | agrees |
| 2:191-191 | 2:175 | unchanged: no mark in print | - |
| 2:235-235 | 2:301 | unchanged: no mark in print | - |
| 3:106-106 | 4:63 | unchanged: no mark in print | agrees |
| 3:145-147 | 4:179 | unchanged: no mark in print | - |
| 3:168-170 | 4:260 | unchanged: no mark in print | - |
| 3:185-185 | 4:298, 4:299 | unchanged: no mark in print | - |
| 3:191-191 | 4:315 | unchanged: no mark in print | - |
| 4:29-29 | 5:41 | unchanged: no mark in print | agrees |
| 4:45-45 | 5:75 | unchanged: no mark in print | - |
| 4:67-68 | 5:113 | unchanged: no mark in print | - |
| 4:74-74 | 5:132 | unchanged: no mark in print | agrees |
| 4:83-83 | 5:160 | unchanged: no mark in print | - |
| 4:142-147 | 5:291 | unchanged: no mark in print | - |
| 4:157-157 | 6:37 | unchanged: no mark in print | agrees |
| 4:173-173 | 6:87 | unchanged: no mark in print | agrees |
| 5:36-36 | 6:218 | unchanged: no mark in print | - |
| 5:46-46 | 6:241 | unchanged: no mark in print | agrees |
| 5:50-50 | 6:254 | unchanged: no mark in print | - |
| 5:56-56 | 6:267 | unchanged: no mark in print | agrees |
| 5:77-77 | 6:304 | unchanged: no mark in print | - |
| 5:78-82 | 6:315 | unchanged: no mark in print | agrees |
| 6:17-17 | 7:157 | unchanged: no mark in print | - |
| 6:57-57 | 7:252, 7:253 | unchanged: no mark in print | - |
| 6:103-103 | 7:388 | unchanged: no mark in print | - |
| 6:105-105 | 7:391 | unchanged: no mark in print | - |
| 6:107-107 | 7:395 | unchanged: no mark in print | - |
| 6:108-108 | 7:398 | unchanged: no mark in print | - |
| 6:109-109 | 7:400 | unchanged: no mark in print | - |
| 6:110-110 | 7:402 | unchanged: no mark in print | agrees |
| 6:123-123 | 8:73 | unchanged: no mark in print | agrees |
| 6:128-128 | 8:91, 8:92 | unchanged: no mark in print | - |
| 6:130-130 | 8:100 | unchanged: no mark in print | - |
| 6:131-131 | 8:103 | unchanged: no mark in print | - |
| 6:132-133 | 8:105 | unchanged: no mark in print | - |
| 7:8-8 | 8:183 | unchanged: no mark in print | - |
| 7:24-24 | 8:214 | unchanged: no mark in print | - |
| 7:26-26 | 8:221, 8:222 | unchanged: no mark in print | - |
| 7:35-35 | 8:248 | unchanged: no mark in print | agrees |
| 7:38-38 | 8:254 | unchanged: no mark in print | agrees |
| 7:56-56 | 8:306 | unchanged: no mark in print | agrees |
| 7:65-65 | 8:322 | unchanged: no mark in print | - |
| 7:71-71 | 8:327 | unchanged: no mark in print | agrees |
| 7:104-104 | 9:42, 9:43 | unchanged: no mark in print | - |
| 7:105-105 | 9:45 | punctuated | agrees |
| 7:155-155 | 9:113 | unchanged: no mark in print | - |
| 7:159-159 | 9:135 | unchanged: no mark in print | agrees |
| 7:161-161 | 9:140 | unchanged: no mark in print | - |
| 7:164-164 | 9:150 | unchanged: no mark in print | - |
| 7:168-168 | 9:156 | unchanged: no mark in print | - |
| 7:169-169 | 9:158 | unchanged: no mark in print | - |
| 7:172-173 | 9:171 | unchanged: no mark in print | - |
| 7:175-175 | 9:174 | unchanged: no mark in print | - |
| 7:176-176 | 9:175, 9:176 | unchanged: no mark in print | - |
| 7:182-183 | 9:188 | unchanged: no mark in print | - |
| 7:191-192 | 9:216 | unchanged: no mark in print | - |
| 8:3-3 | 9:243, 9:244 | unchanged: no mark in print | - |
| 8:5-5 | 9:248 | unchanged: no mark in print | - |
| 8:12-12 | 9:266 | unchanged: no mark in print | agrees |
| 8:21-21 | 9:279 | unchanged: no mark in print | agrees |
| 8:26-26 | 9:291 | unchanged: no mark in print | - |
| 9:3-3 | 10:107 | unchanged: no mark in print | - |
| 9:4-4 | 10:109 | unchanged: no mark in print | - |
| 9:9-9 | 10:123 | unchanged: no mark in print | - |
| 9:21-21 | 10:152 | unchanged: no mark in print | - |
| 9:25-25 | 10:161 | unchanged: no mark in print | agrees |
| 9:26-26 | 10:165 | unchanged: no mark in print | agrees |
| 9:34-34 | 10:191 | unchanged: no mark in print | - |
| 9:45-45 | 10:241 | unchanged: no mark in print | agrees |
| 9:48-48 | 10:245 | unchanged: no mark in print | - |
| 9:51-51 | 10:249 | unchanged: no mark in print | agrees |
| 9:65-65 | 10:286, 10:287 | unchanged: no mark in print | - |
| 9:81-81 | 10:327 | unchanged: no mark in print | - |
| 9:88-88 | 10:341 | unchanged: no mark in print | - |
| 9:124-124 | 11:101 | unchanged: no mark in print | - |
| 10:24-24 | 11:176 | unchanged: no mark in print | - |
| 10:68-68 | 11:245 | unchanged: no mark in print | agrees |
| 10:101-101 | 11:286 | unchanged: no mark in print | agrees |
| 11:13-13 | 12:36 | unchanged: no mark in print | agrees |
| 11:121-121 | 12:159 | unchanged: no mark in print | - |
| 12:11-11 | 12:178 | unchanged: no mark in print | - |
| 12:13-13 | 12:179 | unchanged: no mark in print | agrees |
| 14:1-1 | 13:151 | unchanged: no mark in print | - |
| 16:95-95 | 14:186 | unchanged: no mark in print | agrees |
| 19:46-46 | 16:83 | unchanged: no mark in print | agrees |
| 20:17-19 | 16:147 | unchanged: no mark in print | agrees |
| 24:39-39 | 18:177 | unchanged: no mark in print | - |
| 24:54-54 | 18:203, 18:204 | unchanged: no mark in print | - |
| 26:192-192 | 19:185, 19:184 | unchanged: no mark in print | agrees |
| 26:224-224 | 19:196 | unchanged: no mark in print | - |
| 27:8-8 | 19:208 | unchanged: no mark in print | agrees |
| 29:63-63 | 21:42, 21:43 | unchanged: no mark in print | agrees |
| 31:23-23 | 21:144 | unchanged: no mark in print | - |
| 31:29-29 | 21:148 | unchanged: no mark in print | - |
| 34:9-9 | 22:112, 22:111 | unchanged: no mark in print | - |
| 34:10-10 | 22:114 | unchanged: no mark in print | agrees |
| 35:29-29 | 22:213, 22:214 | unchanged: no mark in print | - |
| 35:34-34 | 22:219 | unchanged: no mark in print | agrees |
| 37:175-176 | 23:121 | unchanged: no mark in print | - |
| 42:32-32 | 25:70 | punctuated | agrees |
| 69:13-13 | 29:76 | unchanged: no mark in print | - |
| 83:1-1 | 30-part1:90, 30-part1:89 | unchanged: no mark in print | agrees |
| 83:18-21 | 30-part1:99, 30-part1:100 | unchanged: no mark in print | agrees |
| 89:27-27 | 30-part1:198 | unchanged: no mark in print | agrees |
| 91:11-12 | 30-part1:233 | unchanged: no mark in print | - |
| 96:6-7 | 30-part2:106 | unchanged: no mark in print | agrees |
| 102:5-6 | 30-part2:165 | unchanged: no mark in print | - |
| 112:1-3 | 30-part2:232 | unchanged: no mark in print | - |
