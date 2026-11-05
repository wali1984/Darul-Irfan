import AVFoundation
import CoreGraphics
import XCTest
@testable import DarulIrfan

/// The live stage run hands-free from Hazrat ji's voice (owner, 2026-11-04):
/// heard stages are never lost, recognition and the microphone come back by
/// themselves, and a Muraqaba added from the stage joins its buttons at once.
/// Everything here runs without a microphone.
final class ZikrStageAutomationTests: XCTestCase {
    private typealias Request = ZikrStageModel.StageRequest

    // MARK: - Heard stages wait their turn

    func testAStageHeardWhileAnotherIsOnItsWayWaits() {
        let waiting = ZikrStageModel.queue([], adding: Request(stageID: "latifa-1", fromVoice: true))
        XCTAssertEqual(waiting, [Request(stageID: "latifa-1", fromVoice: true)])
    }

    func testANewerVoiceDetectionReplacesAnOlderOneStillWaiting() {
        let waiting = [Request(stageID: "latifa-1", fromVoice: true)]
        let next = ZikrStageModel.queue(waiting, adding: Request(stageID: "latifa-2", fromVoice: true))
        XCTAssertEqual(next, [Request(stageID: "latifa-2", fromVoice: true)])
    }

    func testTapsKeepTheirOrderAndAreNeverReplacedByTheVoice() {
        var waiting = ZikrStageModel.queue([], adding: Request(stageID: "tasbih", fromVoice: false))
        waiting = ZikrStageModel.queue(waiting, adding: Request(stageID: "istighfar", fromVoice: false))
        waiting = ZikrStageModel.queue(waiting, adding: Request(stageID: "shahadah", fromVoice: true))
        XCTAssertEqual(waiting.map(\.stageID), ["tasbih", "istighfar", "shahadah"])
    }

    func testTheSameStageTwiceInARowIsAskedOnce() {
        let waiting = [Request(stageID: "raabta", fromVoice: false)]
        XCTAssertEqual(ZikrStageModel.queue(waiting, adding: Request(stageID: "raabta", fromVoice: false)), waiting)
    }

    // MARK: - Recognition starts again by itself

    func testOnlyTheLiveRecognitionRestartsWhenItEnds() {
        XCTAssertTrue(ZikrVoiceListener.restartsRecognition(endedGeneration: 4, currentGeneration: 4, isListening: true))
        // Replaced on purpose (the 50-second renewal) or stopped by the admin.
        XCTAssertFalse(ZikrVoiceListener.restartsRecognition(endedGeneration: 3, currentGeneration: 4, isListening: true))
        XCTAssertFalse(ZikrVoiceListener.restartsRecognition(endedGeneration: 4, currentGeneration: 4, isListening: false))
    }

    func testRestartsBackOffAfterSilentFailuresUpToHalfAMinute() {
        XCTAssertEqual(ZikrVoiceListener.restartDelay(quietEnds: 0), .milliseconds(500))
        XCTAssertEqual(ZikrVoiceListener.restartDelay(quietEnds: 1), .milliseconds(1_000))
        XCTAssertEqual(ZikrVoiceListener.restartDelay(quietEnds: 3), .milliseconds(4_000))
        XCTAssertEqual(ZikrVoiceListener.restartDelay(quietEnds: 50), .milliseconds(30_000))
    }

    func testTheWatchdogRestartsASilentOrStoppedMicrophone() {
        XCTAssertEqual(ZikrVoiceListener.watchdogAction(engineRunning: false, secondsSinceAudio: 1, secondsSinceBegin: 5, interrupted: false), .restartAudio)
        XCTAssertEqual(ZikrVoiceListener.watchdogAction(engineRunning: true, secondsSinceAudio: 9, secondsSinceBegin: 5, interrupted: false), .restartAudio)
        XCTAssertEqual(ZikrVoiceListener.watchdogAction(engineRunning: true, secondsSinceAudio: 0.1, secondsSinceBegin: 52, interrupted: false), .refreshRecognition)
        XCTAssertEqual(ZikrVoiceListener.watchdogAction(engineRunning: true, secondsSinceAudio: 0.1, secondsSinceBegin: 20, interrupted: false), WatchdogAction.none)
        // A phone call has the microphone: wait for it to end.
        XCTAssertEqual(ZikrVoiceListener.watchdogAction(engineRunning: false, secondsSinceAudio: 30, secondsSinceBegin: 90, interrupted: true), WatchdogAction.none)
    }

    private typealias WatchdogAction = ZikrVoiceListener.WatchdogAction

    // MARK: - Interruptions and route changes

    func testAnInterruptionPausesAndItsEndResumes() {
        let began: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        let ended: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue]
        XCTAssertEqual(ZikrVoiceListener.interruptionAction(began), .pause)
        XCTAssertEqual(ZikrVoiceListener.interruptionAction(ended), .resume)
        XCTAssertEqual(ZikrVoiceListener.interruptionAction(nil), .ignore)
    }

    func testAHeadsetComingOrGoingRestartsTheMicrophone() {
        func info(_ reason: AVAudioSession.RouteChangeReason) -> [AnyHashable: Any] {
            [AVAudioSessionRouteChangeReasonKey: reason.rawValue]
        }
        XCTAssertTrue(ZikrVoiceListener.recoversAfterRouteChange(info(.newDeviceAvailable)))
        XCTAssertTrue(ZikrVoiceListener.recoversAfterRouteChange(info(.oldDeviceUnavailable)))
        // The listener's own category setting must not restart it in a loop.
        XCTAssertFalse(ZikrVoiceListener.recoversAfterRouteChange(info(.categoryChange)))
        XCTAssertFalse(ZikrVoiceListener.recoversAfterRouteChange(nil))
    }

    // MARK: - What was heard

    func testTheSameCallOutHeardAgainSoonIsNotAnnouncedTwice() {
        let now = Date()
        XCTAssertTrue(ZikrVoiceListener.isRepeat("latifa-1", last: ("latifa-1", now.addingTimeInterval(-30)), now: now))
        XCTAssertFalse(ZikrVoiceListener.isRepeat("latifa-1", last: ("latifa-1", now.addingTimeInterval(-200)), now: now))
        XCTAssertFalse(ZikrVoiceListener.isRepeat("latifa-2", last: ("latifa-1", now.addingTimeInterval(-5)), now: now))
        XCTAssertFalse(ZikrVoiceListener.isRepeat("latifa-1", last: nil, now: now))
    }

    func testTheLiveIndicatorShowsTheLastFewWords() {
        XCTAssertEqual(ZikrVoiceListener.recentWords("اب سب لوگ توجہ کریں پہلا لطیفہ شروع کریں"), "توجہ کریں پہلا لطیفہ شروع کریں")
        XCTAssertEqual(ZikrVoiceListener.recentWords("  رابطہ  "), "رابطہ")
        XCTAssertEqual(ZikrVoiceListener.recentWords(""), "")
    }

    // MARK: - Adding a Muraqaba from the stage

    func testAMuraqabaAddedFromTheStageJoinsTheStagesAtOnce() {
        let stages = HalqaZikrStages(canBroadcast: true, stages: [
            HalqaZikrStage(id: "latifa-1", title: "Latifa 1", titleUr: nil, isCustom: false)
        ], recitations: [], presets: [])
        let added = HalqaZikrStage(id: "custom-abc", title: "Muraqaba Fana", titleUr: "مراقبہ فنا", isCustom: true)
        let after = ZikrStageModel.catalogue(stages, adding: added)
        XCTAssertEqual(after.stages.map(\.id), ["latifa-1", "custom-abc"])
        XCTAssertTrue(after.canBroadcast)
        // Already there (the server's list came back with it): not twice.
        XCTAssertEqual(ZikrStageModel.catalogue(after, adding: added).stages.count, 2)
    }

    // MARK: - Latifa 7 is a circle around the whole body

    func testLatifaSevenEnclosesTheWholeBodyAndPointsOneToSix() {
        let center = MethodLatifaDiagram.circleCenter
        let radius = MethodLatifaDiagram.circleRadius
        let insideBody = MethodLatifaDiagram.bodyPositions + MethodLatifaDiagram.bodyExtremes
        for point in insideBody {
            let mapped = MethodLatifaDiagram.onPicture(point)
            XCTAssertLessThan(hypot(mapped.x - center.x, mapped.y - center.y), radius, "\(point) must sit inside Latifa 7")
        }
        // The circle, and 7's number on its top edge, fit the picture.
        XCTAssertGreaterThanOrEqual(center.y - radius, 0.06)
        XCTAssertLessThanOrEqual(center.y + radius, 1)
        XCTAssertEqual(MethodLatifaDiagram.bodyPositions.count, 6)
    }

    func testLatifaOneToSixKeepTheirPlacesOnTheBody() {
        let expected: [CGPoint] = [CGPoint(x: 0.70, y: 0.77), CGPoint(x: 0.30, y: 0.77), CGPoint(x: 0.70, y: 0.53),
                                   CGPoint(x: 0.30, y: 0.53), CGPoint(x: 0.50, y: 0.65), CGPoint(x: 0.50, y: 0.24)]
        XCTAssertEqual(MethodLatifaDiagram.bodyPositions, expected)
    }

    // MARK: - Every Halqah has its stage (owner, 2026-11-04)

    func testOnlyOurSheikhsStageShowsHazratJisPhotograph() {
        let standard = URL(string: "https://i.ytimg.com/vi/abc/hqdefault.jpg")!
        let full = URL(string: "https://i.ytimg.com/vi/abc/maxresdefault.jpg")!
        XCTAssertEqual(HalqahStage.portraitURLs(groupID: "our-sheikh", pictureURL: standard, pictureHDURL: full), [full, standard])
        XCTAssertEqual(HalqahStage.portraitURLs(groupID: "our-sheikh", pictureURL: standard, pictureHDURL: nil), [standard])
        // Another Halqah shows the logo, even should the server send a picture.
        XCTAssertEqual(HalqahStage.portraitURLs(groupID: "usa", pictureURL: standard, pictureHDURL: full), [])
    }

    func testAPushNudgesOnlyTheStageOfItsOwnHalqah() {
        XCTAssertEqual(HalqahStage.groupID(fromPath: "groups/our-sheikh"), "our-sheikh")
        XCTAssertEqual(HalqahStage.groupID(fromPath: "/groups/usa"), "usa")
        XCTAssertEqual(HalqahStage.groupID(fromPath: "darulirfan://groups/uk-london?stage=1"), "uk-london")
        XCTAssertEqual(HalqahStage.groupID(fromPath: "groups/usa/"), "usa")
        XCTAssertNil(HalqahStage.groupID(fromPath: "live/official-live"))
        XCTAssertNil(HalqahStage.groupID(fromPath: "groups/"))
        XCTAssertNil(HalqahStage.groupID(fromPath: nil))
    }
}
