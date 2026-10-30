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

/// Drives Today's prayer card and the Prayer times page it opens: today's
/// schedule, the next prayer, Ramadan countdowns, and the gentle prayer
/// tracker, a week at a time back from today. Reads the active place and
/// settings from `AppState`; never persists settings itself.
@Observable
@MainActor
final class PrayerViewModel {

    // MARK: - Dependencies

    private let prayerCalculation: any PrayerCalculationServicing
    private let hijriService: any HijriCalendarServicing
    private let trackerRepository: any TrackerRepositoryProtocol
    private let locationService: any LocationServicing
    private let devotionalMetrics: DevotionalMetricsSyncService
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
    /// The day without the year ("Friday, 30 October"), for the line under
    /// Today's title and the Prayer times page.
    private(set) var gregorianShortText: String = ""
    private(set) var hijriDateText: String = ""
    private(set) var isRamadan = false
    private(set) var ramadanCountdown: RamadanCountdownTarget?
    private(set) var todayCompletions: [Prayer: PrayerCompletion] = [:]
    private(set) var streakSummary: PrayerStreakSummary?
    private(set) var isRequestingLocation = false
    private(set) var locationRequestFailed = false

    // MARK: - Tracker week (the Prayer times page)

    /// The week the tracker shows: 0 is the week holding today, -1 the week
    /// before it, and so on back. Never after the current week.
    private(set) var trackerWeekOffset = 0
    /// The day chosen in the tracker; nil shows the week's own day (today in
    /// the current week, a past week's Friday).
    private(set) var trackerSelectedDay: Date?
    /// Marks of the days the tracker has shown, by day key. Today's marks
    /// are read from `todayCompletions`, which Today's prayer card changes.
    private(set) var trackerMarks: [String: [Prayer: PrayerCompletion]] = [:]

    @ObservationIgnored private var rolloverTask: Task<Void, Never>?

    // MARK: - Init

    init(dependencies: AppDependencies, appState: AppState) {
        self.prayerCalculation = dependencies.prayerCalculation
        self.hijriService = dependencies.hijri
        self.trackerRepository = dependencies.trackerRepository
        self.locationService = dependencies.location
        self.devotionalMetrics = dependencies.devotionalMetrics
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
        let placeTimeZone = appState.activePlace?.timeZone ?? .current
        hijriDateText = hijriService.hijriDateText(
            for: now,
            offsetDays: settings.hijri.dayOffset,
            locale: appLocale,
            timeZone: placeTimeZone
        )
        gregorianDateText = now.formatted(
            Date.FormatStyle(date: .complete, time: .omitted, timeZone: placeTimeZone).locale(appLocale)
        )
        gregorianShortText = now.formatted(
            Date.FormatStyle(timeZone: placeTimeZone).weekday(.wide).day().month(.wide).locale(appLocale)
        )
        isRamadan = hijriService.isRamadan(now, offsetDays: settings.hijri.dayOffset, timeZone: placeTimeZone)

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
        // Only while tomorrow is still a fast: after the last iftar the next
        // Fajr is Eid morning, not the end of a suhoor.
        let placeTimeZone = appState.activePlace?.timeZone ?? .current
        if let fajrTomorrow = tomorrowSchedule?.time(for: .fajr), now < fajrTomorrow,
           hijriService.isRamadan(fajrTomorrow, offsetDays: appState.settings.hijri.dayOffset, timeZone: placeTimeZone) {
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

    /// How far the time has run (0...1) towards the next prayer, from the
    /// last of today's times before now (the start of the day before Fajr),
    /// for the ring on Today's prayer card.
    func nextPrayerProgress(at now: Date) -> Double {
        guard let next = nextPrayer else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = appState.activePlace?.timeZone ?? .current
        let times = (todaySchedule?.orderedTimes ?? []).map { $0.time }
        return TodayHeroMath.ringProgress(
            now: now,
            next: next.time,
            earlierTimes: times,
            dayStart: calendar.startOfDay(for: now)
        )
    }

    /// Today's six times as text, for Share on the Prayer times page: the
    /// date, the place, each time, and the method they follow.
    var todayShareText: String {
        guard let schedule = todaySchedule else { return "" }
        var lines: [String] = []
        lines.append(String(localized: "Darul Irfan — prayer times for \(gregorianDateText)"))
        if let place = appState.activePlace {
            lines.append(place.name)
        }
        lines.append("")
        // Names in the app's language, as the screen shows them.
        for prayer in Prayer.allCases {
            guard let time = schedule.time(for: prayer) else { continue }
            let name = String(localized: String.LocalizationValue(prayer.englishName))
            lines.append("\(name): \(timeText(time))")
        }
        lines.append("")
        let method = String(localized: String.LocalizationValue(appState.settings.calculation.method.englishName))
        lines.append(String(localized: "Method: \(method)"))
        return lines.joined(separator: "\n")
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

    var completedPrayerCount: Int {
        Prayer.obligatory.filter { completion(for: $0).countsAsPrayed }.count
    }

    /// Cycles today's mark for one prayer (Today's prayer card):
    /// unmarked -> prayed -> jamaat -> qaza -> unmarked, and persists.
    func cycleCompletion(for prayer: Prayer) async {
        await cycleCompletion(for: prayer, on: Date())
    }

    /// Cycles one prayer's mark on any day up to today, and persists it
    /// through the tracker repository as that day's entry, the same write
    /// today's mark has always made. A day after today is never marked.
    func cycleCompletion(for prayer: Prayer, on day: Date) async {
        let now = Date()
        guard let entry = PrayerTrackerCalendar.entry(
            cycling: completion(for: prayer, on: day),
            for: prayer,
            on: day,
            now: now
        ) else { return }
        let todayKey = DayKey.make(from: now)
        if entry.dayKey == todayKey {
            todayCompletions[prayer] = entry.completion
        }
        trackerMarks[entry.dayKey, default: [:]][prayer] = entry.completion
        do {
            try await trackerRepository.savePrayerLog(entry)
            // The streak always runs to today, whichever day was marked.
            streakSummary = try await trackerRepository.streakSummary(
                endingAt: todayKey,
                windowDays: 30
            )
            await devotionalMetrics.refresh(reference: now)
        } catch {
            // Persistence hiccups must never interrupt worship; the in-memory
            // mark stays and will be retried on the next cycle/refresh.
        }
    }

    /// A prayer's mark on any day: today's from `todayCompletions`, an
    /// earlier day's from the marks the tracker has loaded.
    func completion(for prayer: Prayer, on day: Date) -> PrayerCompletion {
        let key = DayKey.make(from: day)
        if key == DayKey.make(from: Date()) {
            return completion(for: prayer)
        }
        return trackerMarks[key]?[prayer] ?? .unmarked
    }

    /// How many of a day's five prayers are marked prayed, alone or in
    /// congregation.
    func prayedCount(on day: Date) -> Int {
        Prayer.obligatory.filter { completion(for: $0, on: day).countsAsPrayed }.count
    }

    // MARK: - Tracker week

    /// The tracker's calendar: Saturday-to-Friday weeks in the phone's time
    /// zone, as tracker day keys are.
    private var trackerCalendar: Calendar {
        PrayerTrackerCalendar.calendar()
    }

    /// The seven days of the week shown, Saturday first.
    var trackerWeekDays: [Date] {
        PrayerTrackerCalendar.days(weekOffset: trackerWeekOffset, today: Date(), calendar: trackerCalendar)
    }

    /// The day whose five prayers the tracker shows.
    var trackerShownDay: Date {
        PrayerTrackerCalendar.shownDay(
            selected: trackerSelectedDay,
            weekOffset: trackerWeekOffset,
            today: Date(),
            calendar: trackerCalendar
        )
    }

    /// Next week is offered only from a past week.
    var canShowNextTrackerWeek: Bool {
        PrayerTrackerCalendar.canShowNextWeek(from: trackerWeekOffset)
    }

    /// Any day up to today can be marked; later days wait.
    func isTrackerDayMarkable(_ day: Date) -> Bool {
        PrayerTrackerCalendar.isMarkable(day, today: Date(), calendar: trackerCalendar)
    }

    /// Whether `day` is today, where the phone is.
    func isTrackerToday(_ day: Date) -> Bool {
        PrayerTrackerCalendar.isSameDay(day, Date(), calendar: trackerCalendar)
    }

    /// Shows the week `offset` weeks from the current one (never later than
    /// it) on its own day, and loads its marks.
    func showTrackerWeek(offset: Int) async {
        trackerWeekOffset = PrayerTrackerCalendar.clampedWeekOffset(offset)
        trackerSelectedDay = nil
        await reloadTrackerWeek()
    }

    /// Chooses the day whose prayers the tracker shows. A day after today
    /// cannot be chosen.
    func selectTrackerDay(_ day: Date) {
        guard isTrackerDayMarkable(day) else { return }
        trackerSelectedDay = day
    }

    /// Reads the shown week's marks through the tracker repository. Only
    /// this week's days are replaced, so a slower read for another week
    /// never clears these.
    func reloadTrackerWeek() async {
        let keys = PrayerTrackerCalendar.dayKeys(weekOffset: trackerWeekOffset, today: Date(), calendar: trackerCalendar)
        do {
            let entries = try await trackerRepository.prayerLog(dayKeys: keys)
            var byDay: [String: [Prayer: PrayerCompletion]] = [:]
            for entry in entries {
                byDay[entry.dayKey, default: [:]][entry.prayer] = entry.completion
            }
            for key in keys {
                trackerMarks[key] = byDay[key] ?? [:]
            }
        } catch {
            // Keep whatever was shown before; the tracker is non-critical.
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
            await devotionalMetrics.refresh(reference: now)
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
