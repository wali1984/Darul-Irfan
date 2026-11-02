import XCTest
@testable import DarulIrfan

final class RecitationPracticeFilesTests: XCTestCase {
    @MainActor
    func testFailedReplacementAndStaleCompletionPreserveAcceptedClip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try RecitationPracticeFiles(cacheDirectory: root)
        let first = try files.begin()
        try Data([1, 2, 3]).write(to: first)
        try files.accept(first, decodedDuration: 1)
        let failed = try files.begin()
        XCTAssertThrowsError(try files.accept(failed, decodedDuration: 1))
        XCTAssertEqual(files.current, first)
        XCTAssertEqual(try Data(contentsOf: first), Data([1, 2, 3]))
        let replacement = try files.begin()
        try Data([4]).write(to: replacement)
        XCTAssertThrowsError(try files.accept(failed, decodedDuration: 1))
        XCTAssertThrowsError(try files.accept(replacement, decodedDuration: .nan))
        XCTAssertEqual(files.current, first)
        try files.accept(replacement, decodedDuration: 2)
        XCTAssertEqual(files.current, replacement)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        try files.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: replacement.path))
        XCTAssertThrowsError(try files.begin())
        XCTAssertThrowsError(try files.accept(replacement, decodedDuration: 2))
    }

    @MainActor
    func testForeignClipAndOversizeNeverReplaceOrDeleteCurrent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try RecitationPracticeFiles(cacheDirectory: root)
        let outside = root.appendingPathComponent("unrelated.m4a")
        try Data([9]).write(to: outside)
        XCTAssertThrowsError(try files.accept(outside, decodedDuration: 1))
        let oversized = try files.begin()
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(RecitationPracticeFiles.maximumBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try files.accept(oversized, decodedDuration: 1))
        try files.close()
        XCTAssertEqual(try Data(contentsOf: outside), Data([9]))
        XCTAssertNil(files.current)
    }
}
