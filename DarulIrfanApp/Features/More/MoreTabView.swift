import SwiftUI

/// Root of the "More" tab: a branded hub that hosts Zikr, Events &
/// Dar-ul-Irfan, Qibla, the daily Companion, Settings, and About, plus the
/// global search sheet. Owns its own NavigationStack per the app navigation
/// contract. Elevated to match the living "Today" language: a gradient brand
/// header with a breathing seal, and premium card rows grouped by intent.
@MainActor
struct MoreTabView: View {
    private let dependencies: AppDependencies
    private let appState: AppState

    @State private var isSearchPresented = false

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DISpacing.lg) {
                    MoreBrandHeader()
                        .diAppear()

                    exploreSection
                    spiritualSection
                    settingsSection
                }
                .padding(DISpacing.md)
            }
            .diScreenBackground()
            .navigationTitle("More")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSearchPresented = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search")
                }
            }
            .sheet(isPresented: $isSearchPresented) {
                GlobalSearchView(dependencies: dependencies)
            }
        }
    }

    // MARK: - Sections

    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Explore", systemImage: "safari")
                .diAppear(delay: 0.05)

            MoreNavLink(
                titleKey: "Daily Companion",
                subtitleKey: "99 Names, duas, Islamic days and tasbih",
                systemImage: "heart.text.square.fill",
                delay: 0.10
            ) {
                CompanionHomeView(dependencies: dependencies, appState: appState)
            }

            MoreNavLink(
                titleKey: "Events & Dar-ul-Irfan",
                subtitleKey: "Ijtema dates, announcements and directions",
                systemImage: "calendar",
                delay: 0.16
            ) {
                EventsHomeView(dependencies: dependencies, appState: appState)
            }
        }
    }

    private var spiritualSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Spiritual", systemImage: "moon.stars")
                .diAppear(delay: 0.22)

            MoreNavLink(
                titleKey: "Zikr",
                subtitleKey: "Method of Zikr and online sessions",
                systemImage: "sparkles",
                delay: 0.28
            ) {
                ZikrHomeView(dependencies: dependencies, appState: appState)
            }

            MoreNavLink(
                titleKey: "Qibla Compass",
                subtitleKey: "Direction to the Kaaba",
                systemImage: "location.north.circle.fill",
                accent: true,
                delay: 0.34
            ) {
                QiblaCompassView(dependencies: dependencies, appState: appState)
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Settings", systemImage: "gearshape")
                .diAppear(delay: 0.40)

            MoreNavLink(
                titleKey: "Settings",
                subtitleKey: "Prayer setup, appearance and storage",
                systemImage: "gearshape.fill",
                delay: 0.46
            ) {
                SettingsHomeView(dependencies: dependencies, appState: appState)
            }

            MoreNavLink(
                titleKey: "About",
                subtitleKey: "Darul Irfan and Silsila Naqshbandia Owaisiah",
                systemImage: "info.circle.fill",
                delay: 0.52
            ) {
                AboutView()
            }
        }
    }
}

// MARK: - Brand header

/// The living brand crest for the hub: an emerald gradient panel with a faint
/// octagram watermark, the breathing silsila seal, wordmark and tagline.
private struct MoreBrandHeader: View {
    var body: some View {
        ZStack {
            DIGradient.emerald
            DIOctagram(innerRatio: 0.5)
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 260, height: 260)
                .opacity(0.06)
                .offset(x: 96, y: -66)
                .accessibilityHidden(true)

            VStack(spacing: DISpacing.sm) {
                DISealEmblem(diameter: 76, glow: true)
                    .diBreathingGlow(color: DIColor.goldGlow, maxRadius: 18)

                Text(verbatim: DIBrand.wordmark)
                    .font(DIFont.heading)
                    .foregroundStyle(.white)

                Text(verbatim: DIBrand.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, DISpacing.lg)
            .padding(.horizontal, DISpacing.md)
            .frame(maxWidth: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg + 6, style: .continuous))
        .shadow(color: DIColor.primaryDeep.opacity(0.35), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(DIBrand.wordmark). \(DIBrand.tagline)"))
    }
}

// MARK: - Navigation card row

/// A premium hub row: a gold-rimmed emerald medallion icon, title and
/// subtitle inside an elevated card, with spring press feedback, a soft haptic
/// on tap, and a staggered appear.
private struct MoreNavLink<Destination: View>: View {
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey
    let systemImage: String
    /// Uses the gold gradient medallion instead of emerald (for tool-like rows).
    var accent: Bool = false
    var delay: Double = 0
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            DIElevatedCard {
                HStack(spacing: DISpacing.md) {
                    medallion
                    VStack(alignment: .leading, spacing: 2) {
                        Text(titleKey)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DIColor.textPrimary)
                        Text(subtitleKey)
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                    }
                    Spacer(minLength: DISpacing.sm)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DIColor.textMuted)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(DIPressableStyle())
        .simultaneousGesture(TapGesture().onEnded { DIHaptics.soft() })
        .diAppear(delay: delay)
    }

    private var medallion: some View {
        ZStack {
            Circle()
                .fill(accent ? DIGradient.goldSheen : DIGradient.emerald)
            Circle()
                .strokeBorder(DIColor.accent.opacity(0.5), lineWidth: 1)
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(accent ? DIColor.primaryDeep : Color.white)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}
