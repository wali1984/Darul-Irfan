import Foundation
import XCTest
@testable import DarulIrfan

@MainActor
final class HifzAudioSourceTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hifz-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func response(_ url: URL, status: Int = 200, type: String = "audio/mpeg") throws -> URLResponse {
        try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": type]))
    }

    func testRemotePreparationReturnsCompleteLocalFileAndReusesIt() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = try XCTUnwrap(URL(string: "https://example.invalid/surah.mp3"))
        let temporary = root.appendingPathComponent("transfer")
        try Data([1, 2, 3]).write(to: temporary)
        var calls = 0
        let fetch: (URL) async throws -> (URL, URLResponse) = { url in
            calls += 1
            return (temporary, try self.response(url))
        }
        let cache = root.appendingPathComponent("cache")
        let local = try await HifzAudioSource.localURL(for: remote, directory: cache, download: fetch)
        XCTAssertTrue(local.isFileURL)
        XCTAssertEqual(try Data(contentsOf: local), Data([1, 2, 3]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
        let reused = try await HifzAudioSource.localURL(for: remote, directory: cache, download: fetch)
        XCTAssertEqual(reused, local)
        XCTAssertEqual(calls, 1)
        // A zero-byte cache left by an older failure must not defeat Retry.
        try Data().write(to: local)
        try Data([4, 5]).write(to: temporary)
        let repaired = try await HifzAudioSource.localURL(for: remote, directory: cache, download: fetch)
        XCTAssertEqual(try Data(contentsOf: repaired), Data([4, 5]))
        XCTAssertEqual(calls, 2)
    }

    func testHTTPErrorAndHTMLNeverBecomeCachedAudio() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = try XCTUnwrap(URL(string: "https://example.invalid/surah.mp3"))
        for (status, mime) in [(503, "audio/mpeg"), (200, "text/html")] {
            let temporary = root.appendingPathComponent(UUID().uuidString)
            try Data("server error".utf8).write(to: temporary)
            do {
                _ = try await HifzAudioSource.localURL(for: remote, directory: root.appendingPathComponent("cache")) {
                    (temporary, try self.response($0, status: status, type: mime))
                }
                XCTFail("Invalid response must not become a composition source")
            } catch HifzAudioSource.Failure.invalidResponse { }
            XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("cache").path))
    }

    func testCancellationAfterDownloadDoesNotPublishCache() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = try XCTUnwrap(URL(string: "https://example.invalid/surah.mp3"))
        let temporary = root.appendingPathComponent("transfer")
        try Data([1]).write(to: temporary)
        let cache = root.appendingPathComponent("cache")
        let task = Task { @MainActor in
            try await HifzAudioSource.localURL(for: remote, directory: cache) { url in
                withUnsafeCurrentTask { $0?.cancel() }
                return (temporary, try self.response(url))
            }
        }
        do { _ = try await task.value; XCTFail("Cancelled preparation must not succeed") }
        catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    }

    func testDiscardedCopyIsDownloadedAgain() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = try XCTUnwrap(URL(string: "https://example.invalid/surah.mp3"))
        let temporary = root.appendingPathComponent("transfer")
        var calls = 0
        let fetch: (URL) async throws -> (URL, URLResponse) = { url in
            calls += 1
            try Data([UInt8(calls)]).write(to: temporary)
            return (temporary, try self.response(url))
        }
        let cache = root.appendingPathComponent("cache")
        _ = try await HifzAudioSource.localURL(for: remote, directory: cache, download: fetch)
        HifzAudioSource.discardCachedCopy(for: remote, directory: cache)
        let repaired = try await HifzAudioSource.localURL(for: remote, directory: cache, download: fetch)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(try Data(contentsOf: repaired), Data([2]))
    }

    func testDiscardNeverRemovesAudioKeptAtItsOwnAddress() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appendingPathComponent("audio.mp3")
        try Data([1]).write(to: local)
        HifzAudioSource.discardCachedCopy(for: local, directory: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: local.path))
    }

    func testStorageSummaryCountsAndClearRemovesKeptRecordings() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("one.mp3"))
        try Data([4]).write(to: root.appendingPathComponent("two.mp3"))
        let summary = HifzAudioSource.cacheSummary(directory: root)
        XCTAssertEqual(summary.bytes, 4)
        XCTAssertEqual(summary.files, 2)
        XCTAssertEqual(HifzAudioSource.clearCache(directory: root), 0)
        XCTAssertEqual(HifzAudioSource.cacheSummary(directory: root).files, 0)
        let missing = root.appendingPathComponent("never-created")
        XCTAssertEqual(HifzAudioSource.clearCache(directory: missing), 0)
        XCTAssertEqual(HifzAudioSource.cacheSummary(directory: missing).bytes, 0)
    }

    func testLocalFixtureDoesNotDownload() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appendingPathComponent("audio.wav")
        try Data([1]).write(to: local)
        let result = try await HifzAudioSource.localURL(for: local) { _ in
            XCTFail("Local audio must not start a network request")
            throw URLError(.badURL)
        }
        XCTAssertEqual(result, local)
    }
}
