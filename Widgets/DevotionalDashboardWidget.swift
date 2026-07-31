import AppIntents
import SwiftUI
import WidgetKit

enum DevotionalWidgetFocus: String, AppEnum {
    case overview
    case prayer
    case quran
    case zikr

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Dashboard focus"
    static var caseDisplayRepresentations: [DevotionalWidgetFocus: DisplayRepresentation] = [
        .overview: "Overview",
        .prayer: "Prayer",
        .quran: "Quran",
        .zikr: "Zikr & Tasbih"
    ]
}

struct DevotionalDashboardIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Devotional Dashboard"
    static var description = IntentDescription("Choose the devotional activity highlighted by the widget.")

    @Parameter(title: "Focus", default: .overview)
    var focus: DevotionalWidgetFocus
}

struct DevotionalDashboardEntry: TimelineEntry {
    let date: Date
    let snapshot: PrayerWidgetSnapshot?
    let configuration: DevotionalDashboardIntent

    var relevance: TimelineEntryRelevance? {
        guard let snapshot else { return nil }
        if snapshot.currentOrNextZikr(at: date)?.isActive(at: date) == true {
            return TimelineEntryRelevance(score: 100, duration: 30 * 60)
        }
        if let next = snapshot.nextPrayer(after: date), next.time.timeIntervalSince(date) <= 60 * 60 {
            return TimelineEntryRelevance(score: 80, duration: 60 * 60)
        }
        return TimelineEntryRelevance(score: 20, duration: 60 * 60)
    }
}

struct DevotionalDashboardProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DevotionalDashboardEntry {
        DevotionalDashboardEntry(
            date: Date(),
            snapshot: PrayerWidgetSnapshot.sample(),
            configuration: DevotionalDashboardIntent()
        )
    }

    func snapshot(
        for configuration: DevotionalDashboardIntent,
        in context: Context
    ) async -> DevotionalDashboardEntry {
        DevotionalDashboardEntry(
            date: Date(),
            snapshot: context.isPreview ? PrayerWidgetSnapshot.sample() : PrayerWidgetSnapshot.load(),
            configuration: configuration
        )
    }

    func timeline(
        for configuration: DevotionalDashboardIntent,
        in context: Context
    ) async -> Timeline<DevotionalDashboardEntry> {
        let now = Date()
        let snapshot = PrayerWidgetSnapshot.load()
        var dates = [now]
        if let nextPrayer = snapshot?.nextPrayer(after: now) { dates.append(nextPrayer.time) }
        if let zikr = snapshot?.currentOrNextZikr(at: now) {
            if zikr.startsAt > now { dates.append(zikr.startsAt) }
            dates.append(zikr.endsAt)
        }
        let entries = Array(Set(dates)).sorted().map {
            DevotionalDashboardEntry(date: $0, snapshot: snapshot, configuration: configuration)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60)))
    }
}

struct DevotionalDashboardWidget: Widget {
    let kind = "us.naqshbaniaowaisiah.devotionaldashboard"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: DevotionalDashboardIntent.self,
            provider: DevotionalDashboardProvider()
        ) { entry in
            DevotionalDashboardWidgetView(entry: entry)
        }
        .configurationDisplayName("Devotional Dashboard")
        .description("Prayer, Quran and zikr progress in one configurable widget.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct DevotionalDashboardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: DevotionalDashboardEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let metrics = snapshot.devotionalMetrics {
                switch family {
                case .accessoryRectangular:
                    accessoryView(snapshot: snapshot, metrics: metrics)
                case .systemMedium:
                    mediumView(snapshot: snapshot, metrics: metrics)
                default:
                    focusedView(snapshot: snapshot, metrics: metrics)
                }
            } else {
                WidgetEmptyStateView()
            }
        }
        .containerBackground(for: .widget) {
            WidgetPalette.background(for: colorScheme)
        }
        .widgetURL(widgetURL)
    }

    private func mediumView(
        snapshot: PrayerWidgetSnapshot,
        metrics: WidgetDevotionalMetrics
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image("BrandEmblem")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Devotional Dashboard")
                        .font(.headline)
                        .foregroundStyle(WidgetPalette.emeraldTone(for: colorScheme))
                    Text(snapshot.hijriDateText)
                        .font(.caption2)
                        .foregroundStyle(WidgetPalette.mutedTone(for: colorScheme))
                }
                Spacer()
                if let next = snapshot.nextPrayer(after: entry.date) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(next.displayName).font(.caption.weight(.semibold))
                        Text(next.time, style: .timer).font(.caption2.monospacedDigit())
                    }
                }
            }
            HStack(spacing: 8) {
                metricTile("Prayers", value: "\(metrics.prayersCompleted)/\(metrics.prayerGoal)", progress: prayerProgress(metrics), icon: "checkmark")
                metricTile("30-day", value: "\(Int((metrics.prayerCompletionRate * 100).rounded()))%", progress: metrics.prayerCompletionRate, icon: "chart.line.uptrend.xyaxis")
                metricTile("Quran", value: quranValue(metrics), progress: quranProgress(metrics), icon: "book.fill")
                metricTile("Zikr", value: zikrValue(metrics), progress: tasbihProgress(metrics), icon: "sparkles")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func focusedView(
        snapshot: PrayerWidgetSnapshot,
        metrics: WidgetDevotionalMetrics
    ) -> some View {
        VStack(spacing: 8) {
            Image("BrandEmblem")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
            switch entry.configuration.focus {
            case .overview, .prayer:
                focusMetric("Prayers", value: "\(metrics.prayersCompleted)/\(metrics.prayerGoal)", progress: prayerProgress(metrics))
                (Text(verbatim: "\(metrics.prayerStreakDays)") + Text(" day streak")).font(.caption2)
            case .quran:
                focusMetric("Quran", value: quranValue(metrics), progress: quranProgress(metrics))
                Text("Continue reading").font(.caption2)
            case .zikr:
                focusMetric("Zikr & Tasbih", value: zikrValue(metrics), progress: tasbihProgress(metrics))
                Text(metrics.tasbihTitle ?? "Daily zikr").font(.caption2).lineLimit(1)
            }
        }
        .foregroundStyle(WidgetPalette.textTone(for: colorScheme))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func accessoryView(
        snapshot: PrayerWidgetSnapshot,
        metrics: WidgetDevotionalMetrics
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            switch entry.configuration.focus {
            case .overview, .prayer:
                Label("Prayer progress", systemImage: "checkmark.circle")
                Text(verbatim: "\(metrics.prayersCompleted)/\(metrics.prayerGoal) · \(metrics.prayerStreakDays)") + Text(" day streak")
            case .quran:
                Label("Continue Quran", systemImage: "book.fill")
                Text(quranLongValue(metrics))
            case .zikr:
                Label("Zikr & Tasbih", systemImage: "sparkles")
                Text(verbatim: "\(zikrValue(metrics)) · \(metrics.zikrCompletionsToday)") + Text(" completed today")
            }
        }
        .font(.caption)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func metricTile(
        _ title: LocalizedStringKey,
        value: String,
        progress: Double,
        icon: String
    ) -> some View {
        VStack(spacing: 3) {
            metricRing(progress: progress, icon: icon, diameter: 31)
            Text(verbatim: value).font(.caption2.weight(.bold).monospacedDigit())
            Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    private func focusMetric(
        _ title: LocalizedStringKey,
        value: String,
        progress: Double
    ) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption.weight(.semibold))
            Text(verbatim: value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(WidgetPalette.goldTone(for: colorScheme))
            ProgressView(value: min(max(progress, 0), 1))
                .tint(WidgetPalette.emeraldTone(for: colorScheme))
        }
    }

    private func metricRing(progress: Double, icon: String, diameter: CGFloat) -> some View {
        ZStack {
            Circle().stroke(WidgetPalette.mutedTone(for: colorScheme).opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(WidgetPalette.goldTone(for: colorScheme), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
        }
        .frame(width: diameter, height: diameter)
    }

    private func prayerProgress(_ metrics: WidgetDevotionalMetrics) -> Double {
        guard metrics.prayerGoal > 0 else { return 0 }
        return Double(metrics.prayersCompleted) / Double(metrics.prayerGoal)
    }

    private func quranValue(_ metrics: WidgetDevotionalMetrics) -> String {
        guard let surah = metrics.quranSurahNumber, let ayah = metrics.quranAyahNumber else { return "—" }
        return "\(surah):\(ayah)"
    }

    private func quranLongValue(_ metrics: WidgetDevotionalMetrics) -> String {
        guard let surah = metrics.quranSurahNumber, let ayah = metrics.quranAyahNumber else { return String(localized: "Open Quran to begin") }
        return "\(String(localized: "Surah")) \(surah) · \(String(localized: "Ayah")) \(ayah)"
    }

    private func quranProgress(_ metrics: WidgetDevotionalMetrics) -> Double {
        guard let surah = metrics.quranSurahNumber else { return 0 }
        return min(max(Double(surah) / 114.0, 0), 1)
    }

    private func zikrValue(_ metrics: WidgetDevotionalMetrics) -> String {
        if let target = metrics.tasbihTarget, target > 0 {
            return "\(metrics.tasbihCount)/\(target)"
        }
        return metrics.tasbihCount.formatted()
    }

    private func tasbihProgress(_ metrics: WidgetDevotionalMetrics) -> Double {
        guard let target = metrics.tasbihTarget, target > 0 else {
            return metrics.zikrCompletionsToday > 0 ? 1 : 0
        }
        return min(max(Double(metrics.tasbihCount) / Double(target), 0), 1)
    }

    private var widgetURL: URL? {
        switch entry.configuration.focus {
        case .overview, .prayer: return URL(string: "darulirfan://today")
        case .quran: return URL(string: "darulirfan://quran")
        case .zikr: return URL(string: "darulirfan://zikr")
        }
    }
}
