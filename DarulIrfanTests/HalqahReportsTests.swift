import Foundation
import XCTest
@testable import DarulIrfan

/// Addendum 5 (owner 2026-11-19): a simple page's start sheet opens with the
/// saved zikr time's video, and its admins get the Halqah's own daily and
/// monthly reports.
@MainActor
final class HalqahReportsTests: XCTestCase {
    private let decoder = JSONDecoder.darulIrfanServer()

    // MARK: - The start sheet opens with the saved zikr time's video

    private func session(_ id: String, hour: Int, minute: Int = 0, autoplay: [ZikrAutoplayItem]?) -> ZikrSession {
        ZikrSession(id: id, title: id, weekdays: [1, 2, 3, 4, 5, 6, 7], startHour: hour, startMinute: minute,
                    durationMinutes: 45, timeZoneIdentifier: "America/New_York", autoplay: autoplay)
    }

    func testSimpleStartSheetOpensWithTheSavedZikrTimesVideo() {
        let sessions = [
            session("late", hour: 21, autoplay: [ZikrAutoplayItem(kind: "video", id: "laterVideo1", startSeconds: 10)]),
            session("recording", hour: 6, autoplay: [ZikrAutoplayItem(kind: "recording", id: "r1")]),
            session("nothing", hour: 7, autoplay: nil),
            session("evening", hour: 20, minute: 30,
                    autoplay: [ZikrAutoplayItem(kind: "video", id: "dQw4w9WgXcQ", startSeconds: 221, endSeconds: 2642)]),
        ]
        let form = HalqahStartForm(simple: true, startTitle: "Start Daily Zikr", zikrSessions: sessions)
        XCTAssertEqual(form.prefill, VideoLinkDraft(link: "https://youtu.be/dQw4w9WgXcQ", start: "3:41", end: "44:02"),
                       "the first time by its start that plays a video")
        XCTAssertEqual(VideoLink.id(from: form.prefill?.link ?? ""), "dQw4w9WgXcQ")

        let open = [session("open", hour: 20, autoplay: [ZikrAutoplayItem(kind: "video", id: "dQw4w9WgXcQ")])]
        XCTAssertEqual(HalqahStartForm(simple: true, zikrSessions: open).prefill,
                       VideoLinkDraft(link: "https://youtu.be/dQw4w9WgXcQ", start: "", end: ""), "blank times when absent")
        XCTAssertNil(HalqahStartForm(simple: true, zikrSessions: [sessions[1], sessions[2]]).prefill, "no saved video: empty")
        XCTAssertNil(HalqahStartForm(simple: false, zikrSessions: sessions).prefill, "only a simple page")
        XCTAssertNil(HalqahStartForm().prefill)
    }

    // MARK: - Reports

    func testReportsTileIsForASimplePageOnly() {
        let simple = HalqahPageLayout(simplePage: true)
        XCTAssertTrue(simple.showsReports)
        XCTAssertTrue(simple.showsAdminTile("reports"))
        XCTAssertFalse(HalqahPageLayout(simplePage: false).showsReports, "other Halqahs: no Reports tile")
    }

    func testDailyReportDecodes() throws {
        let json = #"""
        {"date":"2026-11-19","tz":"America/New_York","halqah":{"id":"na-evening","name":"North America - Evening Zikr"},
         "summary":{"sessions":1,"zikrSessions":1,"meetings":0,"attendance":3,"uniqueAttendees":3,"appAttendance":2,
           "webAttendance":1,"averageAttendance":3,"averageMinutes":42,"totalMinutes":42,"activeHalqahs":1,"totalHalqahs":1},
         "sessions":[{"id":"s1","groupID":"na-evening","groupName":"North America - Evening Zikr","kind":"zikr",
           "title":"Daily North America Nightly Zikr","startedAt":"2026-11-20T01:30:00.000Z","endedAt":"2026-11-20T02:12:00.000Z",
           "minutes":42,"attendance":3,"app":2,"web":1,"startedBy":"Sajid","automated":false,
           "attendees":[
             {"memberID":"m1","name":"Sajid","city":"Toronto","country":"CA","via":"app","joinedAt":"2026-11-20T01:30:10.000Z","minutes":42},
             {"memberID":"m2","name":"Visitor","via":"web","joinedAt":"2026-11-20T01:35:00.000Z","minutes":30}]}]}
        """#
        let report = try decoder.decode(HalqahDailyActivity.self, from: Data(json.utf8))
        XCTAssertEqual(report.date, "2026-11-19")
        XCTAssertEqual(report.summary.sessions, 1)
        XCTAssertEqual(report.summary.attendance, 3)
        XCTAssertEqual(report.summary.uniqueAttendees, 3)
        XCTAssertEqual(report.summary.appAttendance, 2)
        XCTAssertEqual(report.summary.webAttendance, 1)
        XCTAssertEqual(report.summary.totalMinutes, 42)
        let session = try XCTUnwrap(report.sessions.first)
        XCTAssertEqual(session.title, "Daily North America Nightly Zikr")
        XCTAssertEqual(session.attendees.map(\.name), ["Sajid", "Visitor"])
        XCTAssertEqual(session.attendees.first?.city, "Toronto")
        XCTAssertEqual(session.attendees.first?.country, "CA")
        XCTAssertFalse(session.attendees[0].isWeb)
        XCTAssertTrue(session.attendees[1].isWeb)
        XCTAssertEqual(session.attendees[1].minutes, 30)
        XCTAssertNil(HalqahReportsView.withoutHalqah(session).groupName, "the Halqah's own list does not repeat its name")

        let empty = try decoder.decode(HalqahDailyActivity.self, from: Data(
            #"{"date":"2026-11-18","tz":"America/New_York","summary":{"sessions":0},"sessions":[]}"#.utf8))
        XCTAssertTrue(empty.sessions.isEmpty, "No Zikr held on this day.")
    }

    func testMonthlyReportDecodes() throws {
        let json = #"""
        {"month":"2026-11","tz":"America/New_York","halqah":{"id":"na-evening","name":"NA"},
         "summary":{"sessions":12,"attendance":40,"uniqueAttendees":9,"appAttendance":30,"webAttendance":10,"totalMinutes":500},
         "previous":{"sessions":10,"attendance":32,"uniqueAttendees":8},
         "daily":[{"date":"2026-11-01","sessions":1,"attendance":4,"unique":4}],
         "sessions":[{"id":"s1","kind":"zikr","title":"Zikr","startedAt":"2026-11-01T01:30:00.000Z","endedAt":"2026-11-01T02:10:00.000Z",
                      "minutes":40,"attendance":4,"app":3,"web":1}],
         "attendanceByPerson":[{"memberID":"m1","name":"Sajid","via":"app","sessions":12,"days":12,"lastSeenAt":"2026-11-19T02:00:00.000Z"}]}
        """#
        let report = try decoder.decode(HalqahMonthlyActivity.self, from: Data(json.utf8))
        XCTAssertEqual(report.month, "2026-11")
        XCTAssertEqual(report.summary.sessions, 12)
        XCTAssertEqual(report.previous?.sessions, 10)
        XCTAssertEqual(report.daily.map(\.date), ["2026-11-01"])
        XCTAssertEqual(report.sessions.map(\.id), ["s1"])
        XCTAssertTrue(report.sessions[0].attendees.isEmpty, "the month lists sessions without attendees")
        XCTAssertEqual(report.attendanceByPerson.first?.name, "Sajid")
        XCTAssertEqual(report.attendanceByPerson.first?.days, 12)

        let figures = HalqahReportsView.figures(report.summary, previous: report.previous)
        XCTAssertEqual(figures.map(\.id), ["sessions", "attendance", "unique", "app", "web", "minutes"])
        XCTAssertEqual(figures.map(\.value), ["12", "40", "9", "30", "10", "500"])
        XCTAssertEqual(figures[0].change ?? 0, 0.2, accuracy: 0.0001)
    }

    func testDaysAndMonthsMoveInThePhonesCalendar() throws {
        XCTAssertEqual(HalqahReportPeriod.day("2026-11-01", moving: -1), "2026-10-31")
        XCTAssertEqual(HalqahReportPeriod.day("2026-12-31", moving: 1), "2027-01-01")
        XCTAssertEqual(HalqahReportPeriod.month("2026-01", moving: -1), "2025-12")
        XCTAssertEqual(HalqahReportPeriod.month("2026-12", moving: 1), "2027-01")

        let now = try XCTUnwrap(MarkazDay.date("2026-11-19")).addingTimeInterval(12 * 3_600)
        XCTAssertEqual(HalqahReportPeriod.today(now: now), "2026-11-19")
        XCTAssertEqual(HalqahReportPeriod.thisMonth(now: now), "2026-11")
        XCTAssertTrue(HalqahReportPeriod.canMoveForward(day: "2026-11-18", now: now))
        XCTAssertFalse(HalqahReportPeriod.canMoveForward(day: "2026-11-19", now: now), "never past today")
        XCTAssertTrue(HalqahReportPeriod.canMoveForward(month: "2026-10", now: now))
        XCTAssertFalse(HalqahReportPeriod.canMoveForward(month: "2026-11", now: now))
    }
}
