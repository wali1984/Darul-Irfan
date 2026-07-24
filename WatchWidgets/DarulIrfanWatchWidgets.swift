import SwiftUI
import WidgetKit

@main
struct DarulIrfanWatchWidgets: WidgetBundle {
    var body: some Widget { NextPrayerComplication() }
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
        completion(Timeline(entries: dates.map { WatchPrayerEntry(date: $0, snapshot: snapshot) }, policy: .atEnd))
    }
}

struct NextPrayerComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DarulIrfan.NextPrayer", provider: WatchPrayerProvider()) { entry in
            let next = entry.snapshot?.upcomingTimes.first(where: { $0.time > entry.date })
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
