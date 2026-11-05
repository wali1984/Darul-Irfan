import XCTest
@testable import DarulIrfan

/// The Markaz reports read the contract's answers (Docs/MARKAZ_ANALYTICS_API.md),
/// and a server that sends more, less or something odd never blanks them.
final class MarkazModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.darulIrfanServer().decode(type, from: Data(json.utf8))
    }

    func testAnalyticsDecodesTheContractSample() throws {
        let json = """
        {
          "range": { "from": "2026-10-07", "to": "2026-11-05", "days": 30, "tz": "America/New_York" },
          "scope": { "kind": "all", "id": null, "name": "All Halqahs" },
          "generatedAt": "2026-11-05T14:00:00Z",
          "summary": {
            "sessions": 41, "zikrSessions": 37, "meetings": 4,
            "attendance": 612, "uniqueAttendees": 118,
            "appAttendance": 540, "webAttendance": 72,
            "averageAttendance": 14.9, "averageMinutes": 47, "totalMinutes": 1927,
            "activeHalqahs": 6, "totalHalqahs": 8, "members": 210, "newMembers": 12,
            "duaRequests": 33, "stagesAnnounced": 402, "chatMessages": 95, "automatedStarts": 18
          },
          "previous": { "from": "2026-09-07", "to": "2026-10-06", "sessions": 35, "attendance": 540, "uniqueAttendees": 101, "averageAttendance": 15.4 },
          "daily": [ { "date": "2026-10-07", "sessions": 1, "attendance": 14, "unique": 14 } ],
          "weekdayHour": [ { "weekday": 1, "hour": 21, "sessions": 6, "attendance": 88 } ],
          "halqahs": [ {
              "id": "usa", "name": "North America", "region": "North America", "kind": "halqah",
              "sessions": 9, "attendance": 140, "averageAttendance": 15.6, "uniqueAttendees": 31,
              "members": 44, "attendanceRate": 0.70,
              "lastSessionAt": "2026-11-04T02:00:00Z", "change": 0.12, "status": "active"
          } ],
          "regions": [ { "name": "North America", "halqahs": 3, "sessions": 20, "attendance": 300, "members": 90 } ],
          "countries": [ { "code": "US", "attendees": 40 } ],
          "regulars": [ { "memberID": "m1", "name": "Ahmad", "sessions": 22, "lastSeenAt": "2026-11-04T02:00:00.000Z", "halqahs": ["North America"] } ],
          "needsCare": [ { "memberID": "m2", "name": "Bilal", "lastSeenAt": "2026-10-01T02:00:00Z", "sessionsBefore": 9, "halqah": "Canada" } ],
          "sessions": [ { "id": "s1", "groupID": "usa", "groupName": "North America", "kind": "zikr", "title": "Halqah Zikr",
                          "startedAt": "2026-11-04T02:00:00Z", "endedAt": "2026-11-04T02:52:00Z", "minutes": 52, "attendance": 18, "app": 15, "web": 3,
                          "startedBy": null, "automated": false } ],
          "insights": [ { "level": "good", "title": "Attendance up 13%", "detail": "More people than last month.", "halqahID": null } ],
          "people": [ { "memberID": "m1", "name": "Ahmad", "via": "app", "sessions": 22, "days": 20, "halqahs": [], "lastSeenAt": "2026-11-04T02:00:00Z" } ]
        }
        """
        let analytics = try decode(MarkazAnalytics.self, json)
        XCTAssertEqual(analytics.range?.days, 30)
        XCTAssertEqual(analytics.scope?.name, "All Halqahs")
        XCTAssertNil(analytics.scope?.id)
        XCTAssertNotNil(analytics.generatedAt)
        XCTAssertEqual(analytics.summary.sessions, 41)
        XCTAssertEqual(analytics.summary.attendance, 612)
        XCTAssertEqual(analytics.summary.averageAttendance, 14.9, accuracy: 0.001)
        XCTAssertEqual(analytics.summary.averageMinutes, 47, accuracy: 0.001)
        XCTAssertEqual(analytics.summary.automatedStarts, 18)
        XCTAssertEqual(analytics.previous?.sessions, 35)
        XCTAssertEqual(analytics.previous?.averageAttendance ?? 0, 15.4, accuracy: 0.001)
        XCTAssertNil(analytics.previous?.webAttendance)
        XCTAssertEqual(analytics.daily.first?.attendance, 14)
        XCTAssertNotNil(analytics.daily.first?.day)
        XCTAssertEqual(analytics.weekdayHour.first?.hour, 21)
        XCTAssertEqual(analytics.halqahs.first?.id, "usa")
        XCTAssertEqual(analytics.halqahs.first?.attendanceRate ?? 0, 0.70, accuracy: 0.001)
        XCTAssertEqual(analytics.halqahs.first?.change ?? 0, 0.12, accuracy: 0.001)
        XCTAssertNotNil(analytics.halqahs.first?.lastSessionAt)
        XCTAssertEqual(analytics.regions.first?.halqahs, 3)
        XCTAssertEqual(analytics.countries.first?.code, "US")
        XCTAssertEqual(analytics.regulars.first?.halqahs, ["North America"])
        XCTAssertNotNil(analytics.regulars.first?.lastSeenAt, "milliseconds are read too")
        XCTAssertEqual(analytics.needsCare.first?.sessionsBefore, 9)
        XCTAssertEqual(analytics.sessions.first?.minutes, 52)
        XCTAssertEqual(analytics.sessions.first?.web, 3)
        XCTAssertNil(analytics.sessions.first?.startedBy)
        XCTAssertEqual(analytics.sessions.first?.automated, false)
        XCTAssertEqual(analytics.insights.first?.level, "good")

        // The figures compare with the period before where it is known.
        let figures = analytics.summary.figures(previous: analytics.previous)
        XCTAssertEqual(figures.count, 8)
        XCTAssertEqual(figures.first?.change ?? 0, 6.0 / 35.0, accuracy: 0.0001)
        XCTAssertNil(figures.first { $0.id == "web" }?.change)
    }

    func testAnalyticsSurvivesMissingAndOddValues() throws {
        let json = """
        {
          "summary": { "sessions": 3.0, "attendance": "many", "averageAttendance": 2 },
          "daily": [ { "date": "2026-10-07", "sessions": 1 }, "not a day" ],
          "halqahs": [ { "id": "usa", "name": "North America", "attendanceRate": null, "change": null, "lastSessionAt": "yesterday" } ],
          "sessions": 7,
          "somethingNew": { "nested": true }
        }
        """
        let analytics = try decode(MarkazAnalytics.self, json)
        XCTAssertNil(analytics.range)
        XCTAssertNil(analytics.previous)
        XCTAssertEqual(analytics.summary.sessions, 3)
        XCTAssertEqual(analytics.summary.attendance, 0)
        XCTAssertEqual(analytics.summary.averageAttendance, 2, accuracy: 0.001)
        XCTAssertEqual(analytics.daily.count, 1)
        XCTAssertEqual(analytics.daily.first?.attendance, 0)
        XCTAssertNil(analytics.halqahs.first?.attendanceRate)
        XCTAssertNil(analytics.halqahs.first?.change)
        XCTAssertNil(analytics.halqahs.first?.lastSessionAt)
        XCTAssertTrue(analytics.sessions.isEmpty)
        XCTAssertTrue(analytics.insights.isEmpty)
    }

    func testOrganizationDecodesTheContractSample() throws {
        let json = """
        { "regions": [ { "name": "North America", "halqahs": [ {
              "id": "usa", "name": "North America", "kind": "halqah", "city": null, "countryCode": "US",
              "members": 44, "administrators": ["Name"], "admins": ["Other", "Third"],
              "zikrTimes": 2, "lastSessionAt": "2026-11-04T02:00:00Z", "sessions30Days": 9, "status": "active", "isLive": false } ] } ],
          "unassigned": [ { "id": "silsila-markaz", "name": "Silsila Markaz", "kind": "markaz", "members": 5, "status": "quiet", "isLive": true } ],
          "markaz": { "id": "silsila-markaz", "members": 5, "officers": 2 },
          "liveNow": [ { "groupID": "usa", "name": "North America", "kind": "zikr", "startedAt": "2026-11-05T01:00:00Z", "listening": 12 } ],
          "totals": { "halqahs": 8, "members": 210, "administrators": 9, "admins": 14 } }
        """
        let organization = try decode(MarkazOrganization.self, json)
        XCTAssertEqual(organization.regions.count, 1)
        let usa = try XCTUnwrap(organization.regions.first?.halqahs.first)
        XCTAssertEqual(usa.countryCode, "US")
        XCTAssertNil(usa.city)
        XCTAssertEqual(usa.administrators, ["Name"])
        XCTAssertEqual(usa.admins.count, 2)
        XCTAssertEqual(usa.sessions30Days, 9)
        XCTAssertFalse(usa.isLive)
        XCTAssertNotNil(usa.lastSessionAt)
        let markaz = try XCTUnwrap(organization.unassigned.first)
        XCTAssertEqual(markaz.kind, "markaz")
        XCTAssertTrue(markaz.administrators.isEmpty)
        XCTAssertEqual(markaz.zikrTimes, 0)
        XCTAssertEqual(organization.markaz?.officers, 2)
        XCTAssertEqual(organization.liveNow.first?.listening, 12)
        XCTAssertEqual(organization.totals.admins, 14)
        XCTAssertEqual(organization.allHalqahs.map(\.id), ["usa", "silsila-markaz"])
    }

    func testAccessAndSmallAnswers() throws {
        let access = try decode(MarkazAccess.self, #"{ "canReport": true, "isSuperAdmin": false, "markazGroupID": "silsila-markaz", "markazRole": "admin" }"#)
        XCTAssertTrue(access.canReport)
        XCTAssertEqual(access.markazRole, "admin")
        let none = try decode(MarkazAccess.self, "{}")
        XCTAssertFalse(none.canReport)
        XCTAssertEqual(none.markazGroupID, "silsila-markaz")

        let sessions = try decode(MarkazReportingSessionList.self, """
        { "sessions": [ { "id": "abc123def456", "name": "Chrome on Windows", "createdAt": "2026-11-05T10:00:00Z",
                          "lastSeenAt": "2026-11-05T11:00:00Z", "expiresAt": "2026-11-05T22:00:00Z", "current": false } ] }
        """)
        XCTAssertEqual(sessions.sessions.first?.id, "abc123def456")
        XCTAssertNotNil(sessions.sessions.first?.expiresAt)

        let result = try decode(MarkazAnnounceResult.self, #"{ "ok": true, "posted": 6, "notified": 140 }"#)
        XCTAssertEqual(result.posted, 6)
        XCTAssertEqual(result.notified, 140)
    }

    func testQueryEncodesRegionNames() {
        let query = MarkazService.query([("scope", "region:North America & Co+"), ("from", "2026-10-07"), ("kind", nil)])
        XCTAssertEqual(query, "scope=region%3ANorth%20America%20%26%20Co%2B&from=2026-10-07")
    }

    func testDigestLinksOpenTheReports() {
        XCTAssertEqual(AppRoute(path: "darulirfan://markaz/reports/daily"), .markazReport(monthly: false))
        XCTAssertEqual(AppRoute(path: "/markaz/reports/monthly"), .markazReport(monthly: true))
        XCTAssertNil(AppRoute(path: "markaz/reports/yearly"))
    }

    @MainActor
    func testComputerCodeIsShownWithItsDash() {
        XCTAssertEqual(MarkazComputerSignInView.shown("k7q29mxd"), "K7Q2-9MXD")
        XCTAssertEqual(MarkazComputerSignInView.shown("K7Q2-9MXD-EXTRA"), "K7Q2-9MXD")
        XCTAssertEqual(MarkazComputerSignInView.shown("k7q"), "K7Q")
    }
}
