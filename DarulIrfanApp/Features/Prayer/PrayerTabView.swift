import SwiftUI

/// Today (board Main, and TodayDark while Daily Zikr is live): the app's
/// first screen. The large title with the Gregorian and Hijri dates under
/// it; a live strip only while a session is on air; the prayer card (the
/// next prayer and its countdown, the five prayers to mark, and the way to
/// every time and alert); the tool orbs; Today's Light, the six daily cards
/// in one place; and where reading and listening left off. The times list,
/// the bells, the method, the Ramadan card and the tracker for earlier days
/// are on the Prayer times page the prayer card opens.
struct PrayerTabView: View {
    private let dependencies: AppDependencies
    private let appState: AppState
    @State private var viewModel: PrayerViewModel
    @State private var liveModel: TodayLiveModel
    @State private var isSearchPresented = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
        _viewModel = State(initialValue: PrayerViewModel(dependencies: dependencies, appState: appState))
        _liveModel = State(initialValue: TodayLiveModel(platform: dependencies.officialPlatform))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DISpacing.md) {
                    // A newer TestFlight or App Store build, while one is out.
                    TodayUpdateBanner()
                    // Only while Daily Zikr or the Tahajjud zikr is live.
                    if let strip = liveModel.strip {
                        TodayOfficialSection(strip: strip, dependencies: dependencies)
                            .transition(.opacity)
                    }
                    TodayHeroView(viewModel: viewModel, dependencies: dependencies, appState: appState)
                        .diAppear()
                    TodayUpcomingCard(dependencies: dependencies, appState: appState, liveShown: liveModel.strip != nil)
                    PersonalZikrLink()
                    TodayQuickTools(dependencies: dependencies, appState: appState)
                        .diAppear(delay: 0.05)
                    TodayDailySection(appState: appState, dependencies: dependencies)
                        .diAppear(delay: 0.10)
                    TodayContinueCard(dependencies: dependencies)
                }
                .padding(DISpacing.md)
                .diResponsiveWidth()
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: liveModel.strip)
            }
            .background { TodayPageGlow() }
            .diScreenBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The app language is one tap from the first screen, not
                // three screens into Settings.
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Language", selection: languageBinding) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(LocalizedStringKey(language.displayName)).tag(language)
                            }
                        }
                    } label: {
                        Image(systemName: "character.bubble")
                    }
                    .accessibilityLabel("Change app language")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSearchPresented = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(Text("Search"))
                }
            }
            .sheet(isPresented: $isSearchPresented) {
                GlobalSearchView(dependencies: dependencies, appState: appState)
            }
            .task {
                await viewModel.refresh()
            }
            // The live strip follows the live state while Today is on
            // screen and the app is in front.
            .task(id: scenePhase == .active) {
                guard scenePhase == .active else { return }
                await liveModel.follow()
            }
            .refreshable {
                await viewModel.refresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await viewModel.refresh() }
                }
            }
            .onChange(of: appState.settings) {
                Task { await viewModel.refresh() }
            }
        }
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { appState.settings.language },
            set: { language in Task { await appState.updateSettings { $0.language = language } } }
        )
    }
}
