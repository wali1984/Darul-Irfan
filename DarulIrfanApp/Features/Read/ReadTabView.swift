import SwiftUI

/// The three readers the Read tab offers. They are peers: none is a section
/// of another, and one switch at the top of each reader's page reaches all
/// three.
enum ReadSection: String, CaseIterable, Hashable, Identifiable {
    case quran
    case hadith
    case books

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .quran: return "Quran"
        case .hadith: return "Hadith"
        case .books: return "Books"
        }
    }

    var symbol: String {
        switch self {
        case .quran: return "book"
        case .hadith: return "book.closed"
        case .books: return "books.vertical"
        }
    }
}

/// What the Read tab hands each reader's page: the switch, which sits in the
/// page under the large title, and the toolbar's Saved and Search.
struct ReadTabActions {
    var selection: Binding<ReadSection>
    var openSaved: () -> Void
    var openSearch: () -> Void
}

private struct ReadTabActionsKey: EnvironmentKey {
    static let defaultValue: ReadTabActions? = nil
}

extension EnvironmentValues {
    /// Set by the Read tab for the readers it holds; nil anywhere else, where
    /// a reader shows its own title and no switch.
    var readTabActions: ReadTabActions? {
        get { self[ReadTabActionsKey.self] }
        set { self[ReadTabActionsKey.self] = newValue }
    }
}

/// Read tab: every text, Qur'an, hadith and books, under one switch.
///
/// There is no landing page: the tab opens on the reader chosen last (the
/// Quran the first time), titled "Read", with Saved (bookmarks, favourites
/// and notes) and Search in its toolbar and the Quran | Hadith | Books switch
/// at the top of the page.
///
/// The readers are kept alive side by side rather than swapped in and out, so
/// each keeps its own navigation history: go three levels into a surah, let
/// a link open a hadith, come back, and the surah is still open. A reader is
/// built the first time it is chosen.
@MainActor
struct ReadTabView: View {
    let dependencies: AppDependencies
    let appState: AppState

    @State private var active: ReadSection
    /// The readers built so far; each is kept once built.
    @State private var opened: Set<ReadSection>
    /// Navigation history per reader, held here so links can open a place in it.
    @State private var quranPath: [QuranRoute] = []
    @State private var hadithPath: [HadithRoute] = []
    @State private var sheet: ReadSheet?
    /// Survives launches, so the tab reopens on the reader left last.
    @AppStorage("read.lastSection") private var lastSection: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum ReadSheet: String, Identifiable {
        case saved
        case search
        var id: String { rawValue }
    }

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
        let remembered = ReadSection(rawValue: UserDefaults.standard.string(forKey: "read.lastSection") ?? "") ?? .quran
        _active = State(initialValue: remembered)
        _opened = State(initialValue: [remembered])
    }

    var body: some View {
        ZStack {
            ForEach(ReadSection.allCases) { section in
                if opened.contains(section) {
                    reader(section)
                        .opacity(section == active ? 1 : 0)
                        .allowsHitTesting(section == active)
                        .accessibilityHidden(section != active)
                        .zIndex(section == active ? 1 : 0)
                }
            }
        }
        .environment(\.readTabActions, actions)
        .sheet(item: $sheet) { presented in
            switch presented {
            case .saved:
                ReadSavedView(dependencies: dependencies, appState: appState, onOpenAyah: openFromSaved)
            case .search:
                GlobalSearchView(dependencies: dependencies, appState: appState)
            }
        }
        .onAppear {
            // A request made before this tab existed - the first "Open in the
            // Quran" after launch, a notification - waits in the router.
            followRouter()
        }
        .onChange(of: DeepLinkRouter.shared.requestCount) { _, _ in followRouter() }
        // The collection opened last, for Hadith's Continue: the reader keeps
        // the narration itself (HadithReadingPosition).
        .onChange(of: hadithPath) { _, path in
            if let bookID = Self.collectionID(in: path) {
                HadithLastCollection.save(bookID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveAppDeepLink)) { notification in
            if let path = notification.object as? String { open(deepLinkPath: path) }
        }
        // An ayah to open, relayed by RootView or posted by a screen that
        // still uses the notification: switch to the Quran reader and open
        // it at that ayah, all in-app, no external site.
        .onReceive(NotificationCenter.default.publisher(for: .openQuranAyah)) { notification in
            guard let link = notification.object as? QuranAyahLink else { return }
            openAyah(link)
        }
    }

    // MARK: - Readers

    /// Each reader owns its `NavigationStack`; the toolbar and the switch are
    /// applied inside it (`readerSwitch`), where its navigation bar is.
    @ViewBuilder
    private func reader(_ section: ReadSection) -> some View {
        switch section {
        case .quran:
            QuranTabView(
                dependencies: dependencies,
                appState: appState,
                navigationPath: $quranPath,
                readerSelection: selectionBinding,
                onShowAllReaders: openSaved
            )
        case .hadith:
            HadithTabView(
                dependencies: dependencies,
                appState: appState,
                navigationPath: $hadithPath,
                readerSelection: selectionBinding,
                onShowAllReaders: openSaved
            )
        case .books:
            LibraryTabView(
                dependencies: dependencies,
                appState: appState,
                readerSelection: selectionBinding,
                onShowAllReaders: openSaved
            )
        }
    }

    private var selectionBinding: Binding<ReadSection> {
        Binding(
            get: { active },
            set: { select($0) }
        )
    }

    private var actions: ReadTabActions {
        ReadTabActions(
            selection: selectionBinding,
            openSaved: { sheet = .saved },
            openSearch: { sheet = .search }
        )
    }

    private func openSaved() {
        sheet = .saved
    }

    // MARK: - Selection

    private func select(_ section: ReadSection) {
        lastSection = section.rawValue
        opened.insert(section)
        // The switch itself may animate; the sacred text it reveals never does.
        if reduceMotion {
            active = section
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { active = section }
        }
    }

    // MARK: - Links

    /// Takes a Quran or Hadith request from the router, once: which reader,
    /// and the ayah to open.
    private func followRouter() {
        guard let route = DeepLinkRouter.shared.take({ $0.isRead ? $0 : nil }) else { return }
        switch route {
        case .hadith:
            select(.hadith)
        case .quran(let surah, let ayah):
            if let surah {
                openAyah(QuranAyahLink(surah: surah, ayah: ayah))
            } else {
                select(.quran)
            }
        default:
            break
        }
    }

    private func openAyah(_ link: QuranAyahLink) {
        Task { @MainActor in
            let surahs = (try? await dependencies.quranRepository.allSurahs()) ?? []
            guard let surah = surahs.first(where: { $0.id == link.surah }) else { return }
            select(.quran)
            quranPath = [.reader(surah: surah, focusAyah: link.ayah)]
        }
    }

    /// A bookmark chosen in Saved: Saved closes, then the Quran reader opens
    /// at that ayah, so it is not opened behind the sheet.
    private func openFromSaved(_ link: QuranAyahLink) {
        sheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            openAyah(link)
        }
    }

    /// The collection a Hadith path last opened, if it opened one.
    private static func collectionID(in path: [HadithRoute]) -> String? {
        for route in path.reversed() {
            if case .collection(let book) = route { return book.id }
            if case .hadith(let book, _) = route { return book.id }
        }
        return nil
    }

    /// Deep links address a reader directly: none is reachable only through
    /// another, so `…/hadith` never has to travel via the Quran.
    func open(deepLinkPath path: String) {
        let lowered = path.lowercased()
        if lowered.contains("hadith") {
            select(.hadith)
        } else if lowered.contains("quran") || lowered.contains("surah") {
            select(.quran)
        }
    }
}

// MARK: - Reader toolbar

/// The Read tab's toolbar inside each reader's navigation bar: Saved on the
/// leading side and Search on the trailing side, as on Today. The switch
/// itself sits in the page (`ReadSectionPicker`), under the large title.
struct ReaderSwitch: ViewModifier {
    @Binding var selection: ReadSection
    /// Opens Saved. (This once led back to a landing page of two cards, which
    /// the switch in the page replaced.)
    let onShowAll: () -> Void
    @Environment(\.readTabActions) private var actions

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        DIHaptics.light()
                        onShowAll()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bookmark")
                            Text("Saved")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityIdentifier("read.saved")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        DIHaptics.light()
                        actions?.openSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(Text("Search"))
                }
            }
    }
}

extension View {
    func readerSwitch(
        selection: Binding<ReadSection>,
        onShowAll: @escaping () -> Void
    ) -> some View {
        modifier(ReaderSwitch(selection: selection, onShowAll: onShowAll))
    }
}
