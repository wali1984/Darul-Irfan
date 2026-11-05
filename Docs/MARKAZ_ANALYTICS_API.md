# Silsila Markaz: reports, analytics and organisation (API + screens)

Owner request 2026-11-05. One contract for the server (`Server/src/markaz.ts`), the iOS and
Android apps (built together, identical behaviour), and reporting.naqshbandiaowaisiah.us.

## Who may see it

- **Super admins** (SUPER_ADMIN_EMAILS) and the **Administrators and Admins of the Silsila
  Markaz group** (`silsila-markaz`) are "Markaz officers": they see every report.
- Everyone else gets 403 `{"error":"Markaz access required"}`.
- The Silsila Markaz is a normal group (`kind: "markaz"`): posts, meetings, rooms and live
  sessions work as in any Halqah. Super admins add people to it as for any Halqah. "Bring in
  Halqah admins" adds every Halqah Administrator and Admin to it as a **member** (so global
  admin meetings and notices reach them); members of the Markaz do not see reports.
- Test sessions (`is_test`) are never counted anywhere.

All routes need the member bearer token (`Authorization: Bearer <64 hex>`), JSON in and out.
Dates are `YYYY-MM-DD` and are read in the caller's time zone `tz` (IANA, default `UTC`);
timestamps in answers are ISO-8601 UTC.

## Routes

### GET /v1/markaz/access
Any signed-in member. `{ "canReport": bool, "isSuperAdmin": bool, "markazGroupID": "silsila-markaz", "markazRole": "administrator"|"admin"|"member"|null }`.
The apps call it to decide whether to show the **Reports & analytics** entry.

### GET /v1/markaz/analytics?from=&to=&tz=&scope=&kind=
- `from`,`to`: inclusive dates, at most 400 days apart (default: the last 30 days to today).
- `scope`: `all` (default) | `region:<Region name>` | `halqah:<groupID>`.
- `kind`: `all` (default) | `zikr` | `meeting`.

```jsonc
{
  "range": { "from": "2026-10-07", "to": "2026-11-05", "days": 30, "tz": "America/New_York" },
  "scope": { "kind": "all", "id": null, "name": "All Halqahs" },
  "generatedAt": "2026-11-05T14:00:00Z",
  "summary": {
    "sessions": 41, "zikrSessions": 37, "meetings": 4,
    "attendance": 612,            // people present, summed over sessions
    "uniqueAttendees": 118,       // different people (app members + website visitors)
    "appAttendance": 540, "webAttendance": 72,
    "averageAttendance": 14.9,    // attendance / sessions, 1 decimal
    "averageMinutes": 47,         // mean session length
    "totalMinutes": 1927,
    "activeHalqahs": 6, "totalHalqahs": 8,
    "members": 210,               // people in the scope's Halqahs now
    "newMembers": 12,             // joined a Halqah in the range
    "duaRequests": 33, "stagesAnnounced": 402, "chatMessages": 95,
    "automatedStarts": 18         // sessions started by the Paltalk relay or a Zikr time by itself
  },
  "previous": { "from": "2026-09-07", "to": "2026-10-06", "sessions": 35, "attendance": 540, "uniqueAttendees": 101, "averageAttendance": 15.4 },
  "daily":   [ { "date": "2026-10-07", "sessions": 1, "attendance": 14, "unique": 14 } ],   // every day in range, zeros included
  "weekdayHour": [ { "weekday": 1, "hour": 21, "sessions": 6, "attendance": 88 } ],        // weekday 1=Monday..7=Sunday, local hour
  "halqahs": [ {
      "id": "usa", "name": "North America", "region": "North America", "kind": "halqah",
      "sessions": 9, "attendance": 140, "averageAttendance": 15.6, "uniqueAttendees": 31,
      "members": 44, "attendanceRate": 0.70,  // uniqueAttendees / members (null when no members)
      "lastSessionAt": "2026-11-04T02:00:00Z", "change": 0.12,  // attendance vs previous period (null when none before)
      "status": "active"                      // active (session in last 7 days) | quiet (8-21 days) | inactive (none in 21 days)
  } ],
  "regions":   [ { "name": "North America", "halqahs": 3, "sessions": 20, "attendance": 300, "members": 90 } ],
  "countries": [ { "code": "US", "attendees": 40 } ],          // from website visitors' and members' stated country
  "regulars":  [ { "memberID": "…", "name": "…", "sessions": 22, "lastSeenAt": "…", "halqahs": ["North America"] } ],  // top 25
  "needsCare": [ { "memberID": "…", "name": "…", "lastSeenAt": "…", "sessionsBefore": 9, "halqah": "Canada" } ],     // attended 3+ times before, not in the last 21 days; top 50
  "sessions":  [ { "id": "…", "groupID": "usa", "groupName": "North America", "kind": "zikr", "title": "Halqah Zikr",
                   "startedAt": "…", "endedAt": "…", "minutes": 52, "attendance": 18, "app": 15, "web": 3,
                   "startedBy": "Name or null", "automated": false } ],  // newest first, up to 200
  "insights":  [ { "level": "good"|"watch"|"alert", "title": "Attendance up 13%", "detail": "…", "halqahID": null } ]
}
```

### GET /v1/markaz/reports/daily?date=&tz=
One day's report (default: yesterday in `tz`).
```jsonc
{ "date": "2026-11-04", "tz": "…", "summary": { …same keys as analytics.summary… },
  "previousDay": { "sessions": 2, "attendance": 30 },
  "halqahs": [ { "id": "usa", "name": "North America", "region": "…",
      "sessions": [ { "id": "…", "kind": "zikr", "title": "…", "startedAt": "…", "endedAt": "…", "minutes": 50,
          "startedBy": "…", "automated": true, "attendance": 18,
          "attendees": [ { "name": "…", "city": "Worcester", "country": "US", "via": "app"|"web", "joinedAt": "…", "minutes": 44 } ] } ] } ],
  "noSession": [ { "id": "canada", "name": "Canada" } ],      // Halqahs with a Zikr time that day but no session
  "insights": [ … ] }
```

### GET /v1/markaz/reports/monthly?month=YYYY-MM&tz=
```jsonc
{ "month": "2026-10", "tz": "…", "summary": {…}, "previous": {…same as analytics.previous…},
  "daily": [ … ], "weekdayHour": [ … ], "halqahs": [ … ], "regions": [ … ],
  "regulars": [ … ], "needsCare": [ … ],
  "attendanceByPerson": [ { "memberID": "…", "name": "…", "via": "app"|"web", "sessions": 12, "days": 11, "halqahs": ["…"], "lastSeenAt": "…" } ], // everyone who attended, most first
  "newMembers": [ { "name": "…", "halqah": "…", "joinedAt": "…" } ],
  "insights": [ … ] }
```

### GET /v1/markaz/sessions/{sessionID}?tz=
`{ "session": {…as in analytics.sessions…}, "attendees": [ {…as in daily attendees…} ], "stages": [ { "title": "1st Latifa", "at": "…" } ], "duaRequests": 3 }`

### GET /v1/markaz/people/{memberID}?tz=
`{ "memberID", "name", "email"?, "halqahs": [{"id","name","role"}], "firstSeenAt", "lastSeenAt", "sessions": 40, "last90Days": 18, "currentStreakDays": 3, "history": [ { "date", "groupName", "title", "minutes" } ] }` (newest first, up to 200).

### GET /v1/markaz/export?type=sessions|attendance|halqahs|people&from=&to=&tz=&scope=
CSV (`text/csv; charset=utf-8`, `content-disposition: attachment`), UTF-8 with BOM so Excel opens Urdu names.

### GET /v1/markaz/organization
```jsonc
{ "regions": [ { "name": "North America", "halqahs": [ {
      "id": "usa", "name": "North America", "kind": "halqah", "city": null, "countryCode": "US",
      "members": 44, "administrators": ["Name"], "admins": ["Name"],
      "zikrTimes": 2, "lastSessionAt": "…", "sessions30Days": 9, "status": "active", "isLive": false } ] } ],
  "unassigned": [ …halqahs without a region… ],
  "markaz": { "id": "silsila-markaz", "members": 5, "officers": 2 },
  "liveNow": [ { "groupID": "…", "name": "…", "kind": "zikr", "startedAt": "…", "listening": 12 } ],
  "totals": { "halqahs": 8, "members": 210, "administrators": 9, "admins": 14 } }
```

### PUT /v1/markaz/halqahs/{groupID}  (super admin)
`{ "region": "North America"|null, "countryCode": "US"|null, "city": "New York"|null }` → `{ "ok": true }`.

### POST /v1/markaz/sync-admins  (super admin)
Adds every Halqah Administrator and Admin to the Silsila Markaz as a member (never lowers a role there). → `{ "added": 7, "total": 23 }`.

### POST /v1/markaz/announce  (Markaz officer)
`{ "title": "…", "body": "…", "audience": "members"|"admins", "scope": "all"|"region:<name>"|"halqahs", "halqahIDs": ["…"], "notify": true }`
- `members`: published as an announcement in each chosen Halqah (members see it in the Halqah's feed; notified when `notify`).
- `admins`: brings Halqah admins into the Markaz first, then posts it in the Silsila Markaz.
→ `{ "ok": true, "posted": 6, "notified": 140 }`. Listed by GET /v1/markaz/announcements → `{ "announcements": [ { "id","title","body","audience","targets": ["North America"],"sentBy","sentAt","posted" } ] }`.

### Reporting website sign-in (device code)
1. Website: `POST /v1/reporting/link` (no auth, rate limited) → `{ "code": "K7Q2-9MXD", "pollToken": "<64 hex>", "expiresAt": "…" }` (5 minutes, single use).
2. App (Markaz officer): `POST /v1/markaz/reporting-link/approve { "code": "K7Q2-9MXD" }` → `{ "ok": true }`; 404 when unknown or expired.
3. Website: `POST /v1/reporting/link/poll { "pollToken" }` → `{ "status": "pending" }` | `{ "status": "approved", "token": "<64 hex>", "expiresAt": "…" }` (a 12-hour session marked for reporting) | `{ "status": "expired" }`.
- `GET /v1/markaz/reporting-sessions` → `{ "sessions": [ { "id": "<first 12 of hash>", "name": "…", "createdAt", "lastSeenAt", "expiresAt", "current": bool } ] }`; `DELETE /v1/markaz/reporting-sessions/{id}` signs that computer out.

### Daily digest
Every day at 12:00 UTC the server notifies officers' phones: "Yesterday: 6 Zikr in 4 Halqahs, 92 attended (+8%)". Tapping opens the daily report (`path` = `/markaz/reports/daily`). On the 1st it also sends "October report is ready".

## Screens (iOS and Android identical)

Entry points:
- Super admin dashboard (Halqah tab): a new full-width card **Reports & analytics** (gold, chart icon) under the existing tiles, and **Organisation** next to it.
- The Silsila Markaz group page: for officers, the same two cards at the top of its admin section.
- Shown only when `GET /v1/markaz/access` says `canReport`.

1. **Reports & analytics** (scrollable dashboard)
   - Period chips: 7 days · 30 days · 90 days · 12 months · This month · Last month; scope picker (All Halqahs / each region / each Halqah); kind segmented control (All · Zikr · Meetings).
   - KPI grid (2 columns): Sessions, Attendance, Different people, Average per session, Website visitors, Average length, Active Halqahs, New members — each with the change vs the previous period (green up / red down arrow, %).
   - **Attendance trend** line/area chart (daily attendance, plus sessions as bars).
   - **When people come**: weekday × hour heatmap (7 rows, only hours with any session).
   - **Halqahs**: horizontal bar chart of attendance; tap a row → that Halqah in scope.
   - **App or website**: donut (app vs web).
   - **Insights** list (coloured by level).
   - **Regulars** (top 25) and **Needs care** (people not seen in 3 weeks) — tap a person → person history.
   - **Sessions** list (newest first) → session detail (attendees with name, city, via, joined time, minutes; stages called; dua count).
   - Toolbar: Share / Export (CSV of sessions, attendance, Halqahs, people via the share sheet), **Daily report**, **Monthly report**, **Sign in on a computer**.
2. **Daily report**: date picker (default yesterday), summary, each Halqah with its sessions and attendee list, "No session" list, share as text/CSV.
3. **Monthly report**: month picker (default last month), summary with changes, trend chart, Halqah table, attendance by person, new members, needs care, share/CSV.
4. **Organisation**: totals strip; "Live now" list; regions (collapsible) → Halqah cards (status dot, members, admins' names, last session, sessions in 30 days); super admin: tap a Halqah → set region / country / city; buttons **Announce to Halqahs** (title, message, audience Members / Halqah admins, scope All / region / chosen Halqahs, notify toggle) and **Bring in Halqah admins** (super admin); list of past announcements.
5. **Sign in on a computer**: explains "Open reporting.naqshbandiaowaisiah.us on the computer and type the code shown there", code field (8 characters, auto-uppercase, dash optional) → Approve; list of signed-in computers with Sign out.

Wording: plain, no technical words. English and Urdu strings for every label (Western digits in both).
Charts: Swift Charts on iOS; Compose Canvas on Android (no new chart library).
