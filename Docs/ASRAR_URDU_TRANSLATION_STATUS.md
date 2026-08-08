# Asrar-at-Tanzil Urdu — translation build: blocked, and a live content defect

Outcome of the attempt to build per-ayah **Asrar Urdu translations** from the
OCR drops in `Asrar u Tanzil - Eng Urdu/`. The build was **not shipped**, and
the reason is not effort — the source is not good enough to attribute or to
print as scripture. Measurements below; every figure is reproducible with
`Tools/Quran/asrar_ur_probe.py`.

It also surfaced a defect in content **already shipping**, which is the more
urgent half of this document.

---

## Part 1 — the shipped Urdu tafsir is corrupted (act on this first)

`quran_tafsir.json` currently ships **1,118 `asrar-at-tanzil-ur` records across
114 surahs**, built from the same OCR drop. Sampling it for garbled tokens:

| Token | Occurrences in shipped seed | Should be |
|---|---|---|
| `ابدالا` | 9 | `ابدالآباد` |
| `انیوال` | 7 | (word does not exist) |
| `کنفرانس` | **2** | (word does not exist — this is the English "conference") |
| `دمحدا` | 1 | (word does not exist) |

The surah 18 record now visible to testers begins:

> نوء کہف مکی ہے اور امیں ایک سو دن آئیں اور بارہ کوع ہیں

which should read *"سورہ کہف مکی ہے اور اس میں ایک سو دس آیات اور بارہ رکوع ہیں"*
— "Surah Kahf is Makkan; it has 110 verses and 12 rukūʿ". The OCR has destroyed
`سورہ`→`نوء`, `اس میں`→`امیں`, `دس آیات`→`دن آئیں`, `رکوع`→`کوع`. The verse
translation that follows it is not recoverable Urdu at all.

**This is religious content, live in TestFlight.** Recommend pulling the
`asrar-at-tanzil-ur` tafsir edition (delete-then-insert path already exists in
`ContentSyncService`) until a clean drop replaces it, rather than leaving
corrupted scripture commentary in front of testers.

Note the QA sidecars say so themselves: all 114 documents carry
`finality: machine_provisional` and `human_verification_complete: false`. The
corpus was never claimed to be verified — it was shipped anyway.

## Part 2 — why the translation build was not attempted further

### Ayah attribution does not exist in the source

`asrar-urdu-layout-v1` — 25,261 blocks across 114 documents:

| content_type | blocks |
|---|---|
| tafsir | 11,763 |
| translation | 6,653 |
| unknown | 6,226 |
| metadata | 619 |

**Blocks carrying `ayah_start`: 0 (0.0%).** `attribution_method` is
`not_ayah_attributed` (18,608) or `repeated_trilingual_parallel_layout_v1`
(6,653) — the latter is a layout guess, not an attribution.

### The printed ayah markers cannot supply it

The parallel-text blocks carry ornate markers ﴿۱﴾﴿۲﴾﴿۳﴾. They do not survive
reconciliation:

* **8 of 114** surahs have a max marker equal to the canonical ayah count.
* **6 more** equal count + 1, because the Basmala is numbered ۱ in this edition.
* **100 surahs match neither.** Surah 2 yields 173 markers with a maximum of 25 —
  the markers restart per rukūʿ. Surah 12 yields a maximum of 155 against 111
  canonical ayat.
* **38 surahs have no marker blocks at all.**

### Anchoring on the Arabic fails too

The honest fallback is to ignore the markers and identify each verse by matching
its Arabic against the bundled mushaf. Trigram-Jaccard, 6,017 ayat probed
against `asrar-urdu-tafsir-final` (the cleaner drop):

```
mean 0.12 | median 0.07
>= 0.80:    75 / 6017 =  1.2%
>= 0.60:   141 / 6017 =  2.3%

surahs fully anchored : 0
surahs partially      : 33
surahs none anchored  : 81
```

**Zero surahs could be fully anchored**, so the "ship only reconciled surahs"
gate admits nothing.

### The reason is OCR quality, not the method

Short surahs come through in a clean line layout (Arabic line, then Urdu line
ending in a circled marker) and anchor well — surah 112:1 matches at 1.00,
112:4 at 0.87. Long surahs do not: Arabic and Urdu run together on one line
separated by ۝, and the Arabic itself is mangled.

Surah 2:2, as OCR'd against what it should be:

```
OCR       لَا رَبُّ عَنْ فِيهِ عَدَّى
correct   لَا رَيْبَ ۛ فِيهِ ۛ هُدًى
```

Surah 2:3 `وَلِيَّقِيُّونَ الصَّلَاةَ وَهِمَّا مَازِيرٌ فَمَنْ يَنْفِقُونَ` for
`وَيُقِيمُونَ الصَّلَاةَ وَمِمَّا رَزَقْنَاهُمْ يُنفِقُونَ`. In surah 18 the
Arabic is absent entirely and only garbled Urdu remains.

## Part 3 — what a usable re-OCR needs

The layout knowledge is worth keeping; it is the text quality that failed.

1. **Preserve the line structure of the short-surah layout across all 114.** The
   pattern `[Arabic verse] \n [Urdu translation + circled marker]` is directly
   parseable. The long-surah collapse into one ۝-separated line is what destroys
   attribution.
2. **Segment on ۝ and the ornate markers**, but treat them as *separators only* —
   their numbers are rukūʿ-relative and unusable as ayah numbers.
3. **Expect the Basmala to be numbered 1**, shifting the edition's numbering by
   +1 against canonical for every surah except al-Fatihah.
4. **Gate on Arabic anchoring, not on block counts.** Require ≥0.75 similarity to
   the bundled mushaf per verse and reject any surah that does not anchor
   completely. That gate is already implemented in the probe script.
5. **Do not ship `machine_provisional` scripture.** Commentary shipped under that
   flag once; the result is Part 1 of this document.

## Part 4 — what was deliberately not done

No per-ayah Urdu translation rows were written, and no partial or
best-effort mapping was committed. Per the project's standing rule — *never infer
missing source-book translation wording from commentary or another translation* —
the alternative routes were all rejected on purpose:

* positional mapping of 6,653 blocks onto 6,236 ayat (ratio 1.07) is a guess;
* filling from Akram-ut-Tarajum Urdu would present a different translator's
  wording as Asrar's;
* accepting the 2.3% that anchors would ship a translation with 97.7% holes and
  no way for a reader to tell which verses are trustworthy.

The reader already handles a missing Asrar translation by leaving it blank, so
absence is safe. Corruption is not.
