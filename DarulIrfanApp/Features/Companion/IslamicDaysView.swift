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
        /// For a night kept from the sunset before its date: that evening.
        /// The night of 15 Sha'ban, for one, begins on the evening of the
        /// 14th, so showing only the 15th would send people a night late.
        var eveDate: Date? = nil
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

    /// `locale` is the app's own language, which may differ from the phone's.
    func load(offsetDays: Int, locale: Locale) {
        let upcoming = hijri.upcomingIslamicDays(from: Date(), within: 400, offsetDays: offsetDays)
            .sorted { $0.gregorianDate < $1.gregorianDate }

        let monthFormatter = DateFormatter()
        monthFormatter.locale = locale
        monthFormatter.setLocalizedDateFormatFromTemplate("MMMM y")

        // The same calendar the dates above were found with (the phone's
        // time zone), so "the day before" is the civil day before.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current

        var result: [MonthGroup] = []
        for entry in upcoming {
            let occurrence = Occurrence(
                day: entry.day,
                gregorianDate: entry.gregorianDate,
                hijriText: hijri.hijriDateText(
                    for: entry.gregorianDate,
                    offsetDays: offsetDays,
                    locale: locale
                ),
                eveDate: entry.day.observedOnEve == true
                    ? gregorian.date(byAdding: .day, value: -1, to: entry.gregorianDate)
                    : nil
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

    /// The soonest upcoming occurrence, highlighted as "Next" in the timeline.
    var firstOccurrenceID: String? {
        groups.first?.occurrences.first?.id
    }
}

// MARK: - Screen

/// Notable Islamic days over the next 400 days as a refined vertical timeline,
/// grouped by month, with the Hijri date and the approximate Gregorian date
/// for each and the soonest day marked "Next".
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
                    DIElevatedCard {
                        DIEmptyState(
                            systemImage: "moon.stars",
                            titleKey: "No upcoming days found",
                            messageKey: "Notable Islamic days will appear here. Updating the app should restore the bundled list."
                        )
                        .diOctagramWatermark(size: 220, opacity: 0.06)
                    }
                } else {
                    ForEach(viewModel.groups) { group in
                        VStack(alignment: .leading, spacing: DISpacing.sm) {
                            monthChip(group.title)
                            VStack(spacing: 0) {
                                ForEach(group.occurrences) { occurrence in
                                    IslamicDayTimelineRow(
                                        occurrence: occurrence,
                                        isNext: occurrence.id == viewModel.firstOccurrenceID,
                                        urdu: appState.settings.language.contentLanguageCode == "ur"
                                    )
                                }
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
            viewModel.load(
                offsetDays: appState.settings.hijri.dayOffset,
                locale: LanguageManager.locale(for: appState.settings.language)
            )
        }
    }

    private func monthChip(_ title: String) -> some View {
        Text(verbatim: title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DIColor.onPrimary)
            .padding(.horizontal, DISpacing.md)
            .padding(.vertical, DISpacing.xs)
            .background(Capsule().fill(DIGradient.emerald))
            .diGoldGlow(radius: 5, opacity: 0.2)
            .padding(.horizontal, DISpacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Timeline row

private struct IslamicDayTimelineRow: View {
    let occurrence: IslamicDaysViewModel.Occurrence
    let isNext: Bool
    /// Shows the day's Urdu name and note where the bundle has them.
    let urdu: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DISpacing.sm) {
            timelineRail
            DIElevatedCard(glow: isNext ? DIColor.accent.opacity(0.7) : nil) {
                HStack(alignment: .top, spacing: DISpacing.md) {
                    VStack(alignment: .leading, spacing: DISpacing.xs) {
                        if isNext {
                            DIPillBadge(text: String(localized: "Next"), color: DIColor.accent)
                        }
                        Text(verbatim: occurrence.day.displayTitle(urdu: urdu))
                            .font(.headline)
                            .foregroundStyle(DIColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let note = occurrence.day.displayNote(urdu: urdu) {
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
                            .foregroundStyle(DIColor.actionForeground)
                        if let eve = occurrence.eveDate {
                            let evening = eve.formatted(date: .abbreviated, time: .omitted)
                            Text("Night of ≈ \(evening)")
                                .font(.caption)
                                .foregroundStyle(DIColor.textMuted)
                        } else {
                            let day = occurrence.gregorianDate.formatted(date: .abbreviated, time: .omitted)
                            Text("≈ \(day)")
                                .font(.caption)
                                .foregroundStyle(DIColor.textMuted)
                        }
                    }
                }
            }
            .padding(.bottom, DISpacing.md)
        }
        .accessibilityElement(children: .combine)
    }

    private var timelineRail: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(DIColor.border)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
            Circle()
                .fill(isNext ? AnyShapeStyle(DIGradient.goldSheen) : AnyShapeStyle(DIGradient.emerald))
                .frame(width: 16, height: 16)
                .overlay(
                    Circle().strokeBorder(DIColor.background, lineWidth: 2)
                )
                .diGoldGlow(radius: isNext ? 8 : 0, opacity: isNext ? 0.5 : 0)
                .padding(.top, 6)
        }
        .frame(width: 18)
        .accessibilityHidden(true)
    }
}
