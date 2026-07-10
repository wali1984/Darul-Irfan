import Foundation
import XCTest
@testable import DarulIrfan

// Shared fixtures and date helpers for the unit test suite.
//
// Known-city fixtures follow Docs/CONTRACTS.md testing conventions:
// Karachi 24.8607/67.0011 Asia/Karachi, New York 40.7128/-74.0060
// America/New_York.

enum TestPlaces {
    static let karachi = PlaceCoordinate(
        latitude: 24.8607,
        longitude: 67.0011,
        name: "Karachi",
        timeZoneIdentifier: "Asia/Karachi"
    )

    static let newYork = PlaceCoordinate(
        latitude: 40.7128,
        longitude: -74.0060,
        name: "New York",
        timeZoneIdentifier: "America/New_York"
    )
}

enum TestDates {
    static let utc = TimeZone(identifier: "UTC")! // fixed zones; force unwrap acceptable in tests
    static let karachi = TimeZone(identifier: "Asia/Karachi")!
    static let newYork = TimeZone(identifier: "America/New_York")!

    /// Builds an exact instant from civil components in `timeZone`.
    static func make(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        minute: Int = 0,
        second: Int = 0,
        timeZone: TimeZone
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        // The fixed fixtures used by these tests always resolve to a valid
        // instant; a nil here is a test-authoring bug, so failing hard is right.
        return calendar.date(from: components)!
    }

    /// Minutes after local midnight of `date` in `timeZone` (hour*60 + minute).
    static func minutesIntoDay(of date: Date, timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
