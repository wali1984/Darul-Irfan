import XCTest

/// Screenshots of the redesigned screens, for checking against the boards
/// (parity-spec/redesign/boards) before a release: every tab, the Prayer times
/// page, the readers' sections, Discover's four sections and Halqah, in
/// English and Urdu, light and dark.
///
/// Runs only when the test runner is given DI_SCREENSHOTS=1, as Codemagic's
/// ios-screens workflow does (TEST_RUNNER_DI_SCREENSHOTS); the ordinary UI
/// test run skips it. DI_SCREENSHOTS=books takes only Read's books, and
/// DI_SCREENSHOTS=shajra only the Shajra. Required routes and reading
/// endpoints assert their presence; screenshots remain available on failure.
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
            ["1", "books", "shajra", "today", "audit", "silsila", "practice", "pages", "settings", "companion", "companion-fixes", "timezone", "resources", "guide-recovery", "parahs", "reader-controls", "reader-audit", "reader-performance", "reader-position", "halqah-resources", "personal-history", "appearance-controls", "notification-choices", "tasbih-preset", "teaching-resources", "reading-controls", "audio-follow", "audio-transport", "halqah-history", "halqah-duas", "dua-race", "sheikh-stage", "pdf-controls", "halqah-schedule", "picture-refresh"].contains(ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] ?? ""),
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

    /// Static reading text need not accept a tap. Its complete bounds must be
    /// inside the app and above the tab bar, including on floating-tab systems.
    private func prayerFitsReadingArea(_ prayer: XCUIElement) -> Bool {
        guard prayer.exists else { return false }
        let frame = prayer.frame
        guard !frame.isEmpty, app.frame.contains(frame) else { return false }
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists && frame.maxY > tabBar.frame.minY - 8 { return false }
        let navigationBar = app.navigationBars.firstMatch
        return !navigationBar.exists || frame.minY >= navigationBar.frame.maxY
    }


    /// Tap all 30 real rows and inspect each visible reader destination and Back.
    /// Expected starts are the approved IndoPak division, not the current UI labels.
    private func parahTour(checkControls: Bool = false, allDestinations: Bool = false) {
        selectTab(1)
        guard tap(button("Quran")) else { XCTFail("Quran selector missing"); return }
        let parahWord = language == "ur" ? "پارہ" : "Parah"
        let ayahWord = language == "ur" ? "آیت" : "Ayah"
        guard tap(app.buttons[parahWord].firstMatch) else {
            shot("parahs-selector-missing"); XCTFail("Parah selector missing"); return
        }
        let expected: [(String, Int)] = [
            ("Al-Faatiha", 1),
            ("Al-Baqara", 142),
            ("Al-Baqara", 253),
            ("Aal-i-Imraan", 92),
            ("An-Nisaa", 24),
            ("An-Nisaa", 148),
            ("Al-Maaida", 83),
            ("Al-An'aam", 111),
            ("Al-A'raaf", 88),
            ("Al-Anfaal", 41),
            ("At-Tawba", 94),
            ("Hud", 6),
            ("Yusuf", 53),
            ("Al-Hijr", 2),
            ("Al-Israa", 1),
            ("Al-Kahf", 75),
            ("Al-Anbiyaa", 1),
            ("Al-Muminoon", 1),
            ("Al-Furqaan", 21),
            ("An-Naml", 60),
            ("Al-Ankaboot", 45),
            ("Al-Ahzaab", 31),
            ("Yaseen", 22),
            ("Az-Zumar", 32),
            ("Fussilat", 47),
            ("Al-Ahqaf", 1),
            ("Adh-Dhaariyat", 31),
            ("Al-Mujaadila", 1),
            ("Al-Mulk", 1),
            ("An-Naba", 1)
        ]
        for (index, target) in expected.enumerated() {
            let positionProbe = ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "reader-position"
            if positionProbe && index != 1 { continue }
            let number = index + 1
            let performanceProbe = ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "reader-performance"
            if performanceProbe && ![2, 3].contains(number) { continue }
            if checkControls && !allDestinations && ![3, 18, 27, 28].contains(number) { continue }
            let rowLabel = "\(parahWord) \(number), \(target.0), \(ayahWord) \(target.1)"
            let row = app.buttons.matching(NSPredicate(format: "label == %@", rowLabel)).firstMatch
            for _ in 0..<8 {
                if row.exists && row.isHittable { break }
                app.swipeUp(); pause(0.4)
            }
            guard row.exists && row.isHittable else {
                shot("parah-\(number)-row-missing"); XCTFail("Missing row: \(rowLabel)"); return
            }
            shot("parah-\(number)-row")
            row.tap()
            if performanceProbe { readerIdleWindow(number: number, phase: "after-open") }
            let title = app.navigationBars[target.0]
            let ayah = app.staticTexts["\(ayahWord) \(target.1)"].firstMatch
            guard title.waitForExistence(timeout: 15) else {
                shot("parah-\(number)-title-failure"); XCTFail("Wrong surah for Parah \(number)"); return
            }
            if target.1 == 1 {
                // A new surah begins with its heading and listening options.
                // Enlarged text can put the first ayah below those controls.
                shot("parah-\(number)-landing")
                let scroll = app.scrollViews.firstMatch
                guard scroll.waitForExistence(timeout: 30) else {
                    XCTFail("Reader content did not become ready"); return
                }
                for _ in 0..<16 {
                    if ayah.exists && ayah.isHittable { break }
                    // Small overlapping drags cannot jump past the first badge
                    // between a tall heading and a short first ayah.
                    scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                        .press(forDuration: 0.1, thenDragTo: scroll.coordinate(
                            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
                    pause(0.4)
                }
            }
            guard title.waitForExistence(timeout: 15), ayah.waitForExistence(timeout: 15),
                  ayah.isHittable else {
                shot("parah-\(number)-destination-failure")
                XCTFail("Expected \(target.0), ayah \(target.1)"); return
            }
            shot("parah-\(number)-reader")
            if checkControls && [3, 18, 27, 28].contains(number) && !checkReaderMenus(number: number, title: title) { return }
            if performanceProbe { readerIdleWindow(number: number, phase: "after-controls") }
            if positionProbe {
                verifyManualReadingPosition()
                return
            }
            goBack()
            guard row.waitForExistence(timeout: 10), row.isHittable else {
                shot("parah-\(number)-back-failure"); XCTFail("Back lost Parah \(number)"); return
            }
        }
    }

    /// Deliberately separate from startup profiling: prove that a manual scroll
    /// updates the real Continue reading card and that reopening lands there.
    private func verifyManualReadingPosition() {
        let scroll = app.scrollViews.firstMatch
        guard scroll.waitForExistence(timeout: 15) else {
            XCTFail("Reader scroll view missing"); return
        }
        // Long verses can fill several screens without a badge. Stop at a
        // known later badge using real short drags, rather than assuming two
        // flings expose one or querying all 286 eager cards individually.
        let first = 144, last = 144
        let laterBadge = app.staticTexts["Ayah 144"].firstMatch
        for _ in 0..<24 {
            if laterBadge.isHittable { break }
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                .press(forDuration: 0.05, thenDragTo:
                    scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)))
            pause(0.5)
        }
        guard laterBadge.isHittable else {
            shot("reader-position-no-visible-badge")
            XCTFail("Manual scrolling did not expose Ayah 144 within 24 short drags"); return
        }
        pause(3)
        print("READER_MANUAL_VISIBLE first=\(first) last=\(last)")
        shot("reader-position-after-manual-scroll")
        goBack()
        scrollToTop()
        let resume = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ AND label CONTAINS %@", "Continue reading", "Al-Baqara"
        )).firstMatch
        guard resume.waitForExistence(timeout: 15), resume.isHittable else {
            shot("reader-position-missing-resume")
            XCTFail("The Quran list did not offer the saved Al-Baqara position"); return
        }
        let regex = try! NSRegularExpression(pattern: "Ayah ([0-9]+) of 286")
        let text = resume.label as NSString
        guard let match = regex.firstMatch(in: resume.label, range: NSRange(location: 0, length: text.length)),
              let saved = Int(text.substring(with: match.range(at: 1))) else {
            XCTFail("Continue reading did not expose its saved ayah: \(resume.label)"); return
        }
        // The preceding card can be partially visible with its badge above
        // the viewport; any earlier/later saved ayah is outside this view.
        XCTAssertGreaterThan(saved, 142)
        XCTAssertGreaterThanOrEqual(saved, first - 1)
        XCTAssertLessThanOrEqual(saved, last)
        shot("reader-position-continue-card")
        guard tap(resume) else { XCTFail("Continue reading could not open"); return }
        let restored = app.staticTexts["Ayah \(saved)"].firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 30) && restored.isHittable,
                      "Continue reading must land on its saved ayah")
        shot("reader-position-restored")
    }

    /// No accessibility queries or screenshots inside this window. Compare the app's
    /// heartbeat gaps here with its gaps while XCTest takes snapshots and opens menus.
    private func readerIdleWindow(number: Int, phase: String) {
        print("READER_IDLE_BEGIN parah=\(number) phase=\(phase) timestamp=\(Date().timeIntervalSince1970)")
        pause(20)
        print("READER_IDLE_END parah=\(number) phase=\(phase) timestamp=\(Date().timeIntervalSince1970)")
    }

    /// Exercise the real contextual menus after the title/controls layout changes.
    private func checkReaderMenus(number: Int, title: XCUIElement) -> Bool {
        let reading = language == "ur" ? "پڑھنے کی زبان" : "Reading language"
        let options = language == "ur" ? "مطالعے کے اختیارات" : "Reader options"
        let goTo = language == "ur" ? "آیت پر جائیں" : "Go to ayah"
        let cancel = language == "ur" ? "منسوخ کریں" : "Cancel"
        guard tap(app.buttons[reading].firstMatch) else {
            XCTFail("Reading-language action missing"); return false
        }
        guard app.descendants(matching: .any).matching(identifier: "English").firstMatch.waitForExistence(timeout: 5) else {
            shot("reader-language-missing"); XCTFail("Language menu did not open"); return false
        }
        shot("parah-\(number)-language-menu")
        // Tap the navigation title outside the menu; do not change the user's reading language.
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        guard tap(app.buttons[options].firstMatch), tap(app.buttons[goTo].firstMatch) else {
            shot("reader-options-missing"); XCTFail("Go-to action missing from reader options"); return false
        }
        let alert = app.alerts.firstMatch
        guard alert.waitForExistence(timeout: 5) else {
            XCTFail("Go-to alert did not open"); return false
        }
        shot("parah-\(number)-go-to-alert")
        guard tap(alert.buttons[cancel]) else { XCTFail("Go-to cancel missing"); return false }
        return title.exists
    }

    // MARK: - The tour

    private func tour(language: String, locale: String, dark: Bool) {
        self.language = language
        prefix = "\(language)-\(dark ? "dark" : "light")"
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))", "-AppleLocale", locale,
            "--uitesting-complete-onboarding", dark ? "--uitesting-theme-dark" : "--uitesting-theme-light",
        ]
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "guide-recovery" {
            app.launchArguments.append("--uitesting-method-guide-failure")
        }
        if ["reader-audit", "reader-performance", "reader-position"].contains(ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] ?? "") {
            app.launchArguments.append("--uitesting-reader-diagnostics")
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "audio-follow" {
            app.launchArguments.append("--uitesting-audio-follow-diagnostics")
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "audio-transport" {
            app.launchArguments.append("--uitesting-audio-transport")
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "picture-refresh" {
            app.launchArguments += ["--uitesting-halqah-resources", "--uitesting-picture-refresh"]
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "halqah-schedule" {
            app.launchArguments += ["--uitesting-halqah-resources", "--uitesting-halqah-schedule-removal"]
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "halqah-resources" {
            app.launchArguments += ["--uitesting-halqah-resources", "--uitesting-halqah-post-removal"]
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "personal-history" {
            app.launchArguments.append("--uitesting-personal-history")
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "halqah-history" {
            app.launchArguments += ["--uitesting-halqah-resources", "--uitesting-halqah-history"]
        }
        if ["halqah-duas", "dua-race"].contains(ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] ?? "") {
            app.launchArguments += ["--uitesting-halqah-resources", "--uitesting-halqah-duas"]
            if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "dua-race" {
                app.launchArguments += ["--uitesting-dua-race"]
            }
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "sheikh-stage" {
            app.launchArguments += ["--uitesting-halqah-resources", "--uitesting-sheikh-stage"]
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "pdf-controls" {
            app.launchArguments.append("--uitesting-pdf-controls")
        }
        app.launch()
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "picture-refresh" {
            pictureRefreshTour()
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "halqah-schedule" {
            halqahScheduleTour()
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "pdf-controls" {
            pdfControlsTour()
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "audio-transport" {
            let phase = app.staticTexts["transport-phase"]
            XCTAssertTrue(phase.waitForExistence(timeout: 180))
            expectation(for: NSPredicate(format: "label == %@ OR label == %@", "Done", "Error"), evaluatedWith: phase)
            waitForExpectations(timeout: 150)
            shot("audio-transport-isolation")
            XCTAssertEqual(phase.label, "Done")
            XCTAssertEqual(app.staticTexts["transport-local"].label, "PASS", "Local audio clock did not advance")
            XCTAssertEqual(app.staticTexts["transport-quran"].label, "PASS", "Production transport did not reach ayah 143 without reader layout")
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "sheikh-stage" {
            sheikhStageTour()
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "dua-race" {
            halqahDuaRaceTour()
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "halqah-duas" {
            halqahDuaRecoveryTour()
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "halqah-history" {
            halqahHistoryTour()
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "personal-history" {
            populatedHistoryTour()
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "halqah-resources" {
            halqahResourcesTour()
            return
        }
        guard app.tabBars.buttons.firstMatch.waitForExistence(timeout: 180) else {
            shot("no-tab-bar")
            XCTFail("The app did not reach its navigation tabs")
            return
        }
        pause(6)
        closePopup()
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "audio-follow" {
            audioFollowTour()
            return
        }
        if ["reader-audit", "reader-performance", "reader-position"].contains(ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] ?? "") {
            parahTour(checkControls: true, allDestinations: true)
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "reader-controls" {
            parahTour(checkControls: true)
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "parahs" {
            parahTour()
            return
        }
        if ["resources", "guide-recovery"].contains(ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] ?? "") {
            contextualResourcesTour()
            return
        }
        if ["companion", "companion-fixes", "timezone"].contains(ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] ?? "") {
            companionTour()
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "notification-choices" {
            selectTab(4)
            guard seek("settings-notifications") else { XCTFail("Notifications route missing"); return }
            shot("notification-choices-top")
            scrollShots("notification-choices", count: 6)
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "reading-controls" {
            readingControlsTour()
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "tasbih-preset" {
            tasbihPresetTour()
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "teaching-resources" {
            teachingResourcesTour()
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "appearance-controls" {
            appearanceControlsTour()
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "settings" {
            settingsTour()
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "pages" {
            silsilaTour()
            practiceTour()
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "practice" {
            shot("today-typography")
            practiceTour()
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "silsila" {
            silsilaTour()
            return
        }
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "audit" {
            auditTour()
            return
        }

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
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "today" { return }
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
    /// (the top through the closing prayer), then Halqah › Silsila's Shajra
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
            // Urdu wraps to more screens than English. Reach the actual end,
            // rather than treating a fixed swipe count as full-chain coverage.
            let closingPrayer = app.staticTexts["shajra.closingPrayer"]
            var endingSwipes = 0
            while !prayerFitsReadingArea(closingPrayer) && endingSwipes < 12 {
                // Keep the gesture inside the reader, away from the floating tab bar.
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
                start.press(forDuration: 0.05, thenDragTo: end)
                pause(1.5)
                endingSwipes += 1
                shot("shajra-ending-\(endingSwipes)")
            }
            let geometry = XCTAttachment(string: "Prayer: \(closingPrayer.exists ? closingPrayer.frame.debugDescription : "missing"); tab bar: \(app.tabBars.firstMatch.frame); app: \(app.frame); navigation: \(app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.debugDescription : "none")")
            geometry.name = "shajra-closing-geometry"
            geometry.lifetime = .keepAlways
            add(geometry)
            XCTAssertTrue(prayerFitsReadingArea(closingPrayer), "Entire Shajra closing prayer must fit above navigation before leaving the page")
            shot("shajra-closing-prayer")
            goBack()
        } else {
            shot("no-shajra-button")
            XCTFail("The Zikr Shajra shortcut must open the chain")
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
            XCTFail("The Halqah Shajra row must open the chain")
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

    private func companionTour() {
        let mode = ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] ?? ""
        let focused = mode != "companion"
        selectTab(0)
        guard seek("quick-tool-square.grid.2x2") else { return }
        shot("tools")
        for symbol in ["location.north.line", "calendar", "moon.haze", "star.circle", "hand.tap", "hands.and.sparkles", "sparkles", "square.grid.2x2", "checklist", "timer", "note.text"] {
            if mode == "timezone" && !["location.north.line", "calendar", "moon.haze", "hand.tap", "checklist", "note.text"].contains(symbol) { continue }
            scrollToTop()
            if seek("tool-" + symbol) {
                pause(2)
                if symbol == "calendar" {
                    let firstDay = app.staticTexts["timetable-first-day"]
                    XCTAssertTrue(firstDay.waitForExistence(timeout: 5))
                    XCTAssertTrue(firstDay.label.contains("01"), "Month must start on day 01 in the selected city's timezone")
                    assertRawalpindiMorning("timetable-first-fajr")
                }
                if symbol == "moon.haze" { assertRawalpindiMorning("fasting-suhoor") }
                shot("tool-" + symbol)
                if !focused || symbol == "timer" { scrollShots("tool-" + symbol, count: 2) }
                goBack()
            }
        }
        goBack()
        if focused { return }
        selectTab(4)
        for entry in ["appearance", "notifications", "hijriCalendar"] {
            scrollToTop()
            if seek("settings-" + entry) {
                shot("contrast-" + entry)
                goBack()
            }
        }
    }

    /// Rawalpindi Fajr is in the morning all year; UTC rendering moves it
    /// to the previous evening/midnight. Assert the rendered SwiftUI label,
    /// because testing Date.FormatStyle alone misses its environment override.
    private func assertRawalpindiMorning(_ identifier: String) {
        let value = app.staticTexts[identifier]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        let hourText = value.label.split(separator: ":").first.map(String.init) ?? ""
        // Urdu date formatting may prefix the Western clock with an LRM.
        let hour = Int(hourText.filter { $0.isASCII && $0.isNumber }) ?? -1
        XCTAssertTrue((3...6).contains(hour), "Selected-city Fajr must be morning, got \(value.label)")
    }

    private func tasbihPresetTour() {
        selectTab(0)
        let zikrLabel = language == "ur" ? "ذکر" : "Zikr"
        var selected = false
        for _ in 0..<10 {
            let choices = app.buttons.matching(NSPredicate(format: "label == %@", zikrLabel))
            for choice in choices.allElementsBoundByIndex where choice.isHittable && choice.frame.maxY < app.tabBars.firstMatch.frame.minY {
                choice.tap()
                selected = true
                break
            }
            if selected { break }
            app.swipeUp()
        }
        guard selected else { XCTFail("Daily Zikr selector missing"); return }
        let badge = app.buttons["today-zikr-count"]
        for _ in 0..<8 {
            if badge.exists && badge.isHittable { break }
            app.swipeUp()
        }
        let arabic = app.staticTexts["today-zikr-arabic"]
        XCTAssertTrue(arabic.exists)
        XCTAssertTrue(badge.isHittable)
        XCTAssertLessThanOrEqual(arabic.frame.maxY, badge.frame.minY, "Count must sit below Arabic, without overlap")
        shot("tasbih-preset-today")
        guard tap(badge) else { XCTFail("Count badge missing"); return }
        let counter = app.buttons["tasbih-count"]
        XCTAssertTrue(counter.waitForExistence(timeout: 20), "Badge must open a counter without an editor or list")
        guard let initial = Int(counter.value as? String ?? "") else { XCTFail("Missing count value"); return }
        for _ in 0..<3 { counter.tap() }
        XCTAssertEqual(counter.value as? String, String(initial + 3))
        shot("tasbih-preset-counted")
        let method = app.buttons["method-of-zikr-shortcut"]
        XCTAssertTrue(method.isHittable, "Guide must be available beside the counter controls")
        guard tap(method) else { XCTFail("Counter guide missing"); return }
        XCTAssertTrue(app.staticTexts["method-guide-load-error"].exists == false)
        let guideSection = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "method-guide-section-")).firstMatch
        XCTAssertTrue(guideSection.waitForExistence(timeout: 30), "Counter guide must load")
        shot("tasbih-preset-method-guide")
        goBack()
        XCTAssertTrue(counter.waitForExistence(timeout: 10))
        XCTAssertEqual(counter.value as? String, String(initial + 3), "Opening the guide must preserve the count")
        goBack()
        let footer = app.buttons["today-zikr-counter-link"]
        for _ in 0..<10 {
            if footer.exists && footer.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50)))
        }
        let meaning = app.staticTexts["today-zikr-meaning"]
        XCTAssertTrue(meaning.exists)
        XCTAssertLessThanOrEqual(footer.frame.minY - meaning.frame.maxY, 80,
                                 "Hidden daily cards must not stretch the Zikr footer away from its meaning")
        shot("tasbih-preset-compact-footer")
        guard tap(footer) else { XCTFail("Counter footer missing"); return }
        XCTAssertTrue(counter.waitForExistence(timeout: 20))
        XCTAssertEqual(counter.value as? String, String(initial + 3), "Footer must reuse the same progress")
        shot("tasbih-preset-reopened")
        selectTab(2)
        guard seek("zikr-tasbih") else { XCTFail("Recent counter tile missing"); return }
        XCTAssertTrue(counter.waitForExistence(timeout: 20))
        counter.tap()
        XCTAssertEqual(counter.value as? String, String(initial + 4))
        selectTab(0)
        XCTAssertTrue(counter.waitForExistence(timeout: 20))
        let refreshed = NSPredicate(format: "value == %@", String(initial + 4))
        expectation(for: refreshed, evaluatedWith: counter)
        waitForExpectations(timeout: 10)
        counter.tap()
        XCTAssertEqual(counter.value as? String, String(initial + 5), "Returning tab must preserve the other tab's increment")
        shot("tasbih-preset-cross-tab")
        goBack()
    }

    private func appearanceControlsTour() {
        selectTab(4)
        guard seek("settings-appearance") else { XCTFail("Appearance route missing"); return }
        let choices = language == "ur" ? ["روشن", "تاریک", "سسٹم", "خودکار"] : ["Light", "Dark", "System", "Auto"]
        for (index, label) in choices.enumerated() {
            let option = app.buttons[label].firstMatch
            guard tap(option) else { XCTFail("Theme choice missing: \(label)"); return }
            let selected = NSPredicate(format: "selected == true")
            expectation(for: selected, evaluatedWith: option)
            waitForExpectations(timeout: 10)
            XCTAssertTrue(option.isHittable)
            shot("appearance-choice-\(index)")
        }
        // The final Auto choice must persist without the test's initial forced theme.
        app.terminate()
        app.launchArguments.removeAll { $0 == "--uitesting-theme-dark" || $0 == "--uitesting-theme-light" }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons.firstMatch.waitForExistence(timeout: 180))
        closePopup()
        selectTab(4)
        guard seek("settings-appearance") else { XCTFail("Appearance route missing after relaunch"); return }
        let automatic = app.buttons[choices[3]].firstMatch
        XCTAssertTrue(automatic.isSelected, "Auto choice must survive relaunch")
        shot("appearance-auto-relaunch")
    }

    /// Exercise the actual file viewer with a local PDF and a damaged file.
    private func pdfControlsTour() {
        let valid = app.buttons["pdf-audit-valid"].firstMatch
        guard valid.waitForExistence(timeout: 180), tap(valid) else {
            XCTFail("Local PDF fixture did not open"); return
        }
        let enlarge = app.buttons[language == "ur" ? "بڑا کریں" : "Zoom in"].firstMatch
        let reduce = app.buttons[language == "ur" ? "چھوٹا کریں" : "Zoom out"].firstMatch
        let fit = app.buttons[language == "ur" ? "صفحہ سکرین کے مطابق کریں" : "Fit page"].firstMatch
        let share = app.buttons[language == "ur" ? "فائل شیئر کریں" : "Share file"].firstMatch
        guard enlarge.waitForExistence(timeout: 30) else {
            shot("pdf-missing-controls"); XCTFail("PDF did not expose localized zoom controls"); return
        }
        for control in [enlarge, reduce, fit, share] {
            XCTAssertTrue(control.isHittable)
            XCTAssertTrue(app.frame.contains(control.frame))
            XCTAssertGreaterThanOrEqual(control.frame.height, 44, "Undersized control: \(control.label)")
        }
        shot("pdf-fitted")
        XCTAssertTrue(tap(enlarge)); pause(1)
        shot("pdf-enlarged-once")
        XCTAssertTrue(tap(enlarge)); pause(1)
        shot("pdf-enlarged-twice")
        XCTAssertTrue(tap(reduce)); pause(1)
        shot("pdf-reduced")
        XCTAssertTrue(tap(fit)); pause(1)
        shot("pdf-reset-to-fit")
        app.swipeUp(); pause(1)
        shot("pdf-scrolled")
        XCTAssertTrue(tap(share))
        let presented = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == false"), object: enlarge
        )
        guard XCTWaiter.wait(for: [presented], timeout: 10) == .completed else {
            shot("pdf-share-present-failure")
            XCTFail("Share did not present a modal sheet"); return
        }
        pause(1)
        shot("pdf-share-sheet")
        // The current system presents sharing as a popover, not a draggable
        // bottom sheet. Tap the uncovered PDF below it to dismiss.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: enlarge
        )
        guard XCTWaiter.wait(for: [dismissed], timeout: 10) == .completed else {
            shot("pdf-share-dismiss-failure")
            XCTFail("Share sheet did not dismiss"); return
        }
        goBack()
        XCTAssertTrue(valid.waitForExistence(timeout: 10))
        XCTAssertTrue(tap(app.buttons["pdf-audit-damaged"].firstMatch))
        let error = app.staticTexts[language == "ur" ? "یہ فائل نہیں کھل سکی" : "Unable to open this file"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 15))
        XCTAssertFalse(enlarge.exists)
        XCTAssertFalse(share.exists)
        shot("pdf-damaged-no-controls")
        goBack()
        XCTAssertTrue(valid.waitForExistence(timeout: 10))
    }

    private func readingControlsTour() {
        // A hittable midpoint does not prove text clears the floating tab bar.
        func revealFully(_ element: XCUIElement) -> Bool {
            let surface = app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app.collectionViews.firstMatch
            guard surface.exists else { return false }
            for _ in 0..<20 {
                if prayerFitsReadingArea(element) { return true }
                let above = element.exists && element.frame.minY < app.navigationBars.firstMatch.frame.maxY
                surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.4 : 0.65))
                    .press(forDuration: 0.05, thenDragTo:
                        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.65 : 0.4)))
                pause(0.3)
            }
            return prayerFitsReadingArea(element)
        }
        let letteringHelp = app.staticTexts[language == "ur" ? "بند ہو تو اردو معیاری رسم الخط میں دکھائی جاتی ہے، جس میں حروف ہمیشہ جڑے رہتے ہیں۔ نستعلیق کے لیے اسے آن کریں؛ تبدیلی دیکھنے کے لیے صفحہ دوبارہ کھولیں۔" : "Off shows Urdu in the standard lettering, which always joins. Turn it on for Nastaliq; reopen a page to see the change."].firstMatch
        let sizeLabel = language == "ur" ? "مطالعے کے متن کا سائز" : "Reader Text Size"
        let fontLabel = language == "ur" ? "اردو نستعلیق میں" : "Urdu in Nastaliq"
        let choices = language == "ur" ? ["چھوٹا", "معیاری", "بڑا", "بہت بڑا"] : ["Small", "Standard", "Large", "Extra Large"]
        selectTab(4)
        guard seek("settings-appearance") else { return }
        let sizeMenu = app.buttons[sizeLabel].firstMatch
        for (index, choice) in choices.enumerated() {
            guard tap(sizeMenu), tap(app.buttons[choice].firstMatch) else {
                XCTFail("Reader size choice missing: \(choice)"); return
            }
            expectation(for: NSPredicate(format: "value == %@", choice), evaluatedWith: sizeMenu)
            waitForExpectations(timeout: 10)
            shot("reading-size-\(index)")
        }
        for enabled in [false, true] {
            let toggle = app.switches[fontLabel].firstMatch
            XCTAssertTrue(toggle.waitForExistence(timeout: 10))
            let value = enabled ? "1" : "0"
            if (toggle.value as? String) != value {
                // SwiftUI exposes the labelled row as a Switch as well as the
                // actual UISwitch. The row midpoint is empty space, not the
                // control. Tap the visible switch at the trailing (RTL-aware)
                // edge; keep the value assertion below to verify the mutation.
                toggle.coordinate(withNormalizedOffset: CGVector(
                    dx: language == "ur" ? 0.125 : 0.875, dy: 0.5
                )).tap()
            }
            expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: toggle)
            waitForExpectations(timeout: 10)
            shot("reading-font-setting-\(enabled)")
            XCTAssertTrue(revealFully(letteringHelp), "The complete lettering explanation must scroll above the tab bar")
            shot("reading-font-setting-footer-\(enabled)")
            goBack()
            selectTab(0)
            guard seek("quick-tool-hands.and.sparkles") else { return }
            shot("reading-font-duas-\(enabled)")
            let firstCitation = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "2:127")).firstMatch
            XCTAssertTrue(revealFully(firstCitation), "The first dua citation must be fully reachable above the tab bar")
            shot("reading-font-duas-body-\(enabled)")
            goBack()
            selectTab(4)
            guard seek("settings-appearance") else { return }
        }
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons.firstMatch.waitForExistence(timeout: 180))
        closePopup()
        selectTab(4)
        guard seek("settings-appearance") else { return }
        XCTAssertEqual(app.buttons[sizeLabel].firstMatch.value as? String, choices[3])
        XCTAssertEqual(app.switches[fontLabel].firstMatch.value as? String, "1")
        shot("reading-settings-relaunch")
    }

    /// Real AVPlayer recitation; no injected player state or synthetic ayah changes.
    private func audioFollowTour() {
        let pauseLabel = (language == "ur" ? "روکیں" : "Pause")
        let parah = language == "ur" ? "پارہ" : "Parah"
        let ayahWord = language == "ur" ? "آیت" : "Ayah"
        selectTab(1)
        guard tap(button("Quran")), tap(app.buttons[parah].firstMatch) else {
            XCTFail("Quran Parah selector missing"); return
        }
        let row = app.buttons["\(parah) 2, Al-Baqara, \(ayahWord) 142"]
        guard tap(row) else { XCTFail("Parah 2 missing"); return }
        XCTAssertTrue(app.navigationBars["Al-Baqara"].waitForExistence(timeout: 20))
        let first = app.buttons["quran-ayah-play-142"]
        guard tap(first) else { XCTFail("Ayah 142 playback control missing"); return }
        let next = app.buttons["quran-ayah-play-143"]
        expectation(for: NSPredicate(format: "label == %@", pauseLabel), evaluatedWith: next)
        waitForExpectations(timeout: 180)
        XCTAssertTrue(next.isHittable, "Playing ayah 143 must be brought into view")
        shot("audio-follow-next-ayah")
        guard tap(next) else { XCTFail("Playing ayah pause is not reachable"); return }
        expectation(for: NSPredicate(format: "label != %@", pauseLabel), evaluatedWith: next)
        waitForExpectations(timeout: 10)

        // Move away while paused, then resume through the main listening control.
        guard tap(app.buttons[(language == "ur" ? "مطالعے کے اختیارات" : "Reader options")].firstMatch),
              tap(app.buttons[(language == "ur" ? "آیت پر جائیں" : "Go to ayah")].firstMatch) else {
            XCTFail("Reader go-to control missing"); return
        }
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        field.tap(); field.typeText("1")
        guard tap(alert.buttons[(language == "ur" ? "جائیں" : "Go")]) else { XCTFail("Go action missing"); return }
        for _ in 0..<5 {
            if app.buttons["quran-listen-toggle"].isHittable { break }
            app.swipeDown()
        }
        guard tap(app.buttons["quran-listen-toggle"]) else { XCTFail("Resume control missing"); return }
        expectation(for: NSPredicate(format: "hittable == true AND label == %@", pauseLabel), evaluatedWith: next)
        waitForExpectations(timeout: 15)
        shot("audio-follow-resume")

        // Audio continues while another tab is selected and while the app is backgrounded.
        selectTab(0)
        pause(3)
        selectTab(1)
        assertPlayingAyahVisible(pauseLabel: pauseLabel)
        shot("audio-follow-tab-return")
        XCUIDevice.shared.press(.home)
        pause(5)
        app.activate()
        XCTAssertTrue(app.tabBars.buttons.firstMatch.waitForExistence(timeout: 20))
        assertPlayingAyahVisible(pauseLabel: pauseLabel)
        shot("audio-follow-foreground")
        let active = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "quran-ayah-play-", pauseLabel)).firstMatch
        guard tap(active) else { XCTFail("Final pause unavailable"); return }
    }

    private func assertPlayingAyahVisible(pauseLabel: String) {
        let active = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "quran-ayah-play-", pauseLabel)).firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 10), "Recitation must still be active")
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: active)
        waitForExpectations(timeout: 15)
        XCTAssertGreaterThanOrEqual(active.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThanOrEqual(active.frame.maxY, app.tabBars.firstMatch.frame.minY)
    }

    private func settingsTour() {
        selectTab(4)
        for entry in ["location", "prayerCalculation", "notifications", "appearance", "hijriCalendar", "contentStorage", "privacy"] {
            scrollToTop()
            if seek("settings-" + entry) {
                shot("settings-" + entry)
                scrollShots("settings-" + entry, count: entry == "notifications" ? 4 : 2)
                goBack()
            }
        }
    }

    /// Uses the production history card with nine in-memory records, never the user's store.
    private func populatedHistoryTour() {
        let history = language == "ur" ? "آپ کے گزشتہ 3 ماہ" : "Your last 3 months"
        let showAll = language == "ur" ? "تمام نشستیں دکھائیں" : "Show all sessions"
        let showRecent = language == "ur" ? "حالیہ نشستیں دکھائیں" : "Show recent sessions"
        let ninth = language == "ur" ? "9 منٹ" : "9 min"
        XCTAssertTrue(app.buttons[history].waitForExistence(timeout: 180))
        XCTAssertFalse(app.buttons[showAll].exists, "History must start collapsed")
        XCTAssertFalse(app.staticTexts[ninth].exists)
        shot("history-populated-collapsed")
        guard seek(history) else { return }
        XCTAssertFalse(app.staticTexts[ninth].exists, "Recent history must limit the list to seven sessions")
        guard seek(showAll) else { return }
        let last = app.staticTexts[ninth]
        for _ in 0..<8 {
            if last.exists && last.isHittable { break }
            app.swipeUp(); pause(0.5)
        }
        XCTAssertTrue(last.exists && last.isHittable, "Show all must expose the ninth session")
        shot("history-populated-all")
        guard seek(showRecent) else { return }
        XCTAssertFalse(last.exists, "Show recent must remove the older rows again")
        scrollToTop()
        guard seek(history) else { return }
        XCTAssertFalse(app.buttons[showAll].exists, "The expanded history must collapse again")
        XCTAssertFalse(last.exists)
        shot("history-populated-recollapsed")
    }

    /// Actual contextual entry points, not a direct test-only destination.
    /// The fresh CI simulator has no personal records; this tour never starts a timer.
    private func contextualResourcesTour() {
        selectTab(0)
        guard seek("personal-zikr-entry") else { return }
        let personalTitle = language == "ur" ? "آپ کا روزانہ ذاتی ذکر" : "Your Daily Personal Zikr"
        XCTAssertTrue(app.navigationBars[personalTitle].waitForExistence(timeout: 10))
        contextualGuideRoundTrip(origin: "personal")
        XCTAssertTrue(app.navigationBars[personalTitle].exists)

        let history = language == "ur" ? "آپ کے گزشتہ 3 ماہ" : "Your last 3 months"
        let explanation = language == "ur"
            ? "ہر نمایاں دن آپ کے ذکر کے لیے مختص وقت کی علامت ہے۔"
            : "Every filled day is time you made for Zikr."
        XCTAssertFalse(app.staticTexts[explanation].exists, "History should begin collapsed")
        guard seek(history) else { return }
        XCTAssertTrue(app.staticTexts[explanation].waitForExistence(timeout: 5))
        shot("resources-history-expanded")
        // Keep the visible disclosure in place; only move upward if it is off screen.
        let historyButton = app.buttons[history]
        for _ in 0..<8 {
            if historyButton.exists && historyButton.isHittable { break }
            app.swipeDown()
            pause(0.5)
        }
        guard tap(historyButton) else {
            XCTFail("The expanded history disclosure must remain reachable")
            shot("missing-history-collapse")
            return
        }
        pause(1)
        XCTAssertFalse(app.staticTexts[explanation].exists, "History must collapse again")
        shot("resources-history-collapsed")
        goBack()

        selectTab(2)
        scrollToTop()
        guard seek("zikr-tasbih") else { return }
        let originTitle = app.navigationBars.firstMatch.identifier
        contextualGuideRoundTrip(origin: "tasbih")
        XCTAssertEqual(app.navigationBars.firstMatch.identifier, originTitle, "Back must return to Tasbih")
        shot("resources-tasbih-return")
    }

    /// The actual Halqah detail view, with local HTTP responses and no live account.
    /// The real schedule controls use an isolated transport; no production writes.
    private func pictureRefreshTour() {
        let count = app.staticTexts["picture-list-request-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 20))
        expectation(for: NSPredicate(format: "label == %@", "1"), evaluatedWith: count)
        waitForExpectations(timeout: 15)
        // Two editor dismissals must coalesce while the first GET is held.
        for _ in 0..<2 {
            guard tap(app.buttons["daily-picture-add"]) else { XCTFail("Add picture missing"); return }
            XCTAssertTrue(app.buttons["daily-picture-editor-cancel"].waitForExistence(timeout: 10))
            guard tap(app.buttons["daily-picture-editor-cancel"]) else { XCTFail("Editor Cancel missing"); return }
            XCTAssertTrue(app.buttons["daily-picture-add"].waitForExistence(timeout: 10))
            expectation(for: NSPredicate(format: "exists == false"),
                        evaluatedWith: app.buttons["daily-picture-editor-cancel"])
            waitForExpectations(timeout: 10)
        }
        XCTAssertEqual(count.label, "1", "List requests must not overlap")
        shot("picture-refresh-held-after-editor")
        guard tap(app.buttons["release-picture-list"]) else { XCTFail("Release fixture missing"); return }
        XCTAssertTrue(app.staticTexts["Fresh picture list"].waitForExistence(timeout: 15),
                      "Closing the editor must trigger a fresh list after the older request")
        XCTAssertEqual(count.label, "2", "Pending refreshes should coalesce")
        XCTAssertFalse(app.staticTexts["Older picture list"].exists)
        shot("picture-refresh-new-list")
    }

    private func halqahScheduleTour() {
        let meetingLabel = language == "ur" ? "میٹنگ منسوخ کریں" : "Cancel meeting"
        let zikrLabel = language == "ur" ? "یہ وقت ہٹائیں" : "Remove this time"
        let cancelLabel = language == "ur" ? "منسوخ کریں" : "Cancel"
        let okayLabel = language == "ur" ? "ٹھیک ہے" : "OK"
        let count = app.staticTexts["audit-schedule-removal-requests"]
        func reveal(_ element: XCUIElement) -> Bool {
            for _ in 0..<16 {
                if element.exists && element.isHittable { return true }
                app.swipeUp()
                pause(0.3)
            }
            return element.exists && element.isHittable
        }
        for role in ["member", "admin"] {
            let entry = app.buttons["halqah-audit-" + role]
            guard entry.waitForExistence(timeout: 180), tap(entry) else { XCTFail("Missing fixture entry"); return }
            let posts = app.descendants(matching: .any).matching(identifier: "halqah-detail-posts").firstMatch
            guard posts.waitForExistence(timeout: 30) else { XCTFail("Schedule fixture did not load"); return }
            if role == "member" {
                for label in [zikrLabel, meetingLabel] {
                    XCTAssertFalse(app.buttons[label].exists, "Members must not see removal controls")
                }
                XCTAssertTrue(reveal(app.staticTexts["Audit meeting"].firstMatch))
                XCTAssertFalse(app.buttons[meetingLabel].exists)
                XCTAssertFalse(app.buttons[zikrLabel].exists)
                XCTAssertEqual(count.label, "0")
                shot("schedule-member")
                goBack()
                continue
            }
            for (index, label) in [zikrLabel, meetingLabel].enumerated() {
                let remove = app.buttons[label]
                guard reveal(remove), tap(remove) else { XCTFail("Missing schedule removal action"); return }
                let confirm = app.sheets.buttons[label]
                guard confirm.waitForExistence(timeout: 10) else { XCTFail("Missing confirmation"); return }
                XCTAssertTrue(app.sheets.staticTexts[index == 0 ? "Audit recurring Zikr" : "Audit meeting"].exists,
                              "Confirmation must identify the selected schedule")
                shot("schedule-\(index)-confirmation")
                guard tap(app.sheets.buttons[cancelLabel]) else { XCTFail("Missing Cancel"); return }
                XCTAssertEqual(count.label, String(index * 2), "Cancel must send no request")
                guard tap(remove), tap(confirm) else { XCTFail("Confirmation not repeatable"); return }
                let okay = app.alerts.buttons[okayLabel]
                guard okay.waitForExistence(timeout: 15) else { XCTFail("Failed removal must show feedback"); return }
                XCTAssertEqual(count.label, String(index * 2 + 1))
                shot("schedule-\(index)-failure")
                guard tap(okay) else { XCTFail("Missing failure acknowledgment"); return }
                XCTAssertTrue(remove.exists, "Failed removal must retain the selected schedule")
                guard tap(remove), tap(confirm) else { XCTFail("Removal must allow retry"); return }
                XCTAssertTrue(remove.waitForNonExistence(timeout: 20))
                XCTAssertEqual(count.label, String(index * 2 + 2))
                if index == 0 { XCTAssertTrue(app.buttons[meetingLabel].exists, "Removing Zikr must retain the meeting") }
                shot("schedule-\(index)-removed")
            }
        }
    }

    private func halqahResourcesTour() {
        for role in ["member", "admin"] {
            let entry = app.buttons["halqah-audit-" + role]
            guard entry.waitForExistence(timeout: 180), tap(entry) else {
                XCTFail("Missing isolated Halqah entry"); return
            }
            let error = app.staticTexts["halqah-detail-error"]
            XCTAssertTrue(error.waitForExistence(timeout: 30), "First detail request must show the injected failure")
            XCTAssertTrue(app.buttons["method-of-zikr-shortcut"].isHittable,
                          "Newcomer resources must remain available when the Halqah cannot load")
            shot("halqah-" + role + "-error")
            guard tap(app.buttons["halqah-detail-retry"]) else {
                XCTFail("The Halqah error must offer Retry"); return
            }
            let posts = app.descendants(matching: .any).matching(identifier: "halqah-detail-posts").firstMatch
            XCTAssertTrue(posts.waitForExistence(timeout: 30), "Retry must load the real detail content")
            XCTAssertFalse(error.exists, "Successful retry must clear the error")
            shot("halqah-" + role + "-loaded")
            contextualGuideRoundTrip(origin: "halqah-" + role)
            XCTAssertTrue(app.buttons["method-of-zikr-shortcut"].waitForExistence(timeout: 10),
                          "Back must return to the same Halqah detail")
            shot("halqah-" + role + "-return")
            inspectAnnouncementRemoval(role: role)
            goBack()
            XCTAssertTrue(entry.waitForExistence(timeout: 10), "Back must return to the fixture list")
        }
    }

    private func inspectAnnouncementRemoval(role: String) {
        let post = app.staticTexts["Audit announcement"]
        for _ in 0..<12 {
            if post.exists && post.isHittable { break }
            app.swipeUp()
            pause(0.3)
        }
        guard post.exists && post.isHittable else {
            XCTFail("Fixture announcement must be readable"); return
        }
        let removeLabel = language == "ur" ? "ہٹائیں" : "Remove"
        let cancelLabel = language == "ur" ? "منسوخ کریں" : "Cancel"
        let okayLabel = language == "ur" ? "ٹھیک ہے" : "OK"
        let count = app.staticTexts["audit-removal-requests"]
        XCTAssertEqual(count.label, "0")
        if role == "member" {
            XCTAssertFalse(app.buttons[removeLabel].exists, "Members cannot remove announcements")
            return
        }
        let remove = app.buttons[removeLabel]
        for _ in 0..<4 {
            if remove.exists && remove.isHittable { break }
            app.swipeUp()
        }
        shot("halqah-removal-before-tap")
        guard tap(remove) else {
            XCTFail("Announcement Remove must be reachable"); return
        }
        let cancel = app.buttons[cancelLabel]
        let cancelAppeared = cancel.waitForExistence(timeout: 10)
        shot("halqah-removal-after-tap")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "halqah-removal-presentation-" + language
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        guard cancelAppeared, tap(cancel) else {
            XCTFail("Removal confirmation must offer Cancel"); return
        }
        XCTAssertEqual(count.label, "0", "Cancel must send no mutation")
        XCTAssertTrue(post.exists)
        guard tap(remove) else { XCTFail("Removal must remain available after Cancel"); return }
        shot("halqah-removal-confirmation")
        let confirm = onScreen(app.sheets.buttons.matching(NSPredicate(format: "label == %@", removeLabel)))
        guard tap(confirm) else { XCTFail("Explicit removal confirmation missing"); return }
        let okay = app.alerts.buttons[okayLabel]
        guard okay.waitForExistence(timeout: 15) else { XCTFail("Injected removal failure must be visible"); return }
        XCTAssertEqual(count.label, "1")
        shot("halqah-removal-failure")
        guard tap(okay) else { XCTFail("Failure acknowledgment missing"); return }
        XCTAssertTrue(post.exists, "Failed removal must retain the post")
        guard tap(remove), tap(confirm) else { XCTFail("Removal must be retryable"); return }
        XCTAssertTrue(post.waitForNonExistence(timeout: 20), "Confirmed retry must refresh the announcement list")
        XCTAssertEqual(count.label, "2", "Only the two confirmed attempts may mutate")
        shot("halqah-removal-complete")
    }

    /// Real history/attendance screens with local transport, including recoverable failures.
    private func sheikhStageTour() {
        let lead = language == "ur" ? "ذکر کی رہنمائی کریں" : "Lead Zikr"
        let first = language == "ur" ? "پہلا لطیفہ" : "1st Latifa"
        let retry = language == "ur" ? "زیرِ التوا کارروائی دوبارہ کریں" : "Retry pending action"
        let add = language == "ur" ? "مراقبہ شامل کریں" : "Add Muraqaba"
        let name = language == "ur" ? "مراقبے کا نام" : "Muraqaba name"
        let save = language == "ur" ? "محفوظ کریں" : "Save"
        // Stage rows and the custom form extend below the viewport, especially
        // with Nastaliq and while the keyboard is open. Exercise real scrolling.
        func reveal(_ element: XCUIElement) -> Bool {
            for _ in 0..<10 {
                if element.exists && element.isHittable { return true }
                let scroll = app.scrollViews.firstMatch
                guard scroll.exists else { return false }
                scroll.swipeUp()
                pause(0.3)
            }
            return element.exists && element.isHittable
        }
        let admin = app.buttons["halqah-audit-admin"]
        guard admin.waitForExistence(timeout: 180), tap(admin), tap(app.buttons[lead]), tap(app.buttons[first]) else { XCTFail("Stage controls unavailable"); return }
        XCTAssertTrue(app.buttons[retry].waitForExistence(timeout: 15))
        shot("sheikh-stage-pending")
        guard tap(app.buttons[retry]) else { XCTFail("Pending action retry unavailable"); return }
        XCTAssertTrue(app.buttons[retry].waitForNonExistence(timeout: 15))
        shot("sheikh-stage-confirmed")
        guard reveal(app.buttons[add]), tap(app.buttons[add]), reveal(app.textFields[name]), tap(app.textFields[name]) else { XCTFail("Custom stage entry missing"); return }
        app.textFields[name].typeText("AuditMuraqaba")
        shot("sheikh-custom-stage-editing")
        let cancel = language == "ur" ? "منسوخ کریں" : "Cancel"
        guard tap(app.buttons[cancel]) else { XCTFail("Custom stage cancel unavailable above keyboard"); return }
        XCTAssertTrue(app.textFields[name].waitForNonExistence(timeout: 5))
        guard reveal(app.buttons[add]), tap(app.buttons[add]), app.textFields[name].waitForExistence(timeout: 5) else {
            XCTFail("Custom stage editor could not reopen"); return
        }
        XCTAssertTrue((app.textFields[name].value as? String)?.contains("AuditMuraqaba") == true, "Cancel must preserve the unsent draft")
        guard tap(app.textFields[name]) else { XCTFail("Custom stage field unreachable on return"); return }
        guard reveal(app.buttons[save]), tap(app.buttons[save]) else {
            shot("sheikh-custom-stage-save-unreachable")
            // The automatic UI snapshots only exported the application root.
            // Capture the actual hierarchy at failure to distinguish a covered
            // button, a disabled form and a changed accessibility label.
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "sheikh-custom-stage-save-hierarchy"
            hierarchy.lifetime = .keepAlways
            self.add(hierarchy)
            XCTFail("Custom stage save missing"); return
        }
        let editorRetry = app.buttons["sheikh-stage-editor-retry"]
        if editorRetry.waitForExistence(timeout: 3) {
            shot("sheikh-custom-stage-pending")
            if !tap(editorRetry) {
                // The periodic refresh can confirm the committed request and
                // dismiss the sheet while the screenshot is being captured.
                // A missing retry is valid only when that editor has closed;
                // the unique saved stage and announcement are checked below.
                guard app.textFields[name].waitForNonExistence(timeout: 5) else {
                    XCTFail("Saved stage retry unavailable while editor remains open"); return
                }
            }
        }
        XCTAssertTrue(app.textFields[name].waitForNonExistence(timeout: 20), "Confirmed stage must close its editor")
        XCTAssertTrue(app.buttons["AuditMuraqaba"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons.matching(identifier: "AuditMuraqaba").count, 1, "Lost response must not duplicate the custom stage")
        guard reveal(app.buttons["AuditMuraqaba"]), tap(app.buttons["AuditMuraqaba"]) else { XCTFail("Saved custom stage is unreachable"); return }
        shot("sheikh-custom-stage")
        goBack()
        guard tap(app.buttons["halqah-audit-member"]) else { XCTFail("Member entry missing"); return }
        XCTAssertTrue(app.staticTexts["AuditMuraqaba"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons[lead].exists, "Members must not have broadcaster controls")
        shot("sheikh-member-stage")
    }

    private func halqahDuaRaceTour() {
        let retry = language == "ur" ? "دوبارہ کوشش کریں" : "Try again"
        let mark = language == "ur" ? "پڑھ لیا" : "Mark as read"
        let entry = app.buttons["halqah-audit-admin"]
        guard entry.waitForExistence(timeout: 180), tap(entry), tap(app.buttons[retry]) else {
            XCTFail("Dua race fixture failed to load"); return
        }
        guard tap(app.buttons[mark]) else { XCTFail("Mark action missing"); return }
        let failure = language == "ur" ? "کارروائی مکمل نہیں ہو سکی۔ اپنا انٹرنیٹ کنکشن چیک کریں اور دوبارہ کوشش کریں۔" : "The action could not be completed. Check your connection and try again."
        XCTAssertTrue(app.staticTexts[failure].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons[mark].exists, "First rejected write must retain action")
        let list = app.collectionViews.firstMatch
        let surface = list.exists ? list : app.scrollViews.firstMatch
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.1, thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        guard tap(app.buttons[mark]) else { XCTFail("Retry mark action missing"); return }
        XCTAssertTrue(app.buttons[mark].waitForNonExistence(timeout: 15))
        shot("dua-race-newer-read-state")
        guard tap(app.buttons["release-older-refresh"]) else { XCTFail("Release control missing"); return }
        XCTAssertTrue(app.buttons["Older response released"].waitForExistence(timeout: 15),
                      "Pull refresh must have captured an older pending response")
        XCTAssertFalse(app.buttons[mark].exists, "Older response must not restore unread state")
        XCTAssertTrue(app.staticTexts["Audit dua request"].exists)
        shot("dua-race-after-older-response")
    }

    private func halqahDuaRecoveryTour() {
        let retry = language == "ur" ? "دوبارہ کوشش کریں" : "Try again"
        let mark = language == "ur" ? "پڑھ لیا" : "Mark as read"
        let failure = language == "ur" ? "کارروائی مکمل نہیں ہو سکی۔ اپنا انٹرنیٹ کنکشن چیک کریں اور دوبارہ کوشش کریں۔" : "The action could not be completed. Check your connection and try again."
        let entry = app.buttons["halqah-audit-admin"]
        guard entry.waitForExistence(timeout: 180), tap(entry), tap(app.buttons[retry]) else {
            XCTFail("Dua requests must recover from initial failure"); return
        }
        let request = app.staticTexts["Audit dua request"].firstMatch
        XCTAssertTrue(request.waitForExistence(timeout: 15))
        shot("dua-requests-loaded")
        guard tap(app.buttons[mark]) else { XCTFail("Unread request must offer Mark as read"); return }
        XCTAssertTrue(app.staticTexts[failure].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons[mark].exists, "Failed mark must retain unread state")
        shot("dua-mark-failed")
        guard tap(app.buttons[mark]) else { XCTFail("Mark retry missing"); return }
        XCTAssertTrue(app.buttons[retry].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons[mark].exists, "Confirmed mark must survive failed refresh")
        XCTAssertTrue(request.exists, "Failed refresh must retain populated content")
        shot("dua-confirmed-mark-refresh-failed")
        guard tap(app.buttons[retry]) else { XCTFail("Refresh retry missing"); return }
        XCTAssertTrue(app.buttons[retry].waitForNonExistence(timeout: 15))
        XCTAssertFalse(app.buttons[mark].exists)
        let list = app.collectionViews.firstMatch
        let refreshSurface = list.exists ? list : app.scrollViews.firstMatch
        XCTAssertTrue(refreshSurface.exists, "Dua requests must expose a scrolling surface")
        refreshSurface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.1, thenDragTo: refreshSurface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(app.buttons[retry].waitForExistence(timeout: 15), "Injected pull refresh failure must offer Retry")
        XCTAssertTrue(request.exists)
        XCTAssertFalse(app.buttons[mark].exists)
        shot("dua-pull-refresh-failed")
        guard tap(app.buttons[retry]), tap(button("Done")) else { XCTFail("Refresh or Done missing"); return }
        XCTAssertTrue(entry.waitForExistence(timeout: 15), "Done must return to fixture entry")
    }

    private func halqahHistoryTour() {
        let retry = language == "ur" ? "دوبارہ کوشش کریں" : "Try again"
        let delete = language == "ur" ? "حذف کریں" : "Delete"
        let cancel = language == "ur" ? "منسوخ کریں" : "Cancel"
        let failure = language == "ur" ? "کارروائی مکمل نہیں ہو سکی۔ اپنا انٹرنیٹ کنکشن چیک کریں اور دوبارہ کوشش کریں۔" : "The action could not be completed. Check your connection and try again."
        for role in ["member", "admin"] {
            let entry = app.buttons["halqah-audit-" + role]
            guard entry.waitForExistence(timeout: 180), tap(entry) else {
                XCTFail("History entry missing"); return
            }
            let historyError = app.staticTexts["halqah-history-load-error"]
            XCTAssertTrue(historyError.waitForExistence(timeout: 15))
            shot("history-" + role + "-load-failure")
            guard tap(app.buttons[retry]) else {
                XCTFail("History must offer Retry after an injected load failure"); return
            }
            let first = app.staticTexts["Audit session 1"].firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 15))
            shot("history-" + role + "-loaded")
            XCTAssertFalse(historyError.exists, "Successful loading must clear its explanation")
            guard tap(first) else { XCTFail("Attendance entry missing"); return }
            let attendanceError = app.staticTexts["halqah-attendance-load-error"]
            XCTAssertTrue(attendanceError.waitForExistence(timeout: 15))
            shot("history-" + role + "-attendance-failure")
            guard tap(app.buttons[retry]) else {
                XCTFail("Attendance must offer Retry after an injected load failure"); return
            }
            XCTAssertTrue(app.staticTexts["Audit attendee 2"].waitForExistence(timeout: 15))
            XCTAssertFalse(attendanceError.exists)
            shot("history-" + role + "-attendees")
            goBack()
            let remove = app.buttons[delete + ": Audit session 1"]
            if role == "member" {
                XCTAssertFalse(remove.exists, "Read-only history must not expose Delete")
            } else {
                guard tap(remove), tap(app.buttons[cancel]) else { XCTFail("Delete Cancel missing"); return }
                XCTAssertTrue(first.exists, "Cancel must preserve the record")
                guard tap(remove), tap(app.buttons[delete]) else { XCTFail("Delete confirmation missing"); return }
                XCTAssertTrue(app.staticTexts[failure].waitForExistence(timeout: 15))
                XCTAssertTrue(first.exists, "Failed delete must preserve the record")
                shot("history-delete-failure")
                guard tap(remove), tap(app.buttons[delete]) else { XCTFail("Delete retry missing"); return }
                XCTAssertTrue(first.waitForNonExistence(timeout: 15), "Successful delete must remove the record")
                XCTAssertFalse(app.staticTexts[failure].exists)
                XCTAssertTrue(app.buttons[retry].waitForExistence(timeout: 15), "Injected refresh failure must offer Retry")
                XCTAssertTrue(historyError.exists, "Refresh failure must explain why Retry is shown")
                shot("history-confirmed-delete-refresh-failed")
                guard tap(app.buttons[retry]) else { XCTFail("Post-delete refresh Retry missing"); return }
                XCTAssertFalse(first.exists, "Refresh must not restore the deleted record")
            }
            let last = app.staticTexts["Audit session 9"].firstMatch
            let lastCell = app.cells.containing(.staticText, identifier: "Audit session 9").firstMatch
            func completeLastRowVisible() -> Bool {
                last.exists && last.isHittable && lastCell.exists
                    && lastCell.frame.minY >= app.navigationBars.firstMatch.frame.maxY
                    && lastCell.frame.maxY <= app.frame.maxY - 34
            }
            for _ in 0..<12 {
                if completeLastRowVisible() { break }
                app.swipeUp(); pause(0.3)
            }
            XCTAssertTrue(completeLastRowVisible(), "The entire last history row, including attendance, must be visible")
            shot("history-" + role + "-last-row")
            guard tap(button("Done")) else { XCTFail("History Done missing"); return }
            XCTAssertTrue(entry.waitForExistence(timeout: 15), "Done must return to the history entry")
        }
    }

    private func contextualGuideRoundTrip(origin: String) {
        scrollToTop()
        guard seek("method-of-zikr-shortcut") else { return }
        let guideTitle = language == "ur" ? "طریقۂ ذکر" : "Method of Zikr"
        XCTAssertTrue(app.navigationBars[guideTitle].waitForExistence(timeout: 10))
        let firstSection = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "method-guide-section-")).firstMatch
        if ProcessInfo.processInfo.environment["DI_SCREENSHOTS"] == "guide-recovery" {
            let error = app.staticTexts["method-guide-load-error"]
            XCTAssertTrue(error.waitForExistence(timeout: 30), "Injected read failure must be visible")
            XCTAssertFalse(firstSection.exists, "A failed load must not show stale guide content")
            shot("resources-" + origin + "-load-error")
            guard tap(app.buttons["method-guide-retry"]) else {
                XCTFail("Failed guide must offer Retry")
                return
            }
        }
        guard firstSection.waitForExistence(timeout: 30) else {
            XCTFail("The local Method of Zikr content must load before reviewing the guide")
            return
        }
        XCTAssertFalse(app.staticTexts["method-guide-load-error"].exists, "Successful retry must clear the error")
        shot("resources-" + origin + "-guide")
        let shajra = onScreen(app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", label("Chain of Transmission"))))
        let originalGuideY = shajra.frame.minY
        guard tap(shajra) else {
            XCTFail("The guide must expose its prominent Shajra shortcut")
            return
        }
        XCTAssertTrue(app.navigationBars[label("Shajra")].waitForExistence(timeout: 10))
        shot("resources-" + origin + "-shajra")
        goBack()
        XCTAssertTrue(app.navigationBars[guideTitle].exists, "Back must return to the guide")
        XCTAssertTrue(firstSection.exists, "Returning from Shajra must retain the loaded guide")
        XCTAssertFalse(app.staticTexts["method-guide-load-error"].exists)
        XCTAssertTrue(shajra.isHittable, "The Shajra shortcut must remain reachable after Back")
        XCTAssertEqual(shajra.frame.minY, originalGuideY, accuracy: 44,
                       "The guide must retain its position after returning from Shajra")
        shot("resources-" + origin + "-guide-return")
        if origin == "personal" {
            inspectCompleteMethodGuide()
        }
        goBack()
    }

    /// Traverse real content with overlapping captures, rather than treating
    /// a screenshot of the first card as coverage of the whole guide.
    private func inspectCompleteMethodGuide() {
        let sectionIDs = language == "ur"
            ? ["quotation", "opening", "tasbih", "istighfar", "shahadah", "taawwudh",
               "basmalah", "start", "latifa-1", "latifa-2", "latifa-3-5", "latifa-6",
               "latifa-7", "return", "rabitah", "conclusion"]
            : (1...6).map { "instruction-\($0)" }
        var unseen = Set(sectionIDs)
        let diagramLabel = language == "ur"
            ? "سامنے سے نظر آنے والا نمبر وار خاکہ:"
            : "Numbered diagram, viewed from the front:"
        let diagram = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", diagramLabel)).firstMatch
        let scroll = app.scrollViews.firstMatch
        guard scroll.exists else {
            XCTFail("Method guide must provide a scrollable reading surface")
            return
        }
        let top = app.navigationBars.firstMatch.frame.maxY
        let bottom = app.tabBars.firstMatch.exists
            ? app.tabBars.firstMatch.frame.minY : app.frame.maxY
        let viewport = CGRect(x: app.frame.minX, y: top,
                              width: app.frame.width, height: bottom - top)
        for step in 0..<32 {
            var sectionDiagnostics: [String] = []
            for id in unseen {
                // SwiftUI can expose a card identifier on several descendants.
                // An offscreen/zero-frame first match is not the visible card.
                let matches = app.descendants(matching: .any)
                    .matching(identifier: "method-guide-section-" + id).allElementsBoundByIndex
                sectionDiagnostics.append("\(id): " + matches.map {
                    "type=\($0.elementType.rawValue) frame=\($0.frame) label=\($0.label.prefix(80))"
                }.joined(separator: " | "))
                if matches.contains(where: { $0.frame.intersection(viewport).height > 44 }) {
                    unseen.remove(id)
                }
            }
            let diagnostic = XCTAttachment(string: "viewport=\(viewport)\n" + sectionDiagnostics.joined(separator: "\n"))
            diagnostic.name = "method-guide-section-frames-\(language)-\(step)"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
            shot("resources-personal-guide-depth-\(step)")
            if diagram.exists && viewport.contains(diagram.frame) {
                XCTAssertTrue(unseen.isEmpty,
                              "Guide sections never reached the viewport: \(unseen.sorted())")
                let footer = app.buttons["method-guide-shajra-footer"]
                for _ in 0..<5 {
                    if footer.exists && viewport.contains(footer.frame) { break }
                    scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
                        .press(forDuration: 0.05, thenDragTo:
                            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
                }
                XCTAssertTrue(footer.exists && viewport.contains(footer.frame),
                              "The complete closing Shajra shortcut must be reachable")
                shot("resources-guide-closing-shajra")
                guard tap(footer) else { XCTFail("Closing Shajra shortcut must open"); return }
                XCTAssertTrue(app.navigationBars[label("Shajra")].waitForExistence(timeout: 10))
                goBack()
                XCTAssertTrue(footer.waitForExistence(timeout: 10))
                XCTAssertTrue(footer.isHittable, "Back must preserve the end-of-guide position")
                shot("resources-guide-closing-return")
                return
            }
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo:
                    scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30)))
            pause(0.5)
        }
        XCTFail("The complete numbered diagram must be reachable below every guide section")
    }

    private func practiceTour() {
        selectTab(2)
        shot("practice-zikr")
        if seek("zikr-method") {
            shot("practice-method")
            scrollShots("practice-method", count: 3)
            goBack()
        }
        scrollToTop()
        if seek("zikr-tasbih") {
            shot("practice-tasbih")
            if seek("tasbih-new-counter") {
                shot("practice-counter-editor")
                _ = seek("tasbih-editor-cancel")
            }
            scrollToTop()
            if seek("personal-zikr-entry") {
                shot("practice-personal-zikr")
                scrollShots("practice-personal-zikr", count: 4)
                goBack()
            }
            goBack()
        }
    }

    /// The contextual guide must return to the teaching text without losing the reader's place.
    private func teachingResourcesTour() {
        selectTab(4)
        guard seek("silsila-teachings"), seek("silsila-tasawwuf") else { return }
        let method = app.buttons["method-of-zikr-shortcut"]
        // Teaching articles can span many screens; traverse their real content.
        for _ in 0..<40 {
            if method.exists && method.isHittable { break }
            app.swipeUp()
            pause(0.3)
        }
        guard method.exists && method.isHittable else {
            shot("teaching-guide-missing")
            XCTFail("Tasawwuf must offer the Method of Zikr after its text")
            return
        }
        let originalY = method.frame.minY
        shot("teaching-before-guide")
        guard tap(method) else { XCTFail("Teaching guide could not open"); return }
        let section = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "method-guide-section-")).firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 30))
        // Existence precedes the entrance animation; capture settled text contrast.
        pause(2)
        XCTAssertFalse(app.staticTexts["method-guide-load-error"].exists)
        shot("teaching-guide-settled")
        goBack()
        expectation(for: NSPredicate(format: "exists == true AND hittable == true"), evaluatedWith: method)
        waitForExpectations(timeout: 15)
        pause(2)
        shot("teaching-after-guide")
        XCTAssertEqual(method.frame.minY, originalY, accuracy: 44,
                       "Returning from the guide must preserve the article's reading position")
    }

    private func silsilaTour() {
        selectTab(4)
        for category in ["aboutSilsila", "sheikhAbdulQadeerAwan", "sheikhMuhammadAkramAwan", "shajra"] {
            scrollToTop()
            if seek("silsila-" + category) {
                shot("silsila-" + category)
                scrollShots("silsila-" + category, count: 2)
                goBack()
            }
        }
        scrollToTop()
        if seek("silsila-teachings") {
            for category in ["tasawwuf", "tazkiyahNafs", "zikrAllah", "baiat", "methodOfZikr"] {
                scrollToTop()
                if seek("silsila-" + category) {
                    shot("teaching-" + category)
                    scrollShots("teaching-" + category, count: 2)
                    goBack()
                }
            }
            goBack()
        }
    }

    private func auditTour() {
        selectTab(0)
        shot("audit-today")
        if seek("personal-zikr-entry") {
            shot("audit-personal-zikr")
            let shajra = app.buttons["personal-zikr-shajra"]
            XCTAssertTrue(shajra.waitForExistence(timeout: 10))
            XCTAssertGreaterThanOrEqual(shajra.frame.height, 44)
            if seek("personal-zikr-shajra") {
                shot("audit-inline-shajra")
                scrollShots("audit-inline-shajra", count: 1)
            }
            goBack()
        }
        selectTab(4)
        if seek("silsila-teachings") {
            shot("audit-teachings")
            if seek("silsila-tasawwuf") {
                pause(3)
                shot("audit-article")
                scrollShots("audit-article", count: 2)
                goBack()
            }
            goBack()
        }
        if seek("silsila-about-app") {
            shot("audit-about")
            scrollShots("audit-about", count: 1)
            goBack()
        }
    }

    @discardableResult
    private func seek(_ identifier: String) -> Bool {
        for _ in 0..<8 {
            let element = app.buttons[identifier]
            if element.exists && element.isHittable {
                element.tap()
                pause(2)
                return true
            }
            app.swipeUp()
            pause(0.5)
        }
        XCTFail("Missing audit destination: \(identifier)")
        shot("missing-" + identifier)
        return false
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
