import Foundation
import XCTest
@testable import DarulIrfan

/// Tests for `EventsRepository`: event/announcement upserts and ordering
/// against an in-memory store.
final class EventsRepositoryTests: XCTestCase {

    private var database: AppDatabase!
    private var repository: EventsRepository!

    override func setUp() async throws {
        database = try await AppDatabase.inMemory()
        repository = EventsRepository(database: database)
    }

    override func tearDown() {
        repository = nil
        database = nil
    }

    // MARK: - Events

    func testEventUpsertRoundtripAndOrdering() async throws {
        let laterDated = CommunityEvent(
            id: "salana-ijtema-2026",
            kind: .salanaIjtema,
            title: "Salana Ijtema",
            titleUrdu: nil,
            details: "Annual gathering at Dar ul Irfan, Munara.",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_200_000),
            datesAreApproximate: false,
            venue: "Dar ul Irfan, Munara",
            sourceUrl: "https://www.naqshbandiaowaisiah.org/",
            updatedAt: nil
        )
        let earlierDated = CommunityEvent(
            id: "monthly-ijtema",
            kind: .monthlyIjtema,
            title: "Monthly Ijtema",
            titleUrdu: nil,
            details: nil,
            startDate: Date(timeIntervalSince1970: 1_750_000_000),
            endDate: nil,
            datesAreApproximate: false,
            venue: "Dar ul Irfan, Munara",
            sourceUrl: nil,
            updatedAt: nil
        )
        let undated = CommunityEvent(
            id: "aitekaaf",
            kind: .ramadanAitekaaf,
            title: "Ramadan Aitekaaf",
            titleUrdu: nil,
            details: nil,
            startDate: nil,
            endDate: nil,
            datesAreApproximate: true,
            venue: nil,
            sourceUrl: nil,
            updatedAt: nil
        )
        try await repository.upsertEvents([undated, laterDated, earlierDated])

        let events = try await repository.events()
        // Dated events first by soonest start; undated events trail.
        XCTAssertEqual(events.map { $0.id }, ["monthly-ijtema", "salana-ijtema-2026", "aitekaaf"])
        XCTAssertEqual(events[1], laterDated)

        // Upserting the same id updates in place — count stays the same.
        var updated = laterDated
        updated.details = "Annual gathering. Dates to be announced."
        try await repository.upsertEvents([updated])
        let afterUpdate = try await repository.events()
        XCTAssertEqual(afterUpdate.count, 3)
        XCTAssertEqual(
            afterUpdate.first { $0.id == laterDated.id }?.details,
            "Annual gathering. Dates to be announced."
        )
    }

    // MARK: - Announcements

    func testAnnouncementsNewestFirstWithLimit() async throws {
        let oldest = Announcement(
            id: "a-1",
            title: "Older announcement",
            body: nil,
            publishedAt: Date(timeIntervalSince1970: 1_600_000_000),
            sourceUrl: nil
        )
        let middle = Announcement(
            id: "a-2",
            title: "Middle announcement",
            body: "Details of the middle announcement.",
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceUrl: nil
        )
        let newest = Announcement(
            id: "a-3",
            title: "Newest announcement",
            body: nil,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000),
            sourceUrl: "https://www.naqshbandiaowaisiah.org/"
        )
        try await repository.upsertAnnouncements([oldest, newest, middle])

        let limited = try await repository.announcements(limit: 2)
        XCTAssertEqual(limited.map { $0.id }, ["a-3", "a-2"])
        XCTAssertEqual(limited[0], newest)

        let all = try await repository.announcements(limit: 10)
        XCTAssertEqual(all.map { $0.id }, ["a-3", "a-2", "a-1"])

        // Upsert replaces on id.
        var revised = newest
        revised.title = "Newest announcement (revised)"
        try await repository.upsertAnnouncements([revised])
        let afterUpdate = try await repository.announcements(limit: 10)
        XCTAssertEqual(afterUpdate.count, 3)
        XCTAssertEqual(afterUpdate.first?.title, "Newest announcement (revised)")
    }
}
