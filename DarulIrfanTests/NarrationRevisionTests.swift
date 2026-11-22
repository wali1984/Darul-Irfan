import Foundation
import XCTest
@testable import DarulIrfan

/// The narration list's revision names the folder of kept narrations. Moving
/// to it must not lose the copies a phone already holds.
@MainActor
final class NarrationRevisionTests: XCTestCase {
    private func manifest(_ json: String) throws -> NarrationManifest {
        try JSONDecoder().decode(NarrationManifest.self, from: Data(json.utf8))
    }

    func testTheRevisionIsUsedAsWritten() throws {
        let list = try manifest(#"{"version":3,"revision":"2b","voices":{"ur":{"name":"r1"}},"editions":{}}"#)
        XCTAssertEqual(NarrationCatalog.tag(for: list), "2b")
    }

    func testTheServersRevisionIsTheFolderThePhoneAlreadyUses() throws {
        // As `publicNarrationManifest` in Server/src/audio.ts sends it.
        var list = try manifest(#"{"version":3,"revision":"1mnt9jxgk87c1","voices":{"en":{"name":"r232xsctr8ixd2"},"ur":{"name":"r1or2hco9dxhcs"}},"editions":{}}"#)
        let withRevision = NarrationCatalog.tag(for: list)
        list.revision = nil
        XCTAssertEqual(withRevision, "1mnt9jxgk87c1")
        XCTAssertEqual(NarrationCatalog.tag(for: list), withRevision)
    }

    func testAListWithoutARevisionKeepsItsFolder() throws {
        let list = try manifest(#"{"version":3,"voices":{"ur":{"name":"Narration · rev 2"},"en":{"name":"Recitation"}},"editions":{}}"#)
        XCTAssertNil(list.revision)
        XCTAssertEqual(NarrationCatalog.tag(for: list), "328az7unrobdi")
    }

    func testARevisionThatCannotNameAFolderIsNotTaken() {
        for revision in ["", ".", "..", "../narration", "r 2", "R2", "2\n", "12345678901234"] {
            let list = NarrationManifest(version: 1, revision: revision, voices: [:], editions: [:])
            XCTAssertEqual(NarrationCatalog.tag(for: list), "33niihzj4ux45", "revision \(revision)")
        }
    }
}
