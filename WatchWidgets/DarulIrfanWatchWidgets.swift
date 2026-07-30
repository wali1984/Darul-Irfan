import SwiftUI
import WidgetKit

@main
struct DarulIrfanWatchWidgets: WidgetBundle {
    var body: some Widget {
        NextPrayerComplication()
        NextZikrComplication()
    }
}

struct WatchPrayerEntry: TimelineEntry {
    var date: Date
    var snapshot: PrayerWidgetSnapshot?
}

struct WatchPrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchPrayerEntry { WatchPrayerEntry(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (WatchPrayerEntry) -> Void) {
        completion(WatchPrayerEntry(date: Date(), snapshot: PrayerWidgetSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchPrayerEntry>) -> Void) {
        let snapshot = PrayerWidgetSnapshot.load()
        var dates = [Date()]
        dates.append(contentsOf: snapshot?.upcomingTimes.filter { $0.time > Date() }.prefix(8).map(\.time) ?? [])
        dates.append(contentsOf: snapshot?.zikrSessions?.flatMap { [$0.startsAt, $0.endsAt] }.filter { $0 > Date() }.prefix(12) ?? [])
        dates = Array(Set(dates)).sorted()
        completion(Timeline(entries: dates.map { WatchPrayerEntry(date: $0, snapshot: snapshot) }, policy: .atEnd))
    }
}

struct NextZikrComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DarulIrfan.NextZikr", provider: WatchPrayerProvider()) { entry in
            ZikrComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Zikr")
        .description("The current or next online zikr session.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct ZikrComplicationView: View {
    let entry: WatchPrayerEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let zikr = entry.snapshot?.currentOrNextZikr(at: entry.date)
        let active = zikr?.isActive(at: entry.date) ?? false
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: active ? "dot.radiowaves.left.and.right" : "heart.fill")
                if let zikr {
                    Text(active ? zikr.endsAt : zikr.startsAt, style: .timer)
                        .font(.caption2.monospacedDigit())
                        .minimumScaleFactor(0.65)
                }
            }
        case .accessoryInline:
            if let zikr {
                Label {
                    if active {
                        Text("Zikr live · \(zikr.endsAt, style: .timer)")
                    } else {
                        Text("Zikr · \(zikr.startsAt, style: .timer)")
                    }
                } icon: {
                    Image(systemName: active ? "dot.radiowaves.left.and.right" : "heart.fill")
                }
            } else {
                Label("Sync zikr", systemImage: "heart")
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Label(active ? "Zikr live" : "Next zikr", systemImage: active ? "dot.radiowaves.left.and.right" : "heart.fill")
                    .font(.headline)
                if let zikr {
                    Text(zikr.title).font(.caption).lineLimit(1)
                    Text(active ? zikr.endsAt : zikr.startsAt, style: .timer)
                        .font(.caption.monospacedDigit())
                } else {
                    Text("Open Zikr on iPhone").font(.caption)
                }
            }
        }
    }
}

struct NextPrayerComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DarulIrfan.NextPrayer", provider: WatchPrayerProvider()) { entry in
            let next = entry.snapshot?.nextPrayer(after: entry.date)
            VStack(alignment: .leading, spacing: 2) {
                Text(next?.displayName ?? "Darul Irfan").font(.headline)
                if let time = next?.time { Text(time, style: .time).font(.caption).monospacedDigit() }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Prayer")
        .description("The next prayer and its local time.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
