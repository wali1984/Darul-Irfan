# Darul Irfan serverless platform

Cloudflare Worker + D1 control plane for the official iOS app. It serves cached,
versioned read APIs; aggregates only the organization-owned YouTube and Facebook
accounts; stores opt-in APNs registrations; and exposes an Access-protected
editor surface. No precise location, prayer history, bookmarks, or reading data
is accepted by these APIs.

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
