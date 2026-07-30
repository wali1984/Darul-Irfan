import SwiftUI

/// The living home hero: a time-of-day gradient with a glowing seal, the
/// animated next-prayer countdown ring, dates, and the anchor verse. The
/// centerpiece that makes the app feel alive and premium.
struct TodayHeroView: View {
    let placeName: String?
    let gregorian: String
    let hijri: String
    let nextPrayerName: String?
    let nextPrayerTime: Date?
    /// Today's prayer instants (for computing ring progress).
    let dayTimes: [Date]
    let completedPrayers: Int
    let prayerGoal: Int
    let streakDays: Int
    let completionRate: Double

    private func progress(at now: Date) -> Double {
        guard let nextPrayerTime, !dayTimes.isEmpty else { return 0 }
        let sorted = dayTimes.sorted()
        let prev = sorted.last(where: { $0 <= now }) ?? sorted.first ?? now
        let total = nextPrayerTime.timeIntervalSince(prev)
        guard total > 0 else { return 0 }
        return now.timeIntervalSince(prev) / total
    }

    var body: some View {
        ZStack {
            DIGradient.hero()
            DIPatternTexture(tint: .white, opacity: 0.07)
            DIOctagram(innerRatio: 0.5)
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 300, height: 300)
                .opacity(0.06)
                .offset(x: 90, y: -70)

            VStack(spacing: DISpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DIGradient.greeting())
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                        if let placeName {
                            HStack(spacing: DISpacing.xs) {
                                Image(systemName: "location.fill").font(.caption2)
                                Text(placeName).font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                        }
                    }
                    Spacer()
                    DILivingSealMark(diameter: 66)
                }

                if let name = nextPrayerName, let time = nextPrayerTime {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        PrayerCountdownRing(
                            progress: progress(at: context.date),
                            prayerName: name,
                            target: time
                        )
                    }
                    .padding(.vertical, DISpacing.xs)
                } else {
                    fallbackCrest
                }

                devotionalMetrics

                HStack(spacing: DISpacing.md) {
                    dateChip(icon: "calendar", text: gregorian)
                    dateChip(icon: "moon", text: hijri)
                }

                Text(DIBrand.anchorVerseArabic)
                    .font(DIFont.quranArabic(scale: 0.72))
                    .foregroundStyle(.white)
                    .diGoldGlow(radius: 12, opacity: 0.5)
                    .environment(\.layoutDirection, .rightToLeft)
                    .multilineTextAlignment(.center)
                    .padding(.top, DISpacing.xs)
            }
            .padding(DISpacing.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg + 6, style: .continuous))
        .shadow(color: DIColor.primaryDeep.opacity(0.35), radius: 18, x: 0, y: 10)
    }

    private var devotionalMetrics: some View {
        HStack(spacing: DISpacing.sm) {
            homeMetric(
                icon: "checkmark",
                value: "\(completedPrayers)/\(prayerGoal)",
                label: "Prayers",
                progress: prayerGoal > 0 ? Double(completedPrayers) / Double(prayerGoal) : 0
            )
            homeMetric(
                icon: "flame.fill",
                value: "\(streakDays)",
                label: "Day streak",
                progress: min(Double(streakDays) / 7.0, 1)
            )
            homeMetric(
                icon: "chart.line.uptrend.xyaxis",
                value: "\(Int((min(max(completionRate, 0), 1) * 100).rounded()))%",
                label: "30-day",
                progress: completionRate
            )
        }
        .accessibilityElement(children: .contain)
    }

    private func homeMetric(
        icon: String,
        value: String,
        label: LocalizedStringKey,
        progress: Double
    ) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.16), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(DIColor.goldGlow, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)
            Text(verbatim: value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.09)))
        .accessibilityElement(children: .combine)
    }

    private var fallbackCrest: some View {
        VStack(spacing: DISpacing.sm) {
            DILivingSealMark(diameter: 92)
            Text("Set your location to see prayer times")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.vertical, DISpacing.sm)
    }

    private func dateChip(icon: String, text: String) -> some View {
        HStack(spacing: DISpacing.xs) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, DISpacing.sm)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.14)))
    }
}
