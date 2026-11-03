# Teachings: Urdu renderings of three English articles, re-reviewed (2026-11-03)

Owner's instruction: re-review the three Urdu Teachings drafts (`what-is-tasawwuf-ur`, `what-is-tazkiyah-ur`, `importance-of-baiat-oath-of-allegiance-ur`, added in iOS 2bbb337, removed in d17bfca) and publish those found error-free.

**Outcome:** all three published again in `library_items.json`, iOS and Android, byte-identical. The library has 665 items; the manifest stays at 56.

## Base text and source
- **Base text:** the removed rows from 2bbb337, a later revision than `outputs/.../teachings-urdu-review/final/*.txt`.
- **English source:** each row's `bodyPlainText`, checked word for word against the live pages on naqshbandiaowaisiah.org. They differ only in web font glyph artefacts ("saw"/"rua" honorific glyphs, hyphenation splits). The website also has "hailed from urban" and the broken-off "it is …".
- **What each row says it is:** each now opens with: "یہ اردو متن سلسلے کی ویب سائٹ پر شائع انگریزی مضمون «…» کا اردو ترجمہ ہے؛ یہ حضرت امیر محمد اکرم اعوان رحمۃ اللہ علیہ کے اپنے اردو الفاظ نہیں…". The same paragraph says where the Qur'an and hadith wording comes from and that unlocated reports are marked.
- **Excerpt:** each row's excerpt is «سلسلے کے انگریزی مضمون «<title>» کا اردو ترجمہ».

## Method
- **Pass 1 (mine):** every sentence read against the English.
- **Qur'an:** every quoted verse checked by script against `quran_translations.json` (`akram-ut-tarajum-ur`). All are verbatim spans: 2:137, 49:3, 8:4, 9:100, 103:1-2, 103:3, 5:32, 33:35, 39:23, 20:70, and 48:10 in four places.
- **Arabic of the verses:** not typed into the text. The app shows it from `quran_ayahs.json` through the verse references; `quran_ayahs.json` was not touched.
- **Hadith:** every saying attributed to the Prophet ﷺ was searched for in all 26 hadith seeds.
- **Names:** checked against the Silsila books in `book_pages.json`.
- **Pass 2:** a separate reviewer subagent was given only the side-by-side texts, the Tarajum and the hadith seeds, and none of my conclusions.
  - It confirmed every Qur'an span and both hadith citations, and found no faithfulness defect.
  - It reported grammar slips and the way paraphrased Qur'anic speech was presented. All are fixed (see the pass 2 table).
- **Paraphrases of Qur'anic speech:** where the English puts a paraphrase in quotation marks, the Urdu keeps the English and adds "(… کا مفہوم)", so it is not read as the Tarajum.

## Hadith: located, cited, or marked
| Article ¶ | Claim in the English | Result |
|---|---|---|
| Tasawwuf p024 | "every non-believer receives the full reward of his apparently good works during his worldly life" | Found: Sahih Muslim 2808 (`muslim/7089/7090`). The record's Arabic and Urdu are quoted and cited. |
| Bai'at p008 | Bukhari: the Badr Companions "may do anything they like … Jannah is their lot" | Found: Sahih Bukhari 6259 (`bukhari/6259/6283`). The record's Arabic and Urdu replace the paraphrase and are cited. "From today onwards" goes; the record has لعل and Allah's words. |
| Bai'at p008 | "even if they sin or do Kufr and Shirk?" / "Do what they may!" | Not in any seed, and not in Bukhari. Kept in the article's words and marked «(مضمون کے الفاظ؛ ایپ میں شامل کتبِ حدیث میں اس کا حوالہ نہیں ملا)». |
| Bai'at p008 | Directive that one living Badri Companion's opinion binds the whole Ummah | Not in any seed. Kept and marked the same way. |
| Tasawwuf p017 | "the sun has never seen a man of his calibre after the Prophets" (Abu Bakr) | Not in any seed. The only "ما طلعت الشمس" reports are about Umar (Tirmidhi 3684, Mishkat 6046). Kept and marked. |
| Tazkiyah p017 | Women said the Qur'an addresses only men; the Prophet's reply | The occasion is found: Jami' at-Tirmidhi 3211 (Umm 'Umarah al-Ansariyyah; 33:35 revealed). It is cited in a marked note «(نوٹ: …)» after the verse. The reply has no source; it is kept and marked. |

**Narrations by others, not attributed to the Prophet ﷺ,** are rendered as the English has them and not marked:
- Abu Bakr's zakat reply. Its core, the rope «عقال», is in Bukhari 1400; the rest is the speech's own narration.
- "His breath smelt of roasted flesh".
- The grave question "Who is your Creator?", kept as خالق as in the English.
- The tafsir dialogue of Musa (AS).

## Earlier open doubts and how each was resolved
- **Tasawwuf p015 (Soviet atrocities in Samarqand and Bukhara):** these are the speaker's own historical statements of 1987. They are rendered exactly; the brief does not allow softening them. One fix brings the rendering closer to the English: "families were separated" is now «خاندانوں کے افراد کو ایک دوسرے سے جدا کردیا گیا».
- **Tasawwuf p027:**
  - **Khansa:** the Silsila's own Urdu tells the same story (Akram-ut-Tafaseer parah 2 p.171, parah 10 p.149; Hasht Roza Course pp.125-126): Khansa, Sakhr, Qadisiyyah, four sons, the tent. The English "Khamsa" is a romanisation slip, so the Urdu uses خنساء as the Silsila writes it.
  - **"This is His beneficence":** in this article a capital "His" mid-sentence refers to Allah, while the Prophet's "his" is lower-case. The Urdu «یہی اس کا فیض» keeps the reference to Allah; the Prophet would be «آپ ﷺ».
  - **The beds allusion (32:16):** the English paraphrases it without quoting, so it stays a paraphrase.
- **Tazkiyah p004 ("hailed from urban areas, simple village folk"):** the English contradicts itself, and the website says "urban" too. The brief forbids changing meaning, so the Urdu follows the English («شہری علاقوں … سادہ دیہاتی لوگ»). **Owner decision:** if "rural" was meant, change both rows together.
- **Tazkiyah p018 ("neither colour nor creed"):** rendered «رنگ یا مسلک». Here "creed" means a person's group or school; «نسل» would mean race, which the English does not say.
- **Bai'at p011-p015 (claims about named people):**
  - Every statement about Hadhrat Ji (RA), Mihar Ali Shah, Ashraf, Manzoor Shah, Major Baig, Bunyad Hussain Shah and Ahmad Nawaz was compared with the English clause by clause. They match, and nothing is identified or inferred beyond the English (the "He" of p012 stays unnamed, as in the English).
  - p015, on Hadhrat Ji's last address, agrees with the Silsila's Hayat-e-Tayyabah I pp. 647-648: only Akram has permission for spiritual Bai'at.
  - Spellings follow the books: چکڑالہ، لنگر مخدوم، میجر بیگ، بنیاد حسین شاہ، احمد نواز.
- **Bai'at p020:**
  - "stand fast against oppression and the implementation of Islam" admits only one reading: «ظلم کے مقابلے میں اور اسلام کے نفاذ کے لیے».
  - The Ghazwa-tul-Hind prayer is the 2002 speech's own words, rendered exactly.
  - The poison and doctor line is the speech's own analogy.
- **"Hadith not found in seeds":** resolved hadith by hadith in the table above.
- **Qur'an spans** (the earlier per-paragraph notes): all verified verbatim against the Tarajum (see Method).
- **Tazkiyah p006/p007:** the English breaks off ("it is …") and runs into 5:32. The Urdu ends p006 with «۔۔۔» and continues with the Tarajum's «تو گویا…».

## Fixes

Two notes on the tables:
- **Header:** all three rows now open with the attribution paragraph above, replacing the 2bbb337 header.
- **Tazkiyah p017:** in pass 1 the Tirmidhi citation sat inside the sentence after the Prophet's reply. Pass 2 moved it to a marked note after (33:35).

### Pass 1 (own review)

**What is Tasawwuf**

| ¶ | was | now | why |
|---|---|---|---|
| p002 | صوفی وہ ناکام اور بے بس لوگ ہیں | صوفی دنیا کے وہ ناکام اور بے بس لوگ ہیں | EN "miserable failures in the world": "in the world" was dropped |
| p012 | فتح کا بڑا سبب تعداد کی برتری | فتح کا سب سے بڑا سبب تعداد کی برتری | EN "the major battle-winning factor": the main factor, not one factor |
| p015 | ان کا تصور کرنا بھی مشکل ہے | ان کا تصور بھی نہیں کیا جاسکتا | EN "One cannot imagine": "difficult" softened it |
| p015 | تعلیم یافتہ خاندانوں کو الگ کردیا گیا | تعلیم یافتہ خاندانوں کے افراد کو ایک دوسرے سے جدا کردیا گیا | EN "the educated families were separated": families were broken up, not set apart from others |
| p015 | صحابۂ کرام کے نقوش نہیں مٹا سکا | صحابۂ کرام کے نقوشِ قدم نہیں مٹا سکا | EN "footprints" |
| p017 | رسول اللہ ﷺ نے فرمایا کہ انبیا کے بعد سورج نے ان جیسا شخص نہیں دیکھا۔ | رسول اللہ ﷺ نے فرمایا کہ انبیا کے بعد سورج نے ان جیسا شخص نہیں دیکھا (مضمون کے الفاظ؛ ایپ میں شامل کتبِ حدیث میں اس کا حوالہ نہیں ملا)۔ | Hadith not found in any hadith seed (searched all 26 books): kept in the article's words and marked |
| p020 | بعض کٹر لوگ اس سے بھی آگے | بعض حد سے بڑھے ہوئے لوگ اس سے بھی آگے | EN "diehards" (over-zealous celebrants), not doctrinal hardliners |
| p023 | اعلیٰ درجے کا دینی علم فرض نہیں؛ کسی شہر میں چند علما کا ہونا کافی ہے۔ | اعلیٰ درجے کا دینی علم لازم نہیں؛ کسی شہر میں چند علما کافی ہوں گے۔ | EN "not obligatory ... would suffice": "فرض" is a fiqh term the English does not use |
| p024 | ایک حدیث کے مطابق ہر کافر کو اس کے بظاہر اچھے اعمال کا پورا بدلہ دنیا ہی میں مل جاتا ہے۔ | ایک حدیث کے مطابق ہر کافر کو اس کے بظاہر اچھے اعمال کا پورا بدلہ دنیا ہی میں مل جاتا ہے: «وَأَمَّا الْكَافِرُ فَيُطْعَمُ بِحَسَنَاتِ مَا عَمِلَ بِهَا لِلَّهِ فِي الدُّنْيَا حَتَّى إِذَا أَفْضَى إِلَى الآخِرَةِ لَمْ تَ… | Hadith located: Sahih Muslim 2808 (muslim/7089/7090); its Arabic and Urdu quoted from the seed and cited |
| p025 | لیکن قرآن صرف اسی حد تک رہنے والے کو مثالی مسلمان قرار نہیں دیتا۔ | لیکن قرآن ایسے شخص کو مثالی مسلمان قرار نہیں دیتا۔ | EN "does not consider such a person": the draft added a qualifier |
| p026 | اور غروب ہوتے وقت بھی اس کی یاد سے بوجھل ہوتا ہے۔ | اور اس کی یاد میں نڈھال ہو کر غروب ہوتا ہے۔ | EN "it sets down weary with his memory" |
| p028 | اسے اللہ کا ذکر زیب نہیں دیتا | اسے اللہ کا ذکر کبھی زیب نہیں دے گا | EN "would never suit" |
| p031 | بھٹکے ہوئے دلوں کو اللہ کے نور سے روشن کیا | بیگانہ دلوں کو اللہ کے انوار سے روشن کیا | EN "enlightened the estranged hearts with Allah's Lights" |
| p032 | یہ میرے شیخ سے گہری وابستگی کی برکت ہے جن کی صحبت میں کچھ وقت گزارنے کا شرف ملا۔ | یہ اپنے شیخ سے میری گہری عقیدت کی وجہ سے ہے، جن کی صحبت میں کچھ عرصہ رہنے کا شرف مجھے حاصل ہوا۔ | EN "It is so because of my deep devotions to my Shaikh": "برکت" added a meaning |

**What is Tazkiyah**

| ¶ | was | now | why |
|---|---|---|---|
| p001 | لیکن اسے سکون نہیں دے سکیں | لیکن اسے کوئی سکون نہیں دیا | EN "haven't brought him any peace" |
| p004 | جس کے افراد دوسری جنگِ عظیم میں قتل نہ ہوئے ہوں | جس کے افراد دوسری جنگِ عظیم میں مارے نہ گئے ہوں | natural Urdu for war dead |
| p004 | کوئی جرمنی یا جاپان میں جنگی قیدی بنا | کوئی جرمنی اور جاپان میں جنگی قیدی بنا | EN "Germany and Japan" |
| p004 | اس کی ترجیحات بدل دیتا ہے | اس کی زندگی کی ترجیحات از سرِ نو ترتیب دیتا ہے | EN "rearranges his priorities in life" |
| p006 | اگر کوئی شخص کسی کو ایسی وجہ یا ایسے طریقے سے قتل کرے جس کی اللہ نے اجازت نہیں دی تو یہ ایسا ہے۔۔۔ | اگر کوئی شخص کسی کو ایسی وجہ یا ایسے طریقے سے قتل کرے جس کی اللہ نے اجازت نہیں دی۔۔۔ | the English breaks off ("it is ...") into 5:32; the Tarajum line that follows opens with "تو گویا", so "تو یہ ایسا ہے" doubled it |
| p006 | فرعون جیسا شخص بھی اپنے لیے ہدایت اختیار کرنے کا حق رکھتا ہے | فرعون جیسے شخص کے پاس بھی اپنے لیے ہدایت اختیار کرنے کا حق باقی رہتا ہے | EN "still retains the right" |
| p008 | تاہم انسان نے یہ عظیم ذمہ داری قبول کرلی | تاہم انسان نے یہ عظیم چیلنج قبول کرلیا | EN "accepted the grand challenge" |
| p011 | انہوں نے اپنی رسیاں ڈالیں اور رسیوں کے سانپ بنا دیے۔ | انہوں نے بس اپنی رسیاں ڈالیں جو سانپ بن گئیں۔ | EN "they just cast their ropes which became snakes" - rendered as the English says, not re-worded |
| p011 | «ہم ایمان لائے جہانوں کے پروردگار پر۔ جو موسیٰ اور ہارون (علیہما السلام) کا پروردگار ہے۔» | «ہم ہارون اور موسیٰ (علیہما السلام) کے پروردگار پر ایمان لائے۔» (20:70) | EN "fell prostrate saying, We believe in the Lord of Musa and Harun": the draft joined 26:47-48 and added "Lord of the worlds"; 20:70 is the verse of the prostration and says exactly this (Tarajum verbatim) |
| p011 | جب فرعون نے ان کی نافرمانی پر سنگین نتائج | جب فرعون نے ان کی بے وفائی پر سنگین نتائج | EN "disloyalty" |
| p011 | «میں تمہیں سخت سزا دوں گا اور جلد معلوم ہوجائے گا کہ زیادہ طاقت ور کون ہے۔ | «میں تمہیں سخت سزا دوں گا اور تمہیں جلد معلوم ہوجائے گا کہ زیادہ طاقت ور کون ہے۔ | EN "you will soon come to know" |
| p012 | وہ نسبتاً سکون سے رہ رہے تھے | وہ خاصے سکون سے رہ رہے تھے | EN "quite peacefully" (not "relatively") |
| p012 | اس کی پوری شخصیت بدل جاتی تھی۔ | اس کی پوری شخصیت یکسر بدل گئی۔ | EN "underwent a complete transformation" |
| p014 | جنہیں وہ اپنے اخبار فروخت کرنے کے لیے لکھتے ہیں | جنہیں وہ صرف اپنے اخبار بیچنے کے لیے لکھتے ہیں | EN "only to sell their papers" |
| p014 | آج اس کی اہمیت اور بھی زیادہ ہوگئی ہے، تاکہ انسان اس مصروف زندگی میں اپنے آپ کو اور اپنے رب کو نہ بھولے اور اپنے مالک کی مرضی کے مطابق کردار درست کرنے کی قوت… | آج اس کی اہمیت اور بھی زیادہ ہوگئی ہے، کیونکہ اس سے انسان اس مصروف زندگی میں اپنے آپ کو اور اپنے رب کو نہیں بھولے گا اور اپنے مالک کی مرضی کے مطابق اپنا کردار درست کرنے کی قوت حاصل کرلے گا۔ | EN "because a human being won't then forget": a reason, not a purpose |
| p016 | «پھر ان کے بدن اور ان کے دل نرم ہو کر اللہ کے ذکر کی طرف متوجہ ہوجاتے ہیں۔» | «پھر ان کے بدن اور ان کے دل نرم ہو کر اللہ کے ذکر کی طرف متوجہ ہوجاتے ہیں» (39:23)۔ | Tarajum 39:23 verbatim (the span has no full stop); reference added |
| p017 | آپ ﷺ نے فرمایا کہ قرآن پوری انسانیت کے لیے کتابِ ہدایت ہے، اس لیے اس کا خطاب تمام انسانوں سے ہے اور مرد و عورت دونوں یکساں طور پر نوعِ انسانی کے افراد ہیں۔ | آپ ﷺ نے فرمایا کہ قرآن پوری انسانیت کے لیے کتابِ ہدایت ہے، اس لیے اس کا خطاب تمام انسانوں سے ہے اور مرد و عورت دونوں یکساں طور پر نوعِ انسانی کے افراد ہیں (مضمون کے الفاظ؛ ایپ میں شامل کتبِ حدیث میں اس کا حوالہ نہیں م… | Occasion located (Tirmidhi 3211, the complaint and the revelation of 33:35); the reply attributed to the Prophet is in no seed: kept and marked, the located report cited |
| p017 | عورتوں کو بھی الگ ذکر کیا گیا | عورتوں کو بھی شامل کیا گیا | EN "included women": "الگ" was added |
| p018 | حالانکہ اس بیٹے نے اپنے باپ کو سلام کرنا بھی گوارا نہ کیا ہو اور اس سے کوئی قابلِ قدر چیز حاصل نہ کی ہو۔ | حالانکہ اس بیٹے نے کبھی اپنے باپ کو سلام کرنے کی بھی پروا نہ کی تھی اور اس سے کوئی قابلِ قدر چیز حاصل نہ کی تھی۔ | EN "in spite of the fact that the son never cared": a fact, not a supposition |
| p019 | یہ شعور دیتی ہے کہ وہ ہر وقت موجود ذات جس کے سامنے میں جواب دہ ہوں ہر وقت مجھے دیکھ رہا ہے۔ | یہ شعور دیتی ہے کہ وہ ہر جگہ موجود ذات، جس کے سامنے میں جواب دہ ہوں، ہمیشہ مجھے دیکھ رہی ہے۔ | EN "The Omnipresent ... is always watching me"; grammar: ذات is feminine (دیکھ رہی ہے) |

**Importance of Bai'at**

| ¶ | was | now | why |
|---|---|---|---|
| p003 | «بے شک جو لوگ آپ سے بیعت کرتے ہیں وہ (واقعی میں) اللہ سے بیعت کرتے ہیں» | «بے شک جو لوگ آپ سے بیعت کرتے ہیں وہ (واقعی میں) اللہ سے بیعت کرتے ہیں» (48:10) | Tarajum 48:10 verbatim; reference added |
| p004 | اپنے آپ کو، اپنی سوچ اور اپنے اختیار کو بیچ دینا | اپنے آپ کو، اپنی سوچ اور اپنی آزادی کو بیچ دینا | EN "freedom" |
| p005 | اللہ کا ہاتھ ان کے ہاتھوں پر ہے» گویا | اللہ کا ہاتھ ان کے ہاتھوں پر ہے» (48:10)۔ گویا | reference added; sentence closed |
| p008 | صحیح بخاری میں اصحابِ بدر کے بارے میں ایک حدیث ہے۔ رسول اللہ ﷺ نے فرمایا: «جو لوگ بدر میں شریک ہوئے، وہ جو چاہیں کریں؛ آج سے جنت ان کا مقدر ہے!» کسی نے فوراً… | صحیح بخاری میں اصحابِ بدر کے بارے میں ایک حدیث ہے۔ رسول اللہ ﷺ نے فرمایا: «لَعَلَّ اللَّهَ قَدِ اطَّلَعَ عَلَى أَهْلِ بَدْرٍ فَقَالَ اعْمَلُوا مَا شِئْتُمْ فَقَدْ وَجَبَتْ لَكُمُ الْجَنَّةُ» «اللہ تعالیٰ بدر کی لڑائی … | Hadith located: Sahih Bukhari 6259 (bukhari/6259/6283): its Arabic and Urdu replace the paraphrase, cited; the follow-up question and answer are in no seed: kept and marked |
| p008 | اس کی رائے درست ہوگی، وہ غلط سوچ نہیں سکتا۔» | اس کی رائے درست ہوگی، وہ غلط سوچ نہیں سکتا۔» (مضمون کے الفاظ؛ ایپ میں شامل کتبِ حدیث میں اس کا حوالہ نہیں ملا) | Directive attributed to the Prophet is in no seed: kept and marked |
| p015 | وہ ادھر اُدھر جاتے ہیں، نذرانے، صدقات اور زکوٰۃ مانگتے اور جمع کرتے ہیں | وہ ادھر اُدھر جاتے ہیں، نذرانے، صدقات اور زکوٰۃ طلب کرتے، مانگتے اور جمع کرتے ہیں | EN "demanding, begging and collecting" |
| p016 | بعض بدقسمت اس نعمت کو سنبھال نہیں پاتے | بعض بدقسمت اس نعمت کو جذب نہیں کرپاتے | EN "cannot absorb this blessing" |
| p017 | وہ کوئی فیس دیتا ہے | وہ کوئی چندہ دیتا ہے | EN "subscription" |

### Pass 2 (independent reviewer, given only the texts)

**What is Tasawwuf**

| ¶ | was | now | why |
|---|---|---|---|
| p001 | شیخ سلسلہ نقشبندیہ اویسیہ | شیخ سلسلۂ نقشبندیہ اویسیہ | izafat |
| p002 | اس سلسلہ عالیہ نے | اس سلسلۂ عالیہ نے | izafat |
| p017 | اپنے محبوب کو قبر میں سپرد کرنے کے بعد بھی | اپنے محبوب کو سپردِ خاک کرنے کے بعد بھی | EN "laid his beloved to eternal rest in the grave": idiom |
| p020 | بعض حد سے بڑھے ہوئے لوگ اس سے بھی آگے بڑھ گئے ہیں | بعض غلو کرنے والے اس سے بھی آگے نکل گئے ہیں | EN "Some diehards have gone even farther"; removes the repeated بڑھ |
| p020 | سالگرہ کی مبارک دی جارہی ہے | سالگرہ کی مبارک باد دی جارہی ہے | wrong word: مبارک باد |
| p023 | مطمئن ہیں کہ ہم مسلمان ہیں | مطمئن ہیں کہ وہ مسلمان ہیں | mixed person |
| p024 | اگر کسی نے دنیا کی زندگی میں انہیں جانا اور ان پر ایمان ہی نہ لایا ہو | اگر کسی نے دنیا کی زندگی میں انہیں جانا ہی نہ ہو اور ان پر ایمان ہی نہ لایا ہو | the negation must cover both verbs (EN "unless he has learnt and believed") |
| p025 | انسان خود ہی صبر کرنے والا نہ ہو | انسان صرف خود ہی صبر کرنے والا نہ ہو | EN "not only ... himself": could be misread as "should not be patient" |
| p032 | رفتار کم کرنا پڑتی ہے | رفتار کم کرنی پڑتی ہے | agreement |

**What is Tazkiyah**

| ¶ | was | now | why |
|---|---|---|---|
| p001 | شیخ سلسلہ نقشبندیہ اویسیہ | شیخ سلسلۂ نقشبندیہ اویسیہ | izafat |
| p001 | اس کا بہت سا بوجھ کم کرچکی ہیں، لیکن اسے کوئی سکون نہیں دیا | انہوں نے اس کا بہت سا بوجھ کم کردیا ہے، لیکن اسے کوئی سکون نہیں دیا | grammar: ergative subject for نہیں دیا |
| p002 | اس کی پیروی کی جائے | ان کی پیروی کی جائے | agreement with رائے اور رہنمائی |
| p006 | اس کی ناراضی سے ڈرو؟» | اس کی ناراضی سے ڈرو؟» (79:18-19 کا مفہوم) | the English gives an expanded paraphrase of 79:18-19 in quotation marks; marked as meaning so it is not taken for the Tarajum |
| p010 | وہ معاشرے کا سب سے پسا ہوا طبقہ تھے، جو اپنے آقاؤں کے سامنے سر اٹھانے کا خواب بھی نہیں دیکھ سکتا تھا۔ | وہ معاشرے کے سب سے پسے ہوئے طبقے سے تعلق رکھتے تھے، جو اپنے آقاؤں کے سامنے سر اٹھانے کا خواب بھی نہیں دیکھ سکتے تھے۔ | agreement |
| p011 | کھجور کے تنوں پر تم کو سولی دے دوں گا» | کھجور کے تنوں پر تم کو سولی دے دوں گا» (20:71 کا مفہوم) | paraphrase of 20:71 (part verbatim Tarajum) marked as meaning |
| p011 | جس کی اب تک نافرمانی کرتے رہے ہیں۔» | جس کی اب تک نافرمانی کرتے رہے ہیں۔» (20:72 کا مفہوم) | paraphrase marked as meaning |
| p011 | اس کی رضا پالیں۔» | اس کی رضا پالیں۔» (مفہوم) | the English "The holy Quran has recorded their conversation" introduces a paraphrase; marked as meaning |
| p012 | راکھ کھانا پڑی | راکھ کھانی پڑی | agreement |
| p017 | تیار فرما رکھا ہے۔» (33:35) | تیار فرما رکھا ہے۔» (33:35) (نوٹ: خواتین کے اس سوال پر اس آیت کے نزول کی روایت جامع ترمذی، حدیث 3211 میں ام عمارہ انصاریہ رضی اللہ عنہا سے ہے۔) | located report cited as a marked editorial note after the verse |
| p018 | صاحبِ علم علما | اہلِ علم | redundant |

**Importance of Bai'at**

| ¶ | was | now | why |
|---|---|---|---|
| p001 | شیخ سلسلہ نقشبندیہ اویسیہ | شیخ سلسلۂ نقشبندیہ اویسیہ | izafat |
| p004 | بہت بڑا اجر ملے گا۔ | بہت بڑا اجر ملے گا۔ (48:10 کا مفہوم) | the English paraphrases 48:10 as "He said"; marked as meaning |
| p005 | یہ موت کی پہلی بیعت تھی | یہ موت پر پہلی بیعت تھی | EN "Bai'at for death" (bai'at ala al-maut) |
| p006 | ان کے ہاتھوں پر ہے» اللہ کی حفاظت | ان کے ہاتھوں پر ہے» (48:10)۔ اللہ کی حفاظت | punctuation; reference |
| p008 | پیروی کرنا ہوگی | پیروی کرنی ہوگی | agreement |
| p009 | برائی کی طرف اس کا میلان کم ہوا اور نیکی کی طلب بڑھی ہے | برائی کی طرف اس کا میلان کم ہوگیا ہے اور نیکی کی طلب بڑھ گئی ہے | tense |
| p010 | دعا کی کہ بنی اسرائیل | دعا کی کہ انہیں بنی اسرائیل | missing object |
| p012 | جس نے فرمایا کہ جو بیعت توڑتا ہے وہ اپنے آپ کو توڑتا ہے۔ | جس نے فرمایا: «تو (بیعت کے بعد) جو عہد کو توڑے، تو توڑنے والے کا وبال خود اُسی پر ہے» (48:10)۔ | words attributed to Allah: the verse meant (48:10) quoted from the Tarajum instead of a paraphrase |
| p018 | خزانے والے کے پاس | خزانچی کے پاس | EN "treasurer" |
| p018 | پکارا: | چلّایا: | EN "shouted" |
| p020 | کوشش بھی کرنا ہوگی | کوشش بھی کرنی ہوگی | agreement |

## Gates
- `python Tools/ContentIntegrity/check_content.py`: PASS.
- `python Tools/Hadith/hadith_gate.py`: PASS (26 collections).
- Android: `LibraryQueriesTest` now expects 665 items. It checks that the three `-ur` rows are present, are in Urdu, share the English row's category and carry the attribution excerpt. It also checks that the Bai'at shelf shows one language per article.
