import SwiftUI

/// Static privacy summary. Mirrors the app's privacy commitments: on-device
/// location, no ads, no trackers, no analytics.
@MainActor
struct PrivacySettingsView: View {
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
                    titleKey: "No ads, no trackers, no analytics",
                    bodyKey: "Darul Irfan contains no advertising, no third-party trackers, and no analytics. Nothing about your reading, listening, or prayer habits leaves your device."
                )
                .diAppear(delay: 0.12)

                PrivacyCard(
                    systemImage: "bell.fill",
                    titleKey: "Notifications are local",
                    bodyKey: "Prayer alerts and the reminders you set are scheduled entirely on your device by iOS. No notification service in the cloud is involved."
                )
                .diAppear(delay: 0.18)

                PrivacyCard(
                    systemImage: "internaldrive.fill",
                    titleKey: "Your data is yours",
                    bodyKey: "Bookmarks, prayer records, tasbih counts, and downloads are stored only on this device. Deleting the app removes them completely."
                )
                .diAppear(delay: 0.24)

                Text("Network access is used only to stream or download the content you request, such as lectures and publications from naqshbandiaowaisiah.org.")
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
