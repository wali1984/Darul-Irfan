# Desktop app sign-in: approve a computer from the phone

The Darul Irfan desktop app (Windows, macOS) cannot sign in with Apple or Google
itself. It shows a short code and a QR code. The member opens Darul Irfan on a
phone that is already signed in (Apple, Google or invitation), goes to
Halqah > Account > **Approve a computer** (or scans the QR with the phone's
camera), checks which computer is asking, and approves it. The computer then
holds a member session for **that same account**: same role (member, Halqah
admin, Super admin, Markaz officer), so every member and admin API works from
the desktop.

Server: `Server/src/computerLinks.ts` (routes in `Server/src/index.ts`),
migration `0024_desktop_computer_sign_in.sql`, tests
`Server/test/computer-link.test.ts`. The reporting website's sign-in uses the
same table and code helpers (`client='reporting'`).

All bodies are JSON (`content-type: application/json`). Times are ISO-8601 in
whole seconds, UTC (`2026-11-09T18:30:00Z`). Errors are `{ "error": "<English
text>" }`. Rate limits are per client address, per hour.

## On the computer (no sign-in)

### `POST /v1/members/computer-link`

```json
{ "deviceName": "Ali's laptop", "platform": "windows" }
```

- `deviceName`: required, shown on the phone. Control characters, line breaks
  and bidirectional overrides are removed; whitespace collapsed; at most 60
  characters.
- `platform`: `"windows"` or `"macos"`.

`201`:

```json
{
  "code": "K7Q2-9MXD",
  "pollToken": "<64 hex>",
  "expiresAt": "2026-11-09T18:35:00Z",
  "pollInterval": 3,
  "qr": "darulirfan://approve-computer?code=K7Q2-9MXD"
}
```

Show `code` in large type and render `qr` as a QR code: the phone's camera opens
the app's Approve a computer screen with the code filled in (it is never
approved without the member confirming). Codes are 8 symbols from
`ACDEFGHJKMNPQRSTUVWXYZ2345679` (no 0/O, 1/I/L, 8/B), valid 5 minutes. Keep
`pollToken` secret (memory only).

Errors: `400` (missing name, unknown platform, invalid JSON), `429` (more than
30 codes per hour from one address).

### `POST /v1/members/computer-link/poll`

```json
{ "pollToken": "<64 hex>" }
```

`200`, one of:

```json
{ "status": "pending" }
{ "status": "expired" }
{ "status": "approved", "token": "<64 hex>", "expiresAt": "2026-12-09T18:31:02Z", "memberID": "<32 hex>" }
```

Poll every `pollInterval` seconds until not `pending`. `approved` is returned
**once**; every later poll of the same token answers `expired`. `expired` also
covers an unknown token, a code nobody approved within 5 minutes, and a member
deleted between approving and polling. On `expired`, start again with a new
code.

Errors: `400` (pollToken missing or not 64 lowercase hex), `429` (more than 900
polls per hour from one address).

### Using the session

Send `authorization: Bearer <token>` on every request, exactly as the phone
apps do. A desktop session (`member_sessions.client = 'desktop'`):

- is accepted on every member route (`/v1/members/*`, `/v1/groups/*`,
  `/v1/markaz/*`, `/v1/daily-media/manage`), with the member's own role;
- lasts 30 days from its last use: each use more than 5 minutes after the
  previous one moves `expires_at` to now + 30 days (sliding). The `expiresAt`
  from the poll is the initial value only; treat `401` as signed out;
- cannot approve another computer, nor the reporting website (`403`);
- ends with `POST /v1/members/signout` (the computer signs itself out), with
  `DELETE /v1/members/computers/{id}` or `DELETE /v1/members/computers` from the
  phone, and with `DELETE /v1/members/me` (account deletion removes every
  session). After any of these the token answers `401 {"error":"Member sign-in required"}`.

## On the phone (app session only)

Each requires the phone's own member session. A reporting-website session gets
`401`; a desktop session gets `403 {"error":"Approve from the app on your phone"}`
for `preview` and `approve`.

### `POST /v1/members/computer-link/preview`

`{ "code": "k7q2 9mxd" }` (any case, spaces or dashes) ->
`200 { "deviceName": "Ali's laptop", "platform": "windows", "expiresAt": "..." }`.
Nothing is approved. Shown on the confirm sheet.

### `POST /v1/members/computer-link/approve`

`{ "code": "K7Q2-9MXD" }` -> `200 { "ok": true, "deviceName": "Ali's laptop", "platform": "windows" }`.
Any signed-in member may approve; the code is then closed to every other phone.
Audit-logged (`computer-link`, code masked).

Errors for both: `400` (not 8 symbols of the alphabet), `404` (one message for
wrong, already approved, used and expired codes), `429` (more than 60 tries per
hour, or 20 refused codes per hour, from one address).

### `GET /v1/members/computers`

```json
{ "computers": [
  { "id": "abc123def456", "name": "Ali's laptop", "platform": "windows",
    "createdAt": "...", "lastSeenAt": "...", "expiresAt": "...", "current": false }
] }
```

This member's unexpired desktop sessions, newest first. `id` is the first 12 hex
of the session's hash (names it, cannot sign in with it). `current` is true for
the computer making the request.

### `DELETE /v1/members/computers/{id}` and `DELETE /v1/members/computers`

Sign one computer out (`204`, or `404` when it is not this member's), or all of
this member's computers (`204`). The phone stays signed in.

## Merge note: community consent gate

The uncommitted consent gate (`communitySafety.ts`, `{adult: true, termsVersion}`)
answers `403 {"code":"community_consent_required"}` to non-GET member writes.
The desktop routes sit before the general `/v1/members` block in `index.ts`, so
when that work is merged, add inside the `computer-link/(preview|approve)` branch:

```ts
if (!await hasCommunityConsent(env, session.memberID)) return consentRequired();
```

and add `DELETE /v1/members/computers…` to its `withdrawing` list (signing out
must stay available without consent). The desktop app should send
`"adult": true, "termsVersion": "<current>"` in its `computer-link` body from
the start; the server ignores them today, and `adultEnrollment(request, env, ()
=> startComputerLink(request, env))` can then wrap the start route in one line.
Desktop sessions are the same member, so the gate on community writes applies to
them automatically.
