import XCTest
@testable import DarulIrfan

final class RecitationPracticeRecorderTests: XCTestCase {
    @MainActor
    func testNewHalqahInvalidatesPendingPermission() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = try RecitationPracticeRecorder(cacheDirectory: root, audioReserved: { false })
        defer { recorder.close() }
        var answer: (@MainActor (Bool) -> Void)?
        recorder.start(permission: { answer = $0 }, prepareAudio: { _ in XCTFail("Retired request handed off audio") }, allowedNow: { true })
        RecitationPracticeRecorder.yieldToHalqah()
        answer?(true)
        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertFalse(recorder.hasClip)
    }

    @MainActor
    func testHalqahOwnershipDuringPermissionPreventsAudioHandoff() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var reserved = false
        let recorder = try RecitationPracticeRecorder(cacheDirectory: root, audioReserved: { reserved })
        defer { recorder.close() }
        var answer: (@MainActor (Bool) -> Void)?
        recorder.start(permission: { answer = $0 }, prepareAudio: { _ in XCTFail("Halqah audio must remain owned") }, allowedNow: { true })
        reserved = true
        answer?(true)
        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertEqual(recorder.failure, .audio)
        recorder.start(permission: { _ in XCTFail("Reserved audio must not request permission") }, prepareAudio: { _ in XCTFail("Reserved audio must not hand off") }, allowedNow: { true })
        XCTAssertEqual(recorder.phase, .idle)
    }

    @MainActor
    func testPermissionGrantedAfterSuspendNeverRequestsAudioOrRecords() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = try RecitationPracticeRecorder(cacheDirectory: root)
        defer { recorder.close() }
        var answer: (@MainActor (Bool) -> Void)?
        var audioRequested = false
        recorder.start(permission: { answer = $0 }, prepareAudio: { _ in audioRequested = true }, allowedNow: { true })
        XCTAssertEqual(recorder.phase, .preparing)
        recorder.suspend()
        answer?(true)
        XCTAssertFalse(audioRequested)
        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertFalse(recorder.hasClip)
    }

    @MainActor
    func testPermissionWaitsBrieflyWhileThePromptIsClosing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = try RecitationPracticeRecorder(cacheDirectory: root, audioReserved: { false })
        defer { recorder.close() }
        var allowed = true
        var answer: (@MainActor (Bool) -> Void)?
        var audioRequested = false
        recorder.start(permission: { answer = $0 }, prepareAudio: { _ in audioRequested = true }, allowedNow: { allowed })
        allowed = false
        answer?(true)
        XCTAssertEqual(recorder.phase, .preparing)
        XCTAssertNil(recorder.failure)
        XCTAssertFalse(audioRequested)
        allowed = true
        let deadline = Date().addingTimeInterval(2)
        while !audioRequested && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(audioRequested)
    }

    @MainActor
    func testLateAudioHandoffCannotReopenClosedRecorder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = try RecitationPracticeRecorder(cacheDirectory: root)
        var ready: (@MainActor (Bool) -> Void)?
        recorder.start(permission: { $0(true) }, prepareAudio: { ready = $0 }, allowedNow: { true })
        XCTAssertNotNil(ready)
        recorder.close()
        ready?(true)
        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertFalse(recorder.hasClip)
        var askedAgain = false
        recorder.start(permission: { _ in askedAgain = true }, prepareAudio: { _ in XCTFail("Closed recorder requested audio") }, allowedNow: { true })
        XCTAssertFalse(askedAgain)
    }
}
