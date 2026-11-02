import XCTest
@testable import DarulIrfan

@MainActor
final class HifzLocalAudioTests: XCTestCase {
    func testMissingFileAndDirectoryFailBeforeMediaPreparation() throws {
        let folder = FileManager.default.temporaryDirectory
        let missing = folder.appendingPathComponent("missing-practice-\(UUID().uuidString).wav")
        XCTAssertThrowsError(try HifzComposition.requireReadableLocalAudio(missing))
        XCTAssertThrowsError(try HifzComposition.requireReadableLocalAudio(folder))
    }

    func testRestoredFileAllowsExplicitRetry() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("restored-practice-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try HifzComposition.requireReadableLocalAudio(url))
        try Data([1, 2]).write(to: url)
        XCTAssertNoThrow(try HifzComposition.requireReadableLocalAudio(url))
    }

    func testRemoteAudioStillUsesMediaLoading() throws {
        XCTAssertNoThrow(try HifzComposition.requireReadableLocalAudio(XCTUnwrap(URL(string: "https://example.invalid/recitation.mp3"))))
    }
}
