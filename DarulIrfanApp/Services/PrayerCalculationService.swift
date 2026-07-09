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

        let times: [Prayer: Date] = [
            .fajr: prayerTimes.fajr,
            .sunrise: prayerTimes.sunrise,
            .dhuhr: prayerTimes.dhuhr,
            .asr: prayerTimes.asr,
            .maghrib: prayerTimes.maghrib,
            .isha: prayerTimes.isha,
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
        // Today's and tomorrow's schedules always contain the next prayer.
        let twoDays = schedules(
            forDaysStarting: reference,
            days: 2,
            at: place,
            preferences: preferences
        )
        for daySchedule in twoDays {
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
