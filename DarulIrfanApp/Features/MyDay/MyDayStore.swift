import Foundation
import Observation

/// The on-device home of My Day: tasks, notes and fasts in one JSON file in
/// Application Support, protected by the device passcode, excluded from
/// nothing and synced to nowhere.
@Observable
@MainActor
final class MyDayStore {
    static let shared = MyDayStore()

    private(set) var document = MyDayDocument()
    private(set) var hasLoaded = false

    @ObservationIgnored private let fileURL: URL
    /// Set when the file could not be decoded and could not be moved aside
    /// either: nothing is saved over it then.
    @ObservationIgnored private var saveBlocked = false

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = base.appendingPathComponent("MyDay", isDirectory: true)
                .appendingPathComponent("my_day.json")
        }
    }

    /// Reads the file once. The next save rewrites the whole file, so the
    /// store must never start empty over one it could not read: a file that
    /// is there but unreadable for now (before the first unlock after a
    /// restart) is tried again later, and one that does not decode is kept
    /// beside the new one rather than overwritten.
    func loadIfNeeded() {
        guard !hasLoaded else { return }
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else {
            hasLoaded = true
            return
        }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        hasLoaded = true
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            document = try decoder.decode(MyDayDocument.self, from: data)
        } catch {
            let aside = fileURL.deletingLastPathComponent()
                .appendingPathComponent("my_day.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            do {
                try manager.moveItem(at: fileURL, to: aside)
            } catch {
                saveBlocked = true
            }
        }
    }

    private func save() {
        guard hasLoaded, !saveBlocked else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(document) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Readable after first unlock so a reminder refresh in the
        // background still works; never readable on a locked, rebooted phone.
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: Tasks

    func tasks(on day: Date, calendar: Calendar = .current) -> [DayTask] {
        document.tasks.filter { $0.occurs(on: day, calendar: calendar) }
    }

    // Every change loads first, so it lands on the stored document rather
    // than replacing it.

    func upsert(_ task: DayTask) {
        loadIfNeeded()
        if let index = document.tasks.firstIndex(where: { $0.id == task.id }) {
            document.tasks[index] = task
        } else {
            document.tasks.append(task)
        }
        save()
    }

    func delete(taskID: UUID) {
        loadIfNeeded()
        document.tasks.removeAll { $0.id == taskID }
        save()
    }

    func toggleDone(taskID: UUID, on day: Date) {
        loadIfNeeded()
        guard let index = document.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let key = DayKey.make(from: day)
        if document.tasks[index].completedDays.contains(key) {
            document.tasks[index].completedDays.remove(key)
        } else {
            document.tasks[index].completedDays.insert(key)
        }
        save()
    }

    // MARK: Notes

    func upsert(_ note: DayNote) {
        loadIfNeeded()
        var note = note
        note.updatedAt = Date()
        if let index = document.notes.firstIndex(where: { $0.id == note.id }) {
            document.notes[index] = note
        } else {
            document.notes.insert(note, at: 0)
        }
        save()
    }

    func delete(noteID: UUID) {
        loadIfNeeded()
        document.notes.removeAll { $0.id == noteID }
        save()
    }

    func notes(about reference: NoteReference) -> [DayNote] {
        document.notes.filter { $0.reference == reference }
    }

    // MARK: Fasting

    func fast(on day: Date) -> FastKind? {
        document.fasts[DayKey.make(from: day)]
    }

    func setFast(_ kind: FastKind?, on day: Date) {
        loadIfNeeded()
        document.fasts[DayKey.make(from: day)] = kind
        save()
    }

    func fastCount(inYearOf date: Date, kind: FastKind? = nil, calendar: Calendar = .current) -> Int {
        let year = String(format: "%04d", calendar.component(.year, from: date))
        return document.fasts.filter { key, value in
            key.hasPrefix(year) && (kind == nil || value == kind)
        }.count
    }
}

// MARK: - Planning (pure)

/// A task with the time it falls on a given day (nil when untimed).
struct PlannedTask: Identifiable {
    let task: DayTask
    let time: Date?
    var id: UUID { task.id }
}

/// Works out when a task falls, from the clock or from the day's prayer times.
enum MyDayPlanner {
    /// The time of `task` on `day`, or nil for an untimed task or when the
    /// prayer it follows has no time that day.
    static func time(
        of task: DayTask,
        on day: Date,
        schedule: PrayerDaySchedule?,
        calendar: Calendar = .current
    ) -> Date? {
        switch task.timing {
        case .anytime:
            return nil
        case .clock(let hour, let minute):
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        case .afterPrayer(let prayer, let minutes):
            return schedule?.time(for: prayer)?.addingTimeInterval(TimeInterval(minutes * 60))
        case .beforePrayer(let prayer, let minutes):
            return schedule?.time(for: prayer)?.addingTimeInterval(TimeInterval(-minutes * 60))
        }
    }

    /// Today's tasks in the order they fall: timed ones by time, then the
    /// rest, each group keeping the order they were added in.
    static func ordered(
        _ tasks: [DayTask],
        on day: Date,
        schedule: PrayerDaySchedule?,
        calendar: Calendar = .current
    ) -> [PlannedTask] {
        let timed = tasks.map { PlannedTask(task: $0, time: time(of: $0, on: day, schedule: schedule, calendar: calendar)) }
        return timed.sorted { lhs, rhs in
            switch (lhs.time, rhs.time) {
            case let (l?, r?): return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.task.createdAt < rhs.task.createdAt
            }
        }
    }

    /// The next time a task falls after `now` within the given schedules'
    /// days, skipping days already marked done.
    static func nextOccurrence(
        of task: DayTask,
        after now: Date,
        schedules: [PrayerDaySchedule],
        calendar: Calendar = .current
    ) -> Date? {
        occurrences(of: task, after: now, schedules: schedules, limit: 1, calendar: calendar).first
    }

    /// Up to `limit` times the task falls after `now`, over the nine days the
    /// schedules cover, skipping days already marked done.
    static func occurrences(
        of task: DayTask,
        after now: Date,
        schedules: [PrayerDaySchedule],
        limit: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        var times: [Date] = []
        for offset in 0..<9 where times.count < limit {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  task.occurs(on: day, calendar: calendar),
                  !task.isDone(on: day, calendar: calendar) else { continue }
            let schedule = schedules.first { daySchedule in
                guard let date = calendar.date(from: daySchedule.date) else { return false }
                return calendar.isDate(date, inSameDayAs: day)
            }
            if let time = time(of: task, on: day, schedule: schedule, calendar: calendar), time > now {
                times.append(time)
            }
        }
        return times
    }

    /// How a task's timing reads, e.g. "After Fajr" or "15 min before Maghrib".
    static func timingText(_ timing: DayTaskTiming, resolved: Date?) -> String {
        switch timing {
        case .anytime:
            return String(localized: "Any time")
        case .clock:
            return resolved?.formatted(date: .omitted, time: .shortened) ?? ""
        case .afterPrayer(let prayer, let minutes):
            let name = String(localized: String.LocalizationValue(prayer.englishName))
            return minutes == 0
                ? String(localized: "After \(name)")
                : String(localized: "\(minutes) min after \(name)")
        case .beforePrayer(let prayer, let minutes):
            let name = String(localized: String.LocalizationValue(prayer.englishName))
            return String(localized: "\(minutes) min before \(name)")
        }
    }
}

// MARK: - Reminders

/// Keeps the next few reminders of each reminding task scheduled. A
/// repeating task used to keep only its next one, so it reminded once and
/// then waited for the app to be opened. Refreshed with the prayer alerts, so
/// a prayer-relative task follows each day's prayer times.
enum MyDayReminders {
    private static let scheduledKey = "myday.scheduledReminderIDs"

    /// Upcoming reminders kept per task.
    static let occurrencesPerTask = 7

    /// All tasks' reminders together, soonest first, so they never crowd the
    /// prayer alerts out of the 64-alert budget.
    static let totalBudget = 21

    @MainActor
    static func refresh(
        store: MyDayStore,
        notifications: any NotificationScheduling,
        schedules: [PrayerDaySchedule],
        now: Date = Date()
    ) async {
        store.loadIfNeeded()
        // A file not readable yet (before the first unlock) leaves the store
        // empty for now: that is not every task being deleted.
        guard store.hasLoaded else { return }
        let previously = Set(UserDefaults.standard.stringArray(forKey: scheduledKey) ?? [])
        let reminding = store.document.tasks.filter { $0.remind && $0.timing.isTimed }
        let soonest = reminding
            .flatMap { task in
                MyDayPlanner.occurrences(of: task, after: now, schedules: schedules, limit: occurrencesPerTask)
                    .map { (taskID: task.id, fire: $0) }
            }
            .sorted { $0.fire < $1.fire }
            .prefix(totalBudget)
        var scheduled: [String] = []
        for task in reminding {
            let id = reminderID(task.id)
            let fires = soonest.filter { $0.taskID == task.id }.map { $0.fire }
            guard let first = fires.first else {
                await notifications.cancelReminder(id: id)
                continue
            }
            await notifications.scheduleReminders(
                id: id,
                title: task.title,
                body: MyDayPlanner.timingText(task.timing, resolved: first),
                at: fires
            )
            scheduled.append(id)
        }
        // Tasks deleted, finished or switched off since the last refresh.
        for stale in previously.subtracting(scheduled) {
            await notifications.cancelReminder(id: stale)
        }
        UserDefaults.standard.set(scheduled, forKey: scheduledKey)
    }

    static func reminderID(_ taskID: UUID) -> String { "myday.\(taskID.uuidString)" }
}
