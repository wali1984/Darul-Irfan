# Public and reporting websites

`src/index.js` serves `oursheikh`, `namerica`, `uk`, `app-demo`, and `reporting` on the two domains in `wrangler.toml`. `CLOSED_DOMAINS` deliberately keeps the official-domain routes unavailable until the owner opens them. Do not remove that guard as an error fix.

The platform API owns whether a Zikr session is live. The SFU feed describes its audio transport only. A transport event must never create a public live session or keep an ended session open. SFU sockets are opened only after a visitor joins. `live-audio.js` owns negotiation deadlines, cancellation, reconnection, and media cleanup. It forwards the optional per-session `sessionToken` as `x-live-session` after receiver creation.

Reporting requests use a secure HttpOnly cookie and the platform checks authorization on every request. A failed upstream revocation still clears the browser cookie; the response distinguishes whether the server session was revoked. Religious content remains in the existing JSON sources, unchanged.

The showcase labels live automation as a supervised preview. Its Get started section uses the verified public TestFlight invitation, describes Android access as internal invitation-only, and links to web listening and private admin reports. The separate R2 interactive showcase is a historical presentation artifact; its screenshots are not evidence that a feature or build has shipped. Public pages expose canonical/social metadata and a share action with a selectable-link fallback.

The reporting API hardening is in `Server/src/markaz.ts`: spreadsheet exports neutralize formula-like text, honor session kind, and validate export type and dates. Computer approval exchange enforces the original code expiry both before and during its atomic claim. The corresponding SQLite-backed route checks are in `Server/test/markaz.test.ts`.

## Local regression checks

From the parent iOS worktree, with its existing Server dependencies installed:

```powershell
node --test Sites/tests/routes.test.mjs Sites/tests/live-audio.test.mjs
```

The tests bundle source into a temporary test fixture. They neither produce a release artifact nor contact production APIs. They cover domain closure, platform outage semantics, script CSP hashes, canonical metadata, role routing, reporting authorization/signout, expired auth approvals, playback cancellation, source replacement, scoped SFU credentials, and missing-track recovery.

The browser check uses an existing Playwright installation and optionally an existing axe-core installation:

```powershell
$env:DARUL_PLAYWRIGHT_MODULE = 'C:/path/to/playwright/index.mjs'
$env:DARUL_BROWSER_CHANNEL = 'chrome'
$env:DARUL_AXE_SOURCE = 'C:/path/to/axe-core/axe.min.js'
$env:DARUL_SITES_EVIDENCE = 'C:/path/to/audit-evidence'
node Sites/tests/browser-check.mjs
```

All visitor joins and reporting operations in this check use local fixtures. It covers mobile navigation, keyboard joining/cancellation, private-mode identity, live-dialog exit, Urdu tabs, reporting retry and dark-mode contrast, mobile admin navigation, and content without JavaScript. It writes screenshots and `browser-checks.json`. Real iOS Safari audio, Android audio, restricted networks/TURN, source outage recovery, and audience capacity require separate runtime validation; passing these fixtures does not certify them.
