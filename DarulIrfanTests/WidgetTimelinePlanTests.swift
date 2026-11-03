import XCTest
@testable import DarulIrfan

/// The widgets' and complications' timelines (WidgetTimelinePlan), the
/// countdown span, the Ayah of the Day lookup, the Watch seal's motion and
/// the one-time widget guide offer.
final class WidgetTimelinePlanTests: XCTestCase {
    private let karachi = TimeZone(identifier: "Asia/Karachi")!
    private let newYork = TimeZone(identifier: "America/New_York")!

    private func karachi(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = karachi
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func newYork(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func prayer(_ key: String, _ time: Date, obligatory: Bool = true) -> WidgetPrayerTime {
        WidgetPrayerTime(prayerKey: key, displayName: key.capitalized, time: time, isObligatory: obligatory)
    }

    private func snapshot(zikr: [WidgetZikrSession]? = nil) -> PrayerWidgetSnapshot {
        var times: [WidgetPrayerTime] = []
        for day in 27...30 {
            times += [
                prayer("fajr", karachi(day, 5, 1)),
                prayer("sunrise", karachi(day, 6, 21), obligatory: false),
                prayer("dhuhr", karachi(day, 11, 57)),
                prayer("asr", karachi(day, 15, 54)),
                prayer("maghrib", karachi(day, 17, 33)),
                prayer("isha", karachi(day, 18, 50))
            ]
        }
        return PrayerWidgetSnapshot(
            generatedAt: karachi(27, 0, 0),
            placeName: "Chakwal",
            upcomingTimes: times,
            hijriDateText: "15 Rabi al-Awwal 1448",
            suhoorEndsAt: nil,
            iftarAt: nil,
            zikrSessions: zikr,
            timeZoneIdentifier: "Asia/Karachi"
        )
    }

    // MARK: - Entry dates

    func testDatesStartNowAndFollowEachPrayerSunriseIncluded() {
        let now = karachi(28, 5, 30)
        let dates = WidgetTimelinePlan.dates(for: snapshot(), from: now, phoneTimeZone: karachi)
        XCTAssertEqual(dates.first, now)
        XCTAssertEqual(Array(dates.dropFirst().prefix(5)), [
            karachi(28, 6, 21), karachi(28, 11, 57), karachi(28, 15, 54), karachi(28, 17, 33), karachi(28, 18, 50)
        ])
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(Set(dates).count, dates.count)
    }

    func testDatesTurnOverAtThePlacesMidnightAndThePhonesMidnight() {
        // A phone in New York showing Karachi's times.
        let now = karachi(28, 19, 0)
        let dates = WidgetTimelinePlan.dates(for: snapshot(), from: now, phoneTimeZone: newYork)
        XCTAssertTrue(dates.contains(karachi(29, 0, 0)), "the place's midnight: today's grid and Hijri date")
        XCTAssertTrue(dates.contains(newYork(28, 0, 0).addingTimeInterval(86_400)), "the phone's midnight: the day's ayah")
    }

    func testDatesIncludeEachZikrStartAndEnd() {
        let session = WidgetZikrSession(id: "daily", title: "Daily Zikr", startsAt: karachi(28, 21, 15), endsAt: karachi(28, 21, 45))
        let dates = WidgetTimelinePlan.dates(for: snapshot(zikr: [session]), from: karachi(28, 19, 0), phoneTimeZone: karachi)
        XCTAssertTrue(dates.contains(session.startsAt))
        XCTAssertTrue(dates.contains(session.endsAt))
    }

    func testDatesStayWithinTheHorizonAndTheEntryLimit() {
        let now = karachi(27, 0, 30)
        let dates = WidgetTimelinePlan.dates(for: snapshot(), from: now, phoneTimeZone: karachi)
        XCTAssertLessThanOrEqual(dates.count, WidgetTimelinePlan.entryLimit)
        XCTAssertTrue(dates.allSatisfy { $0 <= now.addingTimeInterval(WidgetTimelinePlan.horizon) })
        XCTAssertTrue(dates.dropFirst().allSatisfy { $0 > now })
    }

    func testAnExhaustedSnapshotWaitsHalfAnHour() {
        let now = karachi(31, 12, 0).addingTimeInterval(10 * 86_400)
        let dates = WidgetTimelinePlan.dates(for: snapshot(), from: now, phoneTimeZone: karachi)
        // Only the midnights ahead are left.
        XCTAssertTrue(dates.dropFirst().allSatisfy { date in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = karachi
            return calendar.startOfDay(for: date) == date
        })
        XCTAssertEqual(WidgetTimelinePlan.reloadDate(after: [now], from: now), now.addingTimeInterval(30 * 60))
    }

    func testReloadIsAtTheLastEntryButNeverLaterThanSixHours() {
        let now = karachi(28, 5, 30)
        let soon = now.addingTimeInterval(60 * 60)
        XCTAssertEqual(WidgetTimelinePlan.reloadDate(after: [now, soon], from: now), soon)
        let far = now.addingTimeInterval(20 * 60 * 60)
        XCTAssertEqual(WidgetTimelinePlan.reloadDate(after: [now, far], from: now), now.addingTimeInterval(6 * 60 * 60))
    }

    // MARK: - Countdown, five prayers

    func testCountdownRunsFromThePreviousPrayerToTheNext() {
        let snapshot = snapshot()
        let now = karachi(28, 13, 0)
        let next = try! XCTUnwrap(snapshot.nextPrayer(after: now))
        XCTAssertEqual(next.prayerKey, "asr")
        XCTAssertEqual(snapshot.countdownInterval(to: next, at: now), karachi(28, 11, 57)...karachi(28, 15, 54))
    }

    func testCountdownIsNeverReversed() {
        let snapshot = snapshot()
        let early = prayer("fajr", karachi(20, 5, 0))
        let interval = snapshot.countdownInterval(to: early, at: karachi(28, 13, 0))
        XCTAssertLessThanOrEqual(interval.lowerBound, interval.upperBound)
        XCTAssertEqual(interval.upperBound, early.time)
    }

    func testFivePrayersLeaveOutSunriseOnThePlacesDay() {
        let five = snapshot().fivePrayers(on: karachi(28, 23, 30))
        XCTAssertEqual(five.map(\.prayerKey), ["fajr", "dhuhr", "asr", "maghrib", "isha"])
        XCTAssertTrue(five.allSatisfy { Calendar.current.dateComponents(in: karachi, from: $0.time).day == 28 })
    }

    // MARK: - Ayah of the Day, language

    func testDailyAyahFollowsThePhonesDayAndTheAppsLanguage() {
        var snapshot = snapshot()
        snapshot.languageCode = "ur"
        let ayah = WidgetDailyAyah(surah: 2, ayahStart: 255, ayahEnd: 255, arabic: "x", translation: "y", reference: "z", languageCode: "ur")
        let now = newYork(28, 23, 0)
        snapshot.dailyAyahs = [PrayerWidgetSnapshot.dayKey(for: now, in: newYork): ayah]
        XCTAssertEqual(snapshot.dailyAyah(on: now, phoneTimeZone: newYork), ayah)
        XCTAssertNil(snapshot.dailyAyah(on: now.addingTimeInterval(2 * 3600), phoneTimeZone: newYork), "a new day where the phone is")
        snapshot.languageCode = "en"
        XCTAssertNil(snapshot.dailyAyah(on: now, phoneTimeZone: newYork), "never an ayah written in the other language")
        XCTAssertEqual(ayah.link, URL(string: "darulirfan://quran/2/255"))
    }

    func testWidgetsWriteWesternDigitsInUrdu() {
        var snapshot = snapshot()
        XCTAssertNil(snapshot.displayLocale)
        XCTAssertNil(snapshot.readsRightToLeft)
        snapshot.languageCode = "ur"
        XCTAssertEqual(snapshot.displayLocale?.numberingSystem.identifier, "latn")
        XCTAssertEqual(snapshot.readsRightToLeft, true)
        let text = Date(timeIntervalSince1970: 0).formatted(.dateTime.hour().minute().locale(snapshot.displayLocale!))
        XCTAssertNil(text.rangeOfCharacter(from: CharacterSet(charactersIn: "۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩")))
    }

    func testNewSnapshotFieldsRoundTripAndOldSnapshotsStillDecode() throws {
        var snapshot = snapshot()
        snapshot.languageCode = "en"
        snapshot.dailyAyahs = ["2026-10-28": WidgetDailyAyah(surah: 1, ayahStart: 1, ayahEnd: 7, arabic: "a", translation: nil, reference: "r", languageCode: "en")]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(PrayerWidgetSnapshot.self, from: encoder.encode(snapshot)), snapshot)

        let legacy = """
        {"version":1,"generatedAt":"2026-07-30T10:00:00Z","placeName":"Test","upcomingTimes":[],"hijriDateText":"15 Safar 1448"}
        """
        let decoded = try decoder.decode(PrayerWidgetSnapshot.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.languageCode)
        XCTAssertNil(decoded.dailyAyahs)
    }

    // MARK: - Watch seal

    func testWatchSealMotionStates() {
        XCTAssertEqual(WatchSealMotion.resolve(reduceMotion: false, luminanceReduced: false), .animated)
        XCTAssertEqual(WatchSealMotion.resolve(reduceMotion: true, luminanceReduced: false), .still)
        XCTAssertEqual(WatchSealMotion.resolve(reduceMotion: false, luminanceReduced: true), .dimmed)
        XCTAssertEqual(WatchSealMotion.resolve(reduceMotion: true, luminanceReduced: true), .dimmed)
    }

    func testWatchSealDrawsInThenBreathes() {
        let motion = WatchSealMotion.animated
        XCTAssertEqual(motion.phase(elapsed: 0).reveal, 0, accuracy: 0.0001)
        XCTAssertEqual(motion.phase(elapsed: WatchSealPhase.revealDuration).reveal, 1, accuracy: 0.0001)
        XCTAssertEqual(motion.phase(elapsed: 60).reveal, 1, accuracy: 0.0001)
        XCTAssertNotEqual(motion.phase(elapsed: 3).sweepDegrees, motion.phase(elapsed: 6).sweepDegrees)
        XCTAssertNotEqual(motion.phase(elapsed: 2).glow, motion.phase(elapsed: 4.6).glow)
    }

    func testStillAndDimmedSealsNeverMove() {
        for motion in [WatchSealMotion.still, .dimmed] {
            XCTAssertEqual(motion.phase(elapsed: 0), motion.phase(elapsed: 37))
            XCTAssertEqual(motion.phase(elapsed: 0).reveal, 1)
        }
        let dimmed = WatchSealMotion.dimmed.phase(elapsed: 0)
        XCTAssertFalse(dimmed.showsSweep)
        XCTAssertEqual(dimmed.glow, 0)
        XCTAssertLessThan(dimmed.opacity, 1)
    }

    // MARK: - Widget guide offer

    func testWidgetGuideIsOfferedOnceAfterAPlaceIsSet() {
        XCTAssertFalse(WidgetGuideOffer.shouldOffer(handled: false, hasPlace: false))
        XCTAssertTrue(WidgetGuideOffer.shouldOffer(handled: false, hasPlace: true))
        XCTAssertFalse(WidgetGuideOffer.shouldOffer(handled: true, hasPlace: true))
    }
}
