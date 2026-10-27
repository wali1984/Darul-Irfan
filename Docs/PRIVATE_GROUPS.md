# Private regional groups

## Phase 1 community features (2026-10-27)

- **Roles.** `member` reads and joins; `admin` also posts, approves drafts and
  runs zikr and meetings in its own groups; `superadmin` does so in every
  group. Granted by an invitation code minted with a role (admin page), or set
  with `PUT /admin/api/members/{id}/role`. A second code redeemed while signed
  in adds to the same account.
- **Feeds into groups.** Messages forwarded to the WhatsApp Business number
  (+1 929 240 5561) from an allowed sender become drafts in a group: a
  `#usa` / `#canada` / `#darulirfan` tag at the start decides, otherwise the
  sender's mapped group (`PUT /admin/api/whatsapp/senders/{number}`), otherwise
  the public feed's drafts as before. **Pictures** (with or without a caption)
  are fetched from Meta, kept in R2 and shown by signed, expiring link; text
  works as before. Admins approve drafts in the app or on the admin page. Any
  public feed item can be sent into a group:
  `POST /admin/api/groups/{group}/share/{feedItemID}`.
- **Community zikr.** Each group keeps its own zikr times (clock time in the
  admin's zone, or after Isha / Tahajjud at Dar-ul-Irfan), shown in each
  member's own time with reminders. An admin starts it live from the app: a
  live video, a room to join together, or both.
- **Meetings.** In-app audio/video rooms (Cloudflare RealtimeKit), scheduled
  ahead; members can join from ten minutes before.
- **Notifications** go to that group's members only (`member_devices`).

### Setup (once, in `Server/`)

1. `npx wrangler login`
2. `npx wrangler r2 bucket create darul-irfan-media`
3. Secrets (`npx wrangler secret put NAME`): `MEDIA_URL_SECRET` (any long
   random string); `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_APP_SECRET`,
   `WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_ALLOWED_SENDERS` (the admins' own
   numbers, comma separated), `WHATSAPP_CHANNEL_URL`; for meetings
   `REALTIME_ACCOUNT_ID`, `REALTIME_APP_ID`, `REALTIME_API_TOKEN`.
4. In the RealtimeKit app, create presets `group_call_host` (moderator) and
   `group_call_participant` (joins muted).
5. `npm run db:migrate:remote`, then `npm run deploy`.
6. Cloudflare Access: allow wajidali1984@hotmail.com on the `/admin`
   application (`SUPER_ADMIN_EMAILS` grants every staff role once Access lets
   the address through).
7. Meta: point the WhatsApp Business number's webhook at
   `https://<worker>/v1/whatsapp` with the verify token, subscribed to
   `messages`.
8. On the admin page, mint a code with role **Super admin** and redeem it in
   the app.

---


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
