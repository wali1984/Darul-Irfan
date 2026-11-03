import SwiftUI
import WidgetKit

// "Ayah of the Day": the ayah Today shows, as the app wrote it for each day
// (the mushaf's Arabic, the Silsila's translation, the full reference), with
// the next prayer at its foot. Medium and large. It turns over at the
// phone's midnight, as Today does.

struct AyahOfTheDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerOverviewEntry {
        PrayerOverviewEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PrayerOverviewEntry) -> Void) {
        completion(PrayerOverviewEntry(date: Date(), snapshot: PrayerWidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerOverviewEntry>) -> Void) {
        completion(PrayerTimelines.timeline { PrayerOverviewEntry(date: $0, snapshot: $1) })
    }
}

struct AyahOfTheDayWidget: Widget {
    let kind: String = "us.naqshbaniaowaisiah.ayahoftheday"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AyahOfTheDayProvider()) { entry in
            AyahOfTheDayWidgetView(entry: entry)
        }
        .configurationDisplayName("Ayah of the Day")
        .description("Today's ayah with the Silsila's translation.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct AyahOfTheDayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    let entry: PrayerOverviewEntry

    private var ayah: WidgetDailyAyah? { entry.snapshot?.dailyAyah(on: entry.date) }

    var body: some View {
        VStack(spacing: family == .systemLarge ? 10 : 6) {
            HStack(spacing: 6) {
                WidgetSeal(size: family == .systemLarge ? 30 : 22)
                Text("Ayah of the Day")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.emeraldTone(for: colorScheme))
                    .widgetAccentable()
                Spacer(minLength: 4)
                if let snapshot = entry.snapshot {
                    Text(verbatim: snapshot.hijriText(on: entry.date))
                        .font(.system(.caption2, design: .serif))
                        .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            if let ayah {
                WidgetAyahBlock(
                    ayah: ayah,
                    arabicSize: family == .systemLarge ? 24 : 18,
                    translationLines: family == .systemLarge ? 8 : 3
                )
                .frame(maxHeight: .infinity)
            } else {
                Text("Open Darul Irfan to load today's ayah.")
                    .font(.footnote)
                    .foregroundStyle(WidgetPalette.textTone(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if family == .systemLarge, let snapshot = entry.snapshot, let next = entry.nextPrayer {
                HStack(spacing: 6) {
                    Text("Next Prayer")
                        .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
                    Text(next.displayName)
                        .foregroundStyle(WidgetPalette.emeraldTone(for: colorScheme))
                    Text(next.time, style: .time)
                        .foregroundStyle(WidgetPalette.textTone(for: colorScheme))
                    Spacer(minLength: 4)
                    WidgetCountdown(interval: snapshot.countdownInterval(to: next, at: entry.date))
                        .foregroundStyle(WidgetPalette.goldTone(for: colorScheme))
                        .frame(maxWidth: 80, alignment: .trailing)
                        .widgetAccentable()
                }
                .font(.caption)
                .lineLimit(1)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .widgetPlace(entry.snapshot)
        .containerBackground(for: .widget) {
            WidgetPalette.background(for: colorScheme)
        }
        .widgetURL(ayah?.link ?? URL(string: "darulirfan://today"))
    }
}

// MARK: - Silsila Seal (Lock Screen)

struct SilsilaSealEntry: TimelineEntry {
    let date: Date
}

struct SilsilaSealProvider: TimelineProvider {
    func placeholder(in context: Context) -> SilsilaSealEntry { SilsilaSealEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (SilsilaSealEntry) -> Void) {
        completion(SilsilaSealEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SilsilaSealEntry>) -> Void) {
        // The seal never changes: one entry, no reloads.
        completion(Timeline(entries: [SilsilaSealEntry(date: Date())], policy: .never))
    }
}

/// The Silsila's seal on the Lock Screen (circular) and in StandBy or on the
/// Home Screen (small). Tapping it opens Today.
struct SilsilaSealWidget: Widget {
    let kind: String = "us.naqshbaniaowaisiah.seal"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SilsilaSealProvider()) { _ in
            SilsilaSealWidgetView()
        }
        .configurationDisplayName("Silsila Seal")
        .description("The Silsila's seal, for your Lock Screen or Home Screen.")
        .supportedFamilies([.accessoryCircular, .systemSmall])
    }
}

private struct SilsilaSealWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    WidgetSeal(size: 50)
                }
            } else {
                VStack(spacing: 8) {
                    WidgetSeal(size: 96)
                        .shadow(color: WidgetPalette.goldTone(for: colorScheme).opacity(0.45), radius: 10)
                    Text("Darul Irfan")
                        .font(.system(.footnote, design: .serif).weight(.bold))
                        .foregroundStyle(WidgetPalette.goldTone(for: colorScheme))
                        .widgetAccentable()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Darul Irfan"))
        .containerBackground(for: .widget) {
            WidgetPalette.background(for: colorScheme)
        }
        .widgetURL(URL(string: "darulirfan://today"))
    }
}
