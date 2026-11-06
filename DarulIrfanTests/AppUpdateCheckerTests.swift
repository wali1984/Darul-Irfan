import XCTest
@testable import DarulIrfan

/// Today's update banner offers a newer build than the one running: by build
/// number in TestFlight, by version in the App Store. Closed, it stays away
/// only until the app is opened again.
final class AppUpdateCheckerTests: XCTestCase {

    func testVersionsCompareByPart() {
        XCTAssertTrue(AppReleaseCheck.isNewer("1.12.0", than: "1.11.3"))
        XCTAssertTrue(AppReleaseCheck.isNewer("1.10", than: "1.9.9"))
        XCTAssertFalse(AppReleaseCheck.isNewer("1.11.1", than: "1.11.1"))
        XCTAssertFalse(AppReleaseCheck.isNewer("1.11", than: "1.11.0"))
        XCTAssertFalse(AppReleaseCheck.isNewer("1.9", than: "1.10"))
    }

    /// The server's reply exactly as testflight.py announce writes it.
    func testTestFlightOffersOnlyALaterBuild() throws {
        let json = #"{"ios":{"testflight":{"version":"1.11.1","build":69,"releasedAt":"2026-11-02T10:00:00Z"}}}"#
        let published = try JSONDecoder().decode(PublishedReleases.self, from: Data(json.utf8))
        let latest = try XCTUnwrap(published.ios?.testflight)
        let offer = try XCTUnwrap(AppReleaseCheck.newerTestFlight(latest, thanBuild: 68))
        XCTAssertEqual(offer.channel, .testFlight)
        XCTAssertEqual(offer.version, "1.11.1")
        XCTAssertEqual(offer.build, 69)
        XCTAssertEqual(offer.url.scheme, "itms-beta")
        XCTAssertNil(AppReleaseCheck.newerTestFlight(latest, thanBuild: 69))
        XCTAssertNil(AppReleaseCheck.newerTestFlight(latest, thanBuild: 70))
    }

    /// Owner 2026-11-06: the banner stopped on the internal-only builds. An
    /// internal tester (on a build later than the external one) is offered
    /// the internal build; an external tester never is.
    func testInternalTestersAreOfferedTheirNewerBuild() throws {
        let json = #"{"ios":{"testflight":{"version":"1.11.1","build":91},"internal":{"version":"1.11.1","build":99}}}"#
        let published = try XCTUnwrap(try JSONDecoder().decode(PublishedReleases.self, from: Data(json.utf8)).ios)
        XCTAssertEqual(AppReleaseCheck.newerTestFlight(published, thanBuild: 97)?.build, 99)
        XCTAssertNil(AppReleaseCheck.newerTestFlight(published, thanBuild: 99))
        // External testers on 91 or older see only the external build.
        XCTAssertNil(AppReleaseCheck.newerTestFlight(published, thanBuild: 91))
        XCTAssertEqual(AppReleaseCheck.newerTestFlight(published, thanBuild: 90)?.build, 91)
        // A feed written before the internal entry existed still works.
        let old = try XCTUnwrap(try JSONDecoder().decode(PublishedReleases.self, from: Data(#"{"ios":{"testflight":{"version":"1.11.1","build":91}}}"#.utf8)).ios)
        XCTAssertEqual(AppReleaseCheck.newerTestFlight(old, thanBuild: 89)?.build, 91)
        XCTAssertNil(AppReleaseCheck.newerTestFlight(old, thanBuild: 97))
    }

    func testNothingAnnouncedYetMeansNoBanner() throws {
        let published = try JSONDecoder().decode(PublishedReleases.self, from: Data("{}".utf8))
        XCTAssertNil(published.ios?.testflight)
    }

    @MainActor
    func testClosedBannerReturnsWhenTheAppIsOpenedAgain() async {
        let release = AppRelease(channel: .testFlight, version: "1.11.1", build: 69, url: AppReleaseCheck.testFlightURL)
        let checker = AppUpdateChecker(check: { release })
        await checker.refresh()
        XCTAssertEqual(checker.banner, release)

        checker.dismiss()
        XCTAssertNil(checker.banner)
        // Back from Control Centre or a notification: still closed.
        checker.appBecameActive()
        XCTAssertNil(checker.banner)
        // Opened again from the background: shown again.
        checker.appEnteredBackground()
        checker.appBecameActive()
        XCTAssertEqual(checker.banner, release)
    }

    @MainActor
    func testACurrentBuildShowsNoBanner() async {
        let checker = AppUpdateChecker(check: { nil })
        await checker.refresh()
        XCTAssertNil(checker.banner)
    }
}
