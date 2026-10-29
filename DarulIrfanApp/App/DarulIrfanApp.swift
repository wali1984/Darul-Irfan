import SwiftUI
import Combine
import Observation
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

    /// What the seed import is preparing, shown under the splash.
    @State private var importProgress = SeedImportProgress()

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
                        .overlay(alignment: .bottom) {
                            if let step = importProgress.step {
                                SeedImportStatusLine(step: step)
                            }
                        }
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
                      let token = notification.object as? Data else { return }
                if appState.settings.push.isEnabled {
                    Task { try? await dependencies.officialPlatform.registerForPush(token: token, preferences: appState.settings.push) }
                } else if HalqahNoticeChoice.isWanted {
                    // A member signed in here gets their Halqah's notices
                    // with official alerts off too.
                    Task { try? await dependencies.officialPlatform.registerForHalqahNotices(token: token) }
                }
            }
            // A widget or link that launched the app, kept until the screen
            // it names exists (the tab shell's own handler is not there yet
            // during the splash).
            .onOpenURL { url in
                DeepLinkRouter.shared.open(url: url)
            }
        }
    }

    // MARK: - Launch

    @MainActor
    private func launch() async {
        let launchStart = Date()
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
            if launchArguments.contains(where: { $0.hasPrefix("--uitesting") }) {
                // The Read tab reopens on the reader last used, which would
                // make "does Read offer both?" depend on whatever a previous
                // run left behind. Clear it so each run starts at the cards.
                UserDefaults.standard.removeObject(forKey: "read.lastSection")
            }
            #endif
            await dependencies.officialPlatform.setConsent(appState.settings.diagnosticsConsent)

            // Force the saved UI language at the bundle level before first paint
            // so every localized string (Text and String(localized:)) follows it,
            // the launch screen's progress line included.
            LanguageManager.apply(appState.settings.language)

            // Finish the bundled import before content screens can query the
            // database, so every screen opens on the content this build
            // ships. Only the stages whose files changed run; the launch
            // screen says which while they do.
            let progress = importProgress
            _ = try? await dependencies.contentSync.importSeedDataIfNeeded { step in
                await MainActor.run { progress.step = step }
            }
            progress.step = nil

            // Hold the brand splash for a beat so the emblem reads, rather than
            // flashing past when launch work finishes quickly. Skipped in UI tests.
            #if DEBUG
            let skipSplashHold = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--uitesting") }
            #else
            let skipSplashHold = false
            #endif
            let splashElapsed = Date().timeIntervalSince(launchStart)
            if !skipSplashHold, splashElapsed < 2.5 {
                try? await Task.sleep(for: .seconds(2.5 - splashElapsed))
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
                // Keeps the token the server holds current, for official
                // alerts and for a signed-in member's Halqah notices alike.
                if appState.settings.push.isEnabled || HalqahNoticeChoice.isWanted {
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
    /// set (timezone changes) or notification permission changed since the
    /// alerts were last scheduled.
    @MainActor
    private func refreshAfterActivation(force: Bool) {
        guard case .ready(_, let appState) = launchState else { return }
        guard appState.settings.hasCompletedOnboarding else { return }

        let now = Date()
        let throttled = !force
            && lastForegroundRefresh.map { now.timeIntervalSince($0) < Self.foregroundRefreshInterval } == true
        if !throttled {
            lastForegroundRefresh = now
        }

        Task {
            // Allowing notifications in the Settings app usually means coming
            // straight back here, inside the throttle. Alerts added while they
            // were off were rejected, so schedule them now rather than at
            // some later activation.
            if throttled {
                guard await appState.notificationPermissionChangedSinceLastRefresh() else { return }
            }
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
            // Re-apply the bundle-level language and rebuild the tree so every
            // localized string re-resolves when the user switches language.
            .onChange(of: language) { _, newValue in
                LanguageManager.apply(newValue)
            }
            .id(language)

        if let localeIdentifier = language.forcedLocaleIdentifier {
            root
                .environment(\.locale, Locale(identifier: localeIdentifier))
                .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        } else {
            root
        }
    }
}

// MARK: - Seed import progress

/// The step of the bundled-content import running now, if any.
@Observable
@MainActor
final class SeedImportProgress {
    var step: SeedImportStep?
}

/// Says under the splash what is being prepared, so a long first import
/// after installing or updating reads as work rather than a hung app.
private struct SeedImportStatusLine: View {
    let step: SeedImportStep

    var body: some View {
        VStack(spacing: DISpacing.xs) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DIColor.onPrimary)
            Text("This takes a moment after installing or updating the app.")
                .font(.caption)
                .foregroundStyle(DIColor.onPrimary.opacity(0.8))
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, DISpacing.lg)
        .padding(.bottom, DISpacing.xl)
        .accessibilityElement(children: .combine)
    }

    private var title: LocalizedStringKey {
        switch step {
        case .quran: return "Preparing the Qur'an…"
        case .library: return "Preparing the library…"
        case .media: return "Preparing the bayans…"
        case .events: return "Preparing the events…"
        case .books: return "Preparing the books…"
        case .hadith: return "Preparing the hadith collections…"
        case .search: return "Preparing search…"
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
