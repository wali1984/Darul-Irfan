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

    private var progress: Double {
        guard let nextPrayerTime, !dayTimes.isEmpty else { return 0 }
        let now = Date()
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
                    DILivingSealMark(diameter: 60)
                }

                if let name = nextPrayerName, let time = nextPrayerTime {
                    PrayerCountdownRing(progress: progress, prayerName: name, target: time)
                        .padding(.vertical, DISpacing.xs)
                } else {
                    fallbackCrest
                }

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
