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

    /// Resolves a fresh device location (if permitted and in device mode),
    /// stores it as the last known place, and refreshes side effects when it
    /// moved meaningfully.
    func refreshDevicePlaceIfNeeded() async {
        guard settings.locationMode == .device else { return }
        guard let place = try? await dependencies.location.currentPlace() else { return }
        let previous = settings.lastKnownPlace
        let moved = previous.map {
            abs($0.latitude - place.latitude) > 0.02 || abs($0.longitude - place.longitude) > 0.02
        } ?? true
        await updateSettings { $0.lastKnownPlace = place }
        if !moved {
            return
        }
        // updateSettings already refreshed notifications/widgets via the
        // lastKnownPlace change; nothing further needed.
    }

    // MARK: - Side effects

    /// Recomputes the rolling notification window and the widget snapshot.
    /// Call on: settings change (handled above), app foreground, timezone
    /// change notification, and after onboarding completes.
    func refreshScheduledNotificationsAndWidgets() async {
        guard let place = activePlace else { return }
        let schedules = dependencies.prayerCalculation.schedules(
            forDaysStarting: Date(),
            days: 8,
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
                    displayName: entry.prayer.englishName,
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

        var suhoorEndsAt: Date?
        var iftarAt: Date?
        if dependencies.hijri.isRamadan(now, offsetDays: settings.hijri.dayOffset),
           let today = schedules.first {
            suhoorEndsAt = today.time(for: .fajr)
            iftarAt = today.time(for: .maghrib)
        }

        PrayerWidgetSnapshot(
            generatedAt: now,
            placeName: place.name,
            upcomingTimes: upcoming,
            hijriDateText: hijriText,
            suhoorEndsAt: suhoorEndsAt,
            iftarAt: iftarAt
        ).save()
    }
}
