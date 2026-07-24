# Official platform operations

## Ownership and environments

- Production API: `https://api.naqshbandiaowaisiah.org`.
- Cloudflare Worker/D1 deployment source: `Server/`.
- Admin routes must be protected by Cloudflare Access before DNS is enabled.
- Maintain separate Cloudflare Worker/D1 instances and APNs sandbox/production
  credentials for staging and production.
- Never place Facebook, YouTube, APNs, or Cloudflare credentials in Git,
  Codemagic YAML, seed JSON, app configuration, or screenshots.

## Required secrets

Configure with `wrangler secret put`: `YOUTUBE_API_KEY`,
`FACEBOOK_PAGE_ACCESS_TOKEN`, `APNS_KEY_ID`, `APNS_TEAM_ID`, and the PKCS#8
`APNS_PRIVATE_KEY`. Also configure comma-separated `ADMIN_EDITOR_EMAILS` and
`ADMIN_BROADCASTER_EMAILS`; staff writes deny access when these role lists are
missing. Rotate social tokens immediately when an administrator
loses Page/channel access. Rotate the APNs key according to the organization’s
credential policy and after any suspected exposure.

## Publishing workflow

1. Sign in through Cloudflare Access.
2. Create or edit a schedule/announcement as a draft.
3. Verify Urdu/English spelling, source URL, Pakistan timezone, expiry, and
   religious text against the official source.
4. Publish/feature the item. Feed changes never send a push automatically.
5. For a push, use the confirmed push action with a unique stable event ID.
   D1 prevents delivery of the same event ID twice to one installation.
6. Review `audit_log` after urgent or manual live-state changes.

Automatic YouTube live detection runs every five minutes. Facebook and other
feed refreshes run every fifteen minutes. Selecting “manual override” in the
live editor prevents the YouTube poller from replacing an urgent staff update.

## Health and incident response

Alert on Worker exceptions, five consecutive cron failures, YouTube quota or
authentication errors, Facebook authorization errors, APNs 403 responses,
and a live record older than fifteen minutes while marked live. APNs 410
responses automatically remove invalid tokens.

During an outage the app shows its last-known-good feed/live state with an
updated timestamp. Prayer calculations, local alerts, Quran, downloaded
content, and cached schedules remain available. If social authorization
cannot be restored promptly, retain official external links and publish live
state manually; never substitute an unofficial account.

Diagnostics expire after 30 days. Run or verify the expiry query during each
monthly operational review. D1 backups and audit logs must follow the
organization’s access and retention policy.

## Release checklist

- Apply all D1 migrations in staging and production.
- Run `npm ci && npm run check && npm test` in `Server/`.
- Verify `/health`, `/v1/bootstrap`, `/v1/feed`, and `/v1/live` with no auth.
- Verify `/admin` is inaccessible without Cloudflare Access.
- Test one APNs sandbox registration, opt-out deletion, and deduplicated push.
- Verify YouTube foreground playback, Paltalk handoff, and owned-stream
  background playback independently.
- Record credential owners and expiry/review dates outside the repository.
