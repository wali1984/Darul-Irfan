# ContentIngest — Darul Irfan content pipeline

A small Python tool that turns pages of
[naqshbandiaowaisiah.org](https://www.naqshbandiaowaisiah.org/) into the
structured JSON the Darul Irfan iOS app consumes. It runs on the
maintainer's machine only — the app never scrapes HTML at runtime.

The output JSON shapes are a wire contract with the app's Swift Codable
models (`DarulIrfanApp/Models/*.swift`, schema v1): exact camelCase keys,
ISO-8601 dates without fractional seconds, and Swift enum rawValues.

## Requirements

- Python 3.11+
- `pip install -r requirements.txt` (requests + beautifulsoup4; everything
  else is standard library)

## Commands

### crawl

```
python ingest.py crawl \
    --sections about,lectures,books,magazines,articles,tafsir \
    --years 2024-2026 \
    --out output \
    --rate-limit 1.5 \
    --max-pages 200
```

| Flag | Default | Meaning |
|---|---|---|
| `--sections` | all six | Which site sections to fetch. Sections you omit leave their existing output files untouched. |
| `--years` | `2024-2026` | Lecture year archives to fetch (`2026`, `2020,2023`, or a range). |
| `--full-text` | off | Ingest article/about body text. **Requires `--rights-confirmed`.** |
| `--rights-confirmed` | off | Affirms the content owner has confirmed permission for full-text use. |
| `--out` | `output` | Output directory. |
| `--rate-limit` | `1.5` | Seconds slept between HTTP requests. |
| `--max-pages` | `200` | Per-run request cap; the crawl stops politely when it is reached. |
| `--base-url` | the live site | Override for testing against a mirror. |
| `--prune` | off | Remove non-curated items that vanished from the site. Default keeps them, so a partial crawl never silently deletes data. |

The crawler checks `robots.txt` at startup (the site is fully permissive,
but this is verified at runtime), identifies itself as
`DarulIrfanContentIngest/1.0 (+mailto:contact-email-placeholder@example.org)`
(replace the placeholder address with a real maintainer contact before
running against the live site), and retries failed requests with
exponential backoff.

MP3 URLs are always harvested from the actual `href` attributes — lecture
filenames on the site are irregular (e.g. `06-02-2026%20s.mp3`) and must
never be constructed. `.wma` links are excluded with a counted warning
because iOS cannot play WMA.

### validate

```
python ingest.py validate --dir output
```

Checks every output file against the schema: required fields, enum
rawValues, ISO-8601 dates, unique IDs, checksum integrity, no body text on
`linkOnly` items, no `.wma` stream URLs, and manifest counts. Exit code 0
on success, 1 on errors.

### diff

```
python ingest.py diff --previous output_prev --current output_new [--merged-out merged]
```

Reports items added/removed/changed between two output folders and flags
**curated-field conflicts**. With `--merged-out` it writes a merged copy
in which curated fields win. Exit code 3 signals conflicts that need a
human decision.

## Curation workflow (never silently overwritten)

Editors may hand-tune any item in the output JSON (fix a title, add an
author, correct a category). To protect those edits, add
`"curated": true` to the item. From then on:

- a fresh `crawl` into the same `--out` folder, and `diff --merged-out`,
  preserve every curated field;
- only URL fields (`sourceUrl`, `streamUrl`, `downloadUrl`,
  `transcriptUrl`, `mediaUrls`, `downloadUrls`) and the `checksum` are
  refreshed from the site;
- any upstream change to a preserved field is reported as a `CONFLICT`
  (exit code 3) so a human can decide;
- curated items that disappear from the site are kept, with a note.

Prefer overriding a field's value to deleting the field: a deleted field
would be re-added from the next crawl. The `curated` key is ignored by
the app's decoder, so curated files can ship as-is.

## Output files

| File | Contents | Mirrors Swift model |
|---|---|---|
| `content_manifest.json` | `version`, `generatedAt`, `counts`, `files` | — (pipeline index) |
| `articles.json` | About pages + articles | `ContentItem` |
| `documents.json` | Books + Al-Murshid magazine issues (PDF links) | `ContentItem` |
| `media.json` | Audio lectures per year archive | `MediaItem` |
| `events.json` | Community events — **hand-curated**, validated by this tool (the site has no machine-readable events feed) | `CommunityEvent` |
| `quran_tafsir_manifest.json` | The Asrar-at-Tanzil edition + its 114 surah page URLs | `QuranEdition` + page list |

Item IDs are slugs of the item's most specific source URL path (lecture
detail page, book/magazine PDF, article page), so re-runs are stable.
`checksum` is a sha256 over the item's normalized fields (excluding
`checksum` and `curated`), letting the app's sync detect changes cheaply.
Re-running an unchanged crawl produces byte-identical files; only the
manifest's `generatedAt` moves.

## Rights policy

The website's content is copyright reserved. Until the owner confirms
permission:

- every ingested item carries `rightsStatus: "linkOnly"` — metadata plus
  the source URL only, **no body text**;
- the app shows such items with a "Read on naqshbandiaowaisiah.org" link
  and streams public MP3 URLs natively (no bulk re-hosting);
- `--full-text` alone is refused; passing `--full-text --rights-confirmed`
  (only after written permission) ingests body text and marks items
  `rightsStatus: "permissionConfirmed"`.

Religious content is never paraphrased or summarized by this tool —
parsers copy text verbatim or not at all.

## How outputs feed the app

1. **Bundled seed data**: curate a small, representative subset of the
   outputs into `DarulIrfanApp/Resources/SeedData/` — `articles.json` +
   `documents.json` items go into `library_items.json`, `media.json` items
   into `media_items.json`, `events.json` into `events.json`. The app's
   `ContentSyncService` imports them idempotently (guarded by
   `seed.version`), decoding with `JSONDecoder` + `.iso8601` — which is
   why the shapes here must match the Swift models exactly.
2. **Remote manifest (future)**: the same files, hosted at a static
   endpoint. The app will fetch `content_manifest.json`, compare
   `generatedAt`/`counts`, and pull only the changed files; per-item
   `checksum` makes row-level upserts cheap.
3. **`quran_tafsir_manifest.json`** feeds the Quran tab's tafsir edition
   list (`QuranEdition`) and its per-surah "Read on the website" links
   until full-text permission is confirmed.

## Tests

```
pip install -r requirements.txt pytest
python -m pytest tests -q
```

Tests run entirely offline against saved HTML fixtures in
`tests/fixtures/` (authored to match entries verified in
`Docs/RESEARCH_NOTES.md`, including the irregular `%20` MP3 filename).
They cover exact parser outputs, WMA exclusion, idempotent re-runs,
curated-merge behavior, and output validation.
