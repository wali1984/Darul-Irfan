# Hadith CI ingest — how the enriched data is generated automatically

_Internal doc (not shipped). Explains the `hadith-ingest` Codemagic workflow and
the `Tools/Hadith/ingest_sunnah.py` pipeline it runs._

## The split: generate once (CI), bundle everywhere (app builds)

Scraping sunnah.com on every app build would blow Codemagic's build timeout and
hammer the site. So data generation is a **separate, dedicated workflow**; the
normal `ios-verify` / `ios-testflight` builds only bundle the seed that this
workflow already produced. Nothing is scraped at app-build or app-run time.

## How the ingest workflow fires (no command typing needed)

`hadith-ingest` has **no `triggering:` block**, so it never runs on push/PR.
Start it either way:

- **Manual:** Codemagic UI → *Start new build* → pick workflow **hadith-ingest**
  and branch **feat/official-platform** → *Start*.
- **Scheduled:** Codemagic UI → the app → *Builds* schedule → add a cron for the
  **hadith-ingest** workflow (Codemagic schedules are set in the UI, not YAML),
  e.g. monthly.

## What one run does

1. Installs Python deps (`requests`, `beautifulsoup4`, `lxml`) on a Linux VM.
2. Runs `ingest_sunnah.py --all --pack --vet --bump-manifest --translate`,
   which, **keyless and gently** (throttle, on-disk cache, exponential backoff,
   per-chapter fallback for the big books that 500, fully resumable/idempotent):
   - enriches every bundled narration **in place** (matched by `displayNumber`,
     so the lossless sub-numbered keys are preserved) with: Arabic split into
     `isnad` / `matn` / `verse` segments (narratorId on isnad, surah:ayah on
     verse — surah = `openquran` index + 1), flat `quranRefs`, English filled
     from the source where missing, and split Urdu (`urduSanad` / `urduText`)
     plus bab chapter titles (en/ar/ur);
   - builds `hadith_narrators.json`: every narrator referenced by any chain,
     with a full biography in **Arabic-English and Arabic-Urdu** — the Urdu is
     **auto-translated from the existing bio** (English→Urdu, or Arabic→Urdu).
     A narrator is marked missing only if the source has **no** bio in any
     language; an existing bio is never left untranslated and never fabricated.
3. Runs the content-integrity gate (`check_content.py`): counts, unique keys,
   encoding, and cross-platform parity (parity shows "unverified" on CI, where
   only the iOS checkout exists — same as today).
4. **Commits the regenerated seed back** to the branch when `GITHUB_PAT` is set;
   otherwise **publishes it as an artifact** (`hadith_seed.tgz`) and still
   succeeds. The commit message carries `[skip ci]` so it does not loop.

## One-time Codemagic setup (UI)

Create a secure variable group named **`hadith_ingest`** with:

| Variable | Purpose | If omitted |
|---|---|---|
| `GITHUB_PAT` | fine-grained PAT, *contents: write* on `wali1984/Darul-Irfan` | seed is published as an artifact instead of committed |
| `DI_TRANSLATE_URL` | OpenAI-compatible chat completions endpoint | Urdu bios kept pending (`needsUrdu`), never fabricated |
| `DI_TRANSLATE_KEY` | API key for the above | — |
| `DI_TRANSLATE_MODEL` | model id (default `gpt-4o-mini`) | uses the default |

## Cross-platform parity

Only the iOS repo is on CI, so the workflow writes and commits the **iOS** seed.
Byte-identical parity across iOS/Android/Harmony/Web is produced by running the
same packer where all four checkouts live (the ingester writes to every seed dir
it finds), and the integrity gate enforces parity there. On CI, parity is
reported as unverified rather than failing the run.

## Bundle size / download-deferral

If the full corpus + bios exceeds a comfortable bundle size, ship the core
collections in-app and structure the rest for the existing `DownloadManager`
(the packer emits per-collection files, so this is a packaging switch, not a
data change). This is a documented decision point — nothing is silently dropped.

## Local/dev run (optional, same tool)

```
pip install requests beautifulsoup4 lxml
python Tools/Hadith/ingest_sunnah.py --all --pack --vet --bump-manifest --translate \
    --cache-dir .hadith_cache --throttle 1.2
python Tools/ContentIntegrity/check_content.py
```
Run it where all four platform checkouts sit to sync every platform at once.
