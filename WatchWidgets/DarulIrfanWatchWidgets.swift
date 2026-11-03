import SwiftUI
import WidgetKit

// Apple Watch complications. watchOS has no custom lock screen and no
// third-party watch faces: these are what a person adds to the face they
// use. Every family a face offers is supported: circular, corner,
// rectangular and inline. Complications cannot run animations; the seal's
// animation lives on the Watch app's own screen (WatchApp).

@main
struct DarulIrfanWatchWidgets: WidgetBundle {
    var body: some Widget {
        NextPrayerComplication()
        PrayerCountdownComplication()
        SealComplication()
        NextZikrComplication()
    }
}

struct WatchPrayerEntry: TimelineEntry {
    var date: Date
    var snapshot: PrayerWidgetSnapshot?

    var nextPrayer: WidgetPrayerTime? { snapshot?.nextPrayer(after: date) }
}

struct WatchPrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchPrayerEntry { WatchPrayerEntry(date: Date(), snapshot: nil) }

    func getSnapshot(in context: Context, completion: @escaping (WatchPrayerEntry) -> Void) {
        completion(WatchPrayerEntry(date: Date(), snapshot: PrayerWidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchPrayerEntry>) -> Void) {
        let now = Date()
        guard let snapshot = PrayerWidgetSnapshot.load() else {
            let entry = WatchPrayerEntry(date: now, snapshot: nil)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(WidgetTimelinePlan.emptyWait))))
            return
        }
        // An entry at each prayer, zikr boundary and midnight, so the faces
        // turn over on time; a new timeline when it runs out.
        let dates = WidgetTimelinePlan.dates(for: snapshot, from: now)
        completion(Timeline(
            entries: dates.map { WatchPrayerEntry(date: $0, snapshot: snapshot) },
            policy: .after(WidgetTimelinePlan.reloadDate(after: dates, from: now))
        ))
    }
}

// MARK: - Shared pieces

/// The seal: the original emblem where the face shows colour, its
/// monochrome cut in the face's tone where it does not.
private struct ComplicationSeal: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            if renderingMode == .fullColor {
                Image("BrandEmblem")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image("BrandEmblemMono")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .scaledToFit()
                    .widgetAccentable()
            }
        }
        .accessibilityLabel(Text("Darul Irfan"))
    }
}

private struct ComplicationPlace: ViewModifier {
    let snapshot: PrayerWidgetSnapshot?

    func body(content: Content) -> some View {
        content
            // On the place's clock, as the iPhone app shows it, in the app's
            // language with Western digits.
            .environment(\.timeZone, snapshot?.timeZone ?? .current)
            .transformEnvironment(\.locale) { locale in
                if let chosen = snapshot?.displayLocale { locale = chosen }
            }
            .transformEnvironment(\.layoutDirection) { direction in
                if let rtl = snapshot?.readsRightToLeft { direction = rtl ? .rightToLeft : .leftToRight }
            }
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

private extension View {
    func complicationPlace(_ snapshot: PrayerWidgetSnapshot?) -> some View {
        modifier(ComplicationPlace(snapshot: snapshot))
    }
}

// MARK: - Next Prayer

struct NextPrayerComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DarulIrfan.NextPrayer", provider: WatchPrayerProvider()) { entry in
            NextPrayerComplicationView(entry: entry)
                .complicationPlace(entry.snapshot)
        }
        .configurationDisplayName("Next Prayer")
        .description("The next prayer and its local time.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

private struct NextPrayerComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchPrayerEntry

    var body: some View {
        if let next = entry.nextPrayer {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Text(next.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .widgetAccentable()
                        Text(next.time, style: .time)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .padding(4)
                }
            case .accessoryCorner:
                ComplicationSeal()
                    .padding(4)
                    .widgetLabel {
                        Text("\(next.displayName) \(next.time, style: .time)")
                    }
            case .accessoryInline:
                Label {
                    Text("\(next.displayName) \(next.time, style: .time)")
                } icon: {
                    Image(systemName: "moon.stars.fill")
                }
            default:
                HStack(spacing: 6) {
                    ComplicationSeal()
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(next.displayName)
                            .font(.headline)
                            .widgetAccentable()
                        Text(next.time, style: .time)
                            .font(.body.monospacedDigit())
                        if let snapshot = entry.snapshot {
                            Text(verbatim: snapshot.hijriText(on: entry.date))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyComplicationView()
        }
    }
}

// MARK: - Prayer Countdown

struct PrayerCountdownComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DarulIrfan.PrayerCountdown", provider: WatchPrayerProvider()) { entry in
            PrayerCountdownComplicationView(entry: entry)
                .complicationPlace(entry.snapshot)
        }
        .configurationDisplayName("Prayer Countdown")
        .description("The time left until the next prayer.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

private struct PrayerCountdownComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchPrayerEntry

    var body: some View {
        if let snapshot = entry.snapshot, let next = entry.nextPrayer {
            let interval = snapshot.countdownInterval(to: next, at: entry.date)
            switch family {
            case .accessoryCircular:
                ProgressView(timerInterval: interval, countsDown: true) {
                    Text(next.displayName)
                } currentValueLabel: {
                    Text(timerInterval: interval, countsDown: true)
                        .monospacedDigit()
                }
                .progressViewStyle(.circular)
                .widgetAccentable()
            case .accessoryCorner:
                Text(timerInterval: interval, countsDown: true)
                    .monospacedDigit()
                    .widgetCurvesContent()
                    .widgetLabel {
                        ProgressView(timerInterval: interval, countsDown: true) {
                            Text(next.displayName)
                        } currentValueLabel: {
                            EmptyView()
                        }
                    }
            case .accessoryInline:
                Text("\(next.displayName) \(Text(timerInterval: interval, countsDown: true))")
            default:
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(next.displayName)
                            .font(.headline)
                            .widgetAccentable()
                        Text(next.time, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(timerInterval: interval, countsDown: true)
                        .font(.title3.monospacedDigit())
                    ProgressView(timerInterval: interval, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .widgetAccentable()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyComplicationView()
        }
    }
}

// MARK: - Seal

struct SealComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DarulIrfan.Seal", provider: WatchPrayerProvider()) { entry in
            SealComplicationView(entry: entry)
                .complicationPlace(entry.snapshot)
        }
        .configurationDisplayName("Silsila Seal")
        .description("The Silsila's seal on your watch face. Tap it to open Darul Irfan.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

private struct SealComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchPrayerEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                ComplicationSeal()
                    .padding(3)
            }
        case .accessoryCorner:
            ComplicationSeal()
                .padding(4)
                .widgetLabel {
                    if let snapshot = entry.snapshot {
                        Text(verbatim: snapshot.hijriText(on: entry.date))
                    } else {
                        Text("Darul Irfan")
                    }
                }
        case .accessoryInline:
            Label {
                if let snapshot = entry.snapshot {
                    Text(verbatim: snapshot.hijriText(on: entry.date))
                } else {
                    Text("Darul Irfan")
                }
            } icon: {
                Image(systemName: "moon.stars.fill")
            }
        default:
            HStack(spacing: 8) {
                ComplicationSeal()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Darul Irfan")
                        .font(.headline)
                        .widgetAccentable()
                    if let snapshot = entry.snapshot {
                        Text(verbatim: snapshot.hijriText(on: entry.date))
                            .font(.caption2)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Before the iPhone has sent prayer times: the seal, and where to set up.
private struct EmptyComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("Open Darul Irfan on iPhone")
        case .accessoryRectangular:
            HStack(spacing: 6) {
                ComplicationSeal()
                    .frame(width: 30, height: 30)
                Text("Open Darul Irfan on iPhone")
                    .font(.caption)
            }
        default:
            ComplicationSeal()
                .padding(4)
        }
    }
}

// MARK: - Next Zikr

struct NextZikrComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DarulIrfan.NextZikr", provider: WatchPrayerProvider()) { entry in
            ZikrComplicationView(entry: entry)
                .complicationPlace(entry.snapshot)
        }
        .configurationDisplayName("Next Zikr")
        .description("The current or next online zikr session.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

private struct ZikrComplicationView: View {
    let entry: WatchPrayerEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let zikr = entry.snapshot?.currentOrNextZikr(at: entry.date)
        let active = zikr?.isActive(at: entry.date) ?? false
        let target = zikr.map { active ? $0.endsAt : $0.startsAt }
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: active ? "dot.radiowaves.left.and.right" : "heart.fill")
                    .widgetAccentable()
                if let target {
                    Text(timerInterval: entry.date...max(entry.date, target), countsDown: true)
                        .font(.caption2.monospacedDigit())
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.65)
                }
            }
        case .accessoryCorner:
            Image(systemName: active ? "dot.radiowaves.left.and.right" : "heart.fill")
                .font(.title3)
                .widgetAccentable()
                .widgetLabel {
                    if let target {
                        Text(timerInterval: entry.date...max(entry.date, target), countsDown: true)
                    } else {
                        Text("Sync zikr")
                    }
                }
        case .accessoryInline:
            if let target {
                Label {
                    if active {
                        Text("Zikr live · \(target, style: .timer)")
                    } else {
                        Text("Zikr · \(target, style: .timer)")
                    }
                } icon: {
                    Image(systemName: active ? "dot.radiowaves.left.and.right" : "heart.fill")
                }
            } else {
                Label("Sync zikr", systemImage: "heart")
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Label(active ? LocalizedStringKey("Zikr live") : LocalizedStringKey("Next zikr"), systemImage: active ? "dot.radiowaves.left.and.right" : "heart.fill")
                    .font(.headline)
                    .widgetAccentable()
                if let zikr, let target {
                    Text(zikr.title).font(.caption).lineLimit(1)
                    Text(timerInterval: entry.date...max(entry.date, target), countsDown: true)
                        .font(.caption.monospacedDigit())
                } else {
                    Text("Open Zikr on iPhone").font(.caption)
                }
            }
        }
    }
}
