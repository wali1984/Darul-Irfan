import SwiftUI

/// Root shell shown once dependencies are ready: gates on onboarding, then
/// hosts the five-tab navigation with the shared mini audio player bar
/// overlaid above the tab bar. Feature code never draws its own mini player.
struct RootView: View {
    let dependencies: AppDependencies
    let appState: AppState

    /// Height of the standard compact tab bar (points above the bottom safe
    /// area). Used to float the mini player directly above it.
    private static let tabBarHeight: CGFloat = 49

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
        // The mini player lives in a ZStack over the whole TabView, padded by
        // the tab bar height, instead of a `safeAreaInset` repeated inside all
        // five tabs. Tradeoff: the 49pt constant matches the compact-height
        // tab bar (iPhone portrait); tab content does not automatically gain
        // extra bottom inset while the bar is visible, so scrollable feature
        // screens keep comfortable bottom padding of their own.
        ZStack(alignment: .bottom) {
            TabView {
                PrayerTabView(dependencies: dependencies, appState: appState)
                    .tabItem {
                        Label("Today", systemImage: "moon.stars")
                    }

                QuranTabView(dependencies: dependencies, appState: appState)
                    .tabItem {
                        Label("Quran", systemImage: "book")
                    }

                LibraryTabView(dependencies: dependencies, appState: appState)
                    .tabItem {
                        Label("Library", systemImage: "books.vertical")
                    }

                MediaTabView(dependencies: dependencies, appState: appState)
                    .tabItem {
                        Label("Media", systemImage: "play.circle")
                    }

                MoreTabView(dependencies: dependencies, appState: appState)
                    .tabItem {
                        Label("More", systemImage: "ellipsis.circle")
                    }
            }
            .tint(DIColor.primary)

            if dependencies.audioPlayer.nowPlaying != nil {
                MiniPlayerBar(audioPlayer: dependencies.audioPlayer)
                    .environment(\.diMediaRepository, dependencies.mediaRepository)
                    .padding(.bottom, Self.tabBarHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: dependencies.audioPlayer.nowPlaying)
    }
}
