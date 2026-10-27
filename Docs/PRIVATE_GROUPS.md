# Private regional groups

Members-only spaces for the silsila: Darul Irfan, United States and Canada.
Administrators publish; members read. Added 2026-10-26.

## What it is, and what it deliberately is not

- **Three isolated groups.** A post belongs to exactly one group. Reading it
  requires a membership row for that group.
- **Announcements and recorded zikr only.** Members cannot post. Nothing a
  member writes is ever shown to another member, which is why Apple's
  user-generated-content obligations (guideline 1.2: filtering, reporting,
  blocking) do not apply to member-to-member content here.
- **Meetings are a link, not a call.** Each group carries an admin-managed join
  URL for whatever the silsila already uses — Paltalk, Zoom, Jitsi. The app
  does not host conferencing, and nothing in this feature runs a media server.
- **Not public.** None of it is reachable from `/v1/feed`, and every route
  below the session exchange requires a member bearer token.

## The two isolation rules

Both are covered by tests in `Server/test/members.test.ts`.

1. **Signing in grants nothing.** A new member belongs to no group until an
   administrator adds them, so an uninvited sign-in sees an empty list. A
   reviewer who signs in will correctly see no groups; that is the expected
   state, not a broken screen.
2. **A group you are not in is indistinguishable from a group that does not
   exist.** Both answer 404 with the same body. One region therefore cannot
   discover that another region's group exists, let alone read it. The group
   catalogue is private too: `/v1/groups` returns only the caller's own.

## How a member joins

**An invitation code, not a platform sign-in.** Sign in with Apple needs the
`com.apple.developer.applesignin` entitlement, and under manual signing the
distribution profile must already carry it, which it cannot until the capability
is enabled on the App ID. That is what failed `ios-testflight` build 47 and kept
the whole feature switched off. A code needs nothing from Apple, behaves
identically on Android, HarmonyOS and the web, and keeps admission an
administrator's decision rather than a platform's.

1. An admin mints a single-use code for one group and gives it to the person.
2. The member opens **More → Private groups**, types the code and taps Join.
3. They are in that group immediately: redeeming *is* admission, because an
   administrator already decided it by issuing the code.

Properties worth preserving:

- **The code is never stored**, only its SHA-256. A leaked database cannot admit
  anyone.
- **Single use**, claimed by a conditional `UPDATE ... WHERE redeemed_at IS NULL`,
  so two simultaneous redemptions cannot both succeed and a forwarded code
  cannot admit a second person.
- **Expires**, 30 days by default.
- **One refusal message** for a wrong, used or expired code, on the server and
  in the app. Anything finer turns the endpoint into an oracle for guessing.
- The alphabet omits characters people confuse `0`/`O`, `1`/`I`/`L`, `8`/`B`,
  because these are read aloud and typed by hand.
- Redeeming is rate limited harder than the session exchange, since it takes a
  secret that could otherwise be guessed.

Sign in with Apple remains implemented and tested. To offer it as well: enable
the capability on the App ID, restore the two commented lines in `project.yml`,
and set `MemberGroupsFeature.appleSignInAvailable` to `true`. Only the name
scope is ever requested, never email.

## Administration

All admin routes sit behind Cloudflare Access and need the editor role, exactly
like the rest of `/admin`. Every write is recorded in the immutable audit log.

| Call | Does |
|---|---|
| `GET /admin/api/groups` | groups and every membership |
| `GET /admin/api/groups/pending` | signed-in members who are in no group yet — the queue to work through |
| `PUT /admin/api/groups/{group}` | set the meeting link, note, active state |
| `PUT /admin/api/groups/{group}/members/{member}` | `{"member": true}` grants, `{"member": false}` revokes |
| `PUT /admin/api/groups/{group}/posts/{post}` | publish or edit a post |
| `POST /admin/api/groups/{group}/invites` | mint a single-use code; returns it **once** |

Publishing a recorded zikr:

```json
PUT /admin/api/groups/usa/posts/zikr-2026-10-26
{ "kind": "zikr", "title": "Friday zikr", "youtubeVideoID": "dQw4w9WgXcQ" }
```

`kind: "zikr"` requires a valid 11-character YouTube id and is refused without
one, so a zikr post can never render as an empty player. An announcement takes
`title`, optional `body` and an optional `linkURL`.

Minting a code, with an optional note for your own records:

```json
POST /admin/api/groups/usa/invites
{ "label": "Br. Imran, Houston", "expiresInDays": 30 }
-> { "ok": true, "groupID": "usa", "code": "KMQ7R-TDVHX", "expiresInDays": 30 }
```

The code appears in that response and nowhere else: not in the audit log, which
records only that one was issued, and not in the database, which holds the hash.
If it is lost before it reaches the member, mint another and let the first
expire.

Revoking membership takes effect on the member's next request; it does not need
their device to cooperate.

## Deploying it

1. Apply the migrations: `npm run db:migrate:remote` in `Server/`. `0003`
   creates the group tables and seeds the three groups; `0004` creates the
   invite store.
2. No secrets are needed for invitations. `APPLE_CLIENT_ID` matters only if
   Sign in with Apple is turned on later, and defaults to `APNS_TOPIC`, which
   is already the bundle id.
3. **Nothing in the Apple Developer portal is required for the invitation
   path.** That is the point of it: the capability that blocked build 47 is not
   on this route at all.

## Privacy consequences

The app now has accounts, which it did not before. Both files were updated and
must change together:

- `PrivacyInfo.xcprivacy` declares **User ID** and **Name** as collected and
  **linked** to identity, for App Functionality, not tracking. These are the
  app's only linked data; everything else stays unlinked.
- `Docs/PRIVACY.md` records the same, and that in-app account deletion is
  mandatory under 5.1.1(v). "Delete my account" is on the groups screen and
  removes the sign-in, the session and every membership in one call.

The member's bearer token lives in the keychain, not user defaults, because it
is a credential; it is device-only and never synced.

## What is not built

- **No member-to-member messaging**, by decision. Adding it would pull in the
  whole moderation obligation: filtering, reporting, blocking, and a contact
  address, all of which must exist in the product before review.
- **No push notification** when a group is posted to. The topics
  (`liveZikr`, `broadcasts`, `announcements`, `events`) are global, so a
  group-scoped push needs per-member addressing rather than a topic. Worth
  doing next if members ask for it.
- **No HarmonyOS, Android or Web client.** The backend is shared and the
  contract is `/v1/groups` and `/v1/groups/{id}/posts`; see
  `Docs/ANDROID_NEXT.md`.
