import SwiftUI

/// Root shell shown once dependencies are ready: gates on onboarding, then
/// hosts the five-tab navigation with the shared mini audio player bar.
///
/// Five is a hard ceiling, not a preference. iPhone shows at most five tab-bar
/// items and folds everything after that into a system "More" list — with six
/// tabs, Explore vanished from the bar and ended up inside a More within our
/// own More. Quran and Hadith are therefore paired under Read as equals rather
/// than given a tab each; see `ReadTabView`.
struct RootView: View {
    private enum AppTab: Hashable { case today, read, zikr, explore, more }
    let dependencies: AppDependencies
    let appState: AppState
    @State private var selectedTab: AppTab = .today

    var body: some View {
        if appState.settings.hasCompletedOnboarding {
            tabShell
        } else {
            // The flow flips `hasCompletedOnboarding` via
            // `appState.updateSettings` when it finishes; observation of that
            // flag re-evaluates this body, so no extra work is needed here.
            OnboardingFlowView(dependencies: dependencies, appState: appState, onComplete: {})
        }
    }

    private var tabShell: some View {
        TabView(selection: $selectedTab) {
            PrayerTabView(dependencies: dependencies, appState: appState)
                .tabItem { Label("Today", systemImage: "moon.stars") }
                .tag(AppTab.today)

            // Quran and Hadith live here as peers: distinct bodies of
            // knowledge, two equally weighted destinations, neither nested
            // inside the other.
            ReadTabView(dependencies: dependencies, appState: appState)
                .tabItem { Label("Read", systemImage: "books.vertical") }
                .tag(AppTab.read)

            NavigationStack {
                ZikrHomeView(dependencies: dependencies, appState: appState)
            }
            .tabItem { Label("Zikr", systemImage: "sparkles") }
            .tag(AppTab.zikr)

            ExploreTabView(dependencies: dependencies, appState: appState)
                .tabItem { Label("Explore", systemImage: "safari") }
                .tag(AppTab.explore)

            MoreTabView(dependencies: dependencies, appState: appState)
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(AppTab.more)
        }
        .tint(DIColor.primary)
        // `safeAreaInset` adapts to compact/regular tab bars, iPad and future
        // system tab-bar sizes instead of relying on a fixed 49-point offset.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if dependencies.audioPlayer.nowPlaying != nil {
                MiniPlayerBar(audioPlayer: dependencies.audioPlayer)
                    .environment(\.diMediaRepository, dependencies.mediaRepository)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: dependencies.audioPlayer.nowPlaying)
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveAppDeepLink)) { notification in
            guard let path = notification.object as? String else { return }
            selectTab(forDeepLinkPath: path)
        }
        .onOpenURL { url in
            let path = ((url.host ?? "") + url.path)
            selectTab(forDeepLinkPath: path)
            // Re-broadcast so the Read tab can pick the right reader. The
            // AppDelegate route already posts this; a URL opened directly into
            // a running scene does not.
            NotificationCenter.default.post(name: .didReceiveAppDeepLink, object: path)
        }
    }

    /// Both readers are addressable directly: `…/hadith` opens Hadith without
    /// travelling through the Quran, and vice versa. `ReadTabView` picks the
    /// reader from the same path.
    private func selectTab(forDeepLinkPath path: String) {
        let lowered = path.lowercased()
        if lowered.contains("live") || lowered.contains("zikr") { selectedTab = .zikr }
        else if lowered.contains("feed") || lowered.contains("event") { selectedTab = .explore }
        else if lowered.contains("today") || lowered.contains("prayer") { selectedTab = .today }
        else if lowered.contains("quran") || lowered.contains("surah") || lowered.contains("hadith") {
            selectedTab = .read
        }
    }
}
