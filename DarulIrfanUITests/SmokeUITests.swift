import XCTest

/// Launch smoke tests.
///
/// Assumptions (verified against the app source):
/// - The app has NO test-only launch arguments (DarulIrfanApp.swift reads
///   none), so onboarding cannot be skipped via configuration. Onboarding
///   completion is persisted in the app's database, so on a fresh install the
///   first launch shows onboarding and later launches show the tab bar.
/// - Completing onboarding requires selecting a place on the location step
///   (device fix or geocoded city search), which needs simulator location
///   and/or network. When that cannot be satisfied, the walk-through test
///   skips rather than reporting a false failure; the launch test still
///   verifies the app comes up with a meaningful first screen.
final class SmokeUITests: XCTestCase {

    private let tabLabels = ["Prayer", "Quran", "Library", "Media", "More"]

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Launch

    /// The app must reach one of its two valid first screens: the onboarding
    /// welcome step (fresh install) or the five-tab shell (returning user).
    func testLaunchShowsOnboardingOrTabShell() {
        let app = XCUIApplication()
        app.launch()

        let prayerTab = app.tabBars.buttons["Prayer"]
        let getStarted = app.buttons["Get Started"]

        // Launch work is async (database open + bootstrap): give the first
        // real screen a generous-but-bounded window to appear.
        let deadline = Date().addingTimeInterval(20)
        var sawValidScreen = false
        while Date() < deadline {
            if prayerTab.exists || getStarted.exists {
                sawValidScreen = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        XCTAssertTrue(
            sawValidScreen,
            "Expected either the onboarding welcome step or the tab bar after launch"
        )

        if prayerTab.exists {
            assertAllTabsExist(in: app)
        }
    }

    // MARK: - Tab bar

    /// Verifies all five tabs exist and are tappable. If the install is fresh
    /// it first walks onboarding defensively; when onboarding cannot be
    /// completed in this environment (no location/network), the test skips.
    func testTabBarButtonsExistAndSwitchTabs() throws {
        let app = XCUIApplication()
        app.launch()

        let prayerTab = app.tabBars.buttons["Prayer"]
        if !prayerTab.waitForExistence(timeout: 20) {
            try walkOnboarding(app: app)
            try XCTSkipIf(
                !prayerTab.waitForExistence(timeout: 15),
                "Onboarding could not be completed in this environment (location step needs a device fix or network geocoding); skipping tab assertions"
            )
        }

        assertAllTabsExist(in: app)

        for label in tabLabels {
            let button = app.tabBars.buttons[label]
            button.tap()
            XCTAssertTrue(button.isSelected, "Tapping the \(label) tab should select it")
        }
    }

    // MARK: - Onboarding walk-through (defensive)

    /// Advances through onboarding by tapping only buttons that exist:
    /// welcome → language → location → calculation → notifications → finish.
    /// Never asserts mid-flow; the caller decides whether reaching the tab
    /// bar was possible.
    private func walkOnboarding(app: XCUIApplication) throws {
        // System permission alerts (location, notifications) are owned by
        // springboard, not the app.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        func dismissSystemAlertIfPresent() {
            let allowLabels = ["Allow While Using App", "Allow Once", "Allow"]
            for label in allowLabels {
                let button = springboard.buttons[label]
                if button.waitForExistence(timeout: 2) {
                    button.tap()
                    return
                }
            }
        }

        func tapIfPresent(_ button: XCUIElement, timeout: TimeInterval = 5) -> Bool {
            guard button.waitForExistence(timeout: timeout), button.isEnabled else {
                return false
            }
            button.tap()
            return true
        }

        // Step 1: welcome.
        _ = tapIfPresent(app.buttons["Get Started"], timeout: 10)

        // Step 2: language — Continue is always enabled here.
        _ = tapIfPresent(app.buttons["Continue"])

        // Step 3: location — Continue stays disabled until a place is chosen.
        let useMyLocation = app.buttons["Use My Location"]
        if useMyLocation.waitForExistence(timeout: 5) {
            useMyLocation.tap()
            dismissSystemAlertIfPresent()
        }

        // Wait (bounded) for the place to resolve and Continue to enable.
        let continueButton = app.buttons["Continue"]
        let locationDeadline = Date().addingTimeInterval(25)
        while Date() < locationDeadline {
            if continueButton.exists && continueButton.isEnabled && continueButton.isHittable {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        guard continueButton.exists && continueButton.isEnabled else {
            // No location fix available here — the caller will skip.
            return
        }
        continueButton.tap()

        // Step 4: calculation.
        _ = tapIfPresent(app.buttons["Continue"], timeout: 10)

        // Step 5: notifications (may raise the notification permission alert
        // if the step requests it; dismiss defensively either way).
        dismissSystemAlertIfPresent()
        _ = tapIfPresent(app.buttons["Continue"], timeout: 10)
        dismissSystemAlertIfPresent()

        // Step 6: finish.
        _ = tapIfPresent(app.buttons["Begin"], timeout: 10)
    }

    // MARK: - Shared assertions

    private func assertAllTabsExist(in app: XCUIApplication) {
        for label in tabLabels {
            XCTAssertTrue(
                app.tabBars.buttons[label].waitForExistence(timeout: 5),
                "Missing tab bar button: \(label)"
            )
        }
    }
}
