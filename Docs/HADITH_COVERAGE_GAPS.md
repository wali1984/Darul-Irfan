# Hadith corpus — exact gaps

What the bundled hadith corpus does and does not contain, why each gap exists,
and what would actually close it. Every figure here was measured, not estimated;
where something is unverified it says so.

Companion to `HADITH_INGEST_FINDINGS.md`, which covers the ingester's mechanics.

---

## 1. Urdu — the largest gap, and it is a sourcing problem

**Seven collections have Urdu. Nineteen do not, and no open *dataset* supplies
it.** One further website does (see §1a) and is being ingested with a
content-based join; the paragraphs below describe the dataset landscape.

The Urdu on Bukhari, Muslim, Nasa'i, Abu Dawud, Tirmidhi, Ibn Majah and Malik
comes from two places: the `urd-*` editions published by `fawazahmed0/hadith-api`
(Unlicense) that the original packs were built from, and sunnah.com's
`/ajax/urdu/<collection>/<book>` endpoint used to split chain from text.

For every other collection that endpoint returns **HTTP 500**. Measured
2026-08-09 against `riyadussalihin`, `mishkat`, `adab`, `bulugh`, `darimi` and
`ahmad` — all six, no exceptions. There is no Urdu behind it to fetch.

### Sources searched, and why each fails

| Source | Collections | Urdu | Licence | Why it does not close the gap |
|---|---|---|---|---|
| `fawazahmed0/hadith-api` | 10 | Yes, for 7 | Unlicense | Its Urdu covers exactly the seven we already have. Adds `nawawi`, `qudsi`, `dehlawi` in Arabic/English only. |
| `AhmedBaset/hadith-json` | 17 (50,884 hadith) | **No** | **None stated** | Derived from sunnah.com, so it carries the same data and the same gaps. Unlicensed content cannot be bundled. |
| IslamHouse / HadeethEnc API hub | unclear | **No** | MIT (code only) | Lists Chinese, Japanese, Korean, Mongolian, Rohingya. Content governed by source-platform terms. |
| sunnah.com | 19 extra | **No** | see §5 | The `/ajax/urdu/` route 500s for all nineteen. |

The Urdu editions of Mishkat, Riyad as-Salihin and Musnad Ahmad that do exist —
Darussalam, Maktaba, the Naeemi commentary on Mishkat — are **modern copyrighted
books**. The PDFs circulating on scan sites are those same editions, not
licensable data.

### 1a. ahlesunnatpak.com — a real Urdu source for four of the works

Found by the owner after the dataset search above. `ahlesunnatpak.com` carries
paired Arabic+Urdu for Bukhari, Muslim, Tirmidhi, Abu Dawud, Ibn Majah,
Nasa'i, **Mishkat**, **Musnad Ahmad** (177 book sections against sunnah.com's
8) and Al-Silsila as-Sahiha. `robots.txt` allows all crawling. Facts that
shape how it is used:

* **No edition attribution or copyright statement anywhere on the site**, and
  at least one editorial artifact ("wrong same as 59") observed inside content
  — so its text is treated as provisional, tagged
  `urduSource: "ahlesunnatpak.com"` + `urduReviewState: "machine_provisional"`,
  and gated on review like everything else unverified.
* **Its numbering cannot be joined on.** Grouped labels — `(۵،۶)` printed on
  two or three consecutive blocks — mean numbers neither align with ours nor
  identify one narration. A naive parse of one 50-hadith page lost 5 records
  and produced 1 duplicate.
* **Its Arabic is typeset with Urdu code points** (measured on one Musnad page:
  farsi yeh ×872, heh goal ×751, keheh ×277, teh marbuta goal ×100), so the
  join key folds Urdu letter forms to Arabic before matching.

`Tools/Hadith/asp_urdu_ingest.py` therefore joins **on the Arabic text itself**
(same unique-key discipline as the sunnah.com enrichment: no key, no unique
match → no fill), never replaces existing Urdu, and targets exactly the gaps:
Mishkat, Musnad Ahmad, Nasa'i's missing ~1,800, Bukhari books 64–65.

Al-Silsila as-Sahiha is deliberately not ingested — adding an entire new
collection from a single unattributed source is a separate decision.

### What would close the rest

Machine translation, through the pipeline's existing `Translator`: set
`DI_TRANSLATE_URL` and `DI_TRANSLATE_KEY` to an OpenAI-compatible endpoint and
re-run with `--translate`. It is resumable against the warm cache.

Two conditions, from experience on this project rather than caution in the
abstract. Every translated record must carry `urduSource: machineTranslated`,
and public release must be gated on scholarly review while TestFlight is not.
On 2026-08-08 this repo withdrew 1,118 Asrar-at-Tanzil Urdu tafsir records
because machine-provisional religious text shipped without either guard — the
English word "conference" was sitting inside Urdu scripture commentary. Hadith
matn is the words of the Prophet ﷺ and carries more weight than commentary, not
less.

## 2. Musnad Ahmad — ~27,600 narrations do not exist in any open source

sunnah.com publishes **8 sections** of Musnad Ahmad against a canonical ~27,647
narrations. `AhmedBaset/hadith-json` documents the same limitation
independently: *"Musnad Ahmad: Chapters 8–30 are missing from the source."*

This is not a crawler defect and no amount of re-crawling changes it. The
collection ships as the partial set sunnah.com carries, and the catalogue's
`hadithCount` reflects what is actually bundled — counted from the records, never
copied from upstream metadata, so it cannot over-claim.

## 3. Collection completeness — verified against canonical counts

Each from-scratch collection is checked against its canonical total. Confirmed so
far:

| Collection | Bundled | Canonical | Coverage | Note |
|---|---:|---:|---:|---|
| Forty Hadith of an-Nawawi | 42 | 42 | **100%** | |
| Forty Hadith Qudsi | 40 | 40 | **100%** | |
| Riyad as-Salihin | 1,217 → re-running | 1,896 | 64.2% → expected ~100% | named `introduction` book skipped; see §4, fixed |
| Mishkat al-Masabih | 5,306 → re-running | 6,294 | 84.3% → expected ~99% | **same named-book cause** — it too has an unfetched `introduction` book — plus 11 duplicate display numbers and 1 unnumbered |

The remaining collections were still crawling when this was written; their
figures belong in the vetting report the run emits.

**Malik's Urdu is 1,614 of 1,868 (86.4%) and Nasa'i's 3,874 of 5,683 (68.2%),
and the Arabic-text join fix moved both by zero.** Measured after the re-run:
their records were already matched — the Urdu is absent at source, the same
class of gap as Bukhari books 64–65. (An earlier revision of this document
predicted the join fix would improve them; that prediction was wrong.) Nasa'i's
gap is a target of the §1a ingestion; Malik is not on that site.

The join fix's real gain was **Muslim segmentation: 2,960 → 5,598 of 7,482**
(+2,638). The remainder are ambiguous Arabic keys deliberately not guessed at,
plus genuine non-matches.

**Bukhari books 64 and 65 have no Urdu at all — 987 narrations.** Those two
return 500 at the book level on every URL variant tried, and the per-chapter
fallback route (`/ajax/urdu/<slug>/<book>/<chapter>`) does not exist — it 404s.
Source limitation, unfixable from here.

## 4. Defects found and fixed while building this

Recorded because each was silent — the pipeline reported success while losing
data, which is the failure mode that matters.

* **Non-numeric book slugs skipped.** Book discovery matched `/<slug>/(\d+)"`,
  so Riyad as-Salihin's opening book — *The Book of Miscellany*, hadith 1 to 679,
  served at `/riyadussalihin/introduction` — was never fetched. 1,896 − 679 =
  1,217, exactly the count produced. Fixed by `discover_books()`, which accepts
  named books; applies to the enrichment path too.
* **Urdu joined on the wrong key.** Matching Urdu to Arabic by hadith number
  measured 80.5%; the URN both sides already carry measures 99.6% of what exists.
  The number join failed *whole books at once* — kitab 34 of Bukhari lost all 184
  of its Urdu because the source sends `hadithNumber: 0` for every record there.
* **Muslim unjoinable.** Its pack numbers records `0…7563` as a synthetic index
  and carries no `sourceBook`/`sourceHadith`, so both the number and in-book keys
  failed and only 2,960 of 7,482 enriched. Fixed with a unique-only Arabic-text
  fallback: 97.8% for Muslim, 95–99.5% across all seven.
* **Single-page collections produced nothing.** Nawawi 40, Qudsi 40, Hisn
  al-Muslim and Virtues publish their narrations on the landing page rather than
  under `/<slug>/<book>`; the book loop found none.
* **`forty` is not a collection.** `https://sunnah.com/forty` is an index page
  with zero hadith containers. Removed from the collection list.
* **Mojibake in a new field.** Nine Bukhari `chapterTitleEnglish` values carried
  a curly quote encoded UTF-8 and decoded cp1252. The vet reported zero because
  it scanned five hand-listed text fields and not the chapter titles it had just
  added; it now walks every string field recursively.

## 5. Rights — unresolved, and the catalogue currently overstates it

`hadith_books.json` declares:

```
source  : fawazahmed0/hadith-api
license : Unlicense (public domain dedication)
```

That is true of the original seven packs. It is **not** true of the sunnah.com
enrichment layered on top, nor of the nineteen collections built entirely from
sunnah.com. Their `robots.txt` permits crawling (only `/selectiondata/*` is
disallowed) so collection etiquette is not the issue — the issue is the text.
Classical Arabic matn is public domain; the modern English and Urdu translations
are copyrighted derivative works.

The owner has been informed and directed that the work proceed. Recorded here so
whoever ships the build can see it, and so the catalogue's `source`/`license`
fields get corrected to describe what is actually bundled rather than continuing
to claim a public-domain dedication that no longer covers all of it.

## 6. Narrator bios — what is and is not translated

12,643 narrators, each with name, grade, lineage, affiliations, teacher/student
graphs and the source's *jarḥ wa taʿdīl* appraisals.

Narrator identity and grade fields have an Urdu layer, but the scholarly
appraisal prose does not. The current exact appraisal gaps are 72,108 English
and 87,280 Urdu rows. They are now part of the same reviewed translation gate
as Hadith text and kitab titles; see `HADITH_TRANSLATION_GATE.md`.

* `nameUrdu` and `lineageUrdu` re-use the sourced Arabic verbatim — Urdu is
  written in Arabic script, so these need no conversion.
* `gradeUrdu` maps through `Tools/Hadith/grade_glossary_ur.json`, a 207-term
  table covering all 218 distinct grade tokens in the corpus. Grades are a closed
  technical vocabulary, not prose, so this is terminology mapping and every line
  is reviewable individually.
* Arabic appraisals remain the immutable source and are not presented as their
  own English or Urdu translation. The bio sheet renders the Arabic body under
  the scholar's name in the Quran face, right-to-left — visibly the source —
  and adds a translation beneath it only where one has been reviewed. The only
  rows withheld are the 1,250 that carry a scholar label and no body in any
  language; withholding sourced Arabic instead would blank the section for
  every Urdu reader, who reads that script natively, and for 65% of English
  readers, while showing nothing truer in its place.

Tagged `urduSource: arabicSource+glossary`, `urduReviewState: machine_provisional`.
The terminology is accurate but has not been checked by a qualified reviewer;
gate public release on that, per the project's standing rule.

## 7. Summary

| Gap | Size | Closable? |
|---|---|---|
| Urdu overall: 40,209 of 143,294 (28.1%) | ~103,000 narrations | Only by machine translation + review; every open source is exhausted |
| Musnad Ahmad beyond sunnah.com's subset | ~26,000 narrations | **No** open source; ahlesunnatpak carries 13,411 but as a **different edition** — 0 of 13,411 texts match ours (measured), so its Urdu cannot attach and its text would be a single-source new pack needing its own vetting |
| Bukhari 64–65 Urdu residual | ~80 abbreviated repeat-narrations (نحوه) | **No** — genuinely different text on every source checked |
| Mishkat vs canonical | 5,307 of 6,294 (84.3%) | **No** — sunnah.com prints only 5,318 containers; the shortfall is at source. Urdu now 94.8% via ahlesunnatpak |
| Bulugh residual | 39 unnumbered containers (1,557 of 1,596) | Possibly — containers with no printed reference number |
| Advanced collections vs canonical | Bayhaqi 61.8%, Hakim 70.4%, ʿAbd ar-Razzāq 71.7%, Ibn Abi Shayba 80.7% | **No** — capture measured at 100% of what sunnah.com prints; the rest is not digitised there |
| Scholarly review of narrator Urdu | 12,643 narrators (glossary-mapped, `machine_provisional`) | Human review |
| Scholarly review of ahlesunnatpak Urdu fills | 6,453 narrations (Nasa'i 1,423 + Mishkat 5,030) | Human review |
| Catalogue licence accuracy | metadata | Owner decision |

### Final shipped coverage (v1.9.5, measured from the packs)

26 collections, **143,294 narrations** (was 36,221), all four platforms
byte-identical, integrity gate PASS, 0 core canonical IDs lost. Fully recovered
to 100.0% of source: Riyad as-Salihin (+679, its named `introduction` book) and
Darimi (+649, same cause). Ibn Hibban 99.9% (+83), Nasa'i al-Kubra 96.7%,
Hisn al-Muslim restored after the single-page/named-book fix collision.
Urdu: core seven ~93–96%; Mishkat 94.8%; the other new collections 0% (no
source exists — see above).
