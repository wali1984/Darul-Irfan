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

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let stored = try? decoder.decode(MyDayDocument.self, from: data) {
            document = stored
        }
    }

    private func save() {
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

    func upsert(_ task: DayTask) {
        if let index = document.tasks.firstIndex(where: { $0.id == task.id }) {
            document.tasks[index] = task
        } else {
            document.tasks.append(task)
        }
        save()
    }

    func delete(taskID: UUID) {
        document.tasks.removeAll { $0.id == taskID }
        save()
    }

    func toggleDone(taskID: UUID, on day: Date) {
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
        for offset in 0..<9 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  task.occurs(on: day, calendar: calendar),
                  !task.isDone(on: day, calendar: calendar) else { continue }
            let schedule = schedules.first { daySchedule in
                guard let date = calendar.date(from: daySchedule.date) else { return false }
                return calendar.isDate(date, inSameDayAs: day)
            }
            if let time = time(of: task, on: day, schedule: schedule, calendar: calendar), time > now {
                return time
            }
        }
        return nil
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

/// Keeps one local notification per reminding task, for its next
/// occurrence. Refreshed with the prayer alerts, so a prayer-relative task
/// follows that day's prayer times.
enum MyDayReminders {
    private static let scheduledKey = "myday.scheduledReminderIDs"

    @MainActor
    static func refresh(
        store: MyDayStore,
        notifications: any NotificationScheduling,
        schedules: [PrayerDaySchedule],
        now: Date = Date()
    ) async {
        store.loadIfNeeded()
        let previously = Set(UserDefaults.standard.stringArray(forKey: scheduledKey) ?? [])
        var scheduled: [String] = []
        for task in store.document.tasks where task.remind && task.timing.isTimed {
            let id = reminderID(task.id)
            await notifications.cancelReminder(id: id)
            guard let fire = MyDayPlanner.nextOccurrence(of: task, after: now, schedules: schedules) else { continue }
            await notifications.scheduleReminder(
                id: id,
                title: task.title,
                body: MyDayPlanner.timingText(task.timing, resolved: fire),
                at: fire
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
