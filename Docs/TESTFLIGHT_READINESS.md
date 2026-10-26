# iOS TestFlight readiness

State of the iOS app as a release candidate, what has actually been verified
and by what, and what is left before testers can install it. Written
2026-10-26 for build **1.9.7 (43)**.

`Docs/APP_STORE_CHECKLIST.md` remains the line-by-line pre-submission list.
This document is narrower: it answers "can testers have it yet".

## The one thing to understand first

**No iOS build has been compiled on this machine, and none can be.** There is
no Mac and no Xcode here. Every Swift change since the last confirmed-green
Codemagic run is unverified at the compiler level. The only authorities are:

| Pipeline | Trigger | What it proves |
|---|---|---|
| Codemagic `ios-verify` | push to any branch | unsigned build + tests compile |
| GitHub `native-verify` | pull request touching app sources | build + simulator tests |
| Codemagic `ios-testflight` | pushing a `v*` tag | signed release build, uploads to TestFlight |

Codemagic does not report status back to GitHub, so its result must be read in
the Codemagic UI. **Push and read `ios-verify` before tagging.** A tag that
fails to build wastes a build number, because App Store Connect refuses a
repeated `CFBundleVersion`.

## Verified on 2026-10-26

Everything here was run and passed on this machine:

- **Content integrity, release grade** — `check_content.py --require-parity`:
  PASS, 6,236 ayat and 143,294 narrations, review state `testFlightApproved`,
  seed manifest 33, and byte parity enforced across all four platforms.
- **Catalogue validation** — `ingest.py validate --dir content`: passed, 0
  warnings.
- **Ingest tooling** — 65 tests pass.
- **Backend** — 34 tests pass, `tsc --noEmit` clean. The live Worker answers
  `/health` with `ok: true`; its `website` source reported success the same
  day, so the fortnightly catalogue refresh is running.
- **Seed line endings** — all four platforms are LF-only and identical. A
  `.gitattributes` now pins JSON to LF, because a Windows checkout had been
  rewriting the seed with CRLF and silently adding 9.5 MB of carriage returns
  to the iOS bundle.

## Fixed for this build

- **`PrivacyInfo.xcprivacy` added.** It was absent. The app calls
  `UserDefaults` in nine places, which is a required-reason API, so an upload
  without the declaration draws Apple's ITMS-91053 notice and can be rejected.
  Declared: no tracking; Device ID, crash and performance data as
  App Functionality, unlinked and not used for tracking; `CA92.1` for user
  defaults. Location is deliberately **not** declared as collected, because
  prayer and Qibla maths run on the device and coordinates are never sent to
  the service. This mirrors `Docs/PRIVACY.md` exactly — change both together.
- Version moved to **1.9.7 (43)** from 1.9.6 (42), which was already used.

## Blocking testers

1. **[blocker] Apple Developer portal registration.** `project.yml` builds four
   signed bundles: `us.naqshbaniaowaisiah`, `.widgets`, `.watchkitapp` and
   `.watchkitapp.widgets`. All four need identifiers; the app and the iOS
   widget need the App Group `group.us.naqshbaniaowaisiah`; the app needs the
   push capability (`aps-environment: production`). A missing identifier,
   group or capability fails `ios-testflight` at the signing step, not at
   compile, so the failure arrives late. An earlier release shipped with the
   widget and App Group removed precisely to get past this; they are back in
   `project.yml` now, so this must be right before a tag.
2. **[blocker] Written content permission on file.** The owner granted content
   rights verbally on 2026-07-10 and the seed ships
   `rightsStatus: permissionConfirmed`. Keep the written confirmation with the
   release record before any public submission. It does not block internal
   TestFlight.
3. **Beta App Review** applies to *external* testers only, and needs the beta
   description, contact details and the "what to test" notes. Internal testers
   (App Store Connect users on the team) need no review.

## Known content gaps to tell testers about

These are honest gaps, not bugs. Do not let a tester report them as defects.

- **Urdu tafsir is effectively empty.** `asrar-at-tanzil-ur` has 0 rows and
  `akram-ut-tafaseer-ur` covers 1 surah of 114. English is complete: 6,234 of
  6,236 Asrar translations and 640 tafsir blocks across all 114 surahs. For an
  Urdu-first audience this is the most visible hole in the app.
- **Asrar English commentary covers about 80.7%** of the source's sentences.
  Worst surahs: 73, 31, 53 and a cluster near 67%. The repair route is to
  re-run the per-ayah indexer over the clean source. Do **not** attempt
  heuristic span alignment; it silently duplicated commentary across adjacent
  blocks every time it was tried, and was reverted.
- **Two Asrar verses are deliberately blank** — 23:38 and 80:41 — because the
  authoritative source's own English is wrong there. Never guessed at.
- **154 `U+FFFD` in the Arabic of 76 narrations**, inherited from both upstream
  Arabic editions. Inventoried in `known_upstream_defects.json`; the gate fails
  on any replacement character outside that list. Repair needs a second
  authoritative Arabic corpus and is a public-release task.
- **Book text (43 works) is machine OCR**, `machineProvisional`, with 20.3% of
  blocks unresolved and counted per page so the reader marks a page rather than
  hiding it. Quality varies; embedded Arabic quotations are corrupt in places
  and must never be read as Quran or hadith.
- Review state is internal metadata only. It is never rendered as a badge next
  to scripture; provenance lives in Acknowledgements and
  `Docs/CONTENT_INTEGRITY.md`.

## Backend note

`Info.plist` points `OfficialPlatformBaseURL` at the `workers.dev` address,
and that is currently correct: `https://api.naqshbandiaowaisiah.us/health`
answers **403**, so the custom domain is not delegated yet. Swap the key only
once that host returns the health payload, and ship a build afterwards — the
app reads it at launch.

WhatsApp forwarding is configured but inert until the Worker secrets
`WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_APP_SECRET`, `WHATSAPP_ALLOWED_SENDERS` and
`WHATSAPP_CHANNEL_URL` are set, and migration `0002` is applied. Nothing in
the app depends on it.

## Publishing to testers

1. Push `main`. Read `ios-verify` in the Codemagic UI until it is green.
2. Confirm the four identifiers, the App Group and the push capability in the
   developer portal.
3. Apply the D1 migration if the WhatsApp path is wanted:
   `npm run db:migrate:remote` in `Server/`.
4. Tag and push: `git tag v1.9.7 && git push origin v1.9.7`. That is the only
   thing that starts `ios-testflight`.
5. Watch the signing step specifically; it is where a missing portal entry
   surfaces.
6. In App Store Connect, add internal testers, or submit for Beta App Review
   for external ones.

If a tag build fails, fix it and tag `v1.9.7.1` — never reuse a build number.
