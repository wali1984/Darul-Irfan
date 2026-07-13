import SwiftUI

/// Companion hub, linked from the More tab: 99 Names of Allah, Duas,
/// notable Islamic days, and the tasbih counter — presented as a living
/// gradient hero over gilded gateway cards.
@MainActor
struct CompanionHomeView: View {
    private let dependencies: AppDependencies
    private let appState: AppState

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DISpacing.md) {
                CompanionHeroHeader()
                    .diAppear()

                NavigationLink {
                    NamesOfAllahView()
                } label: {
                    CompanionHubCard(
                        systemImage: "sparkles",
                        titleKey: "99 Names of Allah",
                        subtitleKey: "Asma-ul-Husna, with transliteration and meaning",
                        tint: DIColor.primary
                    )
                }
                .buttonStyle(DIPressableStyle())
                .diAppear(delay: 0.05)

                NavigationLink {
                    DuasView()
                } label: {
                    CompanionHubCard(
                        systemImage: "hands.sparkles",
                        titleKey: "Duas",
                        subtitleKey: "Supplications from the Quran, with sources",
                        tint: DIColor.accent
                    )
                }
                .buttonStyle(DIPressableStyle())
                .diAppear(delay: 0.1)

                NavigationLink {
                    IslamicDaysView(hijri: dependencies.hijri, appState: appState)
                } label: {
                    CompanionHubCard(
                        systemImage: "moon.stars",
                        titleKey: "Islamic Days",
                        subtitleKey: "Notable days of the Hijri year, with approximate dates",
                        tint: DIColor.primary
                    )
                }
                .buttonStyle(DIPressableStyle())
                .diAppear(delay: 0.15)

                NavigationLink {
                    TasbihListView(trackerRepository: dependencies.trackerRepository)
                } label: {
                    CompanionHubCard(
                        systemImage: "hand.tap",
                        titleKey: "Tasbih Counter",
                        subtitleKey: "Count your personal zikr and keep a gentle daily habit",
                        tint: DIColor.accent
                    )
                }
                .buttonStyle(DIPressableStyle())
                .diAppear(delay: 0.2)
            }
            .padding(DISpacing.md)
        }
        .navigationTitle("Companion")
        .diScreenBackground()
    }
}

// MARK: - Hero

private struct CompanionHeroHeader: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            DIGradient.hero()
                .overlay(alignment: .topTrailing) {
                    DIOctagram(innerRatio: 0.5)
                        .stroke(Color.white, lineWidth: 1.5)
                        .frame(width: 240, height: 240)
                        .opacity(0.06)
                        .offset(x: 60, y: -60)
                }

            HStack(alignment: .center, spacing: DISpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Companion")
                        .font(DIFont.heading)
                        .foregroundStyle(.white)
                    Text("Names, duas, and sacred days for the heart")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                DISealEmblem(diameter: 56, glow: true)
                    .diBreathingGlow(color: DIColor.goldGlow, maxRadius: 16)
            }
            .padding(DISpacing.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg + 6, style: .continuous))
        .shadow(color: DIColor.primaryDeep.opacity(0.35), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Hub card

private struct CompanionHubCard: View {
    let systemImage: String
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey
    var tint: Color = DIColor.primary

    var body: some View {
        DIElevatedCard {
            HStack(spacing: DISpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 46, height: 46)
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(tint)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text(titleKey)
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                    Text(subtitleKey)
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
