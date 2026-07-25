import Foundation
import Observation

/// Target for the Ramadan countdown card: either the end of Suhoor (Fajr)
/// or Iftar (Maghrib), whichever comes next.
struct RamadanCountdownTarget: Equatable {
    enum Kind: Equatable {
        case suhoorEnds
        case iftar
    }

    var kind: Kind
    var time: Date
}

/// Drives the Prayer tab dashboard: today's schedule, the next-prayer hero,
/// Ramadan countdowns, and the gentle prayer tracker. Reads the active place
/// and settings from `AppState`; never persists settings itself.
@Observable
@MainActor
final class PrayerViewModel {

    // MARK: - Dependencies

    private let prayerCalculation: any PrayerCalculationServicing
    private let hijriService: any HijriCalendarServicing
    private let trackerRepository: any TrackerRepositoryProtocol
    private let locationService: any LocationServicing
    private let appState: AppState

    // MARK: - Published state

    private(set) var hasLoaded = false
    private(set) var todaySchedule: PrayerDaySchedule?
    private(set) var tomorrowSchedule: PrayerDaySchedule?
    private(set) var nextPrayer: NextPrayerInfo?
    /// The prayer currently in effect today (most recent obligatory prayer
    /// whose time has passed), for the gold "Now" accent.
    private(set) var currentPrayer: Prayer?
    private(set) var gregorianDateText: String = ""
    private(set) var hijriDateText: String = ""
    private(set) var isRamadan = false
    private(set) var ramadanCountdown: RamadanCountdownTarget?
    private(set) var todayCompletions: [Prayer: PrayerCompletion] = [:]
    private(set) var streakSummary: PrayerStreakSummary?
    private(set) var isRequestingLocation = false
    private(set) var locationRequestFailed = false

    @ObservationIgnored private var rolloverTask: Task<Void, Never>?

    // MARK: - Init

    init(dependencies: AppDependencies, appState: AppState) {
        self.prayerCalculation = dependencies.prayerCalculation
        self.hijriService = dependencies.hijri
        self.trackerRepository = dependencies.trackerRepository
        self.locationService = dependencies.location
        self.appState = appState
    }

    deinit {
        rolloverTask?.cancel()
    }

    // MARK: - Refresh

    /// Recomputes the schedule and reloads the tracker. Called on appear,
    /// on foreground, when settings change, and when a prayer time passes.
    func refresh() async {
        let now = Date()
        recomputeSchedule(now: now)
        await reloadTracker(now: now)
    }

    private func recomputeSchedule(now: Date) {
        let settings = appState.settings
        // Format dates in the app's chosen language, not the device locale, so
        // the day/date read in Urdu when the app is set to Urdu.
        let appLocale = LanguageManager.locale(for: settings.language)
        hijriDateText = hijriService.hijriDateText(
            for: now,
            offsetDays: settings.hijri.dayOffset,
            locale: appLocale
        )
        gregorianDateText = now.formatted(
            Date.FormatStyle(date: .complete, time: .omitted).locale(appLocale)
        )
        isRamadan = hijriService.isRamadan(now, offsetDays: settings.hijri.dayOffset)

        guard let place = appState.activePlace else {
            todaySchedule = nil
            tomorrowSchedule = nil
            nextPrayer = nil
            currentPrayer = nil
            ramadanCountdown = nil
            cancelRollover()
            hasLoaded = true
            return
        }

        let twoDays = prayerCalculation.schedules(
            forDaysStarting: now,
            days: 2,
            at: place,
            preferences: settings.calculation
        )
        todaySchedule = twoDays.first
        tomorrowSchedule = twoDays.count > 1 ? twoDays[1] : nil
        nextPrayer = prayerCalculation.nextPrayer(
            after: now,
            at: place,
            preferences: settings.calculation
        )
        currentPrayer = todaySchedule?.orderedTimes
            .filter { $0.prayer.isObligatory && $0.time <= now }
            .last?.prayer
        ramadanCountdown = isRamadan ? computeRamadanCountdown(now: now) : nil
        scheduleRolloverRefresh(now: now)
        hasLoaded = true
    }

    private func computeRamadanCountdown(now: Date) -> RamadanCountdownTarget? {
        if let fajr = todaySchedule?.time(for: .fajr), now < fajr {
            return RamadanCountdownTarget(kind: .suhoorEnds, time: fajr)
        }
        if let maghrib = todaySchedule?.time(for: .maghrib), now < maghrib {
            return RamadanCountdownTarget(kind: .iftar, time: maghrib)
        }
        if let fajrTomorrow = tomorrowSchedule?.time(for: .fajr), now < fajrTomorrow {
            return RamadanCountdownTarget(kind: .suhoorEnds, time: fajrTomorrow)
        }
        return nil
    }

    // MARK: - Rollover (no manual per-second timer; countdown text is live)

    /// Schedules one refresh shortly after the next boundary (next prayer,
    /// Ramadan target, or local midnight) so the dashboard rolls over on its
    /// own. The visible countdown itself uses `Text(_, style: .timer)`.
    private func scheduleRolloverRefresh(now: Date) {
        cancelRollover()
        var candidates: [Date] = []
        if let next = nextPrayer?.time { candidates.append(next) }
        if let target = ramadanCountdown?.time { candidates.append(target) }
        // Midnight must be the *place's* midnight, not the device's, so
        // "Today's Times" flips when the day changes at the active place.
        var calendar = Calendar.current
        calendar.timeZone = appState.activePlace?.timeZone ?? .current
        let midnightComponents = DateComponents(hour: 0, minute: 0)
        if let midnight = calendar.nextDate(
            after: now,
            matching: midnightComponents,
            matchingPolicy: .nextTime
        ) {
            candidates.append(midnight)
        }
        guard let fireAt = candidates.filter({ $0 > now }).min() else { return }
        let delaySeconds = max(1.0, fireAt.timeIntervalSince(now) + 1.0)
        rolloverTask = Task { [weak self] in
            let nanoseconds = UInt64(delaySeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            if Task.isCancelled { return }
            await self?.refresh()
        }
    }

    private func cancelRollover() {
        rolloverTask?.cancel()
        rolloverTask = nil
    }

    // MARK: - Formatting

    /// Locale-respecting hour/minute text in the active place's timezone.
    func timeText(_ date: Date) -> String {
        let timeZone = appState.activePlace?.timeZone ?? TimeZone.current
        let style = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)
        return date.formatted(style)
    }

    /// True when this row is the upcoming prayer (matches both prayer and
    /// exact time so tomorrow's Fajr never highlights today's passed Fajr).
    func isNext(prayer: Prayer, time: Date) -> Bool {
        guard let next = nextPrayer, next.prayer == prayer else { return false }
        return abs(next.time.timeIntervalSince(time)) < 1.0
    }

    // MARK: - Alerts (bell cycling)

    func alertStyle(for prayer: Prayer) -> PrayerAlertStyle {
        appState.settings.prayerNotifications.style(for: prayer)
    }

    /// Cycles Off -> Silent -> Default Sound -> Azan Clip -> Off and persists
    /// through AppState (which also reschedules notifications).
    func cycleAlertStyle(for prayer: Prayer) async {
        let next: PrayerAlertStyle
        switch alertStyle(for: prayer) {
        case .off: next = .silent
        case .silent: next = .defaultSound
        case .defaultSound: next = .azanClip
        case .azanClip: next = .off
        }
        await appState.updateSettings { settings in
            settings.prayerNotifications.styles[prayer] = next
        }
    }

    // MARK: - Tracker

    func completion(for prayer: Prayer) -> PrayerCompletion {
        todayCompletions[prayer] ?? .unmarked
    }

    /// Cycles unmarked -> prayed -> jamaat -> qaza -> unmarked and persists.
    func cycleCompletion(for prayer: Prayer) async {
        let next: PrayerCompletion
        switch completion(for: prayer) {
        case .unmarked: next = .prayed
        case .prayed: next = .jamaat
        case .jamaat: next = .qaza
        case .qaza: next = .unmarked
        }
        let now = Date()
        let entry = PrayerLogEntry(
            dayKey: DayKey.make(from: now),
            prayer: prayer,
            completion: next,
            updatedAt: now
        )
        todayCompletions[prayer] = next
        do {
            try await trackerRepository.savePrayerLog(entry)
            streakSummary = try await trackerRepository.streakSummary(
                endingAt: entry.dayKey,
                windowDays: 30
            )
        } catch {
            // Persistence hiccups must never interrupt worship; the in-memory
            // mark stays and will be retried on the next cycle/refresh.
        }
    }

    private func reloadTracker(now: Date) async {
        let dayKey = DayKey.make(from: now)
        do {
            let entries = try await trackerRepository.prayerLog(dayKeys: [dayKey])
            var map: [Prayer: PrayerCompletion] = [:]
            for entry in entries {
                map[entry.prayer] = entry.completion
            }
            todayCompletions = map
            streakSummary = try await trackerRepository.streakSummary(
                endingAt: dayKey,
                windowDays: 30
            )
        } catch {
            // Keep whatever was shown before; the tracker is non-critical.
        }
    }

    // MARK: - Location

    /// Requests device location (asking permission first) and stores the
    /// resolved place through AppState. If the app is in manual mode with no
    /// place at all, switches to device mode — an explicit user action here.
    func requestDeviceLocation() async {
        isRequestingLocation = true
        locationRequestFailed = false
        defer { isRequestingLocation = false }

        let status = await locationService.requestPermission()
        if status == .denied {
            locationRequestFailed = true
            return
        }
        if appState.settings.locationMode == .manual && appState.activePlace == nil {
            await appState.updateSettings { $0.locationMode = .device }
        }
        await appState.refreshDevicePlaceIfNeeded()
        if appState.activePlace == nil {
            locationRequestFailed = true
        } else {
            await refresh()
        }
    }
}
