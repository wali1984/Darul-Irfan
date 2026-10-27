import Foundation
import Adhan

/// Live prayer-time engine backed by batoulapps/adhan-swift. All Adhan types
/// stay inside this file; the rest of the app only sees domain models.
struct PrayerCalculationService: PrayerCalculationServicing, QiblaServicing {

    // MARK: - PrayerCalculationServicing

    func schedule(
        for date: DateComponents,
        at place: PlaceCoordinate,
        preferences: PrayerCalculationPreferences
    ) -> PrayerDaySchedule? {
        let coordinates = Coordinates(latitude: place.latitude, longitude: place.longitude)
        let parameters = calculationParameters(for: preferences)
        guard let prayerTimes = PrayerTimes(
            coordinates: coordinates,
            date: date,
            calculationParameters: parameters
        ) else {
            return nil
        }

        var fajr = prayerTimes.fajr
        var isha = prayerTimes.isha

        // "Automatic" means the sky, wherever the sky gives an answer.
        // adhan-swift treats its high-latitude rule as a limit and applies it
        // even on nights when the twilight angle is reached: in Vancouver in
        // late June it moved Fajr from the true 02:36 to 04:00. So on a night
        // when the sun does sink below the Fajr or Isha angle, the time comes
        // from a pass with the most permissive rule (middle of the night,
        // which only binds when twilight never comes) - that is, from the
        // astronomy. On nights it does not (London in June at 18 degrees) the
        // recommended rule decides, as before. An explicitly chosen rule is
        // always honoured as the library applies it.
        if preferences.highLatitudeRule == .automatic, preferences.method != .moonsightingCommittee {
            let fajrReached = Self.sunReaches(depression: parameters.fajrAngle, latitude: place.latitude, date: date, hour: 0)
            let ishaReached = parameters.ishaInterval == 0
                && Self.sunReaches(depression: parameters.ishaAngle, latitude: place.latitude, date: date, hour: 24)
            if fajrReached || ishaReached {
                var permissive = parameters
                permissive.highLatitudeRule = .middleOfTheNight
                if let astronomical = PrayerTimes(coordinates: coordinates, date: date, calculationParameters: permissive) {
                    if fajrReached { fajr = astronomical.fajr }
                    if ishaReached { isha = astronomical.isha }
                }
            }
        }

        // Umm al-Qura sets Isha at 90 minutes after Maghrib, and at 120 in
        // Ramadan (the Saudi calendar's own rule, which the library leaves to
        // the app). Without it Makkah's Ramadan Isha was half an hour early.
        if preferences.method == .ummAlQura, Self.isRamadanUmmAlQura(date) {
            isha = isha.addingTimeInterval(30 * 60)
        }

        let times: [Prayer: Date] = [
            .fajr: fajr,
            .sunrise: prayerTimes.sunrise,
            .dhuhr: prayerTimes.dhuhr,
            .asr: prayerTimes.asr,
            .maghrib: prayerTimes.maghrib,
            .isha: isha,
        ]
        return PrayerDaySchedule(date: date, location: place, times: times)
    }

    func schedules(
        forDaysStarting start: Date,
        days: Int,
        at place: PlaceCoordinate,
        preferences: PrayerCalculationPreferences
    ) -> [PrayerDaySchedule] {
        guard days > 0 else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            return schedule(for: components, at: place, preferences: preferences)
        }
    }

    func nextPrayer(
        after reference: Date,
        at place: PlaceCoordinate,
        preferences: PrayerCalculationPreferences
    ) -> NextPrayerInfo? {
        // Start one day early: some methods/latitudes put Isha after
        // midnight, so just after midnight the next prayer can belong to
        // yesterday's schedule. The `> reference` filter below discards
        // everything already past.
        let window = schedules(
            forDaysStarting: reference.addingTimeInterval(-86_400),
            days: 3,
            at: place,
            preferences: preferences
        )
        for daySchedule in window {
            let upcoming = daySchedule.orderedTimes
                .filter { $0.prayer.isObligatory && $0.time > reference }
            if let first = upcoming.first {
                return NextPrayerInfo(
                    prayer: first.prayer,
                    time: first.time,
                    scheduleDate: daySchedule.date
                )
            }
        }
        return nil
    }

    /// Whether the sun sinks at least `depression` degrees below the horizon
    /// on the night at the start (`hour` 0) or end (`hour` 24) of a civil
    /// date. The lowest altitude, at solar midnight, is |latitude| plus the
    /// declination toward the visible pole, minus 90 degrees. Half a degree of
    /// margin keeps a borderline night with the recommended rule: there the
    /// astronomy would only just give an answer and the rule is the safer one.
    static func sunReaches(depression: Double, latitude: Double, date: DateComponents, hour: Double) -> Bool {
        guard depression > 0 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let day = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day)),
              let ordinal = calendar.ordinality(of: .day, in: .year, for: day) else { return true }
        // Spencer's series: declination within about 0.04 degrees.
        let g = 2 * Double.pi / 365 * (Double(ordinal - 1) + (hour - 12) / 24)
        let declination = (0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2 * g)
            + 0.000907 * sin(2 * g) - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)) * 180 / Double.pi
        let towardPole = latitude >= 0 ? declination : -declination
        let lowest = abs(latitude) + towardPole - 90
        return lowest < -(depression + 0.5)
    }

    /// Whether a civil date falls in Ramadan on the Umm al-Qura calendar.
    static func isRamadanUmmAlQura(_ date: DateComponents) -> Bool {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "Asia/Riyadh") ?? .current
        guard let day = gregorian.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 12)) else {
            return false
        }
        var hijri = Calendar(identifier: .islamicUmmAlQura)
        hijri.timeZone = gregorian.timeZone
        return hijri.component(.month, from: day) == 9
    }

    // MARK: - QiblaServicing

    func qiblaDirection(from place: PlaceCoordinate) -> Double {
        let coordinates = Coordinates(latitude: place.latitude, longitude: place.longitude)
        return Qibla(coordinates: coordinates).direction
    }

    // MARK: - Mapping to Adhan

    private func calculationParameters(
        for preferences: PrayerCalculationPreferences
    ) -> CalculationParameters {
        var parameters = adhanMethod(for: preferences.method).params

        if preferences.method == .custom {
            parameters.fajrAngle = preferences.customAngles.fajrAngle
            if preferences.customAngles.ishaIntervalMinutes > 0 {
                parameters.ishaInterval = preferences.customAngles.ishaIntervalMinutes
            } else {
                parameters.ishaAngle = preferences.customAngles.ishaAngle
            }
        }

        parameters.madhab = preferences.asrMethod == .hanafi ? .hanafi : .shafi

        switch preferences.highLatitudeRule {
        case .automatic:
            parameters.highLatitudeRule = nil // library picks recommended rule
        case .middleOfTheNight:
            parameters.highLatitudeRule = .middleOfTheNight
        case .seventhOfTheNight:
            parameters.highLatitudeRule = .seventhOfTheNight
        case .twilightAngle:
            parameters.highLatitudeRule = .twilightAngle
        }

        let userOffsets = preferences.adjustments
        parameters.adjustments = PrayerAdjustments(
            fajr: userOffsets.fajr,
            sunrise: userOffsets.sunrise,
            dhuhr: userOffsets.dhuhr,
            asr: userOffsets.asr,
            maghrib: userOffsets.maghrib,
            isha: userOffsets.isha
        )

        return parameters
    }

    private func adhanMethod(for choice: CalculationMethodChoice) -> CalculationMethod {
        switch choice {
        case .muslimWorldLeague: return .muslimWorldLeague
        case .northAmerica: return .northAmerica
        case .egyptian: return .egyptian
        case .ummAlQura: return .ummAlQura
        case .karachi: return .karachi
        case .moonsightingCommittee: return .moonsightingCommittee
        case .dubai: return .dubai
        case .kuwait: return .kuwait
        case .qatar: return .qatar
        case .singapore: return .singapore
        case .tehran: return .tehran
        case .turkey: return .turkey
        case .custom: return .other
        }
    }
}
