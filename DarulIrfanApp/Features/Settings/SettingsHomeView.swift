import SwiftUI

/// Settings root: a branded hub linking to every settings subscreen with a
/// glance at the current value where helpful. Elevated to match the app's
/// living design language — a slim brand banner and premium card rows grouped
/// by intent, each with a gold-rimmed emerald medallion, spring press, a soft
/// haptic and a staggered appear.
@MainActor
struct SettingsHomeView: View {
    private let dependencies: AppDependencies
    private let appState: AppState

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                SettingsBrandBanner(
                    titleKey: "Darul Irfan",
                    subtitleKey: "Prayer, display, content and privacy"
                )
                .diAppear()

                prayerSection
                displaySection
                contentSection
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .navigationTitle("Settings")
    }

    // MARK: - Sections

    private var prayerSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Prayer Setup", systemImage: "sun.max")
                .diAppear(delay: 0.05)

            SettingsNavLink(
                titleKey: "Location",
                systemImage: "location.fill",
                value: locationValue,
                delay: 0.10
            ) {
                LocationSettingsView(dependencies: dependencies, appState: appState)
            }

            SettingsNavLink(
                titleKey: "Calculation",
                systemImage: "sun.and.horizon.fill",
                value: Text(LocalizedStringKey(appState.settings.calculation.method.englishName)),
                delay: 0.16
            ) {
                CalculationSettingsView(appState: appState)
            }

            SettingsNavLink(
                titleKey: "Notifications",
                systemImage: "bell.fill",
                value: Text("\(enabledAlertCount) on"),
                delay: 0.22
            ) {
                NotificationSettingsView(dependencies: dependencies, appState: appState)
            }
        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Display", systemImage: "paintpalette")
                .diAppear(delay: 0.28)

            SettingsNavLink(
                titleKey: "Appearance",
                systemImage: "paintbrush.fill",
                value: nil,
                delay: 0.34
            ) {
                AppearanceSettingsView(appState: appState)
            }

            SettingsNavLink(
                titleKey: "Hijri Calendar",
                systemImage: "moon.stars.fill",
                value: hijriValue,
                accent: true,
                delay: 0.40
            ) {
                HijriSettingsView(dependencies: dependencies, appState: appState)
            }
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Content & Privacy", systemImage: "hand.raised")
                .diAppear(delay: 0.46)

            SettingsNavLink(
                titleKey: "Content & Storage",
                systemImage: "internaldrive.fill",
                value: nil,
                delay: 0.52
            ) {
                ContentStorageSettingsView(dependencies: dependencies, appState: appState)
            }

            SettingsNavLink(
                titleKey: "Privacy",
                systemImage: "hand.raised.fill",
                value: nil,
                delay: 0.58
            ) {
                PrivacySettingsView()
            }
        }
    }

    // MARK: - Value summaries

    private var locationValue: Text {
        if let place = appState.activePlace {
            return Text(place.name)
        }
        return Text("Not set")
    }

    private var enabledAlertCount: Int {
        Prayer.allCases.filter { prayer in
            appState.settings.prayerNotifications.style(for: prayer) != .off
        }.count
    }

    private var hijriValue: Text {
        let offset = appState.settings.hijri.dayOffset
        if offset == 0 {
            return Text("No offset")
        }
        let value = offset.formatted(.number.sign(strategy: .always(includingZero: false)))
        if abs(offset) == 1 {
            return Text("\(value) day")
        }
        return Text("\(value) days")
    }
}

// MARK: - Navigation card row

/// A premium settings row: a gold-rimmed medallion icon, a title, an optional
/// current-value glance, inside an elevated card with spring press, a soft
/// haptic, and a staggered appear.
private struct SettingsNavLink<Destination: View>: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    let value: Text?
    /// Uses the gold gradient medallion instead of emerald.
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
                    Text(titleKey)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DIColor.textPrimary)
                    Spacer(minLength: DISpacing.sm)
                    if let value {
                        value
                            .font(.subheadline)
                            .foregroundStyle(DIColor.textMuted)
                            .lineLimit(1)
                    }
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
                .font(.callout.weight(.semibold))
                .foregroundStyle(accent ? DIColor.primaryDeep : Color.white)
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}
