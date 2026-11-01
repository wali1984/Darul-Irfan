import SwiftUI

/// A private record of fasts - Ramadan, make-up and voluntary - with today's
/// suhoor and iftar times at the person's own place.
@MainActor
struct FastingView: View {
    let dependencies: AppDependencies
    let appState: AppState
    @Environment(\.locale) private var locale

    @State private var store = MyDayStore.shared
    @State private var saveFailed = false
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
        .myDayReadState(store)
        .diScreenBackground()
        .alert("Could not save. Please try again.", isPresented: $saveFailed) {
            Button("OK", role: .cancel) { }
        }
        .tint(DIColor.actionForeground)
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
                        saveFailed = !store.setFast(kind, on: day)
                        DIHaptics.light()
                    }
                }
                if store.fast(on: day) != nil {
                    Button("Clear this day", role: .destructive) { saveFailed = !store.setFast(nil, on: day) }
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
                            Text("Suhoor ends").diInterfaceFont(.caption).foregroundStyle(DIColor.textMuted)
                            Text(verbatim: fajr.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: schedule.location.timeZone))).diInterfaceFont(.title3, weight: .semibold)
                                .accessibilityIdentifier("fasting-suhoor")
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Iftar").diInterfaceFont(.caption).foregroundStyle(DIColor.textMuted)
                            Text(verbatim: maghrib.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: schedule.location.timeZone))).diInterfaceFont(.title3, weight: .semibold)
                                .accessibilityIdentifier("fasting-iftar")
                        }
                    }
                    Text("Suhoor ends at Fajr and iftar is at Maghrib, from your prayer settings.")
                        .diInterfaceFont(.caption)
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
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.backward").frame(width: 48, height: 48) }
                        .buttonStyle(FastingCalendarButtonStyle(background: DIColor.surface, foreground: DIColor.actionForeground, outlined: true))
                        .accessibilityLabel("Previous month")
                    Spacer()
                    Text(month, format: .dateTime.month(.wide).year())
                        .diInterfaceFont(.headline)
                    Spacer()
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.forward").frame(width: 48, height: 48) }
                        .buttonStyle(FastingCalendarButtonStyle(background: DIColor.surface, foreground: DIColor.actionForeground, outlined: true))
                        .accessibilityLabel("Next month")
                }
                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(calendar.shortWeekdaySymbols.indices, id: \.self) { index in
                        Text(verbatim: calendar.shortWeekdaySymbols[(index + calendar.firstWeekday - 1) % 7])
                            .diInterfaceFont(.caption2, weight: .semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .foregroundStyle(DIColor.textMuted)
                    }
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayCell(day)
                        } else {
                            Color.clear.frame(height: 48)
                        }
                    }
                }
                Text("Tap a day to record or clear a fast.")
                    .diInterfaceFont(.caption)
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
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(FastingCalendarButtonStyle(
            background: kind == .ramadan ? DIColor.primary :
                kind == .qada ? DIColor.accent.opacity(0.28) :
                kind == .voluntary ? DIColor.primary.opacity(0.12) : DIColor.surface,
            foreground: kind == .ramadan ? DIColor.onPrimary : DIColor.textPrimary,
            outlined: isToday
        ))
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
                    .diInterfaceFont(.subheadline)
                }
                Text("This record is private and stays on this phone.")
                    .diInterfaceFont(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
    }
}

private struct FastingCalendarButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color
    var outlined = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        configuration.label
            .foregroundStyle(foreground)
            .background(background)
            .background(DIColor.surface)
            .clipShape(shape)
            .overlay(shape.strokeBorder(outlined ? DIColor.accent : DIColor.border, lineWidth: outlined ? 2 : 1))
            .shadow(color: DIColor.primaryDeep.opacity(configuration.isPressed ? 0.04 : 0.12), radius: 2, x: 0, y: 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
