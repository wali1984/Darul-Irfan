import SwiftUI

/// The banner at the top of every main tab while a newer build is out
/// (`AppUpdateChecker`; owner 2026-11-19: in real time, on every tab, not
/// only Today). Update opens TestFlight or the App Store at the app; Cancel
/// and Close hide the banner until the app is next opened. While the app is
/// in front it keeps the five-minute check going.
struct AppUpdateBannerBar: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let checker = AppUpdateChecker.shared
        VStack(spacing: 0) {
            if let release = checker.banner {
                AppUpdateBanner(release: release) { checker.dismiss() }
                    .padding(.horizontal, DISpacing.md)
                    .padding(.vertical, DISpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            if checker.banner != nil {
                DIColor.background.ignoresSafeArea(edges: .top)
            }
        }
        .animation(.easeOut(duration: 0.25), value: checker.banner)
        // Every five minutes while the app is in front; cancelled, and so
        // stopped, when it leaves.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await checker.runWhileActive()
        }
    }
}

struct AppUpdateBanner: View {
    let release: AppRelease
    let onClose: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        DICard(borderColor: DIColor.primary) {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(alignment: .top, spacing: DISpacing.sm) {
                    Image(systemName: "arrow.down.app.fill")
                        .diInterfaceFont(.title2)
                        .foregroundStyle(DIColor.primary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DISpacing.xs) {
                        Text("A newer version is available")
                            .diInterfaceFont(.headline)
                            .foregroundStyle(DIColor.textPrimary)
                        message
                            .diInterfaceFont(.subheadline)
                            .foregroundStyle(DIColor.textMuted)
                    }
                    Spacer(minLength: 0)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .diInterfaceFont(.footnote, weight: .semibold)
                            .foregroundStyle(DIColor.textMuted)
                            .padding(DISpacing.xs)
                    }
                    .accessibilityLabel(Text("Close"))
                }
                HStack(spacing: DISpacing.sm) {
                    Button("Update", action: update)
                        .buttonStyle(DIPrimaryButtonStyle())
                    Button("Cancel", action: onClose)
                        .buttonStyle(DISecondaryButtonStyle())
                }
            }
        }
    }

    private var message: Text {
        if let build = release.build {
            return Text("Version \(release.version) (build \(build)) is in TestFlight.")
        }
        return Text("Version \(release.version) is in the App Store.")
    }

    /// The TestFlight app opens at the app by its own link; failing that, the
    /// web address hands over to it.
    private func update() {
        openURL(release.url) { opened in
            if !opened, release.channel == .testFlight {
                openURL(AppReleaseCheck.testFlightWebURL)
            }
        }
    }
}
