# Hadith corpus — exact gaps

What the bundled hadith corpus does and does not contain, why each gap exists,
and what would actually close it. Every figure here was measured, not estimated;
where something is unverified it says so.

Companion to `HADITH_INGEST_FINDINGS.md`, which covers the ingester's mechanics.

---

## 1. Urdu — the largest gap, and it is a sourcing problem

**Seven collections have Urdu. Nineteen do not, and no open source supplies it.**

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

### What would close it

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
| Riyad as-Salihin | 1,217 → re-running | 1,896 | 64.2% → expected 100% | see §4, fixed |
| Mishkat al-Masabih | 5,306 | 6,294 | 84.3% | 11 lost to duplicate display numbers, 1 with no number; remainder undiagnosed |

The remaining collections were still crawling when this was written; their
figures belong in the vetting report the run emits.

**Malik's Urdu is 1,614 of 1,868 (86.4%) and Nasa'i's 3,874 of 5,683 (68.2%)** —
these predate the Arabic-text join fix and should improve; the re-run's numbers
supersede them.

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

6,641 narrators, each with name, grade, lineage, affiliations, teacher/student
graphs and the source's *jarḥ wa taʿdīl* appraisals.

**Urdu coverage is 100%**, and none of it is machine-translated prose:

* `nameUrdu` and `lineageUrdu` re-use the sourced Arabic verbatim — Urdu is
  written in Arabic script, so these need no conversion.
* `gradeUrdu` maps through `Tools/Hadith/grade_glossary_ur.json`, a 207-term
  table covering all 218 distinct grade tokens in the corpus. Grades are a closed
  technical vocabulary, not prose, so this is terminology mapping and every line
  is reviewable individually.
* Appraisals stay in their sourced Arabic and are not counted as a gap.

Tagged `urduSource: arabicSource+glossary`, `urduReviewState: machine_provisional`.
The terminology is accurate but has not been checked by a qualified reviewer;
gate public release on that, per the project's standing rule.

## 7. Summary

| Gap | Size | Closable? |
|---|---|---|
| Urdu for 19 collections | ~25,000–40,000 narrations | Only by machine translation + review |
| Musnad Ahmad chapters 8–30 | ~27,600 narrations | **No** — absent from every open source |
| Bukhari books 64–65 Urdu | 987 narrations | **No** — source returns 500 |
| Mishkat completeness | ~988 narrations | Undiagnosed; 12 explained |
| Scholarly review of grade Urdu | 6,641 narrators | Human review |
| Catalogue licence accuracy | metadata | Owner decision |
