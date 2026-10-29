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

    /// The onboarding page in view, kept here rather than in the flow's own
    /// state: choosing a language rebuilds the view tree so every string
    /// re-resolves, which used to send the flow back to its welcome page.
    /// For this session only.
    @ObservationIgnored var onboardingStep: OnboardingStep = .welcome

    private let dependencies: AppDependencies

    /// The refresh running now; a newer request waits for it (see
    /// `refreshScheduledNotificationsAndWidgets`).
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Counts refresh requests, so a queued one that a newer request has
    /// overtaken can give way to it.
    @ObservationIgnored private var refreshGeneration = 0
    /// Whether notifications were allowed when the alerts were last scheduled.
    @ObservationIgnored private var notificationsAllowedAtLastRefresh: Bool?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        // Zikr sessions announced against a prayer time are resolved day by
        // day for the widgets and the Watch.
        dependencies.watchSync.prayerCalculation = dependencies.prayerCalculation
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
    /// (reschedule notifications, refresh widget snapshot) when anything the
    /// alerts or the widgets show changed.
    func updateSettings(_ mutate: (inout AppSettings) -> Void) async {
        let before = settings
        var updated = settings
        mutate(&updated)
        settings = updated
        await dependencies.settingsStore.save(updated)

        if before.language != updated.language {
            // Alert titles and the widgets' prayer names are resolved when
            // they are written, so the new language must be in force first.
            LanguageManager.apply(updated.language)
        }

        let alertsOrWidgetsChanged = before.calculation != updated.calculation
            || before.manualPlace != updated.manualPlace
            || before.locationMode != updated.locationMode
            || before.lastKnownPlace != updated.lastKnownPlace
            || before.prayerNotifications != updated.prayerNotifications
            || before.hijri != updated.hijri
            || before.language != updated.language
            || before.liveActivitiesEnabled != updated.liveActivitiesEnabled
        if alertsOrWidgetsChanged {
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

    /// Recomputes the reminders, the rolling notification window and the
    /// widget snapshot. Call on: settings change (handled above), app
    /// foreground, timezone change notification, and after onboarding
    /// completes.
    ///
    /// Requests are queued, never run side by side. Each reschedule reads the
    /// pending alerts, removes them and adds its own, so two that interleave
    /// can leave an older setting's alerts behind: tapping a prayer's bell
    /// quickly from Off round to Off again could keep its Azan alerts. A
    /// queued request that a newer one has overtaken by its turn is skipped,
    /// and the newer one runs with the latest settings.
    func refreshScheduledNotificationsAndWidgets() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let previous = refreshTask
        let task = Task { @MainActor in
            await previous?.value
            guard generation == self.refreshGeneration else { return }
            await self.performRefresh()
        }
        refreshTask = task
        await task.value
    }

    /// True when notifications were allowed or turned off (in the Settings
    /// app, say) since the alerts were last scheduled. Requests added while
    /// they were off were rejected, so the foreground refresh must not wait
    /// out its throttle then.
    func notificationPermissionChangedSinceLastRefresh() async -> Bool {
        let allowed = await dependencies.notifications.notificationsAllowed()
        guard let previous = notificationsAllowedAtLastRefresh else { return false }
        return previous != allowed
    }

    private func performRefresh() async {
        notificationsAllowedAtLastRefresh = await dependencies.notifications.notificationsAllowed()
        let settings = self.settings
        guard let place = activePlace else {
            // No place (device mode without a fix): the alerts and widget
            // times of a place no longer in use must not stay behind.
            await dependencies.notifications.reschedulePrayerNotifications(
                schedules: [],
                preferences: settings.prayerNotifications
            )
            PrayerWidgetSnapshot.remove()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        // Start one day back so yesterday's Isha stays scheduled when it
        // falls after midnight; the notification planner and the widgets
        // both filter out times already past.
        let schedules = dependencies.prayerCalculation.schedules(
            forDaysStarting: Date().addingTimeInterval(-86_400),
            days: 9,
            at: place,
            preferences: settings.calculation
        )
        // My Day and zikr reminders first: the prayer plan sizes itself to
        // the room other reminders leave in the 64-alert budget, so it must
        // see them.
        await MyDayReminders.refresh(
            store: .shared,
            notifications: dependencies.notifications,
            schedules: schedules
        )
        await ZikrReminders.refreshOfficial(
            notifications: dependencies.notifications,
            calculator: dependencies.prayerCalculation
        )
        await dependencies.notifications.reschedulePrayerNotifications(
            schedules: schedules,
            preferences: settings.prayerNotifications
        )
        writeWidgetSnapshot(schedules: schedules, place: place, settings: settings)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func writeWidgetSnapshot(schedules: [PrayerDaySchedule], place: PlaceCoordinate, settings: AppSettings) {
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
        let hijriOffset = settings.hijri.dayOffset
        let locale = LanguageManager.locale(for: settings.language)
        let hijriText = dependencies.hijri.hijriDateText(
            for: now,
            offsetDays: hijriOffset,
            locale: locale,
            timeZone: place.timeZone
        )
        // The Hijri date of every day the snapshot covers, so the widgets and
        // the Watch turn the date over at midnight without the app running.
        var placeCalendar = Calendar(identifier: .gregorian)
        placeCalendar.timeZone = place.timeZone
        var hijriDates: [String: String] = [:]
        for schedule in schedules {
            guard let day = placeCalendar.date(from: schedule.date),
                  let noon = placeCalendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) else { continue }
            hijriDates[PrayerWidgetSnapshot.dayKey(for: noon, in: place.timeZone)] = dependencies.hijri.hijriDateText(
                for: noon,
                offsetDays: hijriOffset,
                locale: locale,
                timeZone: place.timeZone
            )
        }

        // Ramadan extras: the next upcoming fajr/maghrib (not day 0's, which
        // would already be in the past for most of the day), so the widget's
        // pre-dawn "Suhoor ends" and afternoon "Iftar" captions keep working
        // after today's instants pass. Ramadan membership is checked at each
        // event's own time so the fajr after the last fast (Eid morning) is
        // never labelled as suhoor; both stay nil outside Ramadan.
        let suhoorEndsAt: Date? = upcoming.first { entry in
            entry.prayerKey == Prayer.fajr.rawValue
                && entry.time > now
                && dependencies.hijri.isRamadan(entry.time, offsetDays: hijriOffset, timeZone: place.timeZone)
        }?.time
        let iftarAt: Date? = upcoming.first { entry in
            entry.prayerKey == Prayer.maghrib.rawValue
                && entry.time > now
                && dependencies.hijri.isRamadan(entry.time, offsetDays: hijriOffset, timeZone: place.timeZone)
        }?.time

        // Zikr occurrences come from the official schedule the app last knew
        // (bundled until the Zikr tab loads a published one), so the zikr
        // widgets and the Watch fill in without that tab being opened.
        let zikrSessions = ZikrOccurrences.widgetSessions(
            for: OfficialZikrSchedule.sessions(),
            reference: now,
            perSession: WatchSyncService.zikrOccurrencesPerSession,
            calculator: dependencies.prayerCalculation
        )

        let previousSnapshot = PrayerWidgetSnapshot.load()
        let snapshot = PrayerWidgetSnapshot(
            generatedAt: now,
            placeName: place.name,
            upcomingTimes: upcoming,
            hijriDateText: hijriText,
            suhoorEndsAt: suhoorEndsAt,
            iftarAt: iftarAt,
            zikrSessions: zikrSessions,
            devotionalMetrics: previousSnapshot?.devotionalMetrics,
            timeZoneIdentifier: place.timeZoneIdentifier,
            hijriDates: hijriDates
        )
        snapshot.save()
        dependencies.watchSync.send(snapshot)
        Task { await dependencies.devotionalMetrics.refresh(reference: now) }
        Task {
            await dependencies.prayerLiveActivity.update(
                upcoming: upcoming,
                placeName: place.name,
                timeZoneIdentifier: place.timeZoneIdentifier,
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
