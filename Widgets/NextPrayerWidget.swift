import SwiftUI
import WidgetKit

// "Next Prayer" widget: the upcoming obligatory prayer with a live countdown.
// Home Screen small/medium plus Lock Screen circular/rectangular/inline.
// The timeline places one entry per prayer transition, dated at the moment the
// previous prayer arrives, so the widget flips to the new prayer exactly on
// time without any background refresh.

// MARK: - Timeline entry

struct NextPrayerEntry: TimelineEntry {
    let date: Date
    let snapshot: PrayerWidgetSnapshot?
    /// The obligatory prayer this entry features, nil when no data is available.
    let nextPrayer: WidgetPrayerTime?
}

/// A Ramadan moment ("Suhoor ends" / "Iftar") relevant to the featured prayer.
struct RamadanMoment {
    enum Kind {
        case suhoorEnds
        case iftar
    }

    let kind: Kind
    let time: Date
}

extension NextPrayerEntry {
    /// Suhoor caption when the next prayer is Fajr, Iftar caption when it is
    /// Maghrib — only while the moment is still ahead of this entry's date.
    var ramadanMoment: RamadanMoment? {
        guard let snapshot, let next = nextPrayer else { return nil }
        if next.prayerKey == "fajr", let suhoor = snapshot.suhoorEndsAt, suhoor >= date {
            return RamadanMoment(kind: .suhoorEnds, time: suhoor)
        }
        if next.prayerKey == "maghrib", let iftar = snapshot.iftarAt, iftar >= date {
            return RamadanMoment(kind: .iftar, time: iftar)
        }
        return nil
    }

    /// Today's times still ahead of this entry, excluding the featured prayer
    /// (used by the medium family's bottom row).
    var remainingToday: [WidgetPrayerTime] {
        guard let snapshot else { return [] }
        return snapshot.times(onSameDayAs: date).filter { item in
            item.time > date && item != nextPrayer
        }
    }
}

// MARK: - Timeline provider

struct NextPrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextPrayerEntry {
        let now = Date()
        let sample = PrayerWidgetSnapshot.sample(referenceDate: now)
        return NextPrayerEntry(date: now, snapshot: sample, nextPrayer: sample.nextPrayer(after: now))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextPrayerEntry) -> Void) {
        let now = Date()
        if context.isPreview {
            let sample = PrayerWidgetSnapshot.sample(referenceDate: now)
            completion(NextPrayerEntry(date: now, snapshot: sample, nextPrayer: sample.nextPrayer(after: now)))
            return
        }
        let snapshot = PrayerWidgetSnapshot.load()
        completion(NextPrayerEntry(date: now, snapshot: snapshot, nextPrayer: snapshot?.nextPrayer(after: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextPrayerEntry>) -> Void) {
        let now = Date()

        guard let snapshot = PrayerWidgetSnapshot.load() else {
            // No snapshot yet — show the setup hint and try again later.
            let entry = NextPrayerEntry(date: now, snapshot: nil, nextPrayer: nil)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30 * 60))))
            return
        }

        let upcoming: [WidgetPrayerTime] = Array(
            snapshot.upcomingTimes
                .filter { $0.isObligatory && $0.time > now }
                .prefix(12)
        )

        guard let first = upcoming.first else {
            // Snapshot exhausted (app not opened for a long while).
            let entry = NextPrayerEntry(date: now, snapshot: snapshot, nextPrayer: nil)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30 * 60))))
            return
        }

        // One entry per prayer transition: entry i becomes visible when
        // prayer i-1 arrives, and features prayer i.
        var entries: [NextPrayerEntry] = [
            NextPrayerEntry(date: now, snapshot: snapshot, nextPrayer: first)
        ]
        var index = 1
        while index < upcoming.count {
            entries.append(
                NextPrayerEntry(
                    date: upcoming[index - 1].time,
                    snapshot: snapshot,
                    nextPrayer: upcoming[index]
                )
            )
            index += 1
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Widget

struct NextPrayerWidget: Widget {
    let kind: String = "org.naqshbandiaowaisiah.darulirfan.nextprayer"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextPrayerProvider()) { entry in
            NextPrayerWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Prayer")
        .description("The upcoming prayer with a live countdown.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Views

struct NextPrayerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    let entry: NextPrayerEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let next = entry.nextPrayer {
                switch family {
                case .systemMedium:
                    NextPrayerMediumView(entry: entry, snapshot: snapshot, next: next)
                case .accessoryCircular:
                    NextPrayerCircularView(next: next)
                case .accessoryRectangular:
                    NextPrayerRectangularView(next: next, moment: entry.ramadanMoment)
                case .accessoryInline:
                    Text("\(next.displayName) \(next.time, style: .time)")
                default:
                    NextPrayerSmallView(entry: entry, snapshot: snapshot, next: next)
                }
            } else {
                WidgetEmptyStateView()
            }
        }
        .containerBackground(for: .widget) {
            WidgetPalette.background(for: colorScheme)
        }
    }
}

/// Small caption line for "Suhoor ends 4:20 AM" / "Iftar 7:05 PM".
private struct RamadanCaptionView: View {
    @Environment(\.colorScheme) private var colorScheme

    let moment: RamadanMoment

    var body: some View {
        Group {
            switch moment.kind {
            case .suhoorEnds:
                Text("Suhoor ends \(moment.time, style: .time)")
            case .iftar:
                Text("Iftar \(moment.time, style: .time)")
            }
        }
        .font(.caption2)
        .foregroundStyle(WidgetPalette.goldTone(for: colorScheme))
        .lineLimit(1)
    }
}

private struct NextPrayerSmallView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: NextPrayerEntry
    let snapshot: PrayerWidgetSnapshot
    let next: WidgetPrayerTime

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Next Prayer")
                .font(.caption2)
                .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
            Text(next.displayName)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(WidgetPalette.emeraldTone(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(next.time, style: .time)
                .font(.title3.weight(.medium))
                .foregroundStyle(WidgetPalette.textTone(for: colorScheme))
            Text(next.time, style: .timer)
                .font(.caption.monospacedDigit())
                .foregroundStyle(WidgetPalette.goldTone(for: colorScheme))
            if let moment = entry.ramadanMoment {
                RamadanCaptionView(moment: moment)
            }
            Spacer(minLength: 0)
            Text(snapshot.placeName)
                .font(.caption2)
                .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

private struct NextPrayerMediumView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: NextPrayerEntry
    let snapshot: PrayerWidgetSnapshot
    let next: WidgetPrayerTime

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next Prayer")
                        .font(.caption2)
                        .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
                    Text(next.displayName)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(WidgetPalette.emeraldTone(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(next.time, style: .time)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(WidgetPalette.textTone(for: colorScheme))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(next.time, style: .timer)
                        .font(.title3.monospacedDigit().weight(.light))
                        .foregroundStyle(WidgetPalette.goldTone(for: colorScheme))
                        .multilineTextAlignment(.trailing)
                    if let moment = entry.ramadanMoment {
                        RamadanCaptionView(moment: moment)
                    }
                    Text(snapshot.placeName)
                        .font(.caption2)
                        .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            remainingRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var remainingRow: some View {
        let remaining: [WidgetPrayerTime] = Array(entry.remainingToday.prefix(4))
        return Group {
            if remaining.isEmpty {
                Text("Today's prayers are complete")
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
            } else {
                HStack(spacing: 8) {
                    ForEach(remaining, id: \.time) { item in
                        VStack(spacing: 1) {
                            Text(item.displayName)
                                .font(.caption2)
                                .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(item.time, style: .time)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(WidgetPalette.textTone(for: colorScheme))
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

private struct NextPrayerCircularView: View {
    let next: WidgetPrayerTime

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(next.displayName)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(next.time, style: .timer)
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(2)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NextPrayerRectangularView: View {
    let next: WidgetPrayerTime
    let moment: RamadanMoment?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(next.displayName)
                .font(.headline)
                .lineLimit(1)
            Text(next.time, style: .time)
                .font(.caption)
            Text(next.time, style: .timer)
                .font(.caption2.monospacedDigit())
            if let moment {
                switch moment.kind {
                case .suhoorEnds:
                    Text("Suhoor ends \(moment.time, style: .time)")
                        .font(.caption2)
                case .iftar:
                    Text("Iftar \(moment.time, style: .time)")
                        .font(.caption2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
