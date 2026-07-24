import SwiftUI
import Combine
import UIKit

/// App entry point. Builds the dependency graph once, bootstraps session
/// state, then hands everything to `RootView`. Also owns app-lifecycle side
/// effects: foreground refresh of location/notifications/widgets, timezone
/// change handling, and persisting audio progress when backgrounded.
@main
struct DarulIrfanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Launch progression for the single window.
    enum LaunchState {
        case loading
        case ready(AppDependencies, AppState)
        case failed(String)
    }

    @State private var launchState: LaunchState = .loading

    /// Throttles the scene-active refresh so rapid app switching does not
    /// re-run location + notification work on every activation.
    @State private var lastForegroundRefresh: Date?

    @Environment(\.scenePhase) private var scenePhase

    private static let foregroundRefreshInterval: TimeInterval = 60

    init() {
        // Register the bundled Amiri Quran + Noto Nastaliq fonts before any
        // view (and thus any Font.custom) is evaluated.
        AppFonts.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch launchState {
                case .loading:
                    LaunchView()
                case .ready(let dependencies, let appState):
                    ReadyRootView(dependencies: dependencies, appState: appState)
                case .failed(let message):
                    LaunchFailureView(message: message) {
                        launchState = .loading
                        Task { await launch() }
                    }
                }
            }
            .task {
                // Runs once when the window first appears; retries go through
                // the failure view's button instead.
                guard case .loading = launchState else { return }
                await launch()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    refreshAfterActivation(force: false)
                case .background:
                    persistPlaybackProgress()
                default:
                    break
                }
            }
            .onReceive(
                NotificationCenter.default
                    .publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)
                    .receive(on: RunLoop.main)
            ) { _ in
                // Timezone moves must always reschedule, so bypass the throttle.
                refreshAfterActivation(force: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .didReceiveAPNSToken)) { notification in
                guard case .ready(let dependencies, let appState) = launchState,
                      let token = notification.object as? Data,
                      appState.settings.push.isEnabled else { return }
                Task { try? await dependencies.officialPlatform.registerForPush(token: token, preferences: appState.settings.push) }
            }
        }
    }

    // MARK: - Launch

    @MainActor
    private func launch() async {
        do {
            let dependencies = try await AppDependencies.live()
            let appState = AppState(dependencies: dependencies)
            await appState.bootstrap()
            #if DEBUG
            let launchArguments = ProcessInfo.processInfo.arguments
            if launchArguments.contains("--uitesting-complete-onboarding") {
                await appState.updateSettings { settings in
                    settings.hasCompletedOnboarding = true
                    settings.locationMode = .manual
                    settings.manualPlace = PlaceCoordinate(
                        latitude: 33.5651,
                        longitude: 73.0169,
                        name: "Rawalpindi",
                        timeZoneIdentifier: "Asia/Karachi"
                    )
                }
            } else if launchArguments.contains("--uitesting-reset-onboarding") {
                await appState.updateSettings { $0.hasCompletedOnboarding = false }
            }
            #endif
            await dependencies.officialPlatform.setConsent(appState.settings.diagnosticsConsent)

            // Seed import and manifest refresh happen off the critical path so
            // first paint is never blocked on content work. Both are
            // idempotent; failures are silent and retried on next launch.
            let contentSync = dependencies.contentSync
            Task.detached(priority: .utility) {
                _ = try? await contentSync.importSeedDataIfNeeded()
                try? await contentSync.refreshFromRemoteManifest()
            }

            launchState = .ready(dependencies, appState)
            lastForegroundRefresh = Date()

            // Initial refresh of place, notifications, and widgets. Skipped
            // until onboarding is complete: resolving the device place would
            // trigger the location permission prompt before onboarding has
            // explained it (the onboarding flow runs its own refresh when it
            // finishes).
            if appState.settings.hasCompletedOnboarding {
                await appState.refreshDevicePlaceIfNeeded()
                await appState.refreshScheduledNotificationsAndWidgets()
                if appState.settings.push.isEnabled {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        } catch {
            launchState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Lifecycle side effects

    /// Refreshes device place, scheduled notifications, and widget snapshots.
    /// Throttled to once per `foregroundRefreshInterval` unless `force` is
    /// set (timezone changes).
    @MainActor
    private func refreshAfterActivation(force: Bool) {
        guard case .ready(_, let appState) = launchState else { return }
        guard appState.settings.hasCompletedOnboarding else { return }

        let now = Date()
        if !force,
           let last = lastForegroundRefresh,
           now.timeIntervalSince(last) < Self.foregroundRefreshInterval {
            return
        }
        lastForegroundRefresh = now

        Task {
            await appState.refreshDevicePlaceIfNeeded()
            await appState.refreshScheduledNotificationsAndWidgets()
        }
    }

    /// Saves the audio player's position on scene-background so "continue
    /// listening" survives termination.
    @MainActor
    private func persistPlaybackProgress() {
        guard case .ready(let dependencies, _) = launchState else { return }
        guard let progress = dependencies.audioPlayer.snapshotProgress() else { return }
        let repository = dependencies.mediaRepository
        Task {
            try? await repository.savePlaybackProgress(progress)
        }
    }
}

// MARK: - Ready wrapper

/// Wraps `RootView` in the user's appearance and language preferences.
/// A dedicated view (rather than modifiers applied inside the scene builder)
/// so that `@Observable` tracking of `appState.settings` reliably re-renders
/// when the theme or language changes.
private struct ReadyRootView: View {
    let dependencies: AppDependencies
    let appState: AppState

    var body: some View {
        let language = appState.settings.language
        let root = RootView(dependencies: dependencies, appState: appState)
            .preferredColorScheme(appState.settings.theme.colorScheme)

        if let localeIdentifier = language.forcedLocaleIdentifier {
            root
                .environment(\.locale, Locale(identifier: localeIdentifier))
                .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        } else {
            root
        }
    }
}

// MARK: - Launch failure

/// Shown when the dependency graph could not be built (e.g. the database
/// failed to open). Offers a retry without relaunching the app.
private struct LaunchFailureView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: DISpacing.md) {
            Spacer()

            DIEmptyState(
                systemImage: "exclamationmark.triangle",
                titleKey: "We could not finish setting up",
                messageKey: "Something went wrong while preparing the app. Your data is safe — please try again."
            )

            Text(verbatim: message)
                .font(.footnote)
                .foregroundStyle(DIColor.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DISpacing.lg)

            Spacer()

            Button("Try Again", action: onRetry)
                .buttonStyle(DIPrimaryButtonStyle())
                .padding(.horizontal, DISpacing.lg)
                .padding(.bottom, DISpacing.xl)
        }
        .diScreenBackground()
    }
}
