import Foundation
import XCTest
@testable import DarulIrfan

/// Regression tests for the v1.11 fixes: online zikr in local time, reading
/// direction, the app-language default for content, and the shape of the
/// newly segmented Urdu tafsir.
final class ReleaseFixesTests: XCTestCase {

    private let calculator = PrayerCalculationService()

    private func session(anchor: String?, weekdays: [Int] = Array(1...7)) -> ZikrSession {
        ZikrSession(
            id: "test",
            title: "Online Zikr",
            weekdays: weekdays,
            startHour: 21,
            startMinute: 15,
            durationMinutes: 30,
            timeZoneIdentifier: "Asia/Karachi",
            joinUrl: nil,
            instructions: nil,
            availabilityNote: nil,
            sourceUrl: nil,
            anchor: anchor
        )
    }

    // MARK: - Zikr anchors

    /// "After Isha" is Isha at Dar-ul-Irfan that day, not a fixed 21:15.
    func testAfterIshaFollowsIshaAtDarulIrfan() throws {
        let noon = TestDates.make(year: 2026, month: 1, day: 15, hour: 12, minute: 0, timeZone: TestDates.karachi)
        let start = try XCTUnwrap(ZikrAnchorResolver.nextStart(for: session(anchor: "afterIsha"), after: noon, calculator: calculator))
        let day = try XCTUnwrap(calculator.schedule(
            for: DateComponents(year: 2026, month: 1, day: 15),
            at: ZikrAnchorResolver.darulIrfan,
            preferences: PrayerCalculationPreferences()
        ))
        XCTAssertEqual(start, day.time(for: .isha))

        // In January Isha in Chakwal is well before 21:15.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TestDates.karachi
        let hour = calendar.component(.hour, from: start)
        XCTAssertTrue((18...20).contains(hour), "Isha at Dar-ul-Irfan in January should be in the evening, got \(hour)")
    }

    /// The summer and winter starts differ, which a fixed time cannot do.
    func testAfterIshaMovesWithTheSeasons() throws {
        let winter = TestDates.make(year: 2026, month: 1, day: 15, hour: 12, minute: 0, timeZone: TestDates.karachi)
        let summer = TestDates.make(year: 2026, month: 6, day: 21, hour: 12, minute: 0, timeZone: TestDates.karachi)
        let anchored = session(anchor: "afterIsha")
        let winterStart = ZikrAnchorResolver.resolved(anchored, at: winter, calculator: calculator)
        let summerStart = ZikrAnchorResolver.resolved(anchored, at: summer, calculator: calculator)
        let winterMinutes = winterStart.startHour * 60 + winterStart.startMinute
        let summerMinutes = summerStart.startHour * 60 + summerStart.startMinute
        XCTAssertGreaterThan(summerMinutes - winterMinutes, 60, "Summer Isha should be over an hour later")
    }

    /// Tahajjud falls in the last third of the night: after midnight, before Fajr.
    func testTahajjudIsInTheLastThirdOfTheNight() throws {
        let evening = TestDates.make(year: 2026, month: 3, day: 10, hour: 20, minute: 0, timeZone: TestDates.karachi)
        let start = try XCTUnwrap(ZikrAnchorResolver.nextStart(for: session(anchor: "tahajjud"), after: evening, calculator: calculator))
        let nextDay = try XCTUnwrap(calculator.schedule(
            for: DateComponents(year: 2026, month: 3, day: 11),
            at: ZikrAnchorResolver.darulIrfan,
            preferences: PrayerCalculationPreferences()
        ))
        let fajr = try XCTUnwrap(nextDay.time(for: .fajr))
        XCTAssertLessThan(start, fajr)
        XCTAssertGreaterThan(start, fajr.addingTimeInterval(-5 * 3600))
    }

    /// A session at a fixed time is left exactly as announced.
    func testUnanchoredSessionPassesThrough() {
        let fixed = session(anchor: nil)
        XCTAssertEqual(ZikrAnchorResolver.resolved(fixed, at: Date(), calculator: calculator), fixed)
    }

    /// An anchor this build does not know must not fail the whole decode.
    func testUnknownAnchorDecodesAsFixedTime() throws {
        let json = """
        [{"id":"x","title":"t","weekdays":[1],"startHour":1,"startMinute":2,"durationMinutes":3,
          "timeZoneIdentifier":"Asia/Karachi","anchor":"someFutureAnchor"}]
        """
        let sessions = try JSONDecoder().decode([ZikrSession].self, from: Data(json.utf8))
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNil(sessions[0].zikrAnchor)
    }

    // MARK: - Ayah of the Day

    /// The excerpt is the commentary's own first prose, never the section's
    /// opening Arabic or its numbered translation.
    @MainActor
    func testTafsirExcerptSkipsTheOpeningBlock() throws {
        let entry = [
            "سورۃ البقرہ رکوع 18 آیات 148 تا 152",
            "وَلِكُلٍّ وِّجْهَةٌ هُوَ مُوَلِّيْهَا فَاسْتَبِقُوا الْخَيْرٰتِ ؕ اَيْنَ مَا تَكُوْنُوْا يَاْتِ بِكُمُ اللّٰهُ جَمِيْعًا",
            "اور ہر ایک کے واسطے ایک قبلہ رہا ہے جس کی طرف وہ رخ کرتا رہا پس نیکیوں میں بڑھ چڑھ کر کوشش کرو ﴿۱۴۸﴾",
            "ہرگروہ، ہر طبقے، ہر قوم اور ہر مذہب میں کوئی نہ کوئی نقطہ اتحاد ہے۔ عبادات و اعمال ہوں، افکار و خیال ہو، رنگ و نسل کی حد بندی ہو۔",
        ].joined(separator: "\n")
        let excerpt = try XCTUnwrap(TodayDailyViewModel.commentaryOpening(entry))
        XCTAssertTrue(excerpt.hasPrefix("ہرگروہ"))
    }

    // MARK: - Group admin

    /// Whatever an admin pastes - share link, watch link, live link or bare
    /// id - becomes the same video id; anything else is refused.
    func testVideoLinkReading() {
        XCTAssertEqual(VideoLink.id(from: "https://youtu.be/abcdefghijk"), "abcdefghijk")
        XCTAssertEqual(VideoLink.id(from: "https://www.youtube.com/watch?v=abcdefghijk&t=10"), "abcdefghijk")
        XCTAssertEqual(VideoLink.id(from: "https://www.youtube.com/live/abcdefghijk?si=x"), "abcdefghijk")
        XCTAssertEqual(VideoLink.id(from: " abcdefghijk "), "abcdefghijk")
        XCTAssertNil(VideoLink.id(from: "https://example.com/watch?v=short"))
        XCTAssertNil(VideoLink.id(from: "hello"))
    }

    /// The server writes timestamps with milliseconds; the group screens must
    /// read them (the stock ISO-8601 decoder does not).
    func testGroupPostsDecodeServerTimestamps() throws {
        let json = #"{"groupID":"usa","posts":[{"id":"p","kind":"announcement","title":"T","publishedAt":"2026-10-27T10:15:00.000Z","isDraft":false}]}"#
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            return formatter.date(from: text) ?? Date.distantPast
        }
        let list = try decoder.decode(MemberGroupPostList.self, from: Data(json.utf8))
        XCTAssertEqual(list.posts.first?.publishedAt, formatter.date(from: "2026-10-27T10:15:00.000Z"))
    }

    // MARK: - Reading direction

    func testScriptDirectionFollowsTheText() {
        XCTAssertTrue(ScriptDirection.isRightToLeft("یہ کتاب ہے جس میں کوئی شک نہیں", fallbackLanguage: "en"))
        XCTAssertFalse(ScriptDirection.isRightToLeft("This is the Book in which there is no doubt", fallbackLanguage: "ur"))
        XCTAssertTrue(ScriptDirection.isRightToLeft("123", fallbackLanguage: "ur"))
        XCTAssertFalse(ScriptDirection.isRightToLeft("123", fallbackLanguage: "en"))
    }

    // MARK: - Content language

    func testForcedAppLanguageDecidesContentLanguage() {
        XCTAssertEqual(AppLanguage.english.contentLanguageCode, "en")
        XCTAssertEqual(AppLanguage.urdu.contentLanguageCode, "ur")
        XCTAssertTrue(["en", "ur"].contains(AppLanguage.system.contentLanguageCode))
    }

    // MARK: - Urdu tafsir seed

    /// Every ayah row's script matches its edition's language - the data-level
    /// half of "Urdu shows English and English shows Urdu".
    func testTranslationScriptMatchesEditionLanguage() throws {
        try XCTSkipIf(SeedBundle.manifest() == nil, "SeedData resources are not visible to this test host")
        let languages = Dictionary(uniqueKeysWithValues: SeedBundle.quranEditions().map { ($0.id, $0.language) })
        var mismatches: [String] = []
        for row in SeedBundle.quranTranslations() {
            guard let language = languages[row.editionID], !row.text.isEmpty else { continue }
            let isUrduScript = ScriptDirection.isRightToLeft(row.text, fallbackLanguage: language)
            if (language == "ur") != isUrduScript {
                mismatches.append("\(row.editionID) \(row.surahNumber):\(row.ayahNumber)")
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "Script does not match edition language: \(mismatches.prefix(10))")
    }

    /// Akram-ut-Tafaseer is now in the reader per ayah, in rows small enough
    /// for the reader (a 662 KB block once crashed it), one per starting ayah.
    func testAkramUtTafaseerRowsAreWellFormed() throws {
        try XCTSkipIf(SeedBundle.manifest() == nil, "SeedData resources are not visible to this test host")
        let rows = SeedBundle.quranTafsir().filter { $0.editionID == "akram-ut-tafaseer-ur" }
        XCTAssertGreaterThan(rows.count, 1_000)
        XCTAssertTrue(rows.contains { $0.surahNumber == 1 && $0.ayahStart == 1 }, "Al-Fatihah must have Urdu commentary")
        var starts = Set<String>()
        for row in rows {
            XCTAssertLessThanOrEqual(row.text.utf8.count, 41 * 1024, "\(row.surahNumber):\(row.ayahStart) is too large")
            XCTAssertTrue(starts.insert("\(row.surahNumber):\(row.ayahStart)").inserted, "duplicate start \(row.surahNumber):\(row.ayahStart)")
            XCTAssertFalse(row.text.contains("OCR نوٹ"), "OCR notes are not commentary")
        }
    }

    /// Every surah offers its Urdu Asrar-at-Tanzil volume, so Urdu readers
    /// always have the full commentary one tap away.
    func testEverySurahHasAnUrduAsrarVolume() throws {
        try XCTSkipIf(SeedBundle.manifest() == nil, "SeedData resources are not visible to this test host")
        for surah in 1...114 {
            let volumes = TafsirVolumeProvider.shared.volumes(surah: surah, editionPrefix: "asrar-at-tanzil", language: "ur")
            XCTAssertFalse(volumes.isEmpty, "Surah \(surah) has no Urdu Asrar-at-Tanzil volume")
        }
    }

    /// The official schedule ships with its anchors, so the section is never
    /// empty and never a fixed guess.
    func testBundledZikrSessionsAreAnchored() throws {
        try XCTSkipIf(SeedBundle.manifest() == nil, "SeedData resources are not visible to this test host")
        let anchors = Set(SeedBundle.zikrSessions().compactMap(\.zikrAnchor))
        XCTAssertEqual(anchors, [.afterIsha, .tahajjud])
    }
}
