import SwiftUI

/// Settings root: links to every settings subscreen with a glance at the
/// current value where helpful.
@MainActor
struct SettingsHomeView: View {
    private let dependencies: AppDependencies
    private let appState: AppState

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
    }

    var body: some View {
        List {
            prayerSection
            displaySection
            contentSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Settings")
    }

    // MARK: - Sections

    private var prayerSection: some View {
        Section {
            NavigationLink {
                LocationSettingsView(dependencies: dependencies, appState: appState)
            } label: {
                SettingsHomeRow(
                    titleKey: "Location",
                    systemImage: "location.fill",
                    value: locationValue
                )
            }
            .listRowBackground(DIColor.surface)

            NavigationLink {
                CalculationSettingsView(appState: appState)
            } label: {
                SettingsHomeRow(
                    titleKey: "Calculation",
                    systemImage: "sun.and.horizon.fill",
                    value: Text(LocalizedStringKey(appState.settings.calculation.method.englishName))
                )
            }
            .listRowBackground(DIColor.surface)

            NavigationLink {
                NotificationSettingsView(dependencies: dependencies, appState: appState)
            } label: {
                SettingsHomeRow(
                    titleKey: "Notifications",
                    systemImage: "bell.fill",
                    value: Text("\(enabledAlertCount) on")
                )
            }
            .listRowBackground(DIColor.surface)
        } header: {
            Text("Prayer Setup")
        }
    }

    private var displaySection: some View {
        Section {
            NavigationLink {
                AppearanceSettingsView(appState: appState)
            } label: {
                SettingsHomeRow(
                    titleKey: "Appearance",
                    systemImage: "paintbrush.fill",
                    value: nil
                )
            }
            .listRowBackground(DIColor.surface)

            NavigationLink {
                HijriSettingsView(dependencies: dependencies, appState: appState)
            } label: {
                SettingsHomeRow(
                    titleKey: "Hijri Calendar",
                    systemImage: "moon.stars.fill",
                    value: hijriValue
                )
            }
            .listRowBackground(DIColor.surface)
        } header: {
            Text("Display")
        }
    }

    private var contentSection: some View {
        Section {
            NavigationLink {
                ContentStorageSettingsView(dependencies: dependencies, appState: appState)
            } label: {
                SettingsHomeRow(
                    titleKey: "Content & Storage",
                    systemImage: "internaldrive.fill",
                    value: nil
                )
            }
            .listRowBackground(DIColor.surface)

            NavigationLink {
                PrivacySettingsView()
            } label: {
                SettingsHomeRow(
                    titleKey: "Privacy",
                    systemImage: "hand.raised.fill",
                    value: nil
                )
            }
            .listRowBackground(DIColor.surface)
        } header: {
            Text("Content & Privacy")
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

// MARK: - Row

private struct SettingsHomeRow: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    let value: Text?

    var body: some View {
        HStack(spacing: DISpacing.md) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(DIColor.onPrimary)
                .frame(width: 30, height: 30)
                .background(DIColor.primary)
                .clipShape(RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous))
                .accessibilityHidden(true)

            Text(titleKey)
                .foregroundStyle(DIColor.textPrimary)

            Spacer(minLength: DISpacing.sm)

            if let value {
                value
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, DISpacing.xs)
    }
}
