import SwiftUI

/// Privacy summary reflecting the user's current opt-in service choices.
@MainActor
struct PrivacySettingsView: View {
    let appState: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                SettingsBrandBanner(
                    titleKey: "Privacy",
                    subtitleKey: "On-device by design"
                )
                .diAppear()

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
