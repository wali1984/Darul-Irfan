import SwiftUI

/// My Day: the person's own tasks for today and the week ahead, timed by
/// the clock or by the prayers ("after Fajr"), with private notes, a focus
/// timer and a fasting record one tap away. Works with no account and keeps
/// everything on this device.
@MainActor
struct MyDayView: View {
    let dependencies: AppDependencies
    let appState: AppState

    private enum Span: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "This week"
        var id: String { rawValue }
    }

    @State private var store = MyDayStore.shared
    @State private var span: Span = .today
    @State private var editing: DayTask?
    @State private var isAdding = false

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $span) {
                    ForEach(Span.allCases) { span in
                        Text(LocalizedStringKey(span.rawValue)).tag(span)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            switch span {
            case .today:
                daySection(Date(), header: nil)
            case .week:
                ForEach(weekDays, id: \.self) { day in
                    daySection(day, header: day.formatted(.dateTime.weekday(.wide).day().month()))
                }
            }

            Section {
                NavigationLink {
                    NotesView()
                } label: {
                    Label("Private notes", systemImage: "note.text")
                }
                NavigationLink {
                    FocusTimerView(dependencies: dependencies, appState: appState)
                } label: {
                    Label("Your Daily Personal Zikr", systemImage: "timer")
                }
                NavigationLink {
                    FastingView(dependencies: dependencies, appState: appState)
                } label: {
                    Label("Fasting record", systemImage: "moon.haze")
                }
            } footer: {
                Text("Your tasks, notes and fasts stay on this phone. They are not part of any account and are never sent anywhere.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("My Day")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add a task")
            }
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack {
                DayTaskEditorView(task: nil, prayerSchedule: { prayerSchedule(on: $0) }) { task in save(task) }
            }
        }
        .sheet(item: $editing) { task in
            NavigationStack {
                DayTaskEditorView(task: task, prayerSchedule: { prayerSchedule(on: $0) }, onSave: { save($0) }, onDelete: {
                    store.delete(taskID: task.id)
                    refreshReminders()
                })
            }
        }
        .onAppear { store.loadIfNeeded() }
    }

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    @ViewBuilder
    private func daySection(_ day: Date, header: String?) -> some View {
        let schedule = MyDayPrayerTimes.schedule(on: day, dependencies: dependencies, appState: appState)
        let entries = MyDayPlanner.ordered(store.tasks(on: day), on: day, schedule: schedule)
        Section {
            if entries.isEmpty {
                Text(span == .today ? "Nothing planned for today. Tap + to add a task." : "Nothing planned.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
            }
            ForEach(entries) { entry in
                DayTaskRow(task: entry.task, time: entry.time, day: day) {
                    store.toggleDone(taskID: entry.task.id, on: day)
                    DIHaptics.light()
                    refreshReminders()
                } onOpen: {
                    editing = entry.task
                }
                .swipeActions {
                    Button(role: .destructive) {
                        store.delete(taskID: entry.task.id)
                        refreshReminders()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            if let header { Text(verbatim: header) }
        }
        .listRowBackground(DIColor.surface)
    }

    private func save(_ task: DayTask) {
        store.upsert(task)
        refreshReminders()
    }

    private func prayerSchedule(on day: Date) -> PrayerDaySchedule? {
        MyDayPrayerTimes.schedule(on: day, dependencies: dependencies, appState: appState)
    }

    /// Reminders follow the prayer alerts' refresh, which schedules them in
    /// the right order within the 64-alert budget.
    private func refreshReminders() {
        Task { await appState.refreshScheduledNotificationsAndWidgets() }
    }
}

/// One task with its done mark, timing and note.
struct DayTaskRow: View {
    let task: DayTask
    let time: Date?
    let day: Date
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: DISpacing.sm) {
            Button(action: onToggle) {
                Image(systemName: task.isDone(on: day) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone(on: day) ? DIColor.primary : DIColor.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone(on: day) ? Text("Mark as not done") : Text("Mark as done"))

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: task.title)
                        .font(.body)
                        .strikethrough(task.isDone(on: day))
                        .foregroundStyle(task.isDone(on: day) ? DIColor.textMuted : DIColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: DISpacing.xs) {
                        Text(verbatim: MyDayPlanner.timingText(task.timing, resolved: time))
                        if task.timing.prayer != nil, let time {
                            Text(verbatim: "· " + time.formatted(date: .omitted, time: .shortened))
                        }
                        if task.repeatRule != .never {
                            Image(systemName: "repeat")
                        }
                        if task.remind {
                            Image(systemName: "bell.fill")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The prayer times My Day reads for prayer-relative tasks: the person's own
/// place and calculation settings, so "after Fajr" means their Fajr.
enum MyDayPrayerTimes {
    @MainActor
    static func schedule(on day: Date, dependencies: AppDependencies, appState: AppState) -> PrayerDaySchedule? {
        guard let place = appState.activePlace else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return dependencies.prayerCalculation.schedule(
            for: components,
            at: place,
            preferences: appState.settings.calculation
        )
    }
}
