import SwiftUI

/// Root shell shown once dependencies are ready: gates on onboarding, then
/// hosts the five-tab navigation with the shared mini audio player bar.
///
/// Five is a hard ceiling, not a preference. iPhone shows at most five tab-bar
/// items and folds everything after that into a system "More" list — with six
/// tabs, Explore vanished from the bar and ended up inside a More within our
/// own More. Quran and Hadith are therefore paired under Read as equals rather
/// than given a tab each; see `ReadTabView`.
@MainActor
struct RootView: View {
    private enum AppTab: String, Hashable { case today, read, zikr, explore, more }
    let dependencies: AppDependencies
    let appState: AppState
    /// Scene storage, not `@State`: changing the language rebuilds this view
    /// with a new identity (`.id(language)` in `ReadyRootView`), and the tab
    /// the person was on must survive that.
    @SceneStorage("root.selectedTab") private var selectedTab: AppTab = .today
    /// Whether the Read tab has been built: from then on it hears the older
    /// notifications itself.
    @State private var readTabShown = false
    /// Changed to bring the Zikr tab back to its own screen, from wherever it
    /// had been taken, when a notification or a link asks for it.
    @State private var zikrStack = UUID()
    /// Changed to bring the Halqah tab back to its root, with the member's
    /// Halqahs at the top, when a notification or a link asks for them.
    @State private var halqahStack = UUID()
    /// A Halqah a notification opened, shown over the Halqah tab.
    @State private var linkedGroup: LinkedGroup?

    private var router: DeepLinkRouter { .shared }

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
                .onAppear { readTabShown = true }
                .tabItem { Label("Read", systemImage: "books.vertical") }
                .tag(AppTab.read)

            NavigationStack {
                ZikrHomeView(dependencies: dependencies, appState: appState)
            }
            .id(zikrStack)
            .tabItem { Label("Zikr", systemImage: "sparkles") }
            .tag(AppTab.zikr)

            ExploreTabView(dependencies: dependencies, appState: appState)
                .tabItem { Label("Discover", systemImage: "safari") }
                .tag(AppTab.explore)

            MoreTabView(dependencies: dependencies, appState: appState)
                .id(halqahStack)
                .tabItem { Label("Halqah", systemImage: "person.3") }
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
        // Notifications, widgets and links go through DeepLinkRouter, which
        // keeps a request made during the splash or onboarding for this.
        .onAppear(perform: followRouter)
        .onChange(of: router.requestCount) { _, _ in followRouter() }
        // Screens that still ask for a place by notification (Today's
        // buttons) become requests like any other.
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveAppDeepLink)) { notification in
            guard let path = notification.object as? String else { return }
            openFromScreen(AppRoute(path: path))
        }
        .onReceive(NotificationCenter.default.publisher(for: .openQuranAyah)) { notification in
            guard let link = notification.object as? QuranAyahLink else { return }
            openFromScreen(.quranAyah(surah: link.surah, ayah: link.ayah))
        }
        .onOpenURL { url in router.open(url: url) }
        .sheet(item: $linkedGroup) { group in
            NavigationStack {
                GroupLinkView(groupID: group.id, dependencies: dependencies)
            }
        }
    }

    /// A request one of the app's own screens posted. A Read tab that exists
    /// heard the same notification itself, so only the tab bar moves; one not
    /// built yet takes the request from the router when it appears. (Once no
    /// screen posts these notifications, this and the observers above go.)
    private func openFromScreen(_ route: AppRoute?) {
        guard let route else { return }
        router.open(route)
        if readTabShown, route.isRead { router.clear(route) }
    }

    /// Goes where the newest request goes, once per request.
    private func followRouter() {
        if let route = router.takeTabRequest() { show(route) }
    }

    /// Selects the tab a route belongs to. The screen it names takes the
    /// rest: the Read tab the reader and ayah, the Zikr screen the session,
    /// Discover the section, and so on.
    private func show(_ route: AppRoute) {
        switch route {
        case .today:
            selectedTab = .today
            router.clear(route)
        case .quran, .hadith, .library:
            selectedTab = .read
        case .zikr, .live, .personalZikr:
            // A fresh Zikr screen, which shows the session asked for.
            zikrStack = UUID()
            selectedTab = .zikr
        case .groups:
            // A fresh Halqah tab: its root, with My Halqahs at the top, not
            // whatever screen it had been taken to.
            halqahStack = UUID()
            selectedTab = .more
            router.clear(route)
        case .group(let id):
            selectedTab = .more
            router.clear(route)
            linkedGroup = LinkedGroup(id: id)
        case .updates, .events, .media, .topics:
            selectedTab = .explore
        }
    }
}

/// A Halqah opened by a notification.
private struct LinkedGroup: Identifiable {
    let id: String
}
