import SwiftUI

/// Companion hub, linked from the More tab: 99 Names of Allah, Duas,
/// notable Islamic days, and the tasbih counter.
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
                NavigationLink {
                    NamesOfAllahView()
                } label: {
                    CompanionHubCard(
                        systemImage: "sparkles",
                        titleKey: "99 Names of Allah",
                        subtitleKey: "Asma-ul-Husna, with transliteration and meaning"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    DuasView()
                } label: {
                    CompanionHubCard(
                        systemImage: "hands.sparkles",
                        titleKey: "Duas",
                        subtitleKey: "Supplications from the Quran, with sources"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    IslamicDaysView(hijri: dependencies.hijri, appState: appState)
                } label: {
                    CompanionHubCard(
                        systemImage: "moon.stars",
                        titleKey: "Islamic Days",
                        subtitleKey: "Notable days of the Hijri year, with approximate dates"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TasbihListView(trackerRepository: dependencies.trackerRepository)
                } label: {
                    CompanionHubCard(
                        systemImage: "hand.tap",
                        titleKey: "Tasbih Counter",
                        subtitleKey: "Count your personal zikr and keep a gentle daily habit"
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(DISpacing.md)
        }
        .navigationTitle("Companion")
        .diScreenBackground()
    }
}

// MARK: - Hub card

private struct CompanionHubCard: View {
    let systemImage: String
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey

    var body: some View {
        DICard {
            HStack(spacing: DISpacing.md) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(DIColor.primary)
                    .frame(width: 36, height: 36)
                    .background(DIColor.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous))
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
