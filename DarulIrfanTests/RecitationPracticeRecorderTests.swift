import XCTest
@testable import DarulIrfan

final class RecitationPracticeRecorderTests: XCTestCase {
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
