# Darul Irfan 1.5 implementation handoff

## Included in this release candidate

- Native official-update cards and detail views; polling and provenance URLs stay internal.
- Embedded YouTube playback for catalog videos and live broadcasts.
- Native Method of Zikr presentation using the verified content record.
- Native library images, PDF reading, downloads, and availability placeholders.
- No official-content handoff buttons in search, Quran, library, media, events, Zikr, About, or acknowledgements.
- Today prioritizes the next prayer and today's times before secondary content.
- Explore exposes Updates, Library, Media, and Events as equal destinations.
- Bundled seed content finishes importing before content screens query SQLite.
- Remote feed/live feature flags are honored.
- Official push topics default off and require versioned, explicit consent.
- Feed timestamps, ranking, and cursor pagination are stable across Worker refreshes.

All translation, tafseer, audio, video, and future-content placeholders remain in place.

## Build version

- Marketing version: `1.5.0`
- Local project build number: `12`
- Codemagic signed archives override the build number with `BUILD_NUMBER`.

## Codemagic gates

Run `ios-verify` first. It generates the project, enforces the native-content policy, builds all app/Widget/Watch targets, runs Swift unit tests, UI tests, Worker checks, and ingestion tests.

After it passes, run `ios-testflight` from a release tag. That workflow repeats the policy/Worker/ingestion preflight, fetches signing profiles, archives all targets, and uploads an internal TestFlight build.

## Intentionally external actions

- Paltalk opens the `OURSHEIKH` room because Paltalk has no dependable public embedded-player API.
- Phone, email, directions, iOS Settings, and open-source/legal attribution links remain system actions.

## External activation still required

- Deploy the updated Worker before testing feed order in TestFlight.
- Register/fix App Group, Widget, Watch app, and Watch complication identifiers and profiles if they are not already active in the Apple Developer account.
- Keep the current proof-of-concept Worker domain until the organization-controlled domain and credentials are available.
- Add official YouTube, Facebook Page, and APNs credentials only as encrypted server/Codemagic secrets; never add them to the repository or app bundle.
- Complete physical iPhone/iPad/Watch, internal TestFlight, accessibility, content-owner, and organization authorization reviews.
