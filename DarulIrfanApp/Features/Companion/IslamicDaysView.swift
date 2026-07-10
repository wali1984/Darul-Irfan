import Foundation
import Observation
import SwiftUI

// MARK: - View model

@Observable
@MainActor
final class IslamicDaysViewModel {
    /// One occurrence of a notable Islamic day within the lookahead window.
    /// A single day can occur twice inside 400 days, so identity includes
    /// the Gregorian day key.
    struct Occurrence: Identifiable {
        let day: IslamicDay
        let gregorianDate: Date
        let hijriText: String
        var id: String { "\(day.id)|\(DayKey.make(from: gregorianDate))" }
    }

    struct MonthGroup: Identifiable {
        let id: String
        let title: String
        var occurrences: [Occurrence]
    }

    private let hijri: any HijriCalendarServicing
    private(set) var groups: [MonthGroup] = []
    private(set) var isLoaded = false

    init(hijri: any HijriCalendarServicing) {
        self.hijri = hijri
    }

    func load(offsetDays: Int) {
        let upcoming = hijri.upcomingIslamicDays(from: Date(), within: 400, offsetDays: offsetDays)
            .sorted { $0.gregorianDate < $1.gregorianDate }

        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale.current
        monthFormatter.setLocalizedDateFormatFromTemplate("MMMM y")

        var result: [MonthGroup] = []
        for entry in upcoming {
            let occurrence = Occurrence(
                day: entry.day,
                gregorianDate: entry.gregorianDate,
                hijriText: hijri.hijriDateText(
                    for: entry.gregorianDate,
                    offsetDays: offsetDays,
                    locale: Locale.current
                )
            )
            let title = monthFormatter.string(from: entry.gregorianDate)
            if let lastIndex = result.indices.last, result[lastIndex].title == title {
                result[lastIndex].occurrences.append(occurrence)
            } else {
                result.append(MonthGroup(
                    id: "\(result.count)|\(title)",
                    title: title,
                    occurrences: [occurrence]
                ))
            }
        }
        groups = result
        isLoaded = true
    }
}

// MARK: - Screen

/// Notable Islamic days over the next 400 days, grouped by month, with the
/// Hijri date and the approximate Gregorian date for each.
@MainActor
struct IslamicDaysView: View {
    @State private var viewModel: IslamicDaysViewModel
    private let appState: AppState

    init(hijri: any HijriCalendarServicing, appState: AppState) {
        self.appState = appState
        _viewModel = State(initialValue: IslamicDaysViewModel(hijri: hijri))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                if viewModel.isLoaded && viewModel.groups.isEmpty {
                    DIEmptyState(
                        systemImage: "moon.stars",
                        titleKey: "No upcoming days found",
                        messageKey: "Notable Islamic days will appear here. Updating the app should restore the bundled list."
                    )
                } else {
                    ForEach(viewModel.groups) { group in
                        VStack(alignment: .leading, spacing: DISpacing.sm) {
                            Text(verbatim: group.title)
                                .font(DIFont.subheading)
                                .foregroundStyle(DIColor.textPrimary)
                                .padding(.horizontal, DISpacing.xs)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.occurrences) { occurrence in
                                IslamicDayRow(occurrence: occurrence)
                            }
                        }
                    }
                }

                Text("Islamic dates are approximate and may vary with local moon sighting.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .padding(.horizontal, DISpacing.xs)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DISpacing.md)
        }
        .navigationTitle("Islamic Days")
        .diScreenBackground()
        .task {
            viewModel.load(offsetDays: appState.settings.hijri.dayOffset)
        }
    }
}

// MARK: - Row

private struct IslamicDayRow: View {
    let occurrence: IslamicDaysViewModel.Occurrence

    var body: some View {
        DICard {
            HStack(alignment: .top, spacing: DISpacing.md) {
                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text(verbatim: occurrence.day.title)
                        .font(.headline)
                        .foregroundStyle(DIColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = occurrence.day.note {
                        Text(verbatim: note)
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: DISpacing.xs) {
                    Text(verbatim: occurrence.hijriText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.primary)
                    Text("≈ \(occurrence.gregorianDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
