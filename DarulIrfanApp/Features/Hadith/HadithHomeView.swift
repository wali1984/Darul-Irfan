import SwiftUI

/// The Hadith reader's page: Continue (the collection opened last, at the
/// narration it was left on), then the collections in three groups -
/// Sahihain and Sunan, more collections (folded beyond the first few), and
/// the Arabic-only works - with search across all of them.
///
/// Under Read it is titled "Read", with the Quran | Hadith | Books switch at
/// the top of the page.
@MainActor
struct HadithHomeView: View {
    private let dependencies: AppDependencies
    private let appState: AppState
    @State private var books: [HadithBook] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var results: [HadithEntry] = []
    /// How many narrations matched in all, when known; the results are a few
    /// from each collection, so this is usually more than are shown.
    @State private var matchCount: Int?
    @State private var isSearching = false
    /// Debounces typing so a long corpus scan does not run on every keystroke.
    @State private var searchTask: Task<Void, Never>?
    /// The groups opened past their first few with "Show all".
    @State private var expandedGroups: Set<HadithCollectionGroup.Kind> = []
    /// The collection opened last and the narration it was left on.
    @State private var resume: HadithResume?
    @Environment(\.readTabActions) private var readActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
    }

    /// The content language: "System" on an Urdu phone reads in Urdu.
    private var languageCode: String { appState.settings.language.contentLanguageCode }

    private var hasQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                if let selection = readActions?.selection {
                    ReadSectionPicker(selection: selection)
                }
                ReadFindField(prompt: "Search hadith by word or topic", text: $searchText)
                if hasQuery {
                    searchSection
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(DISpacing.xl)
                } else if books.isEmpty {
                    DIEmptyState(
                        systemImage: "books.vertical",
                        titleKey: "Hadith collections are being prepared",
                        messageKey: "They will appear here after the next content update."
                    )
                } else {
                    if let resume {
                        continueCard(resume)
                            .diAppear()
                    }
                    ForEach(HadithCollectionGroup.groups(from: books)) { group in
                        groupSection(group)
                    }
                }
            }
            .padding(.horizontal, DISpacing.md)
            .padding(.top, DISpacing.sm)
            .padding(.bottom, DISpacing.xl)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .diPageHeading(readActions == nil ? "Hadith" : "Read")
        .onChange(of: searchText) { _, term in
            searchTask?.cancel()
            let query = term.trimmingCharacters(in: .whitespaces)
            guard query.count >= 2 else {
                results = []; matchCount = nil; isSearching = false; return
            }
            isSearching = true
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                let repository = dependencies.hadithRepository
                let found = (try? await repository.search(query, bookID: nil, limit: 100)) ?? []
                let total = (try? await repository.searchCount(query, bookID: nil)) ?? nil
                guard !Task.isCancelled else { return }
                results = found
                matchCount = total
                isSearching = false
            }
        }
        .task { await load() }
        // Back from a collection, the narration it was left on has moved.
        .onAppear {
            Task { await refreshResume() }
        }
    }

    // MARK: - Continue

    /// The collection opened last. Opening it as a collection resumes at the
    /// narration the reader saved (`HadithReadingPosition`), with no cover.
    private func continueCard(_ resume: HadithResume) -> some View {
        NavigationLink(value: HadithRoute.collection(resume.book)) {
            HStack(spacing: 14) {
                ReadOrb(systemImage: "book.closed", diameter: 46)
                VStack(alignment: .leading, spacing: 2) {
                    ReadCaps("Continue")
                    Text(verbatim: resume.book.title(languageCode: languageCode))
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(DIColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let number = resume.number {
                        Text("Hadith \(number)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(DIColor.textMuted)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(DISpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .diGlassPanel(cornerRadius: 26)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(DIPressableStyle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Collections

    private func groupSection(_ group: HadithCollectionGroup) -> some View {
        let expanded = expandedGroups.contains(group.kind)
        let shown = group.visibleBooks(expanded: expanded)
        return VStack(alignment: .leading, spacing: DISpacing.sm) {
            ReadGroupTitle(titleKey: group.titleKey)
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, book in
                    if index > 0 {
                        ReadRowRule()
                    }
                    // Value-based so the Read tab can own this reader's
                    // navigation history; see HadithTabView.
                    NavigationLink(value: HadithRoute.collection(book)) {
                        collectionRow(book, showsNote: group.kind != .arabicOnly)
                    }
                    .buttonStyle(.plain)
                }
                if group.isFoldable {
                    ReadRowRule()
                    Button {
                        toggle(group.kind)
                    } label: {
                        showAllRow(expanded: expanded, count: group.books.count)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .readGlassList(cornerRadius: 24)
        }
    }

    private func collectionRow(_ book: HadithBook, showsNote: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: book.title(languageCode: languageCode))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.leading)
                Text("\(book.hadithCount) hadith")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
            }
            Spacer(minLength: DISpacing.sm)
            if showsNote, let note = translationNote(for: book) {
                DIPillBadge(text: note, color: ReadPalette.madinahInk)
            }
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DIColor.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func showAllRow(expanded: Bool, count: Int) -> some View {
        HStack(spacing: DISpacing.sm) {
            if expanded {
                Text("Show less")
            } else {
                Text("Show all \(count)")
            }
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.bold))
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(ReadPalette.emeraldInk)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func toggle(_ kind: HadithCollectionGroup.Kind) {
        DIHaptics.soft()
        let change = {
            if expandedGroups.contains(kind) {
                expandedGroups.remove(kind)
            } else {
                expandedGroups.insert(kind)
            }
        }
        if reduceMotion {
            change()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { change() }
        }
    }

    // MARK: - Search

    /// Results across every collection, searched in all three scripts.
    @ViewBuilder
    private var searchSection: some View {
        if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(DISpacing.xl)
        } else if results.isEmpty {
            DIEmptyState(
                systemImage: "magnifyingglass",
                titleKey: "No hadith match that search",
                messageKey: "Try a different word. Search looks through the Arabic, English and Urdu of every bundled collection."
            )
        } else {
            DISectionHeader(titleKey: "Results", systemImage: "magnifyingglass")
            Group {
                if let matchCount, matchCount > results.count {
                    Text("Showing \(results.count) of \(matchCount) matches, a few from each collection")
                } else {
                    Text("Matches: \(results.count)")
                }
            }
            .font(.caption)
            .foregroundStyle(DIColor.textMuted)
            ForEach(results) { entry in
                // A result must open the exact narration in its collection, not
                // just sit there: wrap it in the same value-based link the
                // collection list uses so tapping navigates within this stack.
                if let book = books.first(where: { $0.id == entry.bookID }) {
                    NavigationLink(value: HadithRoute.hadith(book, entry.canonicalID)) {
                        resultCard(entry)
                    }
                    .buttonStyle(DIPressableStyle())
                } else {
                    resultCard(entry)
                }
            }
        }
    }

    private func resultCard(_ entry: HadithEntry) -> some View {
        let bookTitle = books.first { $0.id == entry.bookID }?
            .title(languageCode: languageCode) ?? entry.bookID
        return DICard {
            VStack(alignment: .leading, spacing: DISpacing.xs) {
                HStack(spacing: DISpacing.sm) {
                    DIPillBadge(text: bookTitle, color: DIColor.primary)
                    Text(verbatim: "#\(entry.displayNumber)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DIColor.textMuted)
                    Spacer(minLength: 0)
                }
                // A search can match a script the reader is not currently in, so
                // the preview shows whatever text exists - but styled for the
                // language it actually is, never the reader's. English set in
                // Nastaliq and reversed would misrepresent it as the Urdu.
                if let preview = entry.availableText(preferring: languageCode) {
                    let style = Self.snippetStyle(for: preview.languageCode)
                    Text(verbatim: preview.text)
                        .font(style.font)
                        .foregroundStyle(DIColor.textPrimary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, style.isRTL ? .rightToLeft : .leftToRight)
                }
            }
        }
    }

    /// Typography for a snippet, chosen by the language the text actually is
    /// rather than the reader's, so a match in one script is never dressed up
    /// as another.
    private static func snippetStyle(for languageCode: String) -> (font: Font, isRTL: Bool) {
        switch languageCode {
        case "ur": return (DIFont.urduBody(scale: 0.95), true)
        case "ar": return (DIFont.quranArabic(scale: 0.62), true)
        default: return (.subheadline, false)
        }
    }

    /// Says on the row when a collection cannot be read in translation, so
    /// nobody opens 30,000 narrations to find each one "has no English
    /// translation".
    private func translationNote(for book: HadithBook) -> String? {
        if !book.hasEnglish && !book.hasUrdu { return String(localized: "Arabic only") }
        if !book.hasUrdu { return String(localized: "No Urdu translation") }
        if !book.hasEnglish { return String(localized: "No English translation") }
        return nil
    }

    // MARK: - Loading

    private func load() async {
        // In reading order: the two Sahihs and the Sunan first, the
        // Arabic-only works after them (HadithRepository.collectionOrder).
        books = (try? await dependencies.hadithRepository.books()) ?? []
        isLoading = false
        await refreshResume()
    }

    /// The collection opened last (recorded by the Read tab as it opens one)
    /// and the narration its reader saved.
    private func refreshResume() async {
        guard let bookID = HadithLastCollection.load(),
              let book = books.first(where: { $0.id == bookID }) else {
            resume = nil
            return
        }
        var number: String?
        if let canonicalID = HadithReadingPosition.load(bookID: book.id) {
            let entries = (try? await dependencies.hadithRepository.entries(canonicalIDs: [canonicalID])) ?? []
            number = entries.first?.displayNumber
        }
        resume = HadithResume(book: book, number: number)
    }
}

/// The collection the Hadith page offers to continue, and the printed number
/// of the narration it was left on.
private struct HadithResume: Equatable {
    let book: HadithBook
    let number: String?
}

// MARK: - Groups

/// The hadith collections in the three groups the Hadith page shows, in the
/// repository's reading order within each.
struct HadithCollectionGroup: Identifiable, Equatable {
    enum Kind: String, Hashable, CaseIterable {
        /// The two Sahihs and the four Sunan.
        case sahihainAndSunan
        /// Every other collection with a translation.
        case more
        /// The works with neither English nor Urdu, by the catalogue's flags.
        case arabicOnly
    }

    let kind: Kind
    let books: [HadithBook]

    var id: String { kind.rawValue }

    /// The six collections of the first group, in their canonical order.
    static let sahihainAndSunanIDs = ["bukhari", "muslim", "abudawud", "tirmidhi", "nasai", "ibnmajah"]

    var titleKey: LocalizedStringKey {
        switch kind {
        case .sahihainAndSunan: return "Sahihain and Sunan"
        case .more: return "More collections"
        case .arabicOnly: return "Arabic only"
        }
    }

    /// How many show before "Show all"; nil shows the whole group.
    var foldedCount: Int? {
        switch kind {
        case .sahihainAndSunan: return nil
        case .more: return 3
        case .arabicOnly: return 1
        }
    }

    /// True when the group holds more than it shows folded.
    var isFoldable: Bool {
        guard let foldedCount else { return false }
        return books.count > foldedCount
    }

    func visibleBooks(expanded: Bool) -> [HadithBook] {
        guard !expanded, let foldedCount, books.count > foldedCount else { return books }
        return Array(books.prefix(foldedCount))
    }

    /// The groups for `books`, leaving out any that would be empty.
    static func groups(from books: [HadithBook]) -> [HadithCollectionGroup] {
        var six: [HadithBook] = []
        var more: [HadithBook] = []
        var arabic: [HadithBook] = []
        for book in books {
            if Self.sahihainAndSunanIDs.contains(book.id) {
                six.append(book)
            } else if !book.hasEnglish && !book.hasUrdu {
                arabic.append(book)
            } else {
                more.append(book)
            }
        }
        six.sort { lhs, rhs in
            let order = HadithCollectionGroup.sahihainAndSunanIDs
            return (order.firstIndex(of: lhs.id) ?? 0) < (order.firstIndex(of: rhs.id) ?? 0)
        }
        let all: [(Kind, [HadithBook])] = [(.sahihainAndSunan, six), (.more, more), (.arabicOnly, arabic)]
        return all.compactMap { kind, list in
            list.isEmpty ? nil : HadithCollectionGroup(kind: kind, books: list)
        }
    }
}

// MARK: - Last collection

/// The collection opened last, for the Hadith page's Continue. The narration
/// in it is kept by the reader (`HadithReadingPosition`). Small, and private
/// to the device.
enum HadithLastCollection {
    private static let key = "read.hadith.lastCollection"

    static func save(_ bookID: String) {
        UserDefaults.standard.set(bookID, forKey: key)
    }

    static func load() -> String? {
        UserDefaults.standard.string(forKey: key)
    }
}
