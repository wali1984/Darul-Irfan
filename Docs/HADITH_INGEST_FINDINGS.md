# Hadith ingest — verified findings

Empirical notes from a full Bukhari run of `Tools/Hadith/ingest_sunnah.py`
(7,277 records) plus targeted probing of the source endpoints. Everything below
was measured, not inferred. Where it contradicts a comment or docstring in the
tool, the measurement is what happened.

Written for whoever continues the hadith work; the ingest output itself was left
in a scratch directory and **nothing was written into any app seed**.

---

## 1. The Urdu join key is wrong — 80.4% where 99.6% is available

`build_collection` indexes Urdu by hadith *number*:

```python
urdu_index[str(h.get("hadithNumber"))] = h      # <- fails silently on some books
```

Measured coverage of that join: **5,856 / 7,277 = 80.4%**.

Both sides already carry a stable URN. The Arabic container is
`<div class="actualHadithContainer" id="h119620">`; the matching Urdu record is
`{"matchingArabicURN": 119620, ...}`. Strip the leading `h` and they are equal.

Measured coverage of the URN join, over every cached book: **6,265 / 6,290 =
99.6%**.

```python
# index by URN instead
urdu_index[str(h.get("matchingArabicURN"))] = h
# ...and look up by the container's own id
urn = cont.get("id", "")[1:]          # "h119620" -> "119620"
u = urdu_index.get(urn, {})
```

**Why the number join fails so badly.** It does not degrade gracefully — on some
books it misses *everything*. In kitab 34 all 183 Urdu records carry
`hadithNumber: 0` (broken upstream) and `ourHadithNumber` is a within-book
sequence (1, 2, 3 …), not the global number. Result: 184 of 184 hadith lost
their Urdu. Same failure in kitab 30 (61) and 37 (25).

Worth roughly **+430 recovered Urdu translations** for a one-line change.

## 2. The per-chapter Urdu fallback cannot be built — the endpoint does not exist

`build_collection` carries this:

```python
# TODO(operator): per-chapter fetch /ajax/urdu/<slug>/<bk>/<chapter>
```

That route is not real. Probed directly:

| Request | Result |
|---|---|
| `/ajax/urdu/bukhari/64` | 500 (consistently, not transient) |
| `/ajax/urdu/bukhari/64/1`, `/2`, `/3` | **404** |
| `/ajax/urdu/bukhari/64/` and `?page=1` | 500 |
| `/urdu/bukhari/64` | 404 |
| `/ajax/urdu/bukhari/64.1`, `/0064` | 200 but **zero bytes** |
| `/ajax/urdu/bukhari/63` (control) | 200 |

Books **64 and 65 return 500 at the book level on every variant**, so their Urdu
is unobtainable from this source: **987 hadith with no Urdu, permanently**.

Record this as a source limitation in the ingest report and let the reader show
its existing "no Urdu translation" state. Do not paper over it — and per the
project's standing rule, never back-fill from another language.

## 3. `grade` and `babName` are empty at source, not lost in transit

Bukhari's Urdu ajax sends `grade: ""` and `babName: null` (real JSON null — the
tool's `or None` handles it correctly; no literal `"None"` string leaks through).
Measured: `grade_ur` 0%, `babName_ur` 0%.

So there is nothing to fix here, and nothing to promise either — a claim that
grades come through the Urdu endpoint is wrong for this collection.

`bookName` **does** carry the Urdu kitab title (e.g. `کتاب وحی کے بیان میں`) and
is currently ignored. That is the one usable Urdu structural field on offer.

## 4. Identifier normalisation is inconsistent and rewrites the printed form

```python
return m.group(1).replace("b", ".2") if m else None   # 402b -> 402.2
```

Two problems, both measured in the output:

* Only `b` is handled. 25 numbers were rewritten to `.2`; `1390c` survived
  untouched and is the sole malformed identifier in 7,277 records.
* It rewrites the source's own printed label. `HadithEntry` documents
  `displayNumber` as "the number exactly as the source prints it" — sunnah.com
  prints `402b`, not `402.2`. Worse, `.2` already means something *different* in
  the bundled fawazahmed0 corpus, so the two schemes collide on the same key.

Suggested shape: keep `displayNumber` verbatim (`"402b"`), and derive the sort
fields separately — `numberMajor = 402`, `numberMinor = 2` from `b → 2`,
`c → 3` — so ordering still works without falsifying the printed identifier.
Reading order should continue to come from `sourceSequence`.

## 5. What the run got right

Worth stating plainly, because the parsing core is sound:

* **Zero data loss.** Every reference number printed across all 97 cached book
  pages was compared against the captured set: 7,252 printed, 7,252 captured,
  **0 dropped**.
* **Zero duplicate identifiers**, so the collision that once lost 86 hadith to an
  integer key does not recur.
* Arabic, typed segments and English at **100%** (7,277 each); **659** records
  carry Quran verse refs.
* Segment typing works: a sample container yields `{matn: 8, isnad: 6, verse: 1}`.
* `openquran(95,1,3)` decodes to **al-Alaq 96:1-3** — the 0-based surah offset is
  handled correctly.
* The 311 numbers absent from 1–7563 are **never printed on the pages at all** —
  a property of the source's merged numbering, not a parser drop.

## 6. Narrator bios are not implemented

`parse_narrator` is defined, returns a placeholder (`"en": {"present": True}`),
and is **never called** from anywhere. No `hadith_narrators.json` is produced, so
the reader's tappable narrator names currently open nothing.

`SEED_DIRS` is likewise defined and never used — output stops at
`hadith_build_out/` and reaches no app.

The page structure is straightforward; selectors mapped from a live sample so
this needs no further exploration:

| Data | Selector |
|---|---|
| Names | first `h1` (English), second `h1` (Arabic) |
| Labelled fields | `<div><span class="label">Kunya</span><span class="field">Abu al-Yman</span></div>` — sibling spans |
| Field labels | EN: `Kunya`, `Generation`, `Narrator Lineage`, `Cities/Regions`, `Affiliations` · AR: `الكنية`, `الطبقة`, `الاسم الكامل`, `بلد الإقامة`, `النسب والنسبة` |
| Appraisals (*jarḥ wa taʿdīl*) | `.verdict-scholar` paired with `.critic-quote` |
| Teachers / Students | under the `h4` headings, via `a[href*="/narrator/"]` |
| Collections | `.chip` |
| Hadith count | `h3`, e.g. "702 Hadith Narrated" |

A sampled page was 88 KB with 8 appraisals and 165 name rows, so the data is
rich enough to fill the bio sheet.

## 7. Rights — unresolved, flagged for the owner

The bundled catalogue currently declares:

```
source  : fawazahmed0/hadith-api
license : Unlicense (public domain dedication)
```

sunnah.com's `robots.txt` permits crawling (only `/selectiondata/*` disallowed,
no crawl-delay), so collection etiquette is not the issue. The issue is the text:
the classical Arabic matn is public domain, but the **English and Urdu
translations are modern derivative works under copyright** (Darussalam-family
editions). Shipping them silently voids the license line above.

The owner has been told and has directed that the work proceed. Recording it here
so the decision is visible to whoever ships the build, and so the catalogue's
`license`/`source` fields get updated to match whatever is actually bundled
rather than continuing to claim a public-domain dedication that no longer applies.

The lowest-risk option, if it is ever revisited: take **structure** from
sunnah.com (narrator IDs, isnad spans, the 659 verse refs) and keep **text** from
the Unlicense corpus. Today's run shows the structural data extracts cleanly on
its own.

---

*Two agents were briefly fetching sunnah.com concurrently during this
investigation. Coordinate before running another crawl.*
