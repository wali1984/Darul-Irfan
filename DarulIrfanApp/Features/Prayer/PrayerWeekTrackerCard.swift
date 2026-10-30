import SwiftUI

/// The prayer tracker on the Prayer times page (board Prayer): a week at a
/// time, Saturday to Friday, paged back from this week (next week is off on
/// the current one); a button for each day with a dot for each prayer, and
/// today outlined in gold; then the chosen day's five prayers, each cycling
/// the four marks with a tap, for any day up to today. Days after today are
/// dimmed and cannot be chosen. A legend, and the way to the history.
@MainActor
struct PrayerWeekTrackerCard: View {
    let viewModel: PrayerViewModel
    let dependencies: AppDependencies
    let appState: AppState

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let days = viewModel.trackerWeekDays
        let shown = viewModel.trackerShownDay
        VStack(alignment: .leading, spacing: 14) {
            header(days: days)
            dayStrip(days: days, shown: shown)
            dayHeader(shown)
            // A new identity for each day, so its prayers rise in afresh.
            dayPrayers(shown)
                .diAppear()
                .id(DayKey.make(from: shown))
            legend
            historyLink
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayGlass(cornerRadius: 26)
    }

    // MARK: - Week paging

    private func header(days: [Date]) -> some View {
        HStack(spacing: DISpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Prayer Tracker")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(DIColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                weekLabel(days: days)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DIColor.textMuted)
            }
            Spacer(minLength: DISpacing.sm)
            pageButton(systemImage: "chevron.backward", label: Text("Previous week"), enabled: true) {
                Task { await viewModel.showTrackerWeek(offset: viewModel.trackerWeekOffset - 1) }
            }
            pageButton(systemImage: "chevron.forward", label: Text("Next week"), enabled: viewModel.canShowNextTrackerWeek) {
                Task { await viewModel.showTrackerWeek(offset: viewModel.trackerWeekOffset + 1) }
            }
        }
    }

    /// "This week · 24 October – 30 October", or a past week's own dates.
    @ViewBuilder
    private func weekLabel(days: [Date]) -> some View {
        if let first = days.first, let last = days.last {
            let style = Date.FormatStyle().day().month(.wide).locale(locale)
            let range = "\(first.formatted(style)) – \(last.formatted(style))"
            if viewModel.trackerWeekOffset == 0 {
                Text("This week · \(range)")
            } else {
                Text(verbatim: range)
            }
        }
    }

    private func pageButton(
        systemImage: String,
        label: Text,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            DIHaptics.soft()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TodayPalette.emerald)
                .frame(width: 44, height: 44)
                .background(TodayPalette.chipFill, in: Circle())
                .overlay(Circle().stroke(TodayPalette.glassEdge, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(DIPressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    // MARK: - Days

    private func dayStrip(days: [Date], shown: Date) -> some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                dayButton(day, selected: DayKey.make(from: day) == DayKey.make(from: shown))
            }
        }
    }

    private func dayButton(_ day: Date, selected: Bool) -> some View {
        let isToday = viewModel.isTrackerToday(day)
        let markable = viewModel.isTrackerDayMarkable(day)
        return Button {
            DIHaptics.soft()
            viewModel.selectTrackerDay(day)
        } label: {
            VStack(spacing: 4) {
                Group {
                    if isToday {
                        Text("Today")
                    } else {
                        Text(day, format: .dateTime.weekday(.abbreviated))
                    }
                }
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Text(day, format: .dateTime.day())
                    .font(.headline.weight(.heavy).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 2) {
                    ForEach(Prayer.obligatory) { prayer in
                        Circle()
                            .fill(dotColor(viewModel.completion(for: prayer, on: day), selected: selected))
                            .frame(width: 4, height: 4)
                    }
                }
                .accessibilityHidden(true)
            }
            .foregroundStyle(selected ? Color.white : DIColor.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 7)
            .background(
                selected ? AnyShapeStyle(TodayGradients.emerald) : AnyShapeStyle(TodayPalette.chipFill),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(dayEdge(selected: selected, isToday: isToday), lineWidth: isToday && !selected ? 1.5 : 1)
            )
            .shadow(color: selected ? Color(hex: 0x0B7250).opacity(0.35) : Color.clear, radius: 9, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!markable)
        .opacity(markable ? 1 : 0.35)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dotColor(_ mark: PrayerCompletion, selected: Bool) -> Color {
        if selected && mark == .unmarked {
            return Color.white.opacity(0.35)
        }
        return PrayerMarkStyle.dot(mark)
    }

    private func dayEdge(selected: Bool, isToday: Bool) -> Color {
        if selected { return Color(hex: 0x34B98A).opacity(0.6) }
        if isToday { return TodayPalette.accent }
        return Color.clear
    }

    // MARK: - The chosen day

    private func dayHeader(_ day: Date) -> some View {
        let dayAndMonth = day.formatted(Date.FormatStyle().day().month(.wide).locale(locale))
        return HStack(alignment: .firstTextBaseline, spacing: DISpacing.sm) {
            Group {
                if viewModel.isTrackerToday(day) {
                    Text("Today, \(dayAndMonth)")
                } else {
                    Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
                }
            }
            .font(.headline.weight(.heavy))
            .foregroundStyle(DIColor.textPrimary)
            Spacer(minLength: DISpacing.sm)
            Text("\(viewModel.prayedCount(on: day)) of 5 prayed")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TodayPalette.goldText)
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    private func dayPrayers(_ day: Date) -> some View {
        // Up to today, and only once the day's stored marks have been read.
        let markable = viewModel.isTrackerDayMarkable(day) && viewModel.isTrackerDayLoaded(day)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 6))
        return layout {
            ForEach(Prayer.obligatory) { prayer in
                markButton(prayer, day: day, markable: markable)
            }
        }
    }

    private func markButton(_ prayer: Prayer, day: Date, markable: Bool) -> some View {
        let mark = viewModel.completion(for: prayer, on: day)
        return Button {
            DIHaptics.soft()
            Task { await viewModel.cycleCompletion(for: prayer, on: day) }
        } label: {
            VStack(spacing: 7) {
                PrayerMarkBadge(mark: mark, surface: .glass, size: 30)
                Text(LocalizedStringKey(prayer.englishName))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DIColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(
                mark == .unmarked ? TodayPalette.chipFill.opacity(0) : TodayPalette.chipFill,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(TodayPalette.tileEdge, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(DIPressableStyle())
        .disabled(!markable)
        .accessibilityLabel(PrayerMarkText.accessibilityLabel(prayer: prayer, completion: mark))
        .accessibilityHint(Text("Double tap to change how this prayer is marked."))
    }

    // MARK: - Legend and history

    private var legend: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                legendItem(.prayed, label: Text("Prayed"))
                legendItem(.jamaat, label: Text("In congregation"))
            }
            HStack(spacing: 14) {
                legendItem(.qaza, label: Text("Qaza, to make up"))
                legendItem(.unmarked, label: Text("Not marked"))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ mark: PrayerCompletion, label: Text) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(mark == .unmarked ? Color.clear : PrayerMarkStyle.dot(mark))
                .overlay(Circle().strokeBorder(PrayerMarkStyle.edge(mark, on: .glass), lineWidth: 1.5))
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
            label
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DIColor.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var historyLink: some View {
        NavigationLink {
            PrayerTrackerDetailView(dependencies: dependencies, appState: appState)
        } label: {
            HStack(spacing: DISpacing.sm) {
                Text("Prayer history and streak")
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(TodayPalette.emerald)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, DISpacing.xs)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TodayPalette.rowEdge)
                .frame(height: 1)
        }
    }
}
