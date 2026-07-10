import SwiftUI
import Observation

/// Computes and holds one month of prayer times for the timetable screen.
@Observable
@MainActor
final class MonthlyTimetableViewModel {
    struct DayRow: Identifiable, Equatable {
        /// Civil day key "yyyy-MM-dd" in the place's timezone.
        var id: String
        var date: Date
        var isToday: Bool
        var times: [Prayer: Date]
    }

    private let prayerCalculation: any PrayerCalculationServicing
    private let appState: AppState

    /// Any instant inside the displayed month.
    private(set) var monthReference: Date = Date()
    private(set) var days: [DayRow] = []
    private(set) var monthTitle: String = ""
    private(set) var shareText: String = ""

    init(dependencies: AppDependencies, appState: AppState) {
        self.prayerCalculation = dependencies.prayerCalculation
        self.appState = appState
    }

    var hasPlace: Bool { appState.activePlace != nil }

    var timeFormat: Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .shortened, timeZone: placeTimeZone)
    }

    var dayLabelFormat: Date.FormatStyle {
        Date.FormatStyle(timeZone: placeTimeZone).day(.twoDigits).weekday(.abbreviated)
    }

    private var placeTimeZone: TimeZone {
        appState.activePlace?.timeZone ?? TimeZone.current
    }

    func load() {
        rebuild()
    }

    func goToPreviousMonth() {
        shiftMonth(by: -1)
    }

    func goToNextMonth() {
        shiftMonth(by: 1)
    }

    func goToCurrentMonth() {
        monthReference = Date()
        rebuild()
    }

    private func shiftMonth(by value: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = placeTimeZone
        if let shifted = calendar.date(byAdding: .month, value: value, to: monthReference) {
            monthReference = shifted
            rebuild()
        }
    }

    private func rebuild() {
        guard let place = appState.activePlace else {
            days = []
            monthTitle = ""
            shareText = ""
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        let components = calendar.dateComponents([.year, .month], from: monthReference)
        guard let monthStart = calendar.date(from: components),
              let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            days = []
            return
        }
        let schedules = prayerCalculation.schedules(
            forDaysStarting: monthStart,
            days: dayRange.count,
            at: place,
            preferences: appState.settings.calculation
        )
        let todayKey = DayKey.make(from: Date(), timeZone: place.timeZone)
        days = schedules.compactMap { schedule in
            guard let date = calendar.date(from: schedule.date) else { return nil }
            let key = DayKey.make(from: date, timeZone: place.timeZone)
            return DayRow(id: key, date: date, isToday: key == todayKey, times: schedule.times)
        }
        monthTitle = monthStart.formatted(
            Date.FormatStyle(timeZone: place.timeZone).month(.wide).year()
        )
        shareText = buildShareText(place: place)
    }

    private func buildShareText(place: PlaceCoordinate) -> String {
        var lines: [String] = []
        lines.append(String(localized: "Darul Irfan — prayer times for \(monthTitle)"))
        lines.append(place.name)
        lines.append("")
        lines.append(Prayer.allCases.map { $0.englishName }.joined(separator: " · "))
        for row in days {
            let dayLabel = row.date.formatted(dayLabelFormat)
            let times = Prayer.allCases.compactMap { prayer -> String? in
                guard let time = row.times[prayer] else { return nil }
                return time.formatted(timeFormat)
            }.joined(separator: " · ")
            lines.append("\(dayLabel): \(times)")
        }
        lines.append("")
        lines.append(String(localized: "Method: \(appState.settings.calculation.method.englishName)"))
        return lines.joined(separator: "\n")
    }
}

/// Pushed from the Prayer tab: the full month of prayer times for the active
/// place, with month navigation and share/export as text.
struct MonthlyTimetableView: View {
    @State private var viewModel: MonthlyTimetableViewModel

    init(dependencies: AppDependencies, appState: AppState) {
        _viewModel = State(initialValue: MonthlyTimetableViewModel(dependencies: dependencies, appState: appState))
    }

    var body: some View {
        Group {
            if viewModel.hasPlace {
                ScrollView {
                    VStack(spacing: DISpacing.md) {
                        monthSwitcher
                        timetableCard
                    }
                    .padding(DISpacing.md)
                }
            } else {
                DIEmptyState(
                    systemImage: "calendar.badge.exclamationmark",
                    titleKey: "No timetable yet",
                    messageKey: "Set a location on the Prayer tab and the monthly timetable will appear here."
                )
            }
        }
        .diScreenBackground()
        .navigationTitle("Monthly Timetable")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.hasPlace {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: viewModel.shareText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(Text("Share this month's timetable"))
                }
            }
        }
        .onAppear {
            viewModel.load()
        }
    }

    // MARK: - Month navigation

    private var monthSwitcher: some View {
        HStack {
            Button {
                viewModel.goToPreviousMonth()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DIColor.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Previous month"))

            Spacer()
            Text(viewModel.monthTitle)
                .font(DIFont.subheading)
                .foregroundStyle(DIColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()

            Button {
                viewModel.goToNextMonth()
            } label: {
                Image(systemName: "chevron.forward")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DIColor.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Next month"))
        }
    }

    // MARK: - Timetable grid

    private var timetableCard: some View {
        DICard(padding: DISpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(horizontalSpacing: DISpacing.md, verticalSpacing: DISpacing.xs) {
                    GridRow {
                        Text("Date")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DIColor.textMuted)
                            .gridColumnAlignment(.leading)
                        ForEach(Prayer.allCases) { prayer in
                            Text(LocalizedStringKey(prayer.englishName))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DIColor.textMuted)
                        }
                    }
                    Divider()
                        .overlay(DIColor.border)
                    ForEach(viewModel.days) { row in
                        GridRow {
                            Text(row.date, format: viewModel.dayLabelFormat)
                                .font(.caption.monospacedDigit().weight(row.isToday ? .bold : .regular))
                                .foregroundStyle(row.isToday ? DIColor.primary : DIColor.textPrimary)
                                .gridColumnAlignment(.leading)
                            ForEach(Prayer.allCases) { prayer in
                                timeCell(row: row, prayer: prayer)
                            }
                        }
                    }
                }
                .padding(.vertical, DISpacing.xs)
            }
        }
    }

    private func timeCell(row: MonthlyTimetableViewModel.DayRow, prayer: Prayer) -> some View {
        Group {
            if let time = row.times[prayer] {
                Text(time, format: viewModel.timeFormat)
            } else {
                Text(verbatim: "—")
            }
        }
        .font(.caption.monospacedDigit().weight(row.isToday ? .semibold : .regular))
        .foregroundStyle(row.isToday ? DIColor.primary : DIColor.textPrimary)
    }
}
