import Foundation
import XCTest
@testable import DarulIrfan

final class TasbihWidgetRouteTests: XCTestCase {
    func testSavedCounterLinksValidateIdentity() {
        let id = UUID()
        XCTAssertEqual(AppRoute(path: "darulirfan://tasbih/\(id.uuidString)"), .tasbih(id: id))
        XCTAssertEqual(AppRoute(path: "darulirfan://tasbih/\(id.uuidString.lowercased())"), .tasbih(id: id))
        XCTAssertNil(AppRoute(path: "darulirfan://tasbih/not-a-counter"))
        XCTAssertNil(AppRoute(path: "darulirfan://tasbih/\(id.uuidString)/extra"))
        XCTAssertNil(AppRoute(path: "darulirfan://tasbih"))
    }
}
