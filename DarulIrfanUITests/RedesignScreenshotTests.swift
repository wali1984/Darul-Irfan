import XCTest

/// Screenshots of the redesigned screens, for checking against the boards
/// (parity-spec/redesign/boards) before a release: every tab, the Prayer times
/// page, the readers' sections, Discover's four sections and Halqah, in
/// English and Urdu, light and dark.
///
/// Runs only when the test runner is given DI_SCREENSHOTS=1, as Codemagic's
/// ios-screens workflow does (TEST_RUNNER_DI_SCREENSHOTS); the ordinary UI
/// test run skips it. DI_SCREENSHOTS=books takes only Read's books, and
/// DI_SCREENSHOTS=shajra only the Shajra. It asserts nothing: a step whose
/// button is missing is skipped, and whatever is on screen is still kept.
final class RedesignScreenshotTests: XCTestCase {

    /// The labels the tour taps, in each language (Localizable.xcstrings).
    private static let labels: [String: [String: String]] = [
        "en": [
            "Quran": "Quran", "Hadith": "Hadith", "Books": "Books",
            "Bayans": "Bayans", "Updates": "Updates", "Events": "Events", "Topics": "Topics",
            "All times and alerts": "All times and alerts", "Done": "Done",
            "Read in App": "Read in App", "Notifications": "Notifications", "Booklets": "Booklets",
            "Pages": "Pages", "Text": "Text", "Keep reading": "Keep reading",
            "Chain of Transmission": "Chain of Transmission", "Shajra": "Shajra",
        ],
        "ur": [
            "Quran": "قرآن", "Hadith": "حدیث", "Books": "کتابیں",
            "Bayans": "بیانات", "Updates": "تازہ معلومات", "Events": "تقریبات", "Topics": "موضوعات",
            "All times and alerts": "تمام اوقات اور الرٹس", "Done": "ہو گیا",
            "Read in App": "ایپ میں پڑھیں", "Notifications": "اطلاعات", "Booklets": "کتابچے",
            "Pages": "صفحات", "Text": "متن", "Keep reading": "پڑھنا جاری رکھیں",
            "Chain of Transmission": "شجرہ مبارک", "Shajra": "شجرہ",
        ],
    ]

    private var app: XCUIApplication!
    private var language = "en"
    private var prefix = ""

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ["1", "books", "shajra"].contains(ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] ?? ""),
            "Screenshots run only in the ios-screens workflow"
        )
        continueAfterFailure = true
    }

    /// Runs first (tests run in name order): a fresh simulator imports the
    /// bundled content on its first launch, which can take minutes, so the
    /// tours that follow find the tab bar at once.
    func test0Warmup() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-complete-onboarding"]
        app.launch()
        _ = app.tabBars.buttons.firstMatch.waitForExistence(timeout: 600)
        pause(5)
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
        guard app.tabBars.buttons.firstMatch.waitForExistence(timeout: 180) else {
            shot("no-tab-bar")
            return
        }
        pause(6)
        closePopup()

        // DI_SCREENSHOTS=books: the Books section, a book page and the reader only.
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "books" {
            selectTab(1)
            pause(3)
            booksTour()
            return
        }

        // DI_SCREENSHOTS=shajra: the Shajra only.
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "shajra" {
            shajraTour()
            return
        }

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
        // The switch sits at the top of each reader's page.
        scrollToTop()
        if tap(button("Hadith")) {
            pause(3)
            shot("read-hadith")
            scrollShots("read-hadith", count: 1)
            scrollToTop()
        }
        booksTour()

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

        // The Shajra, from the Zikr tab and from Halqah.
        shajraTour()
    }

    /// Read › Books, a shelf, a book page, and the reader in both modes.
    private func booksTour() {
        scrollToTop()
        guard tap(button("Books")) else {
            shot("no-books-switch")
            return
        }
        pause(3)
        shot("read-books")
        scrollShots("read-books", count: 2)
        scrollToTop()
        if tap(onScreen(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label("Booklets"))))) {
            pause(3)
            shot("books-shelf")
            tapFirstCard()
            pause(4)
            shot("book-page")
            // No check for the shelf here: the book page's back button is
            // labelled Booklets too.
            scrollShots("book-page", count: 1)
            scrollToTop()
            let read = onScreen(app.buttons.matching(NSPredicate(
                format: "label BEGINSWITH %@ OR label BEGINSWITH %@", label("Read in App"), label("Keep reading")
            )))
            // The gold button, or where it sits when it is not exposed as a button.
            if !tap(read) {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).tap()
            }
            do {
                pause(5)
                shot("book-reader")
                if tap(button("Text")) {
                    pause(3)
                    shot("book-reader-text")
                }
                goBack()
            }
            goBack()
            goBack()
        }
        // Leave Read on the Quran, as a fresh install opens it.
        scrollToTop()
        _ = tap(button("Quran"))
    }

    /// The Shajra: the Zikr tab's button under the ayah, the chain it opens
    /// (the top and three screens down), then Halqah › Silsila's Shajra
    /// row, which opens the same page.
    private func shajraTour() {
        selectTab(2)
        pause(4)
        scrollToTop()
        let shajraButton = onScreen(app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", label("Chain of Transmission")
        )))
        shot("zikr-shajra-button")
        if tap(shajraButton) {
            // The chain takes about three seconds to arrive.
            pause(4)
            shot("shajra")
            scrollShots("shajra", count: 3)
            goBack()
        } else {
            shot("no-shajra-button")
        }

        selectTab(4)
        pause(3)
        scrollToTop()
        // The row sits under the brand header and My Halqahs: scroll to it.
        var opened = tap(button("Shajra"))
        var swipes = 0
        while !opened && swipes < 4 {
            app.swipeUp()
            pause(1)
            opened = tap(button("Shajra"))
            swipes += 1
        }
        if opened {
            pause(4)
            shot("shajra-from-halqah")
            goBack()
        } else {
            shot("no-shajra-row")
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
        onScreen(app.buttons.matching(NSPredicate(format: "label == %@", label(key))))
    }

    /// The first of the matches that can be tapped: Read keeps each reader it
    /// has opened, hidden, with its own copy of the switch.
    private func onScreen(_ matches: XCUIElementQuery) -> XCUIElement {
        _ = matches.firstMatch.waitForExistence(timeout: 6)
        for index in 0..<matches.count {
            let element = matches.element(boundBy: index)
            if element.isHittable { return element }
        }
        return matches.firstMatch
    }

    /// Taps it if it turns up; false when it never did.
    private func tap(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 6), element.isHittable else { return false }
        element.tap()
        return true
    }

    /// The shelf's first card, by where it sits (the cards are not exposed as
    /// list cells).
    private func tapFirstCard() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.22)).tap()
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
