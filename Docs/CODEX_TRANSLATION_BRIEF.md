# Brief: producing the Urdu and English translations

For an agent with full access to this repository. Read this before writing any
code or touching any seed file.

The job is 190,360 queue records — 356,328 language units:

| Kind | English missing | Urdu missing |
|---|---:|---:|
| Hadith narrations | 94,864 | 103,342 |
| Narrator appraisals (*jarḥ wa taʿdīl*) | 70,858 | 86,030 |
| Kitab (book) titles | 325 | 909 |

Confirm these yourself before starting — they are recomputed from the seed, not
stored:

```
python Tools/Hadith/translation_gate.py audit
```

---

## 1. The one rule that matters most

**This is sacred text.** The Arabic is the immutable source: the words of the
Prophet ﷺ, the chains that carry them, and the verdicts of the scholars who
graded their narrators. A wrong translation here is not a cosmetic bug — it
misreports revelation and misreports a scholar's ruling on a man's
trustworthiness.

Therefore:

* **Never modify Arabic source text.** Not to normalise it, not to fix what
  looks like a typo, not to strip a diacritic. The gate hash-binds every source
  string and will reject a response whose `sourceHash` no longer matches.
* **Never invent.** If a source string is empty, malformed, or unintelligible,
  leave it out of your responses. A missing translation renders as an honest
  "no translation" note in every reader on all four platforms. A fabricated one
  is indistinguishable from scholarship until someone is misled by it.
* **Never paraphrase or summarise.** Translate what is there. Do not add
  explanation, do not smooth over difficulty, do not resolve an ambiguity the
  Arabic leaves open.
* **Never issue a ruling.** Some appraisals are technical verdicts. Render the
  verdict; do not adjudicate between scholars who disagree.

`CLAUDE.md` states these as non-negotiable principles for this repository. They
bind you.

## 2. The gate is the only path

`Tools/Hadith/translation_gate.py` is the sole approved route. Do not write
directly to any file under `DarulIrfanApp/Resources/SeedData/`. Do not write a
parallel script. The gate exists because it enforces invariants that are easy
to break silently and expensive to discover later.

```
# 1. Export the work queue (does not touch the seed)
python Tools/Hadith/translation_gate.py export --output build/queue.jsonl

# 2. First pass, if an OpenAI-compatible endpoint is configured
DI_TRANSLATE_URL=... DI_TRANSLATE_KEY=... DI_TRANSLATE_MODEL=... \
python Tools/Hadith/translation_gate.py translate \
    --queue build/queue.jsonl --output build/responses.jsonl --limit 500

# 3. Check without promoting; --allow-partial while the set is incomplete
python Tools/Hadith/translation_gate.py validate \
    --responses build/responses.jsonl --allow-partial

# 4. Write into the seed. Refuses unless every row is complete and approved
python Tools/Hadith/translation_gate.py promote --responses build/responses.jsonl
```

Each queue item carries `kind` (`hadith` | `section` | `appraisal`), `id`,
`sourceLang`, `sourceText`, `sourceHash`, and `needs` (the languages wanted).
Your response must echo `kind`, `id` and `sourceHash` exactly, and supply
`textEnglish` and/or `textUrdu` per `needs`.

`validate` rejects a row that: mismatches the identifier, carries a stale
`sourceHash`, repeats the source verbatim, contains U+FFFD, control characters,
HTML, or placeholder words (`todo`, `tbd`, `missing`, …), gives English with no
Latin script, or gives Urdu with no Arabic-script text. Fix the input rather
than working around the check.

## 3. Translation standards

**Register.** Reverent and plain. This is read in devotion, not in a journal.
Prefer the plain word over the ornate one, and never the chatty one.

**Terminology is fixed, not creative.** Use the forms this app already ships —
they are consistent across the Quran translations and the narrator glossary:

* Honorifics spelled out, never abbreviated: `(Sall Allah-o Alaihi wa Sallam)`
  for the Prophet ﷺ, `(Alaihi as-Salam)` / `(Alaihim as-Salam)` for prophets,
  `(Radi Allah-o Anhu / Anhum)` for companions. Never `-SAW`, `-AS`, `-RA`.
* Grade vocabulary follows `Tools/Hadith/grade_glossary_ur.json` (207 terms).
  `ثقہ` is *thiqa*/trustworthy, `صدوق` *sadūq*/truthful, `ضعیف` *ḍaʿīf*/weak,
  `متروک الحدیث` abandoned in hadith. Do not coin a synonym where the table has
  a term.
* Keep `Allah`, `salah`, `zakat`, `Ansar`, `Muhajirun` and the like as they
  are; do not translate them into English abstractions.

**Isnad.** Render the chain as a chain — "A narrated to us, from B, from C,
who said…" — rather than collapsing it into prose. The chain is evidence, and
its shape is part of the content.

**Urdu specifics.** Natural Urdu, not transliterated English and not Arabic
passed through unchanged. Names of narrators keep their Arabic-script form.
Right-to-left punctuation conventions (`۔` for the full stop, `،` for the
comma). The renderer uses Nastaliq, so write for that.

**Appraisals.** These are short, technical, and quotational — "ثقة ثبت" is
"trustworthy, firm", not a sentence about a man being reliable. Keep them
terse. Attribute nothing the Arabic does not attribute.

**Where the source is English and the need is Urdu** (many appraisals), the
English is itself a translation of a lost or unquoted Arabic original. Translate
it faithfully; do not attempt to reconstruct Arabic from it.

## 4. Scale and mechanics

190,360 records is too large for one pass. Work in resumable batches:

* `--limit` bounds a run. Keep batches at a few hundred and append to the same
  responses file; the gate keys on `(kind, id)` and reports duplicates.
* Group by `kind` and by collection. Finish `section` (1,234 units) first — it
  is small, high-visibility, and every reader shows those headers.
* Then `appraisal`, which is short-form and terminology-driven.
* Then `hadith`, the bulk, ordered by collection so a completed collection can
  ship while the rest is still in progress.
* Re-run `audit` between batches. The number must fall by exactly what you
  promoted; if it does not, stop and find out why before continuing.

After any promotion, all of these must pass — they are release invariants, not
suggestions:

```
python Tools/ContentIntegrity/check_content.py         # must print PASS
python Tools/Hadith/translation_gate.py audit          # counts fell as expected
```

and the seed must remain **byte-identical across all four platforms**:
`DarulIrfanApp/Resources/SeedData/`,
`DarulIrfanAndroid/app/src/main/assets/seed/`,
`DarulIrfanHarmony/entry/src/main/resources/rawfile/seed/`,
`DarulIrfanWeb/content/`. `promote` handles this; verify it by hashing rather
than assuming. Bump `manifest.json`'s `version` so installed apps re-import.

Do not commit `build/queue.jsonl` or the responses file — they are working
artifacts, and the responses file will be large.

## 5. The attestation problem — read before promoting anything

`promote` refuses any row not marked `reviewState: "humanVerified"` with a
non-empty `reviewer` and `reviewedAt`. That is deliberate, and it is the whole
point of the gate.

**Do not stamp `humanVerified` on your own machine output.** Those fields are a
factual claim recorded permanently in the shipped data: that a named human read
this translation of sacred text and vouched for it. An agent writing its own
name there makes the record false and defeats the only safeguard standing
between a machine draft and a reader who will treat it as scholarship. It also
silently converts a documented gap into an undocumented error — the worst
outcome available, because nobody downstream can tell which rows to re-check.

You have three honest options. **Ask the repository owner which one applies
before promoting a single row:**

1. **Human review.** Produce drafts, hand them to a qualified reviewer, and
   promote only what comes back approved with that reviewer's name. Correct,
   and slow at this scale.
2. **Ship as machine-translated, labelled.** Extend the gate with a distinct
   `machineTranslated` review state that promotes into fields carrying explicit
   provenance — the pattern already used for the ahlesunnatpak Urdu fills
   (`urduSource`, `urduReviewState: machine_provisional`), which the readers
   surface and which gates public release while allowing TestFlight. This is
   honest and it unblocks the content. It requires the owner's decision, a
   reader-visible label, and a corresponding note in
   `Docs/HADITH_TRANSLATION_GATE.md`.
3. **Do not promote.** Leave the drafts staged. Every reader already shows a
   plain "no translation" note, on all four platforms, and that is not a defect.

Option 2 is the likely intent, but it is the owner's call, not yours, and it
needs the label built before the data lands — not after.

## 6. What "done" looks like

* `audit` shows the intended counts at zero, or reduced by exactly what was
  promoted, with the remainder explained.
* `check_content.py` prints PASS.
* Seed byte-identical across four platforms; manifest bumped.
* Every promoted row carries truthful provenance — whoever or whatever produced
  it is identifiable from the data alone.
* `Docs/HADITH_TRANSLATION_GATE.md` and `Docs/HADITH_COVERAGE_GAPS.md` updated
  so the numbers there match reality.
* Nothing in `DarulIrfanApp/Resources/SeedData/` changed except through
  `promote`.

If you find yourself editing a seed file directly, disabling a validation
check, or writing a script that bypasses the gate, stop: the gate is what makes
this reversible and auditable, and those three moves are exactly how sacred
text gets silently corrupted.
