import XCTest
@testable import DarulIrfan

final class NativeChatAttachmentTests: XCTestCase {
    func testCopySurvivesOriginalRemovalAndDiscardRemovesOnlyCopy() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("picked-\(UUID().uuidString).png")
        let bytes = Data([1, 2, 3, 4])
        try bytes.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let prepared = try NativeChatAttachment.prepare(source)
        defer { prepared.discard() }
        XCTAssertNotEqual(prepared.url, source)
        XCTAssertEqual(prepared.name, source.lastPathComponent)
        XCTAssertEqual(prepared.bytes, bytes.count)
        XCTAssertTrue(prepared.isImage)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: prepared.url), bytes)
        prepared.discard()
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.url.path))
    }

    func testMissingAndEmptyFilesAreRejected() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: source) }
        XCTAssertThrowsError(try NativeChatAttachment.prepare(source))
        try Data().write(to: source)
        XCTAssertThrowsError(try NativeChatAttachment.prepare(source))
    }
}
