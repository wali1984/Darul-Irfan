import SwiftUI

/// Root shell shown once dependencies are ready: gates on onboarding, then
/// hosts the five-tab navigation with the shared mini audio player bar.
struct RootView: View {
    private enum AppTab: Hashable { case today, quran, zikr, explore, more }
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

            QuranTabView(dependencies: dependencies, appState: appState)
                .tabItem { Label("Quran", systemImage: "book") }
                .tag(AppTab.quran)

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
            if path.contains("/live") || path.contains("/zikr") { selectedTab = .zikr }
            else if path.contains("/feed") || path.contains("/events") { selectedTab = .explore }
            else if path.contains("/today") || path.contains("/prayer") { selectedTab = .today }
            else if path.contains("/quran") { selectedTab = .quran }
        }
        .onOpenURL { url in
            let path = ((url.host ?? "") + url.path).lowercased()
            if path.contains("live") || path.contains("zikr") { selectedTab = .zikr }
            else if path.contains("feed") || path.contains("event") { selectedTab = .explore }
            else if path.contains("today") || path.contains("prayer") { selectedTab = .today }
            else if path.contains("quran") { selectedTab = .quran }
        }
    }
}
