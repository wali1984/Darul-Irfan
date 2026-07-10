import SwiftUI
import Observation

/// Loads the last 7/30 days of prayer log entries and the streak summary
/// for the history screen.
@Observable
@MainActor
final class PrayerTrackerDetailViewModel {
    enum Window: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30

        var id: Int { rawValue }
    }

    struct DayRow: Identifiable, Equatable {
        /// Civil day key "yyyy-MM-dd" in the user's timezone.
        var id: String
        var date: Date
        var isToday: Bool
        var completions: [Prayer: PrayerCompletion]
    }

    private let trackerRepository: any TrackerRepositoryProtocol

    var window: Window = .week
    private(set) var rows: [DayRow] = []
    private(set) var summary: PrayerStreakSummary?
    private(set) var hasAnyEntries = false
    private(set) var isLoading = true

    init(dependencies: AppDependencies, appState: AppState) {
        self.trackerRepository = dependencies.trackerRepository
        // appState is not needed here: tracker day keys use the user's own
        // timezone (DayKey default), matching how entries are recorded.
        _ = appState
    }

    func reload() async {
        isLoading = true
        let now = Date()
        let todayKey = DayKey.make(from: now)
        let keys = DayKey.trailing(window.rawValue, endingAt: now)
        do {
            let entries = try await trackerRepository.prayerLog(dayKeys: keys)
            var byDay: [String: [Prayer: PrayerCompletion]] = [:]
            for entry in entries {
                byDay[entry.dayKey, default: [:]][entry.prayer] = entry.completion
            }
            let calendar = Calendar.current
            let newestFirst = Array(keys.reversed())
            var builtRows: [DayRow] = []
            for (index, key) in newestFirst.enumerated() {
                guard let date = calendar.date(byAdding: .day, value: -index, to: now) else { continue }
                builtRows.append(
                    DayRow(
                        id: key,
                        date: date,
                        isToday: key == todayKey,
                        completions: byDay[key] ?? [:]
                    )
                )
            }
            rows = builtRows
            hasAnyEntries = entries.contains { $0.completion != .unmarked }
            summary = try await trackerRepository.streakSummary(
                endingAt: todayKey,
                windowDays: window.rawValue
            )
        } catch {
            // Keep whatever was shown before; the tracker is non-critical.
        }
        isLoading = false
    }
}

/// Pushed from the Prayer tab: the last 7/30 days of the prayer tracker as a
/// grid, plus a gentle streak summary. Marking prayers happens on the
/// dashboard; this screen is for reflection.
struct PrayerTrackerDetailView: View {
    @State private var viewModel: PrayerTrackerDetailViewModel

    init(dependencies: AppDependencies, appState: AppState) {
        _viewModel = State(initialValue: PrayerTrackerDetailViewModel(dependencies: dependencies, appState: appState))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                Picker("History window", selection: $viewModel.window) {
                    Text("Last 7 Days").tag(PrayerTrackerDetailViewModel.Window.week)
                    Text("Last 30 Days").tag(PrayerTrackerDetailViewModel.Window.month)
                }
                .pickerStyle(.segmented)

                if let summary = viewModel.summary {
                    summaryCard(summary)
                }

                if !viewModel.hasAnyEntries && !viewModel.isLoading {
                    DIEmptyState(
                        systemImage: "circle.dashed",
                        titleKey: "No prayers marked yet",
                        messageKey: "Tap the circles on the Prayer tab to record each prayer — gently, at your own pace."
                    )
                } else {
                    historyCard
                }

                legendCard
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .navigationTitle("Prayer History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.reload()
        }
        .onChange(of: viewModel.window) {
            Task { await viewModel.reload() }
        }
    }

    // MARK: - Summary

    private func summaryCard(_ summary: PrayerStreakSummary) -> some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                HStack(spacing: DISpacing.sm) {
                    statBlock(
                        value: Text("\(summary.currentStreakDays)"),
                        label: Text("Current streak")
                    )
                    statBlock(
                        value: Text("\(summary.bestStreakDays)"),
                        label: Text("Best streak")
                    )
                    statBlock(
                        value: Text(summary.completionRate, format: .percent.precision(.fractionLength(0))),
                        label: Text("Prayers marked")
                    )
                }
                gentleLine(summary)
            }
        }
    }

    private func statBlock(value: Text, label: Text) -> some View {
        VStack(spacing: DISpacing.xs) {
            value
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(DIColor.primary)
            label
                .font(.caption)
                .foregroundStyle(DIColor.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func gentleLine(_ summary: PrayerStreakSummary) -> some View {
        if summary.currentStreakDays >= 2 {
            Text("MashaAllah — \(summary.currentStreakDays) days of consistent prayer.")
                .font(.footnote)
                .foregroundStyle(DIColor.primary)
        } else if summary.currentStreakDays == 1 {
            Text("MashaAllah — a full day of prayer. Keep going gently.")
                .font(.footnote)
                .foregroundStyle(DIColor.primary)
        } else {
            Text("Every prayer you mark is a fresh beginning.")
                .font(.footnote)
                .foregroundStyle(DIColor.textMuted)
        }
    }

    // MARK: - History grid

    private var historyCard: some View {
        DICard(padding: DISpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(horizontalSpacing: DISpacing.sm, verticalSpacing: DISpacing.sm) {
                    GridRow {
                        Text("Day")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DIColor.textMuted)
                            .gridColumnAlignment(.leading)
                        ForEach(Prayer.obligatory) { prayer in
                            Text(LocalizedStringKey(prayer.englishName))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(DIColor.textMuted)
                                .lineLimit(1)
                        }
                    }
                    Divider()
                        .overlay(DIColor.border)
                    ForEach(viewModel.rows) { row in
                        GridRow {
                            Text(row.date, format: dayLabelFormat)
                                .font(.caption.monospacedDigit().weight(row.isToday ? .bold : .regular))
                                .foregroundStyle(row.isToday ? DIColor.primary : DIColor.textPrimary)
                                .gridColumnAlignment(.leading)
                            ForEach(Prayer.obligatory) { prayer in
                                completionCell(
                                    prayer: prayer,
                                    completion: row.completions[prayer] ?? .unmarked
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, DISpacing.xs)
            }
        }
    }

    private var dayLabelFormat: Date.FormatStyle {
        Date.FormatStyle().day(.twoDigits).weekday(.abbreviated)
    }

    private func completionCell(prayer: Prayer, completion: PrayerCompletion) -> some View {
        ZStack {
            Circle()
                .fill(PrayerTrackerPalette.fill(for: completion))
            Circle()
                .strokeBorder(PrayerTrackerPalette.stroke(for: completion), lineWidth: 1)
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel(cellAccessibilityLabel(prayer: prayer, completion: completion))
    }

    private func cellAccessibilityLabel(prayer: Prayer, completion: PrayerCompletion) -> Text {
        switch completion {
        case .unmarked: return Text("\(prayer.englishName): not marked")
        case .prayed: return Text("\(prayer.englishName): prayed")
        case .jamaat: return Text("\(prayer.englishName): prayed in congregation")
        case .qaza: return Text("\(prayer.englishName): marked as Qaza")
        }
    }

    // MARK: - Legend

    private var legendCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                legendRow(completion: .prayed, label: Text("Prayed"))
                legendRow(completion: .jamaat, label: Text("Prayed in congregation (Jamaat)"))
                legendRow(completion: .qaza, label: Text("Qaza — to make up later, in your own time"))
                legendRow(completion: .unmarked, label: Text("Not marked"))
            }
        }
    }

    private func legendRow(completion: PrayerCompletion, label: Text) -> some View {
        HStack(spacing: DISpacing.sm) {
            ZStack {
                Circle()
                    .fill(PrayerTrackerPalette.fill(for: completion))
                Circle()
                    .strokeBorder(PrayerTrackerPalette.stroke(for: completion), lineWidth: 1)
            }
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
            label
                .font(.footnote)
                .foregroundStyle(DIColor.textPrimary)
        }
    }
}
