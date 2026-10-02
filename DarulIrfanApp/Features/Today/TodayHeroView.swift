import SwiftUI

/// Prayer, dates and personal progress, with the original Darul Irfan seal.
/// The hierarchy adapts to accessibility text sizes without shrinking labels.
struct TodayHeroView: View {
    let placeName: String?
    let timeZone: TimeZone
    let gregorian: String
    let hijri: String
    let nextPrayerName: String?
    let nextPrayerTime: Date?
    let completedPrayers: Int
    let prayerGoal: Int
    let streakDays: Int
    let completionRate: Double
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                HStack(alignment: .top, spacing: DISpacing.md) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DARUL IRFAN")
                            .font(.caption.weight(.bold)).tracking(2)
                            .foregroundStyle(DIColor.goldGlow)
                        Text(DIGradient.greeting(for: context.date, timeZone: timeZone))
                            .font(.title2.weight(.semibold)).foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        if let placeName {
                            Label(placeName, systemImage: "location.fill")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    DISealEmblem(diameter: dynamicTypeSize.isAccessibilitySize ? 44 : 64, glow: false)
                        .accessibilityHidden(true)
                }

                if let name = nextPrayerName, let time = nextPrayerTime {
                    VStack(alignment: .leading, spacing: DISpacing.sm) {
                        Text("Next prayer").font(.subheadline).foregroundStyle(.white.opacity(0.9))
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline) {
                                prayerName(name)
                                Spacer(minLength: DISpacing.md)
                                prayerTime(time)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                prayerName(name)
                                prayerTime(time)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        HStack(spacing: DISpacing.sm) {
                            Image(systemName: "hourglass").accessibilityHidden(true)
                            if scenePhase == .active && time > context.date {
                                Text(timerInterval: context.date...time, countsDown: true)
                                    .monospacedDigit().fixedSize()
                            } else {
                                Text("Prayer time").fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .font(.headline).foregroundStyle(DIColor.goldGlow)
                        // VoiceOver reads the stable prayer/time pair; a changing
                        // second counter otherwise interrupts navigation.
                        .accessibilityHidden(true)
                    }
                    .padding(DISpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                } else {
                    Label("Set your location to see prayer times", systemImage: "location.circle")
                        .font(.body).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(gregorian, systemImage: "calendar")
                    Label(hijri, systemImage: "moon")
                }
                .font(.subheadline).foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

                Rectangle().fill(.white.opacity(0.2)).frame(height: 1).accessibilityHidden(true)
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: DISpacing.md))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: DISpacing.md))
                layout {
                    metric("\(completedPrayers)/\(prayerGoal)", label: "Prayers today", icon: "checkmark.circle")
                    metric("\(streakDays)", label: "Day streak", icon: "flame")
                    metric("\(Int((min(max(completionRate.isFinite ? completionRate : 0, 0), 1) * 100).rounded()))%", label: "Last 30 days", icon: "chart.bar")
                }

                Text(DIBrand.anchorVerseArabic)
                    .font(DIFont.quranArabic(scale: 0.72)).foregroundStyle(.white)
                    .environment(\.layoutDirection, .rightToLeft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DISpacing.lg)
            .background(DIGradient.hero(for: context.date, timeZone: timeZone))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    private func prayerName(_ name: String) -> some View {
        Text(name).font(.largeTitle.weight(.semibold))
            .foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
    }

    private func prayerTime(_ time: Date) -> some View {
        Text(time, style: .time).environment(\.timeZone, timeZone)
            .font(.title2.weight(.medium).monospacedDigit()).foregroundStyle(.white)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func metric(_ value: String, label: LocalizedStringKey, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(value, systemImage: icon).font(.headline).foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
