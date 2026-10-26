# iOS TestFlight readiness

State of the iOS app as a release candidate, what has actually been verified
and by what, and what is left before testers can install it. Written
2026-10-26 for build **1.10.1 (45)**.

## Why 1.10.0 did not ship

`ios-testflight` build 47 failed at **Build signed archive**, exit 65, after 12
seconds. Everything before it passed: release preflight, the unit tests
including the schema migration (4m16s), the content integrity gate, and code
signing setup.

Twelve seconds is far too fast for a compile failure, and `ios-verify` had
already built the same tree. The cause is the entitlement added for the private
groups: with `CODE_SIGN_STYLE=Manual` the distribution profile must already
carry every entitlement in the target, and it cannot carry
`com.apple.developer.applesignin` until Sign in with Apple is enabled on the
App ID in the developer portal. **`ios-verify` can never catch this**, because
an unsigned build needs no profile at all.

1.10.1 removes that entitlement and holds the groups screen behind
`MemberGroupsFeature.isEnabled`, so the release builds and everything else is
testable. The groups code and its backend are untouched and tested. To turn it
on: enable the capability on the App ID, restore the two commented lines in
`project.yml`, and set the flag to `true` - all three together.

`Docs/APP_STORE_CHECKLIST.md` remains the line-by-line pre-submission list.
This document is narrower: it answers "can testers have it yet".

## The one thing to understand first

**GitHub Actions is dead on this account: "the job was not started because
your account is locked due to a billing issue."** That one fact explains three
separate things that looked like code failures:

- `iOS native verification` never ran on 2026-10-02 — it was never started.
- `Content validation` never ran either.
- **The fortnightly content sync has not run since 2026-09-15.** The 10-01 and
  10-15 schedules both fired and were refused for billing. It is not a broken
  crawler; nothing started. Settle the GitHub billing and it resumes.

**Codemagic is unaffected, and the iOS app is in good shape.** On commit
`e1ee654` (2026-10-02) both Codemagic workflows reported success to GitHub:

| Check | Result on `e1ee654` |
|---|---|
| `iOS verify (build + unit tests, unsigned)` | **success** |
| `iOS TestFlight release (signed)` | **success** |
| `verify` (GitHub `native-verify`) | failure — billing, never started |

So the app compiles, its unit tests pass, and it signs and uploads a release
build. Codemagic *does* post status back to GitHub as check runs, contrary to
an earlier note in this project's history.

`e1ee654` is an ancestor of `main`, and `7a67ef5` was then verified green by
`ios-verify` directly (build 26, 2026-10-26: Build Succeeded, unit and UI tests
passed, content gate clean).

**1.10.0 does add new Swift** — the private regional groups: four new files,
plus the Sign in with Apple entitlement and the privacy manifest. That has not
been through `ios-verify` yet, so run it on `main` before tagging. Everything
else in the build is already verified.

| Pipeline | Trigger | What it proves |
|---|---|---|
| Codemagic `ios-verify` | push to any branch | unsigned build + tests compile |
| Codemagic `ios-testflight` | pushing a `v*` tag | signed release build, uploads to TestFlight |
| GitHub `native-verify` | pull request touching app sources | blocked by billing |

**Push and read `ios-verify` before tagging.** A tag that fails to build wastes
a build number, because App Store Connect refuses a repeated
`CFBundleVersion`.

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

1. ~~**[blocker] Apple Developer portal registration.**~~ **Already proven.**
   `project.yml` builds four signed bundles: `us.naqshbaniaowaisiah`,
   `.widgets`, `.watchkitapp` and `.watchkitapp.widgets`, needing all four
   identifiers, the App Group `group.us.naqshbaniaowaisiah` on the app and the
   iOS widget, and the push capability. `ios-testflight` is the workflow that
   signs all of them, and it **succeeded** on `e1ee654` — which it could not
   have done with a missing identifier, group or capability. The portal is
   therefore in order, and the earlier release that dropped the widget and App
   Group to get past signing is history. Nothing to do here unless the
   identifiers change.
2. **[blocker] Written content permission on file.** The owner granted content
   rights verbally on 2026-07-10 and the seed ships
   `rightsStatus: permissionConfirmed`. Keep the written confirmation with the
   release record before any public submission. It does not block internal
   TestFlight.
3. **Beta App Review** applies to *external* testers only, and needs the beta
   description, contact details and the "what to test" notes. Internal testers
   (App Store Connect users on the team) need no review.
4. **GitHub billing.** Not a blocker for shipping the app, since Codemagic
   builds it, but it keeps the fortnightly content refresh dead and removes the
   second opinion `native-verify` used to give. Content in the app is bundled,
   so testers are unaffected; the catalogue simply stops getting fresher.
5. **[blocker for 1.10.0] Enable Sign in with Apple on the App ID.** The
   private groups identify members through it and the entitlement is in
   `project.yml`, but a capability missing from the developer portal fails
   *signing*, not compiling — so it surfaces late, in `ios-testflight`, after
   `ios-verify` has already passed. Turn it on before tagging.
6. **Apply migration `0003`** (`npm run db:migrate:remote` in `Server/`) or the
   groups screen will error for every member. See `Docs/PRIVATE_GROUPS.md`.
7. **The Codemagic webhook is not delivering.** Builds must be started by hand
   from the Codemagic UI; a pushed tag will not start `ios-testflight` on its
   own. Builds themselves are fine — build 26 ran green when started manually.

## Known content gaps to tell testers about

These are honest gaps, not bugs. Do not let a tester report them as defects.

- **Urdu tafsir now ships as readable text, not as per-ayah tafsir.** Both
  Urdu works were ingested on 2026-10-26 from the owner's OCR drops as
  page-structured library text: Asrar-at-Tanzil Urdu, all 114 surahs, 2,415
  pages; and Akram-ut-Tafaseer, 30 parahs, 7,838 pages — 10,253 pages and
  34.3 MB in total. They open through the library's "Read the text" reader on
  every platform.

  What they are **not** is per-ayah commentary in the Quran reader's Asrar tab,
  which stays English-only. The OCR pipeline's own `verse_refs` are 8%
  populated for Asrar and 2% for Akram, and the populated ones are wrong: the
  Surah-100 document's first page claims verse 88:8, Surah-102 claims 1:3, and
  Akram's Para 10 — which covers roughly 8:41 to 9:93 — claims 2:244. All of
  them were matched against OCR'd Arabic that is itself corrupted. Attaching a
  guessed verse number to scripture commentary is worse than not offering it,
  so `quran_tafsir.json` was left alone. The per-ayah editions
  `asrar-at-tanzil-ur` and `akram-ut-tafaseer-ur` therefore still read 0 and 1
  rows, and that is deliberate.
- **Akram-ut-Tafaseer parah 30 is part 1 only.** The drop contains
  `QuranTafseer-Para-30-part1` and no part 2 exists anywhere in it; the source
  PDF is itself named that way. Its 232 pages are genuine and ship, but the
  juz is incomplete.
- **English Asrar is complete**: 6,234 of 6,236 translations and 640 tafsir
  blocks across all 114 surahs.
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
