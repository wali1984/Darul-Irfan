import SwiftUI

/// The Halqah tab: the community and you. At its root, top to bottom: the
/// brand header (the living Silsila seal, Darul Irfan, the site's tagline
/// and the Silsila's name); My Halqahs, so a Halqah is two taps from launch;
/// the Silsila's pages; every setting, Language first; and the account
/// while signed in. Search is in the toolbar. Owns its own NavigationStack
/// per the app navigation contract.
///
/// What left: Events & Dar-ul-Irfan and Official Updates (in Discover), and
/// All tools, Daily Companion and Qibla (Tools and Qibla are on Today; Qibla
/// also on the Prayer times page). The language menu left the toolbar for
/// the first row of Settings; it stays on Today.
@MainActor
struct MoreTabView: View {
    private let dependencies: AppDependencies
    private let appState: AppState

    @State private var isSearchPresented = false
    /// The member's private groups, shown at the root.
    @State private var groups = GroupsModel()
    /// The Silsila's pages: their favourites and their lists.
    @State private var library: LibraryViewModel

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
        _library = State(initialValue: LibraryViewModel(contentRepository: dependencies.contentRepository))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DISpacing.lg) {
                    HalqahBrandHeader()
                        .diAppear()

                    if MemberGroupsFeature.isEnabled {
                        MyHalqahsSection(model: groups, dependencies: dependencies)
                            .diAppear(delay: 0.05)
                    }

                    SilsilaSection(dependencies: dependencies, appState: appState, library: library)
                        .diAppear(delay: 0.10)

                    settingsSection
                        .diAppear(delay: 0.15)

                    if MemberGroupsFeature.isEnabled && groups.showsAccount {
                        HalqahAccountSection(model: groups)
                    }
                }
                .padding(DISpacing.md)
                .diResponsiveWidth()
                .background { HalqahPageDecor() }
            }
            .diScreenBackground()
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSearchPresented = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search")
                }
            }
            .sheet(isPresented: $isSearchPresented) {
                GlobalSearchView(dependencies: dependencies, appState: appState)
            }
            .task {
                groups.platform = dependencies.officialPlatform
                await groups.appear()
            }
            .refreshable { await groups.checkAgain() }
        }
    }

    /// Every setting, in one list: the Halqah notices in Notifications are
    /// the same switch as the one under My Halqahs.
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            HalqahSectionLabel(titleKey: "Settings")
            SettingsList(dependencies: dependencies, appState: appState, halqahNotices: groups.noticesModel)
        }
    }
}
