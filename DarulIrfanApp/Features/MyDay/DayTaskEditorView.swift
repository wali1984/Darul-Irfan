import EventKit
import SwiftUI

/// Adds or edits one task: what, which day, when (a clock time or relative
/// to a prayer), how it repeats, and whether to be reminded.
@MainActor
struct DayTaskEditorView: View {
    let original: DayTask?
    let onSave: (DayTask) -> Void
    let onDelete: (() -> Void)?
    /// The day's prayer times (nil without a place), for placing a
    /// prayer-relative task in the calendar.
    let prayerSchedule: @MainActor (Date) -> PrayerDaySchedule?

    private enum TimingKind: String, CaseIterable, Identifiable {
        case anytime = "Any time"
        case clock = "At a time"
        case after = "After a prayer"
        case before = "Before a prayer"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var day: Date
    @State private var timingKind: TimingKind
    @State private var clock: Date
    @State private var prayer: Prayer
    @State private var minutes: Int
    @State private var repeatRule: DayTaskRepeat
    @State private var remind: Bool
    @State private var note: String
    @State private var calendarMessage: LocalizedStringKey?

    init(
        task: DayTask?,
        prayerSchedule: @escaping @MainActor (Date) -> PrayerDaySchedule?,
        onSave: @escaping (DayTask) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.original = task
        self.prayerSchedule = prayerSchedule
        self.onSave = onSave
        self.onDelete = onDelete
        let calendar = Calendar.current
        _title = State(initialValue: task?.title ?? "")
        _day = State(initialValue: task?.startDay ?? calendar.startOfDay(for: Date()))
        _repeatRule = State(initialValue: task?.repeatRule ?? .never)
        _remind = State(initialValue: task?.remind ?? false)
        _note = State(initialValue: task?.note ?? "")
        var kind = TimingKind.anytime
        var clock = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        var prayer = Prayer.fajr
        var minutes = 0
        switch task?.timing ?? .anytime {
        case .anytime:
            break
        case .clock(let hour, let minute):
            kind = .clock
            clock = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? clock
        case .afterPrayer(let p, let m):
            kind = .after; prayer = p; minutes = m
        case .beforePrayer(let p, let m):
            kind = .before; prayer = p; minutes = m
        }
        _timingKind = State(initialValue: kind)
        _clock = State(initialValue: clock)
        _prayer = State(initialValue: prayer)
        _minutes = State(initialValue: minutes)
    }

    var body: some View {
        Form {
            Section {
                TextField("What do you want to do?", text: $title, axis: .vertical)
                DatePicker("Day", selection: $day, displayedComponents: .date)
            }

            Section {
                Picker("When", selection: $timingKind) {
                    ForEach(TimingKind.allCases) { kind in
                        Text(LocalizedStringKey(kind.rawValue)).tag(kind)
                    }
                }
                switch timingKind {
                case .anytime:
                    EmptyView()
                case .clock:
                    DatePicker("Time", selection: $clock, displayedComponents: .hourAndMinute)
                case .after, .before:
                    Picker("Prayer", selection: $prayer) {
                        ForEach(Prayer.obligatory, id: \.self) { prayer in
                            Text(LocalizedStringKey(prayer.englishName)).tag(prayer)
                        }
                    }
                    Stepper(value: $minutes, in: 0...180, step: 5) {
                        Text(timingKind == .after ? "\(minutes) minutes after" : "\(minutes) minutes before")
                    }
                }
            } footer: {
                if timingKind == .after || timingKind == .before {
                    Text("Follows your prayer times each day, so it moves with the seasons and your location.")
                }
            }

            Section {
                Picker("Repeat", selection: $repeatRule) {
                    ForEach(DayTaskRepeat.allCases) { rule in
                        Text(LocalizedStringKey(rule.title)).tag(rule)
                    }
                }
                Toggle("Remind me", isOn: $remind)
                    .disabled(timingKind == .anytime)
            } footer: {
                if timingKind == .anytime {
                    Text("Choose a time or a prayer to be reminded.")
                }
            }

            Section("Note") {
                TextField("Optional", text: $note, axis: .vertical)
                    .lineLimit(2...6)
            }

            if timingKind != .anytime {
                Section {
                    Button {
                        Task { await addToCalendar() }
                    } label: {
                        Label("Add to Calendar", systemImage: "calendar.badge.plus")
                    }
                    if let calendarMessage {
                        Text(calendarMessage)
                            .font(.footnote)
                            .foregroundStyle(DIColor.textMuted)
                    }
                }
            }

            if let onDelete {
                Section {
                    Button("Delete task", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle(original == nil ? "New task" : "Edit task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(builtTask)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var timing: DayTaskTiming {
        switch timingKind {
        case .anytime:
            return .anytime
        case .clock:
            let parts = Calendar.current.dateComponents([.hour, .minute], from: clock)
            return .clock(hour: parts.hour ?? 9, minute: parts.minute ?? 0)
        case .after:
            return .afterPrayer(prayer, minutes: minutes)
        case .before:
            return .beforePrayer(prayer, minutes: max(minutes, 5))
        }
    }

    private var builtTask: DayTask {
        var task = original ?? DayTask(title: "", startDay: day)
        task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.startDay = Calendar.current.startOfDay(for: day)
        task.timing = timing
        task.repeatRule = repeatRule
        task.remind = remind && timing.isTimed
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        task.note = trimmed.isEmpty ? nil : trimmed
        return task
    }

    /// Adds the next occurrence to the calendar, write-only: the app never
    /// asks to read the calendar. A prayer-relative task is placed at its
    /// first day's computed prayer time, and says so in its notes.
    private func addToCalendar() async {
        guard Bundle.main.object(forInfoDictionaryKey: "NSCalendarsWriteOnlyAccessUsageDescription") != nil else {
            calendarMessage = "Calendar access is not available in this build."
            return
        }
        let task = builtTask
        let start: Date
        switch task.timing {
        case .clock(let hour, let minute):
            start = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: task.startDay) ?? task.startDay
        default:
            // From the later of now and the task's first day, over the days
            // the planner looks at, with each day's own prayer times.
            let calendar = Calendar.current
            let from = max(Date().addingTimeInterval(-60), task.startDay)
            let firstDay = calendar.startOfDay(for: from)
            var schedules: [PrayerDaySchedule] = []
            for offset in 0..<9 {
                if let day = calendar.date(byAdding: .day, value: offset, to: firstDay),
                   let schedule = prayerSchedule(day) {
                    schedules.append(schedule)
                }
            }
            guard !schedules.isEmpty else {
                calendarMessage = "Set your location first, so the task can follow your prayer times."
                return
            }
            // The next time it falls; for a one-off whose time has passed,
            // that day's time.
            guard let resolved = MyDayPlanner.nextOccurrence(of: task, after: from, schedules: schedules)
                ?? MyDayPlanner.time(of: task, on: task.startDay, schedule: prayerSchedule(task.startDay)) else {
                calendarMessage = "The task could not be added to your calendar."
                return
            }
            start = resolved
        }
        let store = EKEventStore()
        do {
            guard try await store.requestWriteOnlyAccessToEvents() else {
                calendarMessage = "Allow calendar access in Settings to add tasks to your calendar."
                return
            }
            let event = EKEvent(eventStore: store)
            event.title = task.title
            event.startDate = start
            event.endDate = start.addingTimeInterval(30 * 60)
            event.notes = [task.note, MyDayPlanner.timingText(task.timing, resolved: start)]
                .compactMap { $0 }
                .joined(separator: "\n")
            event.calendar = store.defaultCalendarForNewEvents
            switch task.repeatRule {
            case .never: break
            case .daily: event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))
            case .weekly: event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil))
            case .weekdays:
                let days = [EKWeekday.monday, .tuesday, .wednesday, .thursday, .friday].map { EKRecurrenceDayOfWeek($0) }
                event.addRecurrenceRule(EKRecurrenceRule(
                    recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days,
                    daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil,
                    setPositions: nil, end: nil
                ))
            }
            try store.save(event, span: .futureEvents)
            calendarMessage = "Added to your calendar."
        } catch {
            calendarMessage = "The task could not be added to your calendar."
        }
    }
}
