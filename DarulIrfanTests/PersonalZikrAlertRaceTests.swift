import XCTest
import UserNotifications
@testable import DarulIrfan

@MainActor
final class PersonalZikrAlertRaceTests: XCTestCase {
    func testDisablingWhileAddIsPendingLeavesNoAlert() async throws {
        let name = "personal-alert-off-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let entered = expectation(description: "First add is awaiting completion")
        let center = DelayedPersonalAlertCenter { entered.fulfill() }
        let store = PersonalZikrStore(defaults: defaults, alertCenter: center)
        store.setReminder(0, PersonalZikrReminder(enabled: true, minuteOfDay: 420))
        await fulfillment(of: [entered], timeout: 5)
        store.setReminder(0, PersonalZikrReminder(enabled: false, minuteOfDay: 420))
        // Give the newer request an opportunity to run while the old add is held.
        for _ in 0..<10 { await Task.yield() }
        center.finishFirstAdd()
        await store.waitForAlertRefresh()
        XCTAssertEqual(center.addCount, 1)
        XCTAssertTrue(center.requests.isEmpty, "Off must remove an alert that completed late")
    }

    func testRapidTimeChangesKeepOnlyLatestReminder() async throws {
        let name = "personal-alert-time-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let entered = expectation(description: "First add is awaiting completion")
        let center = DelayedPersonalAlertCenter { entered.fulfill() }
        let store = PersonalZikrStore(defaults: defaults, alertCenter: center)
        store.setReminder(0, PersonalZikrReminder(enabled: true, minuteOfDay: 420))
        await fulfillment(of: [entered], timeout: 5)
        store.setReminder(0, PersonalZikrReminder(enabled: true, minuteOfDay: 480))
        store.setReminder(0, PersonalZikrReminder(enabled: true, minuteOfDay: 540))
        for _ in 0..<10 { await Task.yield() }
        center.finishFirstAdd()
        await store.waitForAlertRefresh()
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertEqual(center.addCount, 2, "Superseded queued changes should not be scheduled")
        let trigger = try XCTUnwrap(center.requests.first?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, 9)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
    }
}

@MainActor
private final class DelayedPersonalAlertCenter: PersonalZikrAlertCenter {
    var requests: [UNNotificationRequest] = []
    var addCount = 0
    private var gate: CheckedContinuation<Void, Never>?
    private let entered: () -> Void
    init(entered: @escaping () -> Void) { self.entered = entered }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { requests }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        requests.removeAll { identifiers.contains($0.identifier) }
    }
    func add(_ request: UNNotificationRequest) async throws {
        addCount += 1
        if addCount == 1 {
            await withCheckedContinuation { continuation in
                gate = continuation
                entered()
            }
        }
        requests.removeAll { $0.identifier == request.identifier }
        requests.append(request)
    }
    func finishFirstAdd() { gate?.resume(); gate = nil }
}
