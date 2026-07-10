import SwiftUI
import WidgetKit

// "Today's Prayer Times" widget: a medium grid of all six of today's times
// with the next one highlighted, headed by the Hijri date the app precomputed
// with the user's offset. The timeline reloads at the next prayer time (or in
// an hour, whichever comes first) so the highlight advances on schedule.

// MARK: - Timeline entry

struct TodayTimesEntry: TimelineEntry {
    let date: Date
    let snapshot: PrayerWidgetSnapshot?
}

// MARK: - Timeline provider

struct TodayTimesProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayTimesEntry {
        TodayTimesEntry(date: Date(), snapshot: PrayerWidgetSnapshot.sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayTimesEntry) -> Void) {
        let now = Date()
        if context.isPreview {
            completion(TodayTimesEntry(date: now, snapshot: PrayerWidgetSnapshot.sample(referenceDate: now)))
            return
        }
        completion(TodayTimesEntry(date: now, snapshot: PrayerWidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayTimesEntry>) -> Void) {
        let now = Date()
        let snapshot = PrayerWidgetSnapshot.load()
        let entry = TodayTimesEntry(date: now, snapshot: snapshot)

        // Reload when the highlight should move: at the next upcoming time,
        // capped at one hour, and never later than the start of tomorrow so
        // the grid rolls over to the new day.
        var refreshDate = now.addingTimeInterval(60 * 60)
        if let nextTime = snapshot?.upcomingTimes.first(where: { $0.time > now })?.time,
           nextTime < refreshDate {
            refreshDate = nextTime
        }
        let calendar = Calendar.current
        if let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           startOfTomorrow > now, startOfTomorrow < refreshDate {
            refreshDate = startOfTomorrow
        }

        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

// MARK: - Widget

struct TodayTimesWidget: Widget {
    let kind: String = "org.naqshbandiaowaisiah.darulirfan.todaytimes"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayTimesProvider()) { entry in
            TodayTimesWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Prayer Times")
        .description("All of today's times at a glance, with the next one highlighted.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Views

struct TodayTimesWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: TodayTimesEntry

    private var todayTimes: [WidgetPrayerTime] {
        guard let snapshot = entry.snapshot else { return [] }
        return snapshot.times(onSameDayAs: entry.date)
    }

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, !todayTimes.isEmpty {
                content(snapshot: snapshot, times: todayTimes)
            } else {
                WidgetEmptyStateView()
            }
        }
        .containerBackground(for: .widget) {
            WidgetPalette.background(for: colorScheme)
        }
    }

    private func content(snapshot: PrayerWidgetSnapshot, times: [WidgetPrayerTime]) -> some View {
        let nextTime: WidgetPrayerTime? = times.first { $0.time > entry.date }
        let columns: [GridItem] = Array(
            repeating: GridItem(.flexible(), spacing: 6),
            count: 3
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.hijriDateText)
                    .font(.system(.footnote, design: .serif).weight(.semibold))
                    .foregroundStyle(WidgetPalette.emeraldTone(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(snapshot.placeName)
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
                    .lineLimit(1)
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(times, id: \.time) { item in
                    TodayTimeCell(item: item, isNext: item == nextTime)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TodayTimeCell: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: WidgetPrayerTime
    let isNext: Bool

    var body: some View {
        VStack(spacing: 1) {
            Text(item.displayName)
                .font(.caption2)
                .foregroundStyle(
                    isNext
                        ? WidgetPalette.emeraldTone(for: colorScheme)
                        : WidgetPalette.mutedTone(for: colorScheme)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(item.time, style: .time)
                .font(.footnote.weight(isNext ? .semibold : .regular))
                .foregroundStyle(WidgetPalette.textTone(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isNext
                        ? WidgetPalette.goldTone(for: colorScheme).opacity(0.22)
                        : Color.clear
                )
        )
        .accessibilityElement(children: .combine)
    }
}
