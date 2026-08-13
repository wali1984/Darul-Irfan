# Hadith translation and appraisal release gate

Measured 2026-08-13 from the bundled seed corpus:

| Content | English missing | Urdu missing |
|---|---:|---:|
| Hadith narrations | 94,864 | 103,342 |
| Kitab titles | 325 | 909 |
| Narrator scholarly appraisals with source text | 70,858 | 86,030 |

The corpus contains 143,294 narrations and 87,280 appraisal-shaped rows. Of
those, 1,250 legacy rows contain a citation/label but no appraisal body in any
language; they are quarantined and never translated or rendered. These numbers
are release invariants, not estimates. A translation is never made visible by
falling back to Arabic or another target language.

## Workflow

`Tools/Hadith/translation_gate.py` is the only approved path for filling these
gaps.

1. `audit` recomputes exact missing counts from the seed files and reports
   source-less appraisal artifacts separately.
2. `export` writes a stable JSONL queue. Every item includes its native id,
   context, source language, source text, and SHA-256 source hash.
3. `translate` can create a resumable first pass through an OpenAI-compatible
   translation endpoint. Its output is always `machineProvisional`.
4. A reviewer corrects each row and marks it `humanVerified`, adding their name
   and an ISO-8601 review timestamp.
5. `validate` checks identifiers, completeness, source hashes, script, controls,
   markup, placeholders, duplicates, and review metadata.
6. `promote` refuses the entire batch unless every required item passes. It
   fills blank translations only and proves that no Arabic Hadith source text
   changed.

The app publishes an appraisal only when its body exists in the active app
language. Existing sourced English rows remain available. It does not expose
Arabic-only appraisals in the English or Urdu interface while review is
incomplete.

Example:

```powershell
python Tools/Hadith/translation_gate.py audit
python Tools/Hadith/translation_gate.py export --output C:\HadithReview\queue.jsonl
python Tools/Hadith/translation_gate.py validate `
  --responses C:\HadithReview\reviewed.jsonl
python Tools/Hadith/translation_gate.py promote `
  --responses C:\HadithReview\reviewed.jsonl
```

Machine translation can accelerate drafting, but automated structural checks
cannot certify the meaning of sacred text. Promotion therefore requires an
explicit human verification record. Until that review file is complete, the
existing Arabic and sourced translations remain unchanged in the app.
