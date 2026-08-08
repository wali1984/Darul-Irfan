import XCTest

/// Launch smoke tests.
///
/// Assumptions (verified against the app source):
/// DEBUG-only launch arguments provide deterministic onboarding and completed
/// states without requesting simulator location or notification permissions.
final class SmokeUITests: XCTestCase {

    /// Exactly five, and no more: iPhone folds anything past the fifth into a
    /// system "More" list, which is how Explore stopped being a tab button when
    /// Hadith was briefly given a sixth tab. Quran and Hadith now sit together
    /// under Read.
    private let tabLabels = ["Today", "Read", "Zikr", "Explore", "More"]

    override func setUp() {
        continueAfterFailure = false
    }

    /// The assertions match English UI strings; pin the app run to English so
    /// the suite passes on simulators whose language is Urdu.
    private func makeApp(completedOnboarding: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchArguments.append(completedOnboarding ? "--uitesting-complete-onboarding" : "--uitesting-reset-onboarding")
        return app
    }

    // MARK: - Launch

    /// A fresh install must show the contextual onboarding welcome screen.
    func testFreshLaunchShowsOnboarding() {
        let app = makeApp(completedOnboarding: false)
        app.launch()
        let getStarted = app.buttons["Get Started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 20), "Expected onboarding on a fresh launch")
    }

    // MARK: - Tab bar

    /// Verifies all five tabs exist and are tappable. If the install is fresh
    /// it first walks onboarding defensively; when onboarding cannot be
    /// completed in this environment (no location/network), the test skips.
    func testTabBarButtonsExistAndSwitchTabs() {
        let app = makeApp()
        app.launch()

        let prayerTab = app.tabBars.buttons["Today"]
        XCTAssertTrue(prayerTab.waitForExistence(timeout: 20), "Expected the completed five-tab shell")

        assertAllTabsExist(in: app)

        // No system-generated overflow tab: its presence would mean a real tab
        // had been pushed off the bar.
        XCTAssertEqual(app.tabBars.buttons.count, tabLabels.count,
                       "Expected exactly \(tabLabels.count) tabs with no iOS overflow tab")

        for label in tabLabels {
            let button = app.tabBars.buttons[label]
            button.tap()
            XCTAssertTrue(button.isSelected, "Tapping the \(label) tab should select it")
        }
    }

    /// Read must offer both readers as equals: Hadith cannot be buried inside
    /// the Quran, nor reachable only through it.
    func testReadTabOffersQuranAndHadithAsEqualDestinations() {
        let app = makeApp()
        app.launch()

        let readTab = app.tabBars.buttons["Read"]
        XCTAssertTrue(readTab.waitForExistence(timeout: 20), "Expected a Read tab")
        readTab.tap()

        // Launching with a --uitesting argument clears the remembered reader,
        // so Read always opens on its two cards here.
        let quran = app.buttons["read.destination.quran"]
        let hadith = app.buttons["read.destination.hadith"]
        XCTAssertTrue(quran.waitForExistence(timeout: 10), "Read must offer Quran")
        XCTAssertTrue(hadith.waitForExistence(timeout: 10), "Read must offer Hadith")

        // Opening one must not hide the other: the switch keeps both reachable.
        hadith.tap()
        XCTAssertTrue(
            app.navigationBars.buttons["Show both readers"].waitForExistence(timeout: 10),
            "Entering a reader should keep a way back to both"
        )
    }

    /// Launches under an RTL locale and ensures the app reaches a usable root.
    /// Exact Urdu copy is intentionally not asserted so translation edits do
    /// not make this layout smoke test brittle.
    func testUrduRTLLaunchSmoke() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ur)", "-AppleLocale", "ur_PK", "--uitesting-complete-onboarding"]
        app.launch()
        let hasTabBar = app.tabBars.firstMatch.waitForExistence(timeout: 20)
        let hasOnboarding = app.buttons.count > 0 || app.scrollViews.count > 0
        XCTAssertTrue(hasTabBar || hasOnboarding, "Expected a usable tab shell or onboarding screen in Urdu RTL")
    }

    // MARK: - Onboarding walk-through (defensive)

    /// Advances through onboarding by tapping only buttons that exist:
    /// welcome â†’ language â†’ location â†’ calculation â†’ notifications â†’ finish.
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

        // Step 2: language â€” Continue is always enabled here.
        _ = tapIfPresent(app.buttons["Continue"])

        // Step 3: location â€” Continue stays disabled until a place is chosen.
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
            // No location fix available here â€” the caller will skip.
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
