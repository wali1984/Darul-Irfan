import EventKit
import SwiftUI
import UserNotifications

/// Adds or edits one task: what, which day, when (a clock time or relative
/// to a prayer), how it repeats, and whether to be reminded.
@MainActor
struct DayTaskEditorView: View {
    let original: DayTask?
    let onSave: (DayTask) -> Bool
    let onDelete: (() -> Bool)?
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

    @State private var newTaskID = UUID()
    @State private var saveFailed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationDenied = false
    @State private var requestingNotifications = false
    @State private var notificationRequestTask: Task<Void, Never>?
    @State private var calendarRequestTask: Task<Void, Never>?
    @State private var title: String
    @State private var day: Date
    @State private var timingKind: TimingKind
    @State private var clock: Date
    @State private var prayer: Prayer
    @State private var minutes: Int
    @State private var repeatRule: DayTaskRepeat
    @State private var remind: Bool
    @State private var note: String
    @State private var isAddingToCalendar = false
    @State private var calendarMessage: LocalizedStringKey?

    init(
        task: DayTask?,
        prayerSchedule: @escaping @MainActor (Date) -> PrayerDaySchedule?,
        onSave: @escaping (DayTask) -> Bool,
        onDelete: (() -> Bool)? = nil
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
                    .diInterfaceFont(.body)
                DatePicker("Day", selection: $day, displayedComponents: .date)
                    .diInterfaceFont(.body)
            }
            .listRowBackground(DIColor.surface)

            Section {
                taskMenu("When", selection: $timingKind, options: TimingKind.allCases) { LocalizedStringKey($0.rawValue) }
                switch timingKind {
                case .anytime:
                    EmptyView()
                case .clock:
                    DatePicker("Time", selection: $clock, displayedComponents: .hourAndMinute)
                        .diInterfaceFont(.body)
                case .after, .before:
                    taskMenu("Prayer", selection: $prayer, options: Prayer.obligatory) { LocalizedStringKey($0.englishName) }
                    let minimumMinutes = timingKind == .before ? 5 : 0
                    let displayedMinutes = max(minimumMinutes, minutes)
                    let offsetLabel = Text(timingKind == .after ? "\(displayedMinutes) minutes after" : "\(displayedMinutes) minutes before")
                    VStack(alignment: .leading, spacing: DISpacing.sm) {
                        offsetLabel.diInterfaceFont(.body).foregroundStyle(DIColor.textPrimary)
                        HStack(spacing: DISpacing.sm) {
                            Spacer(minLength: 0)
                            Button { minutes = max(minimumMinutes, displayedMinutes - 5) } label: {
                                Image(systemName: "minus").frame(minWidth: 16)
                            }
                            .buttonStyle(DICompactButtonStyle(minimumHeight: 48))
                            .disabled(displayedMinutes <= minimumMinutes)
                            .accessibilityLabel(Text("Decrease") + Text(": ") + offsetLabel)
                            .accessibilityValue(offsetLabel)
                            Button { minutes = min(180, displayedMinutes + 5) } label: {
                                Image(systemName: "plus").frame(minWidth: 16)
                            }
                            .buttonStyle(DICompactButtonStyle(minimumHeight: 48))
                            .disabled(displayedMinutes >= 180)
                            .accessibilityLabel(Text("Increase") + Text(": ") + offsetLabel)
                            .accessibilityValue(offsetLabel)
                        }
                    }
                }
            } footer: {
                if timingKind == .after || timingKind == .before {
                    Text("Follows your prayer times each day, so it moves with the seasons and your location.")
                        .diInterfaceFont(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
            .listRowBackground(DIColor.surface)

            Section {
                taskMenu("Repeat", selection: $repeatRule, options: DayTaskRepeat.allCases) { LocalizedStringKey($0.title) }
                Toggle("Remind me", isOn: Binding(get: { remind }, set: { enabled in
                    guard enabled else { remind = false; return }
                    requestingNotifications = true
                    notificationRequestTask = Task {
                        defer { requestingNotifications = false }
                        let allowed = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                        guard !Task.isCancelled else { return }
                        remind = allowed
                        await refreshNotificationAccess()
                    }
                }))
                    .diInterfaceFont(.body)
                    .disabled(timingKind == .anytime || requestingNotifications)
                if notificationDenied && timingKind != .anytime {
                    Text("Enable notifications in Settings to receive task reminders.")
                        .diInterfaceFont(.footnote).foregroundStyle(DIColor.textMuted)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.buttonStyle(DICompactButtonStyle())
                }
            } footer: {
                if timingKind == .anytime {
                    Text("Choose a time or a prayer to be reminded.")
                        .diInterfaceFont(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
            .listRowBackground(DIColor.surface)

            Section("Note") {
                TextField("Optional", text: $note, axis: .vertical)
                    .lineLimit(2...6)
                    .diInterfaceFont(.body)
            }
            .listRowBackground(DIColor.surface)

            if timingKind != .anytime {
                Section {
                    Button {
                        calendarRequestTask?.cancel()
                        calendarRequestTask = Task { await addToCalendar() }
                    } label: {
                        HStack {
                            Label("Add to Calendar", systemImage: "calendar.badge.plus")
                                .frame(maxWidth: .infinity)
                            if isAddingToCalendar { ProgressView() }
                        }
                    }
                    .buttonStyle(DISecondaryButtonStyle())
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingToCalendar)
                    if let calendarMessage {
                        Text(calendarMessage)
                            .diInterfaceFont(.footnote)
                            .foregroundStyle(DIColor.textMuted)
                    }
                }
                .listRowBackground(DIColor.surface)
            }

            if let onDelete {
                Section {
                    Button("Delete task", role: .destructive) {
                        if onDelete() { dismiss() } else { saveFailed = true }
                    }
                    .buttonStyle(DISecondaryButtonStyle(destructive: true))
                }
                .listRowBackground(DIColor.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .alert("Could not save. Please try again.", isPresented: $saveFailed) {
            Button("OK", role: .cancel) { }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear {
            notificationRequestTask?.cancel()
            calendarRequestTask?.cancel()
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await refreshNotificationAccess() }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: DISpacing.sm) {
                Text(original == nil ? "New task" : "Edit task")
                    .diInterfaceFont(.headline)
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: DISpacing.md) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(DISecondaryButtonStyle())
                Button("Save") {
                    if onSave(builtTask) { dismiss() } else { saveFailed = true }
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || requestingNotifications)
                .buttonStyle(DISecondaryButtonStyle())
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
            .frame(maxWidth: .infinity)
            .background(DIColor.background)
        }
    }

    private func refreshNotificationAccess() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard !Task.isCancelled else { return }
        notificationDenied = settings.authorizationStatus == .denied
    }

    private func taskMenu<Value: Hashable>(
        _ title: LocalizedStringKey,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            Text(title).diInterfaceFont(.body).foregroundStyle(DIColor.textPrimary)
            Menu {
                Picker(title, selection: selection) {
                    ForEach(options, id: \.self) { option in
                        Text(label(option)).diInterfaceFont(.body).tag(option)
                    }
                }
            } label: {
                Label(label(selection.wrappedValue), systemImage: "chevron.up.chevron.down")
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(DISecondaryButtonStyle())
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(label(selection.wrappedValue)))
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
        var task = original ?? DayTask(id: newTaskID, title: "", startDay: day)
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
        guard !Task.isCancelled, !isAddingToCalendar, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isAddingToCalendar = true
        defer { isAddingToCalendar = false }
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
            let allowed = try await store.requestWriteOnlyAccessToEvents()
            guard !Task.isCancelled else { return }
            guard allowed else {
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
            guard !Task.isCancelled else { return }
            calendarMessage = "The task could not be added to your calendar."
        }
    }
}
