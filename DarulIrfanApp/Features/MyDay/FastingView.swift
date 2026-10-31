import SwiftUI

/// A private record of fasts - Ramadan, make-up and voluntary - with today's
/// suhoor and iftar times at the person's own place.
@MainActor
struct FastingView: View {
    let dependencies: AppDependencies
    let appState: AppState
    @Environment(\.locale) private var locale

    @State private var store = MyDayStore.shared
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var choosingDay: Date?

    private var calendar: Calendar {
        var value = Calendar.current
        value.locale = locale
        return value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                todayTimes
                monthGrid
                totals
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .diPageHeading("Fasting record")
        .onAppear { store.loadIfNeeded() }
        .confirmationDialog(
            "Record a fast",
            isPresented: Binding(get: { choosingDay != nil }, set: { if !$0 { choosingDay = nil } }),
            titleVisibility: .visible
        ) {
            if let day = choosingDay {
                ForEach(FastKind.allCases) { kind in
                    Button(LocalizedStringKey(kind.title)) {
                        store.setFast(kind, on: day)
                        DIHaptics.light()
                    }
                }
                if store.fast(on: day) != nil {
                    Button("Clear this day", role: .destructive) { store.setFast(nil, on: day) }
                }
            }
        }
    }

    // MARK: Today

    @ViewBuilder
    private var todayTimes: some View {
        if let schedule = MyDayPrayerTimes.schedule(on: Date(), dependencies: dependencies, appState: appState),
           let fajr = schedule.time(for: .fajr),
           let maghrib = schedule.time(for: .maghrib) {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    DISectionHeader(titleKey: "Today", systemImage: "sun.horizon")
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Suhoor ends").font(.caption).foregroundStyle(DIColor.textMuted)
                            Text(fajr, format: Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: schedule.location.timeZone)).font(.title3.weight(.semibold))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Iftar").font(.caption).foregroundStyle(DIColor.textMuted)
                            Text(maghrib, format: Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: schedule.location.timeZone)).font(.title3.weight(.semibold))
                        }
                    }
                    Text("Suhoor ends at Fajr and iftar is at Maghrib, from your prayer settings.")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
        }
    }

    // MARK: Month

    private var monthGrid: some View {
        DICard {
            VStack(spacing: DISpacing.sm) {
                HStack {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.backward") }
                        .accessibilityLabel("Previous month")
                    Spacer()
                    Text(month, format: .dateTime.month(.wide).year())
                        .font(.headline)
                    Spacer()
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.forward") }
                        .accessibilityLabel("Next month")
                }
                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(calendar.veryShortWeekdaySymbols.indices, id: \.self) { index in
                        Text(verbatim: calendar.veryShortWeekdaySymbols[(index + calendar.firstWeekday - 1) % 7])
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DIColor.textMuted)
                    }
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayCell(day)
                        } else {
                            Color.clear.frame(height: 36)
                        }
                    }
                }
                Text("Tap a day to record or clear a fast.")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let kind = store.fast(on: day)
        let isToday = calendar.isDateInToday(day)
        return Button {
            choosingDay = day
        } label: {
            Text(verbatim: "\(calendar.component(.day, from: day))")
                .font(.subheadline.weight(isToday ? .bold : .regular))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(
                    Circle().fill(color(for: kind))
                )
                .foregroundStyle(kind == nil ? DIColor.textPrimary : DIColor.onPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day, format: .dateTime.day().month(.wide)))
        .accessibilityValue(kind.map { Text(LocalizedStringKey($0.title)) } ?? Text("No fast recorded"))
    }

    private func color(for kind: FastKind?) -> Color {
        switch kind {
        case .ramadan: return DIColor.primary
        case .qada: return DIColor.accent
        case .voluntary: return DIColor.primary.opacity(0.55)
        case nil: return Color.clear
        }
    }

    private var cells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: month)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: leading) + days.map { Optional($0) }
    }

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: month) { month = next }
    }

    // MARK: Totals

    private var totals: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                DISectionHeader(titleKey: "This year", systemImage: "chart.bar")
                ForEach(FastKind.allCases) { kind in
                    HStack {
                        Circle().fill(color(for: kind)).frame(width: 10, height: 10)
                        Text(LocalizedStringKey(kind.title))
                        Spacer()
                        Text(verbatim: "\(store.fastCount(inYearOf: month, kind: kind))")
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
                Text("This record is private and stays on this phone.")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
    }
}
