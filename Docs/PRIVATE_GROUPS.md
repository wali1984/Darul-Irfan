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

1. The member opens **More → Private groups** and signs in with Apple.
2. They see "Waiting to be added" and a member identifier, with a copy button.
   That identifier exists so they can send it to an administrator — it is the
   only thing an admin needs.
3. The admin adds them to a group (below). On next refresh the group appears.

Only the **name** scope is requested from Apple, never email: a group needs to
know who you are to an administrator, not how to contact you.

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

Publishing a recorded zikr:

```json
PUT /admin/api/groups/usa/posts/zikr-2026-10-26
{ "kind": "zikr", "title": "Friday zikr", "youtubeVideoID": "dQw4w9WgXcQ" }
```

`kind: "zikr"` requires a valid 11-character YouTube id and is refused without
one, so a zikr post can never render as an empty player. An announcement takes
`title`, optional `body` and an optional `linkURL`.

Revoking membership takes effect on the member's next request; it does not need
their device to cooperate.

## Deploying it

1. Apply the migration: `npm run db:migrate:remote` in `Server/`. Migration
   `0003` creates the tables and seeds the three groups.
2. No new secrets are needed. The Apple audience defaults to `APNS_TOPIC`,
   which is already the bundle id; set `APPLE_CLIENT_ID` only if that ever
   stops being true.
3. **Enable Sign in with Apple on the App ID in the developer portal.** The
   entitlement is in `project.yml`, but a capability missing from the portal
   fails signing while the build still compiles — so it surfaces late, in
   `ios-testflight`, not in `ios-verify`.

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
