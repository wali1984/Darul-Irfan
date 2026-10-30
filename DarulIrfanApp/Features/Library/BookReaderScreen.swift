import Observation
import SwiftUI

// The one reader for the Silsila's books and publications: the printed pages
// (`BookReaderView`, the PDF, cached for offline reading) and the text
// (`BookTextPagesView`, searchable), under a Pages | Text switch. A glass bar
// at the top carries the title and "PAGE n OF N", the text size and search
// in the book; a floating bar at the foot turns the pages, with a scrubber
// that runs right to left for an Urdu book, and Go to page. Each view keeps
// its own logic: caching, the "Preparing pages" seal, the machine-read
// notice, the page it was left on.

// MARK: - Mode

/// How a work is read: its printed pages (the PDF) or its text.
enum BookReaderMode: String, CaseIterable, Hashable, Identifiable {
    case pages
    case text

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .pages: return "Pages"
        case .text: return "Text"
        }
    }
}

// MARK: - Session

/// What the reader's bars show and ask of the page view under them: the page
/// on screen, the pages there are, a page to go to, and the PDF to share.
@Observable
@MainActor
final class BookReaderSession {
    /// The PDF page, or the printed page of the text, at the top of the screen.
    var currentPage: Int = 1
    /// The pages that can be turned to, in order: 1...N for the PDF, the
    /// printed numbers for the text (a scan skips blank pages).
    var pageNumbers: [Int] = []
    /// A page the bars asked for; the page view goes there and clears it.
    var requestedPage: Int?
    /// The cached PDF, once open, for Share.
    var shareURL: URL?
}

// MARK: - Turning pages

/// Turning the pages of a work whose pages are numbered as printed: the next
/// page is the next one there is.
enum BookPageNavigator {
    /// Where `page` sits among `pages`: its own place, or the page before it
    /// when it falls between two (or the first, before them all).
    static func index(of page: Int, in pages: [Int]) -> Int? {
        guard !pages.isEmpty else { return nil }
        if let exact = pages.firstIndex(of: page) { return exact }
        if let after = pages.firstIndex(where: { $0 > page }) { return max(0, after - 1) }
        return pages.count - 1
    }

    static func page(after page: Int, in pages: [Int]) -> Int? {
        guard let index = index(of: page, in: pages) else { return nil }
        if pages[index] > page { return pages[index] }
        return index + 1 < pages.count ? pages[index + 1] : nil
    }

    static func page(before page: Int, in pages: [Int]) -> Int? {
        guard let index = index(of: page, in: pages) else { return nil }
        if pages[index] < page { return pages[index] }
        return index > 0 ? pages[index - 1] : nil
    }

    /// The page at a scrubber position (0 for the first page).
    static func page(atPosition position: Double, in pages: [Int]) -> Int? {
        guard !pages.isEmpty, position.isFinite else { return nil }
        let index = min(max(Int(position.rounded()), 0), pages.count - 1)
        return pages[index]
    }
}

// MARK: - Reading history

/// Where a work was left, for "Keep reading": the way it was read and the
/// page there, and how many pages it has.
struct BookResume: Equatable {
    let mode: BookReaderMode
    let page: Int
    let pageCount: Int?

    /// How far through, when the number of pages is known.
    var fraction: Double? {
        guard let pageCount, pageCount > 0 else { return nil }
        return min(max(Double(page) / Double(pageCount), 0), 1)
    }
}

/// The work opened last, the way each work was read last, and how many pages
/// each has, beside the page positions the readers keep
/// (`PDFReadingPosition`, `BookReadingPosition`). Small, and private to the
/// device.
enum BookReadingHistory {
    private static let lastItemKey = "library.lastBook"

    private static func modeKey(_ itemID: String) -> String { "library.book.mode.\(itemID)" }

    private static func pageCountKey(_ itemID: String, _ mode: BookReaderMode) -> String {
        "library.book.pages.\(mode.rawValue).\(itemID)"
    }

    static func recordOpened(itemID: String, mode: BookReaderMode) {
        UserDefaults.standard.set(itemID, forKey: lastItemKey)
        UserDefaults.standard.set(mode.rawValue, forKey: modeKey(itemID))
    }

    static func lastItemID() -> String? {
        UserDefaults.standard.string(forKey: lastItemKey)
    }

    static func lastMode(itemID: String) -> BookReaderMode? {
        guard let raw = UserDefaults.standard.string(forKey: modeKey(itemID)) else { return nil }
        return BookReaderMode(rawValue: raw)
    }

    static func savePageCount(_ count: Int, itemID: String, mode: BookReaderMode) {
        guard count > 0 else { return }
        UserDefaults.standard.set(count, forKey: pageCountKey(itemID, mode))
    }

    static func pageCount(itemID: String, mode: BookReaderMode) -> Int? {
        let count = UserDefaults.standard.integer(forKey: pageCountKey(itemID, mode))
        return count > 0 ? count : nil
    }

    /// The work has a PDF to read as printed pages.
    static func hasPDF(_ item: ContentItem) -> Bool {
        item.downloadUrls.contains { $0.lowercased().hasSuffix(".pdf") }
    }

    /// Where the work was left: the way it was read last first, then the
    /// other; nil when it has not been opened.
    static func resume(itemID: String, hasPDF: Bool, hasText: Bool) -> BookResume? {
        var order: [BookReaderMode] = [.pages, .text]
        if lastMode(itemID: itemID) == .text {
            order = [.text, .pages]
        }
        for mode in order {
            let available = mode == .pages ? hasPDF : hasText
            guard available else { continue }
            let page = mode == .pages
                ? PDFReadingPosition.page(itemID: itemID)
                : BookReadingPosition.page(bookID: itemID)
            if let page {
                return BookResume(mode: mode, page: page, pageCount: pageCount(itemID: itemID, mode: mode))
            }
        }
        return nil
    }
}

// MARK: - Reader

@MainActor
struct BookReaderScreen: View {
    let item: ContentItem
    let dependencies: AppDependencies
    /// A printed page to open the text at (a search result, a surah's start).
    private let startPage: Int?
    /// Where the text size is kept; nil keeps it for this reading only.
    private let appState: AppState?

    @State private var mode: BookReaderMode
    /// The views built so far; each is kept once built, with its place.
    @State private var opened: Set<BookReaderMode>
    @State private var pdf: BookReaderSession
    @State private var text: BookReaderSession
    @State private var hasText: Bool
    @State private var scale: Double
    @State private var showsGoToPage = false
    @State private var goToPageText = ""
    @State private var showsSearch = false
    /// The scrubber's place while it is held.
    @State private var scrubPosition: Double?
    @State private var isScrubbing = false
    @Environment(\.locale) private var locale

    init(
        item: ContentItem,
        dependencies: AppDependencies,
        mode: BookReaderMode,
        startPage: Int? = nil,
        appState: AppState? = nil,
        fontScale: Double = 1
    ) {
        self.item = item
        self.dependencies = dependencies
        self.startPage = startPage
        self.appState = appState
        let first: BookReaderMode = (mode == .pages && !BookReadingHistory.hasPDF(item)) ? .text : mode
        _mode = State(initialValue: first)
        _opened = State(initialValue: [first])
        _pdf = State(initialValue: BookReaderSession())
        _text = State(initialValue: BookReaderSession())
        _hasText = State(initialValue: first == .text)
        _scale = State(initialValue: fontScale)
    }

    private var hasPDF: Bool { BookReadingHistory.hasPDF(item) }

    private var showsModeSwitch: Bool { hasPDF && hasText }

    private var activeSession: BookReaderSession { mode == .pages ? pdf : text }

    /// An Urdu or Arabic book turns its pages right to left.
    private var bookIsRightToLeft: Bool {
        let code = item.language.lowercased()
        return code.hasPrefix("ur") || code.hasPrefix("ar")
    }

    private var readsUrdu: Bool { locale.language.languageCode?.identifier == "ur" }

    var body: some View {
        ZStack {
            if opened.contains(.pages) {
                BookReaderView(item: item, dependencies: dependencies, session: pdf)
                    .modifier(BookReaderLayer(isActive: mode == .pages))
            }
            if opened.contains(.text) {
                BookTextPagesView(
                    item: item,
                    dependencies: dependencies,
                    startPage: startPage,
                    fontScale: scale,
                    session: text
                )
                .modifier(BookReaderLayer(isActive: mode == .text))
            }
        }
        .navigationTitle(Text(verbatim: item.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                titleBlock
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if mode == .pages, let url = pdf.shareURL {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel(Text("Share"))
                }
                if mode == .text {
                    textSizeMenu
                }
                if hasText {
                    Button {
                        showsSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(Text("Search in this book"))
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsModeSwitch {
                modeSwitch
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if activeSession.pageNumbers.count > 1 {
                pageBar
            }
        }
        .alert("Go to page", isPresented: $showsGoToPage) {
            TextField("Page number", text: $goToPageText)
                .keyboardType(.numberPad)
            Button("Go") {
                let digits = SearchNormalizer.normalize(goToPageText).trimmingCharacters(in: .whitespaces)
                goToPageText = ""
                if let number = Int(digits) { goTo(number) }
            }
            Button("Cancel", role: .cancel) { goToPageText = "" }
        } message: {
            if let first = activeSession.pageNumbers.first, let last = activeSession.pageNumbers.last {
                Text("Pages \(first) to \(last)")
            }
        }
        .sheet(isPresented: $showsSearch) {
            BookTextSearchView(item: item, dependencies: dependencies) { page in
                showText(at: page)
            }
        }
        .onChange(of: pdf.pageNumbers.last) { _, last in
            if let last { BookReadingHistory.savePageCount(last, itemID: item.id, mode: .pages) }
        }
        .onChange(of: text.pageNumbers.last) { _, last in
            if let last { BookReadingHistory.savePageCount(last, itemID: item.id, mode: .text) }
        }
        .task {
            BookReadingHistory.recordOpened(itemID: item.id, mode: mode)
            if !hasText {
                let count = (try? await dependencies.contentRepository.bookPageCount(bookID: item.id)) ?? 0
                hasText = count > 0
            }
        }
    }

    // MARK: - Top bar

    private var titleBlock: some View {
        VStack(spacing: 0) {
            if let urdu = item.titleUrdu, !urdu.isEmpty, bookIsRightToLeft {
                Text(verbatim: urdu)
                    .font(DIFont.urduBody(scale: 0.85))
                    .lineLimit(1)
            } else {
                Text(verbatim: item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            pageCaption
        }
        .foregroundStyle(DIColor.textPrimary)
        .frame(maxWidth: 220)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var pageCaption: some View {
        if let last = activeSession.pageNumbers.last {
            Text("Page \(displayedPage) of \(last)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .tracking(readsUrdu ? 0 : 0.6)
                .textCase(.uppercase)
                .foregroundStyle(DIColor.textMuted)
                .lineLimit(1)
        }
    }

    /// The page on screen, or the one under the scrubber while it is held.
    private var displayedPage: Int {
        let session = activeSession
        if let scrubPosition,
           let page = BookPageNavigator.page(atPosition: scrubPosition, in: session.pageNumbers) {
            return page
        }
        return session.currentPage
    }

    private var modeSwitch: some View {
        DISegmentedControl(
            items: BookReaderMode.allCases,
            title: { $0.title },
            selection: modeBinding
        )
        .frame(maxWidth: 280)
        .padding(.horizontal, DISpacing.md)
        .padding(.vertical, DISpacing.sm)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: Rectangle())
    }

    private var modeBinding: Binding<BookReaderMode> {
        Binding(
            get: { mode },
            set: { choose($0) }
        )
    }

    private func choose(_ next: BookReaderMode) {
        opened.insert(next)
        mode = next
        BookReadingHistory.recordOpened(itemID: item.id, mode: next)
    }

    /// Aa: the reader's text size, kept in Settings when the reader came
    /// with the app's settings.
    private var textSizeMenu: some View {
        Menu {
            Picker("Text Size", selection: scaleBinding) {
                ForEach(ReaderFontScale.allCases) { option in
                    Text(LocalizedStringKey(option.bookReaderName)).tag(option)
                }
            }
        } label: {
            Text(verbatim: "Aa")
                .font(.body.weight(.heavy))
                .foregroundStyle(ReadPalette.emeraldInk)
        }
        .accessibilityLabel(Text("Text Size"))
    }

    private var scaleBinding: Binding<ReaderFontScale> {
        Binding(
            get: { ReaderFontScale(rawValue: scale) ?? .standard },
            set: { option in
                scale = option.rawValue
                if let appState {
                    Task { await appState.updateSettings { $0.readerFontScale = option } }
                }
            }
        )
    }

    // MARK: - Bottom bar

    private var pageBar: some View {
        let numbers = activeSession.pageNumbers
        let current = activeSession.currentPage
        let lastPosition = Double(max(numbers.count - 1, 1))
        return HStack(spacing: 10) {
            turnButton(
                systemImage: "chevron.backward",
                label: "Previous page",
                isEnabled: BookPageNavigator.page(before: current, in: numbers) != nil
            ) {
                turn(forward: false)
            }
            VStack(spacing: 6) {
                Slider(
                    value: scrubBinding,
                    in: 0...lastPosition,
                    onEditingChanged: { editing in
                        if editing {
                            isScrubbing = true
                        } else {
                            isScrubbing = false
                            commitScrub()
                        }
                    }
                )
                .tint(DIColor.accent)
                // Drawn left to right and then mirrored for a book read right
                // to left, so page 1 and the pages read sit at the right
                // whether or not the slider would mirror itself.
                .environment(\.layoutDirection, .leftToRight)
                .scaleEffect(x: bookIsRightToLeft ? -1 : 1, y: 1)
                .accessibilityLabel(Text("Page"))
                .accessibilityValue(Text("Page \(displayedPage) of \(numbers.last ?? 1)"))
                HStack(spacing: DISpacing.xs) {
                    Text(verbatim: "\(numbers.first ?? 1)")
                    Spacer(minLength: DISpacing.xs)
                    Button {
                        showsGoToPage = true
                    } label: {
                        Text("Go to page")
                            .foregroundStyle(ReadPalette.emeraldInk)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: DISpacing.xs)
                    Text(verbatim: "\(numbers.last ?? 1)")
                }
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(DIColor.textMuted)
            }
            turnButton(
                systemImage: "chevron.forward",
                label: "Next page",
                isEnabled: BookPageNavigator.page(after: current, in: numbers) != nil
            ) {
                turn(forward: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
        .overlay(Capsule(style: .continuous).stroke(ReadPalette.glassEdge, lineWidth: 1))
        .shadow(color: ReadPalette.softShadow, radius: 20, y: 14)
        .padding(.horizontal, 14)
        .padding(.bottom, DISpacing.sm)
        // An Urdu book runs right to left: page 1 at the right, the next
        // page to the left.
        .environment(\.layoutDirection, bookIsRightToLeft ? .rightToLeft : .leftToRight)
    }

    private func turnButton(
        systemImage: String,
        label: LocalizedStringKey,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.bold))
                .foregroundStyle(ReadPalette.emeraldInk)
                .frame(width: 44, height: 44)
                .background(Circle().fill(ReadPalette.chipTrack))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(Text(label))
    }

    /// The scrubber, in page positions (0 for the first page).
    private var scrubBinding: Binding<Double> {
        Binding(
            get: {
                if let scrubPosition { return scrubPosition }
                let session = activeSession
                return Double(BookPageNavigator.index(of: session.currentPage, in: session.pageNumbers) ?? 0)
            },
            set: { value in
                scrubPosition = value
                // VoiceOver moves the scrubber without holding it: go at once.
                if !isScrubbing { commitScrub() }
            }
        )
    }

    private func commitScrub() {
        guard let position = scrubPosition else { return }
        scrubPosition = nil
        let session = activeSession
        guard let page = BookPageNavigator.page(atPosition: position, in: session.pageNumbers),
              page != session.currentPage else { return }
        session.requestedPage = page
        session.currentPage = page
    }

    private func turn(forward: Bool) {
        let session = activeSession
        let target = forward
            ? BookPageNavigator.page(after: session.currentPage, in: session.pageNumbers)
            : BookPageNavigator.page(before: session.currentPage, in: session.pageNumbers)
        guard let target else { return }
        DIHaptics.light()
        session.requestedPage = target
        session.currentPage = target
    }

    private func goTo(_ number: Int) {
        let session = activeSession
        guard let first = session.pageNumbers.first, let last = session.pageNumbers.last else { return }
        let page = min(max(number, first), last)
        session.requestedPage = page
        if session.pageNumbers.contains(page) {
            session.currentPage = page
        }
    }

    /// A result of search in the book: the text, at that page.
    private func showText(at page: Int) {
        opened.insert(.text)
        text.requestedPage = page
        mode = .text
        BookReadingHistory.recordOpened(itemID: item.id, mode: .text)
    }
}

/// Keeps a page view alive behind the other: hidden, untouchable, unheard.
private struct BookReaderLayer: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .zIndex(isActive ? 1 : 0)
    }
}

private extension ReaderFontScale {
    var bookReaderName: String {
        switch self {
        case .small: return "Small"
        case .standard: return "Standard"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }
}

// MARK: - Search in the book

/// Search in one book's text: the pages that hold the words, found as the
/// app's search finds them (letter forms folded, vowel marks ignored, any
/// case), and a short passage around the first match taken from the page as
/// it is written.
enum BookTextSearch {
    /// One page's text, folded for comparing.
    struct Entry: Sendable {
        let page: Int
        let text: String
    }

    static func folded(_ text: String) -> String {
        SearchNormalizer.normalize(text).lowercased()
    }

    static func index(_ pages: [BookPage]) -> [Entry] {
        pages.map { Entry(page: $0.page, text: folded($0.text)) }
    }

    /// The pages whose text holds `query`, in page order.
    static func pages(matching query: String, in entries: [Entry]) -> [Int] {
        let needle = folded(query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return entries.filter { $0.text.contains(needle) }.map(\.page)
    }

    /// About `radius` letters either side of the first match, whole words,
    /// from the page as written; nil when the page does not hold `query`.
    static func passage(for query: String, in text: String, radius: Int = 60) -> String? {
        let needle = Array(folded(query).trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars)
        guard !needle.isEmpty else { return nil }
        let original = Array(text.unicodeScalars)
        // The page folded letter by letter, remembering where each came from.
        var foldedScalars: [Unicode.Scalar] = []
        var origins: [Int] = []
        foldedScalars.reserveCapacity(original.count)
        origins.reserveCapacity(original.count)
        for (offset, scalar) in original.enumerated() {
            for piece in folded(String(scalar)).unicodeScalars {
                foldedScalars.append(piece)
                origins.append(offset)
            }
        }
        guard let start = firstMatch(of: needle, in: foldedScalars) else { return nil }
        let matchStart = origins[start]
        let matchEnd = origins[start + needle.count - 1]
        var lower = max(0, matchStart - radius)
        var upper = min(original.count, matchEnd + 1 + radius)
        // Whole words at either end, looking a little way for a space.
        var steps = 0
        while lower > 0, steps < 20, !original[lower - 1].properties.isWhitespace {
            lower -= 1
            steps += 1
        }
        steps = 0
        while upper < original.count, steps < 20, !original[upper].properties.isWhitespace {
            upper += 1
            steps += 1
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: original[lower..<upper])
        var passage = String(view)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if lower > 0 { passage = "…" + passage }
        if upper < original.count { passage += "…" }
        return passage
    }

    private static func firstMatch(of needle: [Unicode.Scalar], in haystack: [Unicode.Scalar]) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        let last = haystack.count - needle.count
        var index = 0
        while index <= last {
            if haystack[index] == needle[0] {
                var offset = 1
                while offset < needle.count && haystack[index + offset] == needle[offset] {
                    offset += 1
                }
                if offset == needle.count { return index }
            }
            index += 1
        }
        return nil
    }
}

/// Search in this book: a field, and the pages that hold the words with a
/// passage from each. Choosing one opens the text at that page.
@MainActor
struct BookTextSearchView: View {
    let item: ContentItem
    let dependencies: AppDependencies
    let onPick: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFieldFocused: Bool
    @State private var query = ""
    @State private var entries: [BookTextSearch.Entry] = []
    @State private var pagesByNumber: [Int: String] = [:]
    @State private var results: [Int] = []
    /// The words `results` were found for; the field may already say more.
    @State private var resultTerm = ""
    @State private var isPreparing = true
    @State private var searchTask: Task<Void, Never>?

    init(item: ContentItem, dependencies: AppDependencies, onPick: @escaping (Int) -> Void) {
        self.item = item
        self.dependencies = dependencies
        self.onPick = onPick
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                field
                content
            }
            .diScreenBackground()
            .navigationTitle("Search in this book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
        .tint(DIColor.primary)
        .onAppear { isFieldFocused = true }
        .onChange(of: query) { _, _ in scheduleSearch() }
        .task { await prepare() }
    }

    private var field: some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(isFieldFocused ? DIColor.primary : DIColor.textMuted)
                .accessibilityHidden(true)
            TextField("Search in this book", text: $query)
                .focused($isFieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(DIColor.textPrimary)
            if !query.isEmpty {
                Button {
                    DIHaptics.light()
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DIColor.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search text")
            }
        }
        .padding(.horizontal, DISpacing.md)
        .frame(minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                .fill(DIColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                .stroke(DIColor.border, lineWidth: 1)
        )
        .padding(.horizontal, DISpacing.md)
        .padding(.top, DISpacing.md)
        .padding(.bottom, DISpacing.xs)
    }

    @ViewBuilder
    private var content: some View {
        if isPreparing {
            ProgressView()
                .tint(DIColor.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if trimmedQuery.count < 2 {
            DIEmptyState(systemImage: "text.magnifyingglass", titleKey: "Search in this book")
                .frame(maxHeight: .infinity, alignment: .top)
        } else if results.isEmpty {
            DIEmptyState(systemImage: "magnifyingglass", titleKey: "No matches in this book")
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            List {
                Section {
                    ForEach(results, id: \.self) { page in
                        Button {
                            pick(page)
                        } label: {
                            resultRow(page)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(DIColor.surface)
                    }
                } header: {
                    Text("Matches: \(results.count)")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private func resultRow(_ page: Int) -> some View {
        let pageText = pagesByNumber[page] ?? ""
        let passage = BookTextSearch.passage(for: resultTerm, in: pageText)
        let rightToLeft = ScriptDirection.isRightToLeft(passage ?? pageText, fallbackLanguage: item.language)
        return VStack(alignment: .leading, spacing: DISpacing.xs) {
            Text("Page \(page)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ReadPalette.emeraldInk)
            if let passage {
                Text(verbatim: passage)
                    .font(rightToLeft ? DIFont.urduBody(scale: 0.9) : .subheadline)
                    .foregroundStyle(DIColor.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
            }
        }
        .padding(.vertical, DISpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func pick(_ page: Int) {
        DIHaptics.soft()
        onPick(page)
        dismiss()
    }

    /// The book's pages, folded once for comparing, off the main thread.
    private func prepare() async {
        guard isPreparing else { return }
        let loaded = (try? await dependencies.contentRepository.bookPages(bookID: item.id)) ?? []
        let readable = loaded.filter { !$0.text.isEmpty }
        let folded = await Task.detached(priority: .userInitiated) {
            BookTextSearch.index(readable)
        }.value
        var texts: [Int: String] = [:]
        for page in readable {
            texts[page.page] = page.text
        }
        pagesByNumber = texts
        entries = folded
        isPreparing = false
        scheduleSearch()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let term = trimmedQuery
        guard !isPreparing, term.count >= 2 else {
            results = []
            resultTerm = ""
            return
        }
        let index = entries
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                BookTextSearch.pages(matching: term, in: index)
            }.value
            guard !Task.isCancelled else { return }
            results = found
            resultTerm = term
        }
    }
}
