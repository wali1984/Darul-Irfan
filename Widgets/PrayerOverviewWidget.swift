import SwiftUI
import WidgetKit

// "Prayer Overview": the Home Screen and StandBy widget that gathers the day.
// Small: the seal, the next prayer and its live countdown, the Hijri date.
// Medium: that, beside the five prayers with the next one highlighted.
// Large: all of it, with Daily Zikr's status and the Ayah of the Day.
// One entry per moment that changes what it shows (WidgetTimelinePlan), so it
// turns over at each prayer and at midnight without the app running.

// MARK: - Timeline

struct PrayerOverviewEntry: TimelineEntry {
    let date: Date
    let snapshot: PrayerWidgetSnapshot?

    var nextPrayer: WidgetPrayerTime? { snapshot?.nextPrayer(after: date) }

    var relevance: TimelineEntryRelevance? {
        guard let snapshot else { return nil }
        if snapshot.currentOrNextZikr(at: date)?.isActive(at: date) == true {
            return TimelineEntryRelevance(score: 100, duration: 30 * 60)
        }
        guard let next = nextPrayer else { return nil }
        let wait = next.time.timeIntervalSince(date)
        let score = Float(max(10, 90 - min(wait / 60, 80)))
        return TimelineEntryRelevance(score: score, duration: min(max(wait, 15 * 60), 2 * 60 * 60))
    }
}

/// The timeline every prayer widget here uses: the snapshot, an entry at
/// each moment WidgetTimelinePlan lists, and a new timeline when it runs out.
enum PrayerTimelines {
    static func timeline<Entry: TimelineEntry>(
        now: Date = Date(),
        make: (Date, PrayerWidgetSnapshot?) -> Entry
    ) -> Timeline<Entry> {
        guard let snapshot = PrayerWidgetSnapshot.load() else {
            // No snapshot yet: the setup hint, and a look again later.
            return Timeline(entries: [make(now, nil)], policy: .after(now.addingTimeInterval(WidgetTimelinePlan.emptyWait)))
        }
        let dates = WidgetTimelinePlan.dates(for: snapshot, from: now)
        return Timeline(
            entries: dates.map { make($0, snapshot) },
            policy: .after(WidgetTimelinePlan.reloadDate(after: dates, from: now))
        )
    }
}

struct PrayerOverviewProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerOverviewEntry {
        PrayerOverviewEntry(date: Date(), snapshot: PrayerWidgetSnapshot.sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (PrayerOverviewEntry) -> Void) {
        let now = Date()
        let snapshot = PrayerWidgetSnapshot.load()
        completion(PrayerOverviewEntry(
            date: now,
            snapshot: context.isPreview ? (snapshot ?? PrayerWidgetSnapshot.sample(referenceDate: now)) : snapshot
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerOverviewEntry>) -> Void) {
        completion(PrayerTimelines.timeline { PrayerOverviewEntry(date: $0, snapshot: $1) })
    }
}

// MARK: - Widget

struct PrayerOverviewWidget: Widget {
    let kind: String = "us.naqshbaniaowaisiah.prayeroverview"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrayerOverviewProvider()) { entry in
            PrayerOverviewWidgetView(entry: entry)
        }
        .configurationDisplayName("Prayer Overview")
        .description("The next prayer with a live countdown, today's five prayers, the Hijri date and the Ayah of the Day.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct PrayerOverviewWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    let entry: PrayerOverviewEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let next = entry.nextPrayer {
                switch family {
                case .systemLarge:
                    OverviewLargeView(entry: entry, snapshot: snapshot, next: next)
                case .systemMedium:
                    OverviewMediumView(entry: entry, snapshot: snapshot, next: next)
                default:
                    OverviewSmallView(entry: entry, snapshot: snapshot, next: next)
                }
            } else {
                WidgetEmptyStateView()
            }
        }
        .widgetPlace(entry.snapshot)
        .containerBackground(for: .widget) {
            WidgetPalette.background(for: colorScheme)
        }
        .widgetURL(URL(string: "darulirfan://today"))
    }
}

/// The seal, "Next Prayer" and the prayer's name, time and countdown.
private struct OverviewNextBlock: View {
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: PrayerWidgetSnapshot
    let next: WidgetPrayerTime
    let date: Date
    var sealSize: CGFloat = 26
    var nameFont: Font = .system(.title3, design: .serif).weight(.semibold)
    var countdownFont: Font = .title2.weight(.medium)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                WidgetSeal(size: sealSize)
                Text("Next Prayer")
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
                    .lineLimit(1)
            }
            Text(next.displayName)
                .font(nameFont)
                .foregroundStyle(WidgetPalette.emeraldTone(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
            WidgetCountdown(interval: snapshot.countdownInterval(to: next, at: date))
                .font(countdownFont)
                .foregroundStyle(WidgetPalette.goldTone(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            Text(next.time, style: .time)
                .font(.footnote.weight(.medium))
                .foregroundStyle(WidgetPalette.textTone(for: colorScheme))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OverviewSmallView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: PrayerOverviewEntry
    let snapshot: PrayerWidgetSnapshot
    let next: WidgetPrayerTime

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            OverviewNextBlock(snapshot: snapshot, next: next, date: entry.date)
            Spacer(minLength: 0)
            Text(verbatim: snapshot.hijriText(on: entry.date))
                .font(.system(.caption2, design: .serif).weight(.semibold))
                .foregroundStyle(WidgetPalette.emeraldTone(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: snapshot.placeName)
                .font(.caption2)
                .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct OverviewMediumView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: PrayerOverviewEntry
    let snapshot: PrayerWidgetSnapshot
    let next: WidgetPrayerTime

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                OverviewNextBlock(snapshot: snapshot, next: next, date: entry.date)
                Spacer(minLength: 0)
                Text(verbatim: snapshot.hijriText(on: entry.date))
                    .font(.system(.caption2, design: .serif).weight(.semibold))
                    .foregroundStyle(WidgetPalette.emeraldTone(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            WidgetFivePrayers(prayers: snapshot.fivePrayers(on: entry.date), date: entry.date)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct OverviewLargeView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: PrayerOverviewEntry
    let snapshot: PrayerWidgetSnapshot
    let next: WidgetPrayerTime

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                WidgetSeal(size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Darul Irfan")
                        .font(.system(.headline, design: .serif).weight(.bold))
                        .foregroundStyle(WidgetPalette.goldTone(for: colorScheme))
                        .widgetAccentable()
                    Text(verbatim: snapshot.hijriText(on: entry.date))
                        .font(.system(.caption, design: .serif).weight(.semibold))
                        .foregroundStyle(WidgetPalette.emeraldTone(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 6)
                Text(verbatim: snapshot.placeName)
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
                    .lineLimit(1)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next Prayer")
                        .font(.caption2)
                        .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
                    Text(next.displayName)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(WidgetPalette.emeraldTone(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .widgetAccentable()
                    WidgetCountdown(interval: snapshot.countdownInterval(to: next, at: entry.date))
                        .font(.title.weight(.medium))
                        .foregroundStyle(WidgetPalette.goldTone(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .widgetAccentable()
                    Text(next.time, style: .time)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(WidgetPalette.textTone(for: colorScheme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                WidgetFivePrayers(prayers: snapshot.fivePrayers(on: entry.date), date: entry.date)
                    .frame(maxWidth: .infinity)
            }
            if let zikr = snapshot.currentOrNextZikr(at: entry.date) {
                Link(destination: URL(string: "darulirfan://zikr") ?? URL(fileURLWithPath: "/")) {
                    WidgetZikrLine(session: zikr, date: entry.date)
                }
            }
            if let ayah = snapshot.dailyAyah(on: entry.date) {
                Rectangle()
                    .fill(WidgetPalette.goldTone(for: colorScheme).opacity(0.45))
                    .frame(height: 1)
                Link(destination: ayah.link ?? URL(fileURLWithPath: "/")) {
                    VStack(spacing: 4) {
                        Text("Ayah of the Day")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
                        WidgetAyahBlock(ayah: ayah, arabicSize: 18, translationLines: 3)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
