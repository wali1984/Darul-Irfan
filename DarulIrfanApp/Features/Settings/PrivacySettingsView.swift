import SwiftUI

/// Privacy: the choices that stayed with privacy when "Official Alerts &
/// Privacy" and "Privacy" became one screen (the next-prayer Live Activity
/// and sharing diagnostics; the official alerts moved to Notifications),
/// then a summary reflecting the user's current opt-in service choices.
@MainActor
struct PrivacySettingsView: View {
    let appState: AppState
    /// Tells the platform service the diagnostics choice; Settings passes it.
    var dependencies: AppDependencies? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                SettingsBrandBanner(
                    titleKey: "Privacy",
                    subtitleKey: "On-device by design"
                )
                .diAppear()

                PrivacyChoicesCard(appState: appState, dependencies: dependencies)
                    .diAppear(delay: 0.03)

                PrivacyCard(
                    systemImage: "location.fill",
                    titleKey: "Location stays on this device",
                    bodyKey: "Prayer times and the Qibla direction are calculated locally. Your coordinates are never sent to a server, and no location history is kept — only the city used for calculations is saved, with its coordinates rounded to city-level accuracy."
                )
                .diAppear(delay: 0.06)

                PrivacyCard(
                    systemImage: "hand.raised.fill",
                    titleKey: "No ads or third-party trackers",
                    bodyKey: "Darul Irfan contains no advertising and no third-party tracking SDK. Reading, listening, prayer history, bookmarks, and tasbih activity remain on this device. Anonymous Apple diagnostics are sent only if you explicitly opt in."
                )
                .diAppear(delay: 0.12)

                PrivacyCard(
                    systemImage: "bell.fill",
                    titleKey: "Notification choice",
                    bodyKey: LocalizedStringKey(
                        appState.settings.push.isEnabled
                            ? "Prayer and reminder alerts are scheduled locally. You also opted in to official live/update alerts; only a random installation ID, Apple push token, locale, timezone, app version, and selected topics are registered."
                            : "Prayer alerts and reminders are scheduled entirely on this device. Official live/update push alerts are currently off."
                    )
                )
                .diAppear(delay: 0.18)

                PrivacyCard(
                    systemImage: "internaldrive.fill",
                    titleKey: "Your data is yours",
                    bodyKey: "Bookmarks, prayer records, tasbih counts, and downloads are stored only on this device. Deleting the app removes them completely."
                )
                .diAppear(delay: 0.24)

                Text("Network access refreshes official public content and live status, and streams or downloads content you request. Precise location is never included.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .padding(.horizontal, DISpacing.xs)
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Choices

/// The next-prayer Live Activity, and whether anonymous diagnostics are
/// shared: the same settings Official Alerts & Privacy held.
@MainActor
private struct PrivacyChoicesCard: View {
    let appState: AppState
    let dependencies: AppDependencies?

    var body: some View {
        DIElevatedCard {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                Toggle(isOn: Binding(
                    get: { appState.settings.liveActivitiesEnabled },
                    set: { enabled in
                        // Saving the setting starts or ends the Live Activity.
                        Task { await OfficialAlertSwitches.setLiveActivity(enabled, appState: appState) }
                    }
                )) {
                    Text("Next-prayer Live Activity")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.textPrimary)
                }
                .tint(DIColor.primary)

                if let dependencies {
                    Divider()
                    HStack(spacing: DISpacing.sm) {
                        Text("Share diagnostics")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DIColor.textPrimary)
                        Spacer(minLength: DISpacing.sm)
                        Picker("Share diagnostics", selection: Binding(
                            get: { appState.settings.diagnosticsConsent },
                            set: { consent in
                                Task { await OfficialAlertSwitches.setDiagnostics(consent, dependencies: dependencies, appState: appState) }
                            }
                        )) {
                            Text("Ask me later").tag(DiagnosticsConsent.notAsked)
                            Text("Do not share").tag(DiagnosticsConsent.declined)
                            Text("Share anonymously").tag(DiagnosticsConsent.granted)
                        }
                        .pickerStyle(.menu)
                        .tint(DIColor.primary)
                    }
                    Text("Anonymous Apple MetricKit diagnostics are uploaded only after consent. Payloads exclude location, bookmarks, prayer history, names, and email addresses, and are retained for 30 days.")
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Card

private struct PrivacyCard: View {
    let systemImage: String
    let titleKey: LocalizedStringKey
    let bodyKey: LocalizedStringKey

    var body: some View {
        DIElevatedCard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) {
                    ZStack {
                        Circle().fill(DIColor.accent.opacity(0.14))
                        Image(systemName: systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DIColor.accent)
                    }
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                    Text(titleKey)
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                }
                .accessibilityAddTraits(.isHeader)

                Text(bodyKey)
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textPrimary)
            }
        }
    }
}
