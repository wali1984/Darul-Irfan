import Foundation
import Observation
import WidgetKit

/// App-wide observable session state: settings, resolved place, and the
/// downstream effects of changing either (notification rescheduling, widget
/// snapshot refresh). Feature ViewModels read from this and call
/// `updateSettings` rather than persisting settings themselves.
@Observable
@MainActor
final class AppState {
    private(set) var settings: AppSettings = .default
    private(set) var isLoaded = false

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    // MARK: - Lifecycle

    /// Loads settings; called once before the root view appears.
    func bootstrap() async {
        settings = await dependencies.settingsStore.load()
        isLoaded = true
    }

    /// The place used for calculations right now: manual place if chosen,
    /// otherwise the last device-resolved place. Nil until onboarding
    /// provides one.
    var activePlace: PlaceCoordinate? {
        switch settings.locationMode {
        case .manual: return settings.manualPlace ?? settings.lastKnownPlace
        case .device: return settings.lastKnownPlace
        }
    }

    // MARK: - Settings mutations

    /// Applies a mutation to settings, persists it, and runs side effects
    /// (reschedule notifications, refresh widget snapshot) when prayer-time
    /// inputs changed.
    func updateSettings(_ mutate: (inout AppSettings) -> Void) async {
        let before = settings
        var updated = settings
        mutate(&updated)
        settings = updated
        await dependencies.settingsStore.save(updated)

        let calculationChanged = before.calculation != updated.calculation
            || before.manualPlace != updated.manualPlace
            || before.locationMode != updated.locationMode
            || before.lastKnownPlace != updated.lastKnownPlace
            || before.prayerNotifications != updated.prayerNotifications
            || before.hijri != updated.hijri
        if calculationChanged {
            await refreshScheduledNotificationsAndWidgets()
        }
    }

    /// Resolves a fresh device location (if permitted and in device mode)
    /// and stores it as the last known place. Coordinates are rounded to
    /// city precision (~1.1 km) before comparison and persistence, so the
    /// app never stores a precise location and unchanged fixes are no-ops.
    func refreshDevicePlaceIfNeeded() async {
        guard settings.locationMode == .device else { return }
        guard let place = try? await dependencies.location.currentPlace() else { return }
        let rounded = place.roundedToCityPrecision()
        guard rounded != settings.lastKnownPlace else { return }
        // updateSettings refreshes notifications/widgets via the
        // lastKnownPlace change; nothing further needed.
        await updateSettings { $0.lastKnownPlace = rounded }
    }

    // MARK: - Side effects

    /// Recomputes the rolling notification window and the widget snapshot.
    /// Call on: settings change (handled above), app foreground, timezone
    /// change notification, and after onboarding completes.
    func refreshScheduledNotificationsAndWidgets() async {
        guard let place = activePlace else { return }
        // Start one day back so yesterday's Isha stays scheduled when it
        // falls after midnight; the notification planner and the widgets
        // both filter out times already past.
        let schedules = dependencies.prayerCalculation.schedules(
            forDaysStarting: Date().addingTimeInterval(-86_400),
            days: 9,
            at: place,
            preferences: settings.calculation
        )
        await dependencies.notifications.reschedulePrayerNotifications(
            schedules: schedules,
            preferences: settings.prayerNotifications
        )
        writeWidgetSnapshot(schedules: schedules, place: place)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func writeWidgetSnapshot(schedules: [PrayerDaySchedule], place: PlaceCoordinate) {
        let upcoming: [WidgetPrayerTime] = schedules
            .flatMap { $0.orderedTimes }
            .sorted { $0.time < $1.time }
            .map { entry in
                WidgetPrayerTime(
                    prayerKey: entry.prayer.rawValue,
                    displayName: String(localized: String.LocalizationValue(entry.prayer.englishName)),
                    time: entry.time,
                    isObligatory: entry.prayer.isObligatory
                )
            }

        let now = Date()
        let hijriText = dependencies.hijri.hijriDateText(
            for: now,
            offsetDays: settings.hijri.dayOffset,
            locale: Locale.current
        )

        // Ramadan extras: the next upcoming fajr/maghrib (not day 0's, which
        // would already be in the past for most of the day), so the widget's
        // pre-dawn "Suhoor ends" and afternoon "Iftar" captions keep working
        // after today's instants pass. Ramadan membership is checked at each
        // event's own time so the fajr after the last fast (Eid morning) is
        // never labelled as suhoor; both stay nil outside Ramadan.
        let hijriOffset = settings.hijri.dayOffset
        let suhoorEndsAt: Date? = upcoming.first { entry in
            entry.prayerKey == Prayer.fajr.rawValue
                && entry.time > now
                && dependencies.hijri.isRamadan(entry.time, offsetDays: hijriOffset)
        }?.time
        let iftarAt: Date? = upcoming.first { entry in
            entry.prayerKey == Prayer.maghrib.rawValue
                && entry.time > now
                && dependencies.hijri.isRamadan(entry.time, offsetDays: hijriOffset)
        }?.time

        let snapshot = PrayerWidgetSnapshot(
            generatedAt: now,
            placeName: place.name,
            upcomingTimes: upcoming,
            hijriDateText: hijriText,
            suhoorEndsAt: suhoorEndsAt,
            iftarAt: iftarAt,
            zikrSessions: PrayerWidgetSnapshot.load()?.zikrSessions
        )
        snapshot.save()
        dependencies.watchSync.send(snapshot)
        Task {
            await dependencies.prayerLiveActivity.update(
                upcoming: upcoming,
                placeName: place.name,
                enabled: settings.liveActivitiesEnabled
            )
        }
    }
}

// MARK: - City-precision rounding

extension PlaceCoordinate {
    /// A copy with latitude/longitude rounded to 2 decimal places (~1.1 km,
    /// city precision). Every device-resolved place is rounded this way
    /// before persisting, backing the privacy promise that precise
    /// coordinates are never stored; the difference is far below what
    /// affects prayer-time or qibla calculations.
    func roundedToCityPrecision() -> PlaceCoordinate {
        var copy = self
        copy.latitude = (latitude * 100).rounded() / 100
        copy.longitude = (longitude * 100).rounded() / 100
        return copy
    }
}
