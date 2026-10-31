# Darul Irfan serverless platform

Cloudflare Worker + D1 control plane for the official iOS and Android apps. It
serves cached, versioned read APIs; aggregates only the organization-owned
YouTube and Facebook accounts; stores opt-in APNs (iPhone) and FCM (Android)
registrations; and exposes an Access-protected editor surface. No precise
location, prayer history, bookmarks, or reading data is accepted by these APIs.

## Provisioning

1. Create a Cloudflare D1 database and replace the placeholder `database_id` in
   `wrangler.toml`.
2. Apply `migrations/0001_initial.sql` with `npm run db:migrate:remote`.
3. Configure Cloudflare Access for `/admin*`, allowing only approved staff.
4. Store `YOUTUBE_API_KEY`, `FACEBOOK_PAGE_ACCESS_TOKEN`, `APNS_KEY_ID`,
   `APNS_TEAM_ID`, and the PKCS#8 `APNS_PRIVATE_KEY` with `wrangler secret put`.
   Set comma-separated `ADMIN_EDITOR_EMAILS` and `ADMIN_BROADCASTER_EMAILS` as
   encrypted secrets as well. Mutating staff APIs deny access when the matching
   role list is absent; only broadcasters can send confirmed pushes.
5. Bind `api.naqshbandiaowaisiah.org` as a Worker custom domain and update the
   iOS `OfficialPlatformConfiguration` only if a different host is chosen.
6. Run `npm test`, `npm run check`, then `npm run deploy`.

Missing or expired social credentials mark the corresponding source degraded
in `/health`; failures never replace the last-known-good feed.

## Android: real-time alerts (FCM) and Google sign-in

Android phones get the same alerts as iPhones - Halqah notices, the Daily Zikr
live alerts and the official alerts - through Firebase Cloud Messaging
(HTTP v1, called directly with a service account; no Firebase SDK on the
server), and members, admins and super admins sign in on Android with Google.
Nothing changes for iOS: every existing request body and response shape is as
before, and an alert going only to iPhones is sent exactly as it was.

### Secrets and variables

| Name | Kind | Value |
|---|---|---|
| `FCM_PROJECT_ID` | secret | The Firebase project id (`project_id` in the service account key file). |
| `FCM_CLIENT_EMAIL` | secret | The service account's `client_email`. |
| `FCM_PRIVATE_KEY` | secret | The service account's `private_key`, a PKCS#8 PEM. Paste it as it is in the JSON file; its literal `\n` line breaks are accepted. |
| `GOOGLE_CLIENT_IDS` | var (public) | Comma-separated OAuth client IDs a Google ID token may be issued to (its `aud`): the **Web** client ID the Android app asks Google for tokens with. |

- Until all three `FCM_*` values are set, Android phones are skipped (logged,
  never an error) and iPhones are sent as before.
- Until `GOOGLE_CLIENT_IDS` is set, a Google sign-in answers 503; Sign in with
  Apple is unaffected.
- `SUPER_ADMIN_EMAILS` applies to the Google account's verified email exactly
  as it does to Apple's.
- Keep `GOOGLE_CLIENT_IDS` in `wrangler.toml` `[vars]` (or set it as a secret):
  a plain variable set only in the dashboard is dropped by the next deploy.

### Migration `0015_android_push_google.sql`

- `devices.platform`: `'ios'` (the default for every existing row) or
  `'android'`. An Android phone's FCM registration token is kept in
  `apns_token`, exactly as sent (FCM tokens are case-sensitive).
- `members.google_subject` (unique when set) and `members.google_email`.

It only adds columns, and the Worker in production keeps working on the
migrated schema. **Apply it before deploying this code** (the new code writes
`devices.platform`; deployed first, device registration would fail).

### Request contracts

`POST /v1/devices` - the iPhone body is unchanged. An Android phone sends:

```json
{
  "platform": "android",
  "installationID": "<a random UUID, kept by the app>",
  "token": "<the FCM registration token>",
  "locale": "en",
  "timeZone": "Asia/Karachi",
  "topics": ["liveZikr", "broadcasts", "announcements", "events"],
  "appVersion": "1.0.0",
  "keepTopics": false
}
```

`201 {"ok":true}`, or `400 {"error":"Invalid registration"}`. `topics` are the
official topics the phone wants (unknown ones are dropped); `keepTopics: true`
registers the phone for Halqah notices only and keeps the official topics it
already has, as on iOS. `environment` may be left out (FCM has no sandbox).
Register again whenever FCM issues a new token (`onNewToken`).

`DELETE /v1/devices/{installationID}` with header `x-push-token: <FCM token>`
(exact) - `204`; the iPhone's `x-apns-token` works as before.

`POST /v1/members/devices` `{"installationID": "..."}` with the member's bearer
token - unchanged; links the registered phone to the member's Halqah notices.
`DELETE /v1/members/devices/{installationID}` and `POST /v1/members/signout`
`{"installationID": "..."}` unlink it, as on iOS.

`POST /v1/members/session` - the Apple body (no `provider`, or `"apple"`) is
unchanged. Google:

```json
{ "provider": "google", "idToken": "<Google ID token>", "name": "<optional display name>" }
```

| Status | Body |
|---|---|
| 201 | `{"token":"<64 hex>","expiresAt":"<ISO 8601>","memberID":"<32 hex>"}` - the Apple session's shape |
| 400 | `{"error":"Unknown sign-in provider"}` |
| 401 | `{"error":"Google identity could not be verified"}` - signature, issuer, audience or expiry |
| 401 | `{"error":"The Google account's email address is not verified"}` |
| 503 | `{"error":"Google sign-in is not configured on this server"}` - `GOOGLE_CLIENT_IDS` unset |
| 503 | `{"error":"Google sign-in is unavailable right now. Try again shortly."}` - Google's keys unreadable |
| 429 | `{"error":"Too many requests"}` - shared with Apple, 20 an hour per address |

The token is verified as RS256 against Google's JWKS
(`https://www.googleapis.com/oauth2/v3/certs`, kept as its Cache-Control says);
`iss` must be `accounts.google.com` or `https://accounts.google.com`, `aud` one
of `GOOGLE_CLIENT_IDS`, `exp` in the future and `email_verified` true. The
member is the one this Google account (`sub`) signed in as before; failing
that, the member who already has the same verified email and no Google account
yet (someone who signed in with Apple) - the accounts are linked; failing
that, a new member, who like an Apple one belongs to no Halqah until admitted.
Halqahs an admin added the email to are claimed as for Apple. A name is only
given where none is known (`name`, else the Google profile name).

### What an Android phone is sent

```json
{
  "message": {
    "token": "<FCM token>",
    "notification": { "title": "Daily Zikr has started", "body": "Join the official daily zikr in Darul Irfan." },
    "android": {
      "priority": "high",
      "ttl": "1800s",
      "collapse_key": "live-zikr",
      "notification": { "channel_id": "daily_zikr_live", "sound": "default", "tag": "live-zikr" }
    },
    "data": { "path": "darulirfan://live/official-live", "eventID": "youtube-live:<video>", "topic": "liveZikr" }
  }
}
```

`ttl`, `collapse_key` and `tag` are only on live alerts (`live-zikr`, and
`live-cue` for the host's cues), where the iPhone gets `apns-expiration` and
`apns-collapse-id`. The channel is a fixed contract with the Android app:

| `channel_id` | Topics |
|---|---|
| `halqah_notifications` | `group:<halqah id>` - posts, Halqah zikr, meetings, notices |
| `daily_zikr_live` | `liveZikr` - Daily Zikr and Tahajjud zikr started, the host's cues; and `live-alerts` |
| `official_alerts` | every other official topic: `broadcasts`, `announcements`, `events` |

A token FCM answers `UNREGISTERED`, or `INVALID_ARGUMENT` naming the
registration token, is forgotten (its `devices` row deleted), as APNs 410 is.
Other failures keep the phone and are recorded; `fcm` in `/admin/api/health`
is FCM's state. A refused access token (401) is renewed for the next alert.

### Owner setup

1. **Firebase project.** In the Firebase console add a project (or add Firebase
   to an existing Google Cloud project), then add an Android app with package
   `org.naqshbandiaowaisiah.darulirfan` (and
   `org.naqshbandiaowaisiah.darulirfan.debug` for debug builds). Its
   `google-services.json` goes to the Android build. Check that "Firebase
   Cloud Messaging API (V1)" is enabled (Project settings -> Cloud Messaging).
2. **Service account key.** Project settings -> Service accounts -> Generate
   new private key. Keep the JSON file outside git, like the other credentials.
3. **Worker secrets**, from that file:
   `npx wrangler secret put FCM_PROJECT_ID` (`project_id`),
   `npx wrangler secret put FCM_CLIENT_EMAIL` (`client_email`),
   `npx wrangler secret put FCM_PRIVATE_KEY` (`private_key`, as it is).
4. **Google sign-in.** In Google Cloud console -> APIs & Services (the same
   project): configure the OAuth consent screen; create an OAuth client of type
   **Web application** - its client ID is what the Android app passes as its
   server client ID, and what goes in `GOOGLE_CLIENT_IDS`; and create
   **Android** OAuth clients for the package names above with the SHA-1 of each
   signing certificate (upload key, Play app signing key, debug key). Set
   `GOOGLE_CLIENT_IDS = "<web client id>.apps.googleusercontent.com"` in
   `wrangler.toml` `[vars]`.
5. If a super admin's Google account uses an email that is not in
   `SUPER_ADMIN_EMAILS`, add it there.
6. Back up D1, apply the migration with `npm run db:migrate:remote`, then
   `npm test`, `npm run check` and `npm run deploy`.

## Apple Weather on Today

Both native clients use `GET /v1/weather/current?lat=<city>&lon=<city>`.
Coordinates are rounded on the phone to a 0.1-degree city grid and normalized
again by the Worker. Successful readings are cached for ten minutes at the
edge; cache misses are limited per client. The response contains temperature,
feels-like temperature, humidity, timestamps, and Apple attribution. It never
contains the developer token or signing key. Missing access, invalid readings,
and provider failures return an unavailable response; the clients hide the
weather rather than substitute a reading. Location settings can turn it off.

The required Worker secrets are `WEATHERKIT_TEAM_ID`, `WEATHERKIT_KEY_ID`,
`WEATHERKIT_SERVICE_ID`, and `WEATHERKIT_PRIVATE_KEY`. Keep the `.p8` outside git.
The owner has a local credential note with `Key ID:`, `Issuer ID:` (the
10-character Apple Team ID), `Service ID:`, and `Path` (the key directory or
file). A key's `Services: WeatherKit` capability is separate from its registered
Services ID. Register that ID through Apple's developer account:
[Apple's WeatherKit setup](https://developer.apple.com/help/account/capabilities/create-a-services-identifier-and-private-key-for-weatherkit).

From the repository root, `python Tools/Release/weatherkit.py --credentials
<local-note>` tests a real signed request. Add `--configure` after it succeeds
to set the four Worker secrets using Wrangler's stdin; no key is printed.
`--service-id <registered-id>` can supply the ID without editing the note.
Then deploy the checked Worker with `npm run deploy` from `Server`.

The apps bundle Apple's unmodified white Weather mark obtained from its
public attribution endpoint, and link to Apple's weather-data attribution.
No WeatherKit private key or developer token belongs in a native binary.
