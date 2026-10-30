import XCTest

/// Screenshots of the redesigned screens, for checking against the boards
/// (parity-spec/redesign/boards) before a release: every tab, the Prayer times
/// page, the readers' sections, Discover's four sections and Halqah, in
/// English and Urdu, light and dark.
///
/// Runs only when the test runner is given DI_SCREENSHOTS=1, as Codemagic's
/// ios-screens workflow does (TEST_RUNNER_DI_SCREENSHOTS); the ordinary UI
/// test run skips it. It asserts nothing: a step whose button is missing is
/// skipped, and whatever is on screen is still kept.
final class RedesignScreenshotTests: XCTestCase {

    /// The labels the tour taps, in each language (Localizable.xcstrings).
    private static let labels: [String: [String: String]] = [
        "en": [
            "Quran": "Quran", "Hadith": "Hadith", "Books": "Books",
            "Bayans": "Bayans", "Updates": "Updates", "Events": "Events", "Topics": "Topics",
            "All times and alerts": "All times and alerts", "Done": "Done",
            "Read in App": "Read in App", "Notifications": "Notifications", "Booklets": "Booklets",
        ],
        "ur": [
            "Quran": "قرآن", "Hadith": "حدیث", "Books": "کتابیں",
            "Bayans": "بیانات", "Updates": "تازہ معلومات", "Events": "تقریبات", "Topics": "موضوعات",
            "All times and alerts": "تمام اوقات اور الرٹس", "Done": "ہو گیا",
            "Read in App": "ایپ میں پڑھیں", "Notifications": "اطلاعات", "Booklets": "کتابچے",
        ],
    ]

    private var app: XCUIApplication!
    private var language = "en"
    private var prefix = ""

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "1",
            "Screenshots run only in the ios-screens workflow"
        )
        continueAfterFailure = true
    }

    func testEnglishLight() { tour(language: "en", locale: "en_US", dark: false) }
    func testEnglishDark() { tour(language: "en", locale: "en_US", dark: true) }
    func testUrduLight() { tour(language: "ur", locale: "ur_PK", dark: false) }
    func testUrduDark() { tour(language: "ur", locale: "ur_PK", dark: true) }

    // MARK: - The tour

    private func tour(language: String, locale: String, dark: Bool) {
        self.language = language
        prefix = "\(language)-\(dark ? "dark" : "light")"
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))", "-AppleLocale", locale,
            "--uitesting-complete-onboarding", dark ? "--uitesting-theme-dark" : "--uitesting-theme-light",
        ]
        app.launch()
        guard app.tabBars.buttons.firstMatch.waitForExistence(timeout: 40) else {
            shot("no-tab-bar")
            return
        }
        pause(6)
        closePopup()

        // Today, then the Prayer times page it opens.
        selectTab(0)
        shot("today")
        scrollShots("today", count: 3)
        scrollToTop()
        if tap(button("All times and alerts")) {
            pause(3)
            shot("prayer-times")
            scrollShots("prayer-times", count: 2)
            goBack()
        }

        // Read: the Quran, Hadith and Books sections, a shelf, a book page and the reader.
        selectTab(1)
        pause(3)
        shot("read-quran")
        scrollShots("read-quran", count: 1)
        if tap(button("Hadith")) {
            pause(3)
            shot("read-hadith")
            scrollShots("read-hadith", count: 1)
        }
        if tap(button("Books")) {
            pause(3)
            shot("read-books")
            scrollShots("read-books", count: 1)
            scrollToTop()
            if tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label("Booklets"))).firstMatch) {
                pause(3)
                shot("books-shelf")
                if tap(firstListItem()) {
                    pause(3)
                    shot("book-page")
                    scrollShots("book-page", count: 1)
                    scrollToTop()
                    if tap(button("Read in App")) {
                        pause(5)
                        shot("book-reader")
                        goBack()
                    }
                    goBack()
                }
                goBack()
            }
            // Leave Read on the Quran, as a fresh install opens it.
            _ = tap(button("Quran"))
        }

        // Zikr.
        selectTab(2)
        pause(4)
        shot("zikr")
        scrollShots("zikr", count: 3)

        // Discover: each section, ending on Bayans, its first.
        selectTab(3)
        pause(4)
        shot("discover-bayans")
        scrollShots("discover-bayans", count: 1)
        for section in ["Updates", "Events", "Topics"] {
            scrollToTop()
            if tap(button(section)) {
                pause(4)
                shot("discover-\(section.lowercased())")
                scrollShots("discover-\(section.lowercased())", count: 1)
            }
        }
        scrollToTop()
        _ = tap(button("Bayans"))

        // Halqah, and its one Notifications screen.
        selectTab(4)
        pause(4)
        shot("halqah")
        scrollShots("halqah", count: 3)
        if tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label("Notifications"))).firstMatch) {
            pause(3)
            shot("notifications")
            scrollShots("notifications", count: 2)
            goBack()
        }
    }

    // MARK: - Steps

    private var shotNumber = 0

    /// Keeps what is on screen, named so the files sort in tour order.
    private func shot(_ name: String) {
        shotNumber += 1
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = String(format: "%@-%03ld-%@", prefix, shotNumber, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Scrolls down a screen at a time, keeping each.
    private func scrollShots(_ name: String, count: Int) {
        for index in 1...count {
            app.swipeUp()
            pause(1.5)
            shot("\(name)-\(index + 1)")
        }
    }

    private func scrollToTop() {
        for _ in 0..<4 { app.swipeDown() }
        pause(1)
    }

    /// The tabs in their order: Today, Read, Zikr, Discover, Halqah.
    private func selectTab(_ index: Int) {
        let tab = app.tabBars.buttons.element(boundBy: index)
        if tab.exists { tab.tap() }
        pause(1)
    }

    private func label(_ key: String) -> String {
        Self.labels[language]?[key] ?? key
    }

    private func button(_ key: String) -> XCUIElement {
        app.buttons[label(key)].firstMatch
    }

    /// Taps it if it turns up; false when it never did.
    private func tap(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 6), element.isHittable else { return false }
        element.tap()
        return true
    }

    /// The first entry of the list on screen, below the navigation bar.
    private func firstListItem() -> XCUIElement {
        let candidates = [
            app.collectionViews.cells.firstMatch,
            app.tables.cells.firstMatch,
            app.scrollViews.firstMatch.buttons.element(boundBy: 0),
        ]
        return candidates.first(where: { $0.waitForExistence(timeout: 3) }) ?? candidates[0]
    }

    private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists, back.isHittable {
            back.tap()
        } else {
            app.swipeRight()
        }
        pause(1.5)
    }

    /// The day's picture opens over Today on launch when one is published.
    private func closePopup() {
        let done = app.buttons[label("Done")].firstMatch
        if done.waitForExistence(timeout: 3) {
            shot("daily-picture")
            done.tap()
            pause(1.5)
        }
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
