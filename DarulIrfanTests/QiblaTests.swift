import Foundation
import XCTest
@testable import DarulIrfan

/// Qibla bearing tests. Expected values were computed with the standard
/// great-circle initial-bearing formula toward the Kaaba (21.4225 N,
/// 39.8262 E — the same constants adhan-swift uses):
///
///     bearing = atan2(sin Δλ, cos φ₁ · tan φ_Kaaba − sin φ₁ · cos Δλ)
///
/// which gives Karachi → 267.74° and New York → 58.48°. Published qibla
/// tables for these cities quote ~267–268.5° and ~58.5° respectively, so a
/// ±2° tolerance covers both the exact formula result and table rounding.
final class QiblaTests: XCTestCase {

    private let service = PrayerCalculationService()

    func testKarachiQiblaBearing() {
        let bearing = service.qiblaDirection(from: TestPlaces.karachi)
        XCTAssertEqual(bearing, 267.74, accuracy: 2.0)
    }

    func testNewYorkQiblaBearing() {
        let bearing = service.qiblaDirection(from: TestPlaces.newYork)
        XCTAssertEqual(bearing, 58.48, accuracy: 2.0)
    }

    func testBearingIsNormalizedToCompassRange() {
        // Both fixtures — one west of Makkah, one east — must come back as
        // compass degrees in [0, 360).
        for place in [TestPlaces.karachi, TestPlaces.newYork] {
            let bearing = service.qiblaDirection(from: place)
            XCTAssertGreaterThanOrEqual(bearing, 0.0)
            XCTAssertLessThan(bearing, 360.0)
        }
    }
}
