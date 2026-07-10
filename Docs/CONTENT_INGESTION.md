# Content ingestion

How content travels from naqshbandiaowaisiah.org into the app, and how to
update it safely. The authoritative tool-level reference (every flag, the
curation rules, output file formats) is `Tools/ContentIngest/README.md`; this
document is the maintainer's overview and workflow.

## Pipeline architecture

```
naqshbandiaowaisiah.org
        │  polite HTTP crawl (robots-checked, rate-limited, fixture-tested)
        ▼
Tools/ContentIngest  (Python: ingest.py + parsers.py + schema.py)
        │  structured JSON — exact camelCase keys, ISO-8601 dates,
        │  Swift enum rawValues (a wire contract with the Codable models)
        ▼
   output/ folder
        ├──► curated subset copied into DarulIrfanApp/Resources/SeedData/
        │       imported idempotently at launch by ContentSyncService
        │       (guarded by the seed.version row), then FTS-indexed
        └──► future: hosted as-is at a static endpoint; the app polls
                https://www.naqshbandiaowaisiah.org/app/content_manifest.json
                and upserts changed media_items / events payloads
```

Two hard rules follow from this design:

- **The app never scrapes HTML at runtime.** All parsing happens on the
  maintainer's machine, tested against saved fixtures.
- **JSON shape is a contract.** `Tools/ContentIngest/schema.py`
  (`SCHEMA_VERSION = 1`) and the Swift models in `DarulIrfanApp/Models/`
  must agree exactly: camelCase keys, ISO-8601 dates without fractional
  seconds (`JSONDecoder` uses `.iso8601`), and enum rawValues.

## Rights gating

The website's content is copyright reserved. **The owner granted content
permission on 2026-07-10** (owner confirmation — keep the written record on
file), so the `--rights-confirmed` precondition is satisfied and the normal
posture for site content is now `permissionConfirmed`. The pipeline still
enforces the rights model mechanically:

| `rightsStatus` | Meaning | How it is produced |
|---|---|---|
| `permissionConfirmed` | Full body text may ship | Via `crawl --full-text --rights-confirmed` — the standard mode since the 2026-07-10 grant. First run: 2026-07-10 (seed manifest v2) |
| `publicDomain` | Freely shippable | Hand-curated seed only (Quran Arabic, Pickthall translation, surah index, 99 Names, Quranic duas) |
| `linkOnly` | Metadata + source URL only — **no body text** | The pre-grant default; no longer used for newly crawled site content, but the gate below still applies to any item carrying it |

`--full-text` without `--rights-confirmed` is refused. `validate` fails any
`linkOnly` item that carries `bodyHtml`/`bodyPlainText`, so a rights
violation cannot pass CI-style checks. The app still renders any `linkOnly`
item as metadata plus a "Read on naqshbandiaowaisiah.org" link. Even with
permission granted, book/magazine/tafsir PDFs and lecture MP3s stay as
**remote URLs on the site** — the app downloads/streams them natively but
never bulk re-hosts or bundles them. Religious text is copied verbatim or
not at all — the pipeline never paraphrases or summarizes.

## How to run

```sh
cd Tools/ContentIngest
python -m venv .venv && source .venv/bin/activate   # optional
pip install -r requirements.txt                      # requests + beautifulsoup4

# Crawl with full text — the standard mode since the owner's permission
# grant of 2026-07-10 (sections and years to taste)
python ingest.py crawl \
    --sections about,lectures,books,magazines,articles,tafsir \
    --years 2024-2026 \
    --full-text --rights-confirmed \
    --out output \
    --rate-limit 1.5 \
    --max-pages 200

# Check every output file against the schema (exit 0 = clean)
python ingest.py validate --dir output

# Compare against a previous run; exit 3 flags curated-field conflicts
python ingest.py diff --previous output_prev --current output_new --merged-out merged

# Offline test suite
pip install pytest
python -m pytest tests -q
```

Before crawling the live site, replace the placeholder contact address in the
tool's User-Agent (see `Tools/ContentIngest/README.md`). Editors can hand-fix
any output item and mark it `"curated": true`; crawls and merges then preserve
those fields and report upstream conflicts instead of overwriting them.

## Schema versioning policy

There are four version numbers; know which one you are bumping:

| Version | Lives in | Bump when |
|---|---|---|
| Wire schema (`SCHEMA_VERSION = 1`) | `Tools/ContentIngest/schema.py` + Swift `Models/` | A **breaking** shape change: key rename, type change, new required field. Requires a coordinated change to the Swift Codable models in the same release. Purely **additive optional fields need no bump** — the Swift decoder ignores unknown keys and tolerates missing optionals. |
| Seed content version | `Resources/SeedData/manifest.json` → `"version"` (integer) | Any time bundled seed content changes. `ContentSyncService` re-imports when the installed `seed.version` row is lower. Forgetting this bump means existing installs never see the new seed data. |
| Database schema (`AppDatabase.schemaVersion = 1`) | `Core/Persistence/AppDatabase.swift` | A wire-schema change that needs new/changed columns. Add a migration script; never edit `migrationV1` retroactively. |
| Remote manifest version | Served `content_manifest.json` → `version` (integer) | Every published content update. The app applies a manifest only when its `version` exceeds the stored `remote.manifest.version`. |

Keep the wire schema stable and versioned; the seed and remote versions are
cheap monotonic counters you bump routinely.

## Updating the bundled seed data, step by step

The seed bundle is a **curated subset** of pipeline output plus
hand-maintained files. Since the 2026-07-10 full-text ingest (seed manifest
v2) it carries the full library/media catalog — 291 library items and 199
media items, ~0.8 MB — but it is still text/metadata only: PDFs and MP3s are
never bundled; they stay remote URLs on the site.

1. **Crawl and validate** into a fresh folder (commands above).
2. **Diff against the previous output**; resolve any `CONFLICT` lines (exit
   code 3) by deciding whether the site's change or the curated value wins.
3. **Curate the subset** into `DarulIrfanApp/Resources/SeedData/`:
   - `articles.json` + `documents.json` items → `library_items.json`
   - `media.json` items → `media_items.json`
   - `events.json` → `events.json`; announcements → `announcements.json`
   - `quran_tafsir_manifest.json` informs `quran_editions.json` /
     `quran_tafsir.json` (per-surah pointer rows — rights are granted, but
     the site's tafsir pages carry no HTML text and the PDF booklets are
     image scans with no text layer; no OCR, religious text must be verbatim)

   Copy items verbatim — same keys, same ISO-8601 dates. These files are
   decoded by `Core/Persistence/SeedBundle.swift` with a plain `JSONDecoder`;
   a malformed file decodes to an empty array (logged, not crashing), which
   silently drops that content, so validate before shipping.
4. **Hand-maintained files** are *not* pipeline outputs — edit them directly
   and only with verified sources (`Docs/RESEARCH_NOTES.md`):
   `quran_surahs.json`, `quran_ayahs.json`, `quran_translations.json`,
   `names_of_allah.json`, `duas.json`, `islamic_days.json`,
   `zikr_sessions.json`, `darul_irfan_place.json`.
5. **Bump `manifest.json`**: increment `"version"`, refresh `"generatedAt"`.
6. **Sanity-check on macOS**: regenerate the project if files were added
   (XcodeGen picks up the folder), build, launch — `ContentSyncService`
   re-imports the seed and rebuilds the FTS index off the critical launch
   path. Confirm the new items appear and are searchable.

## Verified URL patterns (from Docs/RESEARCH_NOTES.md)

robots.txt is fully permissive; all pages are static server-rendered HTML.

| Content | Pattern | Notes |
|---|---|---|
| Lecture year archive | `/lectures/{YYYY}` | Years 1976–2026 |
| Lecture detail page | `/lecture/{ID}/{YYYY-MM-DD}-{slug}.html` | Hosts the YouTube embed |
| Lecture MP3 | `/uploads/{LECTURE_ID}/{DD-MM-YYYY}.mp3` | **Filenames are irregular** (e.g. `06-02-2026%20s.mp3`) — always harvest actual `href`s, never construct URLs |
| Lecture WMA | same rows | Excluded — iOS cannot play WMA |
| Magazine archive pages | `/almurshid-magazine-{Y1}-to-{Y2}.html` | 5-year pages; 1981–2015 populated, 2016–2020 placeholder |
| Magazine PDF | `/uploads/almurshid-magazines/almurshid_{month(s)}_{year}.pdf` | e.g. `almurshid_february_march_1981.pdf` |
| Books index | `/books-on-tasawwuf.html` | Reached from `/download` |
| Book PDF | `/uploads/books/{Title-Slug-Language}.pdf` | e.g. `Dalael-us-Salook-Urdu.pdf` |
| Tafsir (Asrar-at-Tanzil) | `/asrar-at-tanzil/{ID}/tafseer-quran-in-english-surah-{name}.html` | 114 static pages, IDs from 1229. **No HTML tafsir text** — the pages only link to per-surah PDF booklets, which are image scans with no text layer (verified 2026-07-10) |
| About pages | `/hazrat-ameer-abdul-qadeer-awan.html`, `/hazrat-ameer-muhammad-akram-awan-ra.html`, `/silsila-naqshbandia-owaisiah.html`, `/shajra-silsila-naqshbandia-owaisiah.html` | |
| Method of Zikr | `/method-of-zikr.html` | Instructions are **images** (English JPG + Urdu PNG) — shipped as image URLs in `mediaUrls` plus the verbatim on-page caption; not OCR'd (religious text must be verbatim) |

Item IDs are slugs of the item's most specific source URL path, so re-runs
are stable; each item's `checksum` (sha256 of normalized fields) lets the
app's sync detect changes cheaply.
