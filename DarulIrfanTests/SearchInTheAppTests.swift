import Foundation
import XCTest
@testable import DarulIrfan

/// Global search's "In the app" group (parity-spec/redesign, October 2026):
/// the app's own screens, found by their names in English or Urdu.
final class SearchInTheAppTests: XCTestCase {

    // MARK: - Search: In the app

    /// Global search finds the app's own screens by their names.
    func testInTheAppFindsToolsAndSettingsByName() {
        let english: (SearchAppDestination) -> [String] = { $0.nameKeys }
        XCTAssertEqual(SearchAppDestination.matches(for: "qibla", names: english), [.qibla])
        XCTAssertEqual(SearchAppDestination.matches(for: "Tasbih", names: english), [.tasbih])
        XCTAssertEqual(SearchAppDestination.matches(for: "duas", names: english), [.duas])
        XCTAssertEqual(SearchAppDestination.matches(for: "99", names: english), [.names])
        XCTAssertEqual(SearchAppDestination.matches(for: "islamic days", names: english), [.islamicDays])
        XCTAssertEqual(SearchAppDestination.matches(for: "my day", names: english), [.myDay])
        XCTAssertEqual(SearchAppDestination.matches(for: "focus", names: english), [.focus])
        XCTAssertEqual(SearchAppDestination.matches(for: "notes", names: english), [.notes])
        XCTAssertEqual(SearchAppDestination.matches(for: "fasting", names: english), [.fasting])
        XCTAssertEqual(SearchAppDestination.matches(for: "timetable", names: english), [.timetable])
        XCTAssertEqual(SearchAppDestination.matches(for: "groups", names: english), [.privateGroups])
        XCTAssertEqual(SearchAppDestination.matches(for: "hijri", names: english), [.hijri])
        XCTAssertEqual(SearchAppDestination.matches(for: "NOTIF", names: english), [.notifications])
        XCTAssertEqual(SearchAppDestination.matches(for: "settings", names: english), [.settings])
        XCTAssertEqual(Set(SearchAppDestination.matches(for: "privacy", names: english)), [.privacy, .officialAlerts])

        // One letter lists nothing, nor does a blank query or another word.
        XCTAssertTrue(SearchAppDestination.matches(for: "q", names: english).isEmpty)
        XCTAssertTrue(SearchAppDestination.matches(for: "   ", names: english).isEmpty)
        XCTAssertTrue(SearchAppDestination.matches(for: "prophet", names: english).isEmpty)
    }

    /// An Urdu name is found however it was typed: an Arabic keyboard's
    /// letters, or a vowel mark.
    func testInTheAppFindsUrduNamesHoweverTyped() {
        let names: (SearchAppDestination) -> [String] = { destination in
            switch destination {
            case .qibla: return ["Qibla", "قبلہ"]
            case .tasbih: return ["Tasbih", "تسبیح"]
            default: return destination.nameKeys
            }
        }
        XCTAssertEqual(SearchAppDestination.matches(for: "قبلہ", names: names), [.qibla])
        XCTAssertEqual(SearchAppDestination.matches(for: "قِبله", names: names), [.qibla])
        XCTAssertEqual(SearchAppDestination.matches(for: "تسبيح", names: names), [.tasbih])
    }

    /// The app's own names (the English keys at least) are searched by
    /// default, and every destination the redesign names is there once.
    func testInTheAppDestinations() {
        XCTAssertTrue(SearchAppDestination.matches(for: "Qibla").contains(.qibla))
        XCTAssertTrue(SearchAppDestination.matches(for: "monthly timetable").contains(.timetable))

        let all = SearchAppDestination.allCases
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        for destination in all {
            XCTAssertFalse(destination.nameKeys.isEmpty, destination.rawValue)
            XCTAssertFalse(destination.systemImage.isEmpty, destination.rawValue)
        }
        let named: Set<SearchAppDestination> = [
            .qibla, .tasbih, .duas, .names, .islamicDays, .myDay, .focus, .notes, .fasting, .timetable,
            .privateGroups, .settings, .location, .calculation, .notifications, .appearance, .hijri,
            .contentStorage, .officialAlerts, .privacy,
        ]
        XCTAssertTrue(named.isSubset(of: Set(all)))
    }
}
