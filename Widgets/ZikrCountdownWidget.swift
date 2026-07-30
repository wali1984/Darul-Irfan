import SwiftUI
import WidgetKit

struct ZikrCountdownEntry: TimelineEntry {
    let date: Date
    let snapshot: PrayerWidgetSnapshot?
    let session: WidgetZikrSession?
}

struct ZikrCountdownProvider: TimelineProvider {
    func placeholder(in context: Context) -> ZikrCountdownEntry {
        let now = Date()
        let sample = PrayerWidgetSnapshot.sample(referenceDate: now)
        return ZikrCountdownEntry(date: now, snapshot: sample, session: sample.currentOrNextZikr(at: now))
    }

    func getSnapshot(in context: Context, completion: @escaping (ZikrCountdownEntry) -> Void) {
        let now = Date()
        let snapshot = context.isPreview ? PrayerWidgetSnapshot.sample(referenceDate: now) : PrayerWidgetSnapshot.load()
        completion(ZikrCountdownEntry(date: now, snapshot: snapshot, session: snapshot?.currentOrNextZikr(at: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ZikrCountdownEntry>) -> Void) {
        let now = Date()
        guard let snapshot = PrayerWidgetSnapshot.load() else {
            completion(Timeline(
                entries: [ZikrCountdownEntry(date: now, snapshot: nil, session: nil)],
                policy: .after(now.addingTimeInterval(30 * 60))
            ))
            return
        }

        var boundaries = [now]
        for session in snapshot.zikrSessions ?? [] where session.endsAt > now {
            if session.startsAt > now { boundaries.append(session.startsAt) }
            boundaries.append(session.endsAt)
        }
        let entries = Array(Set(boundaries)).sorted().map { date in
            ZikrCountdownEntry(
                date: date,
                snapshot: snapshot,
                session: snapshot.currentOrNextZikr(at: date)
            )
        }
        let refresh = entries.last?.date.addingTimeInterval(15 * 60) ?? now.addingTimeInterval(30 * 60)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct ZikrCountdownWidget: Widget {
    let kind = "us.naqshbaniaowaisiah.zikrcountdown"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ZikrCountdownProvider()) { entry in
            ZikrCountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Zikr")
        .description("The current or next online zikr session with a live countdown.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

private struct ZikrCountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: ZikrCountdownEntry

    private var active: Bool {
        entry.session?.isActive(at: entry.date) == true
    }

    private var target: Date? {
        guard let session = entry.session else { return nil }
        return active ? session.endsAt : session.startsAt
    }

    var body: some View {
        Group {
            if let session = entry.session, let target {
                switch family {
                case .accessoryCircular:
                    circular(session: session, target: target)
                case .accessoryRectangular:
                    rectangular(session: session, target: target)
                case .accessoryInline:
                    if active {
                        Text("Zikr in progress") + Text(" · ") + Text(target, style: .timer)
                    } else {
                        Text("Zikr begins in") + Text(" ") + Text(target, style: .timer)
                    }
                default:
                    systemWidget(session: session, target: target)
                }
            } else if entry.snapshot == nil {
                WidgetEmptyStateView()
            } else {
                noSessionView
            }
        }
        .containerBackground(for: .widget) {
            WidgetPalette.background(for: colorScheme)
        }
        .widgetURL(URL(string: "darulirfan://zikr"))
    }

    private func systemWidget(session: WidgetZikrSession, target: Date) -> some View {
        HStack(spacing: 12) {
            Image("BrandEmblem")
                .resizable()
                .scaledToFit()
                .frame(width: family == .systemMedium ? 62 : 46, height: family == .systemMedium ? 62 : 46)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                statusText
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(active ? WidgetPalette.emeraldTone(for: colorScheme) : WidgetPalette.mutedTone(for: colorScheme))
                Text(session.title)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(WidgetPalette.textTone(for: colorScheme))
                    .lineLimit(2)
                Text(target, style: .timer)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(WidgetPalette.goldTone(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if active {
                    Text("until session ends")
                        .font(.caption2)
                        .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
                        .lineLimit(1)
                } else {
                    Text(target.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func circular(session: WidgetZikrSession, target: Date) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: active ? "dot.radiowaves.left.and.right" : "sparkles")
                    .font(.caption)
                Text(target, style: .timer)
                    .font(.system(.caption2, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            .padding(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(active ? "Zikr in progress" : session.title))
    }

    private func rectangular(session: WidgetZikrSession, target: Date) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label {
                statusText
            } icon: {
                Image(systemName: active ? "dot.radiowaves.left.and.right" : "sparkles")
            }
                .font(.headline)
                .lineLimit(1)
            Text(session.title).font(.caption).lineLimit(1)
            Text(target, style: .timer).font(.caption.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var noSessionView: some View {
        VStack(spacing: 4) {
            Image(systemName: "sparkles")
            Text("No zikr session scheduled")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var statusText: some View {
        if active {
            Text("Zikr in progress")
        } else {
            Text("Next Zikr")
        }
    }
}
