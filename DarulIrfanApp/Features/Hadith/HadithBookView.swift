import SwiftUI

/// One collection, paged. Each hadith shows its Arabic alongside the reader's
/// language, using the same RTL and script handling as the Quran reader.
@MainActor
struct HadithBookView: View {
    let book: HadithBook
    let repository: any HadithRepositoryProtocol
    let appState: AppState
    /// When set, the reader opens scrolled to this narration (canonicalID —
    /// printed numbers repeat in some collections) instead of at the top.
    /// Also suppresses the cover page: a tapped search result should land on
    /// the hadith, not on a splash.
    var initialHadith: String? = nil
    /// The cover page shown briefly when a collection is opened normally.
    @State private var showsCover = false
    /// Native table of contents. A normal collection open proceeds cover ->
    /// contents -> selected kitab; deep links bypass both and land on the row.
    @State private var showsContents = false
    /// Guards against the cover re-appearing when the view's task re-runs
    /// (e.g. returning from a pushed screen).
    @State private var hasShownCover = false

    @State private var entries: [HadithEntry] = []
    /// Rows that open a kitab or a chapter in the loaded listing, and so carry
    /// its heading. Worked out whenever the listing changes.
    @State private var bookHeadingRows: Set<String> = []
    @State private var chapterHeadingRows: Set<String> = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var isLoadingEarlier = false
    @State private var reachedEnd = false
    @State private var showsArabic = true
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    /// Search results mix books, so the book (kitab) headers that group the
    /// ordinary listing are suppressed while showing them.
    @State private var isSearchResults = false
    /// True while a tapped search result is clearing the search box and
    /// loading its own window, so the cleared box's onChange must not stomp
    /// the jump with a restore-to-top.
    @State private var isJumpingToResult = false
    /// Offset the next page load starts at. Tracked explicitly (not derived
    /// from `entries.count`) so paging is correct even when the first page
    /// begins partway into the book — as it does when opening to a hadith.
    @State private var nextOffset = 0
    /// Offset of the first loaded row: above it, earlier narrations are loaded
    /// when the reader scrolls up, so a jump into a book can be read back.
    @State private var firstOffset = 0
    /// The row to scroll to once it is loaded, then briefly highlight.
    @State private var pendingScrollTarget: String?
    @State private var highlightedID: String?
    /// The row to keep in place after earlier rows are added above it.
    @State private var anchorAfterPrepend: String?
    /// The row at the top of the screen, saved so the collection reopens there.
    @State private var topRowID: String?
    /// A tapped isnad narrator, presented as a bio sheet (nil = none open).
    @State private var selectedNarrator: NarratorRef?

    @ScaledMetric(relativeTo: .body) private var englishBaseSize: CGFloat = 17

    private static let pageSize = 50

    /// The content language: "System" on an Urdu phone reads in Urdu, as the
    /// Quran reader does.
    private var languageCode: String { appState.settings.language.contentLanguageCode }
    /// Same reader text-size setting the Quran uses, so both scale together.
    private var fontScale: Double { appState.settings.readerFontScale.rawValue }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DISpacing.md) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(DISpacing.xl)
                    } else if entries.isEmpty && isSearchResults {
                        DIEmptyState(
                            systemImage: "magnifyingglass",
                            titleKey: "No hadith match that search",
                            messageKey: "Try a different word or a shorter phrase."
                        )
                    } else if entries.isEmpty {
                        DIEmptyState(
                            systemImage: "book.closed",
                            titleKey: "This collection is not on your device yet",
                            messageKey: "It will arrive with the next content update."
                        )
                    } else {
                        Toggle(isOn: $showsArabic) {
                            Text("Show Arabic")
                                .font(.subheadline)
                                .foregroundStyle(DIColor.textPrimary)
                        }
                        .tint(DIColor.primary)
                        .padding(.horizontal, DISpacing.xs)

                        if isLoadingEarlier {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(DISpacing.md)
                        }

                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: DISpacing.sm) {
                                if !isSearchResults, bookHeadingRows.contains(entry.id) {
                                    sectionHeader(for: entry)
                                }
                                if !isSearchResults, chapterHeadingRows.contains(entry.id) {
                                    chapterHeader(for: entry)
                                }
                                if isSearchResults {
                                    // A result must land the reader ON the
                                    // narration, in its reading context.
                                    Button {
                                        jump(to: entry)
                                    } label: {
                                        hadithCard(entry)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    hadithCard(entry)
                                }
                            }
                            .id(entry.id)
                            .padding(.vertical, highlightedID == entry.id ? DISpacing.xs : 0)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(DIColor.accent.opacity(highlightedID == entry.id ? 0.18 : 0))
                            )
                            .onAppear {
                                if entry.id == entries.last?.id { Task { await loadMore() } }
                            }
                        }

                        if isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(DISpacing.md)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(DISpacing.md)
                .diResponsiveWidth()
            }
            .scrollPosition(id: $topRowID, anchor: .top)
            .onChange(of: topRowID) { _, id in
                guard let id, !isSearchResults else { return }
                HadithReadingPosition.save(id, bookID: book.id)
                // Scrolled up to the first row loaded: bring in the ones
                // before it.
                if id == entries.first?.id { Task { await loadEarlier() } }
            }
            .onChange(of: pendingScrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(target, anchor: .center)
                    highlightedID = target
                }
                // Clear the target so a later change re-triggers, and fade the
                // highlight after a moment.
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { highlightedID = nil }
                    pendingScrollTarget = nil
                }
            }
            .onChange(of: anchorAfterPrepend) { _, anchor in
                guard let anchor else { return }
                proxy.scrollTo(anchor, anchor: .top)
                anchorAfterPrepend = nil
            }
        }
        .diScreenBackground()
        .sheet(item: $selectedNarrator) { ref in
            NarratorBioSheet(narratorId: ref.id, repository: repository, appState: appState)
        }
        .sheet(isPresented: $showsContents) {
            HadithContentsView(book: book, languageCode: languageCode) { section in
                showsContents = false
                if let section {
                    Task { await jumpToSection(section.number) }
                } else {
                    Task {
                        await loadWindow(startingAt: 0)
                        pendingScrollTarget = entries.first?.canonicalID
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: book.title(languageCode: languageCode)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsContents = true
                } label: {
                    Label("Contents", systemImage: "list.bullet.rectangle")
                }
                .accessibilityHint("Browse the books in this collection")
            }
        }
        .searchable(text: $searchText, prompt: Text("Search in this collection"))
        .onChange(of: searchText) { _, term in
            searchTask?.cancel()
            let query = term.trimmingCharacters(in: .whitespaces)
            guard query.count >= 2 else {
                // Leaving results returns to the narration read before the
                // search; short text on the listing changes nothing. A tapped
                // result mid-jump owns the listing.
                if isSearchResults && !isJumpingToResult {
                    Task { await restorePagedListing() }
                }
                return
            }
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                let found = (try? await repository.search(
                    query, bookID: book.id, limit: 200
                )) ?? []
                guard !Task.isCancelled else { return }
                entries = found
                isSearchResults = true
                reachedEnd = true          // results are not paged
                firstOffset = 0
                isLoading = false
            }
        }
        .task {
            // The cover shows on a normal open only: a tapped search result,
            // or a collection the reader is returning to, must land on its
            // hadith, not a splash. Content loads beneath it, so dismissal
            // reveals a ready page.
            let resume = initialHadith == nil ? HadithReadingPosition.load(bookID: book.id) : nil
            if initialHadith == nil && resume == nil && !hasShownCover {
                hasShownCover = true
                showsCover = true
            }
            await loadFirstPage(target: initialHadith ?? resume, highlights: initialHadith != nil)
        }
        .overlay { if showsCover { coverPage } }
    }

    // MARK: - Cover page

    /// A brief cover when a collection opens — the book's name as a title
    /// page, in the tradition of printed hadith books — auto-advancing to the
    /// narrations after three seconds, or on tap.
    private var coverPage: some View {
        ZStack {
            LinearGradient(
                colors: [DIColor.primary, DIColor.primary.opacity(0.82)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: DISpacing.lg) {
                Spacer()
                Text(verbatim: "۞")
                    .font(.system(size: 44))
                    .foregroundStyle(DIColor.accent)
                Text(verbatim: book.titleUrdu)
                    .font(DIFont.quranArabic(scale: fontScale * 1.6))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .rightToLeft)
                Text(verbatim: book.titleEnglish)
                    .font(DIFont.heading)
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                VStack(spacing: DISpacing.xs) {
                    Text("\(book.hadithCount) narrations")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                    if book.sectionCount > 0 {
                        Text("\(book.sectionCount) books")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer()
                Text("Tap to continue")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.bottom, DISpacing.xl)
            }
            .padding(DISpacing.lg)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismissCoverAndShowContents() }
        .task {
            try? await Task.sleep(for: .seconds(3))
            guard showsCover else { return }
            dismissCoverAndShowContents()
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: book.titleEnglish))
        .accessibilityHint(Text("Opens the narrations"))
    }

    private func hadithCard(_ entry: HadithEntry) -> some View {
        DICard(
            background: DIColor.primary.opacity(0.055),
            borderColor: DIColor.primary.opacity(0.45),
            borderWidth: 1.5
        ) {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) {
                    // The number exactly as the collection prints it, including
                    // sub-numbers such as 402.2 — never rounded to an integer.
                    DIPillBadge(text: "#\(entry.displayNumber)", color: DIColor.primary)
                    Spacer(minLength: 0)
                }

                if showsArabic {
                    let segments = entry.arabicDisplaySegments()
                    if !segments.isEmpty {
                        // One Text so the Arabic stays connected and correctly
                        // shaped; the isnad narrators and any quoted verse are
                        // links (rendered in our green via `.tint`), the matn is
                        // plain (near-black). Taps are routed by `openURL`.
                        Text(arabicAttributed(from: segments))
                            .font(DIFont.quranArabic(scale: fontScale * 1.15))
                            .lineSpacing(CGFloat(18 * fontScale))
                            .foregroundStyle(DIColor.textPrimary)
                            .tint(DIColor.primary)
                            .diGoldGlow(radius: 5, opacity: 0.18)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .environment(\.layoutDirection, .rightToLeft)
                            .environment(\.openURL, OpenURLAction { url in
                                handleArabicTap(url)
                                return .handled
                            })
                        Divider().overlay(DIColor.border)
                    }
                }

                // Strictly the reader's own language. No cross-language
                // fallback: English prose set in Nastaliq and laid out
                // right-to-left would read as though it were the Urdu
                // translation, and repeating the Arabic would present the
                // source text as its own translation. A gap is shown as a gap.
                if languageCode == "ur", entry.urduSanad != nil || entry.urduText != nil {
                    urduSplitView(entry)
                } else if let text = entry.text(languageCode: languageCode) {
                    if languageCode == "ur" {
                        Text(verbatim: text)
                            .font(DIFont.urduBody(scale: fontScale))
                            .lineSpacing(CGFloat(6 * fontScale))
                            .foregroundStyle(DIColor.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .environment(\.layoutDirection, .rightToLeft)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(verbatim: text)
                            .font(.system(size: englishBaseSize * fontScale))
                            .lineSpacing(CGFloat(5 * fontScale))
                            .foregroundStyle(DIColor.textPrimary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    missingTranslationNote
                }

                if entry.isMachineTranslated(languageCode: languageCode) {
                    machineDraftNote
                } else if entry.isProvisional(languageCode: languageCode) {
                    provisionalNote
                }

                referenceBlock(entry)
            }
        }
    }

    /// The citation block shown beneath each narration: the collection
    /// reference (with its exact printed number, sub-numbers and all), when
    /// the source carries it the in-book "Book N, Hadith M", and every grading
    /// the source prints. All of them: the graders disagree, and showing only
    /// the first - alphabetically - hid a Da'if behind a Sahih.
    @ViewBuilder
    private func referenceBlock(_ entry: HadithEntry) -> some View {
        Divider().overlay(DIColor.border)
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(book.title(languageCode: languageCode)) \(entry.displayNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DIColor.textMuted)
            if let refBook = entry.sourceBook, let hadithNumber = entry.sourceHadith {
                // The book as the source prints it: Sunan an-Nasa'i's "35b",
                // not the stand-in number it is stored under.
                let bookLabel = book.section(number: refBook)?.displayNumber ?? String(refBook)
                Text("In-book reference: Book \(bookLabel), Hadith \(hadithNumber)")
                    .font(.caption2)
                    .foregroundStyle(DIColor.textMuted)
            }
            if let grades = entry.grades, !grades.isEmpty {
                Text("Grading")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DIColor.accent)
                    .padding(.top, 2)
                ForEach(grades, id: \.self) { grade in
                    Text(verbatim: grade)
                        .font(.caption2)
                        .foregroundStyle(DIColor.textMuted)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Builds the Arabic as one attributed string: isnad narrators and quoted
    /// verses become links (shown in our green via the Text's `.tint`), the matn
    /// stays plain. Kept as a single Text so Arabic shaping and RTL are intact.
    private func arabicAttributed(from segments: [HadithSegment]) -> AttributedString {
        var out = AttributedString()
        for (index, seg) in segments.enumerated() {
            var run = AttributedString(seg.text)
            switch seg.kind {
            case .isnad:
                // The unnamed narrator ("a man", "someone") has no biography
                // to open, so that span stays plain text, like the matn.
                if let nid = seg.linkedNarratorID, let url = URL(string: "narrator:\(nid)") {
                    run.link = url
                }
            case .verse:
                if let surah = seg.surah {
                    let a = seg.ayahStart ?? 1
                    let b = seg.ayahEnd ?? a
                    if let url = URL(string: "diquran:\(surah)/\(a)/\(b)") { run.link = url }
                }
            case .matn:
                break
            }
            out.append(run)
            if index < segments.count - 1 { out.append(AttributedString(" ")) }
        }
        return out
    }

    /// Routes a tap on a coloured Arabic span. Narrator → native bio sheet;
    /// verse → the app's own Quran reader, switching to the Read tab when the
    /// hadith is shown elsewhere (Today, a topic). No external links.
    private func handleArabicTap(_ url: URL) {
        switch url.scheme {
        case "narrator":
            let raw = url.absoluteString.replacingOccurrences(of: "narrator:", with: "")
            if let id = Int(raw) { selectedNarrator = NarratorRef(id: id) }
        case "diquran":
            let raw = url.absoluteString.replacingOccurrences(of: "diquran:", with: "")
            let parts = raw.split(separator: "/").compactMap { Int($0) }
            guard let surah = parts.first else { return }
            let ayah = parts.count > 1 ? parts[1] : nil
            DeepLinkRouter.shared.open(.quranAyah(surah: surah, ayah: ayah))
        default:
            break
        }
    }

    /// The Urdu shown with its chain (isnad) in grey above the narration text,
    /// mirroring the Arabic — both in the app's Urdu face, right-to-left.
    @ViewBuilder
    private func urduSplitView(_ entry: HadithEntry) -> some View {
        VStack(alignment: .trailing, spacing: DISpacing.xs) {
            if let sanad = entry.urduSanad, !sanad.isEmpty {
                Text(verbatim: sanad)
                    .font(DIFont.urduBody(scale: fontScale * 0.92))
                    .lineSpacing(CGFloat(6 * fontScale))
                    .foregroundStyle(DIColor.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, .rightToLeft)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let matn = entry.urduText, !matn.isEmpty {
                Text(verbatim: matn)
                    .font(DIFont.urduBody(scale: fontScale))
                    .lineSpacing(CGFloat(6 * fontScale))
                    .foregroundStyle(DIColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, .rightToLeft)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Headings

    /// Works out which rows carry a kitab or chapter heading. A kitab heading
    /// opens a run of its book's narrations. A single row inside another
    /// book that carries a different book's number (the source mislabels a
    /// few) neither gets that book's heading nor breaks the run it sits in,
    /// which used to repeat both headings in the middle of a book.
    private func refreshHeadings() {
        var books: Set<String> = []
        var chapters: Set<String> = []
        var currentBook: Int?
        var previousChapter: String?
        for index in entries.indices {
            let entry = entries[index]
            if let number = entry.sourceBook {
                let before = index > 0 ? entries[index - 1].sourceBook : nil
                let after = index + 1 < entries.count ? entries[index + 1].sourceBook : nil
                let isStray = index > 0 && index + 1 < entries.count
                    && number != before && number != after
                    && (book.section(number: number)?.hadithCount ?? 2) > 1
                if !isStray, number != currentBook {
                    books.insert(entry.id)
                    currentBook = number
                }
            }
            let chapter = Self.chapterKey(entry)
            if let chapter, chapter != previousChapter { chapters.insert(entry.id) }
            previousChapter = chapter
        }
        bookHeadingRows = books
        chapterHeadingRows = chapters
    }

    private static func chapterKey(_ entry: HadithEntry) -> String? {
        let title = entry.chapterTitleEnglish ?? entry.chapterTitleArabic ?? entry.chapterTitleUrdu
        guard let title, !title.isEmpty else { return nil }
        return "\(entry.sourceBook ?? -1)|\(entry.chapterNumber ?? -1)|\(title)"
    }

    /// A book (kitab) heading: its number (a collection's unnumbered opening
    /// book has none), its name in the reader's language, and its Arabic name
    /// in the Quran face.
    @ViewBuilder
    private func sectionHeader(for entry: HadithEntry) -> some View {
        if let number = entry.sourceBook {
            let section = book.section(number: number)
            let title = section?.title(languageCode: languageCode) ?? ""
            VStack(alignment: .leading, spacing: 2) {
                if let bookLabel = book.printedSectionNumber(number) {
                    Text("Book \(bookLabel)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DIColor.accent)
                }
                if !title.isEmpty {
                    Text(verbatim: title)
                        .font(languageCode == "ur" ? DIFont.urduBody(scale: 1.05) : DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                }
                if let arabic = section?.titleArabic, !arabic.isEmpty, arabic != title {
                    Text(verbatim: arabic)
                        .font(DIFont.quranArabic(scale: fontScale * 0.7))
                        .foregroundStyle(DIColor.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DISpacing.sm)
            .padding(.bottom, DISpacing.xs)
        }
    }

    /// The chapter (bab) a run of narrations sits under - in Hisn al-Muslim
    /// the occasion each supplication is for. In Urdu the Arabic heading is
    /// shown where the pack has no Urdu one, rather than the English.
    @ViewBuilder
    private func chapterHeader(for entry: HadithEntry) -> some View {
        let urdu = entry.chapterTitleUrdu.flatMap { $0.isEmpty ? nil : $0 }
        let arabic = entry.chapterTitleArabic.flatMap { $0.isEmpty ? nil : $0 }
        let english = entry.chapterTitleEnglish.flatMap { $0.isEmpty ? nil : $0 }
        VStack(alignment: .leading, spacing: 2) {
            if languageCode == "ur" {
                if let heading = urdu ?? arabic {
                    Text(verbatim: heading)
                        .font(DIFont.urduBody(scale: 0.95))
                        .foregroundStyle(DIColor.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            } else {
                if let english {
                    Text(verbatim: english)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DIColor.primary)
                }
                if let arabic {
                    Text(verbatim: arabic)
                        .font(DIFont.quranArabic(scale: fontScale * 0.6))
                        .foregroundStyle(DIColor.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, DISpacing.xs)
    }

    /// Shown when this narration has no text in the reader's language. Says so
    /// plainly rather than substituting another language's text.
    private var missingTranslationKey: LocalizedStringKey {
        switch languageCode {
        case "ur": return "This narration has no Urdu translation"
        case "ar": return "This narration has no Arabic text"
        default: return "This narration has no English translation"
        }
    }

    /// Shown beneath a translation that is still an unreviewed machine draft.
    /// Sacred text carries its provenance visibly: a reader must be able to
    /// tell a reviewed translation from one awaiting scholarly review without
    /// leaving the page.
    private var machineDraftNote: some View {
        Label("Machine translation — pending scholarly review", systemImage: "exclamationmark.triangle")
            .font(.caption2)
            .foregroundStyle(DIColor.textMuted)
            .frame(maxWidth: .infinity, alignment: languageCode == "ur" ? .trailing : .leading)
    }

    /// Beneath a translation taken from a source that has not been reviewed
    /// (the provisional Urdu of Mishkat and part of Sunan an-Nasa'i).
    private var provisionalNote: some View {
        Label("Provisional translation — pending scholarly review", systemImage: "exclamationmark.triangle")
            .font(.caption2)
            .foregroundStyle(DIColor.textMuted)
            .frame(maxWidth: .infinity, alignment: languageCode == "ur" ? .trailing : .leading)
    }

    private var missingTranslationNote: some View {
        Text(missingTranslationKey)
            .font(.footnote)
            .italic()
            .foregroundStyle(DIColor.textMuted)
            .frame(maxWidth: .infinity, alignment: languageCode == "ur" ? .trailing : .leading)
    }

    // MARK: - Loading

    /// Leaves search mode and opens the reader at this narration, exactly as
    /// a cross-collection search result does.
    private func jump(to entry: HadithEntry) {
        isJumpingToResult = true
        searchTask?.cancel()
        searchText = ""
        Task {
            let index = (try? await repository.readingIndex(
                bookID: book.id, canonicalID: entry.canonicalID)) ?? 0
            await loadWindow(startingAt: max(0, index - 6))
            pendingScrollTarget = entry.canonicalID
            isJumpingToResult = false
        }
    }

    /// Opens the first narration in the selected kitab. The repository lookup
    /// uses collection id + source book and returns a canonical id, avoiding
    /// repeated display-number collisions across books.
    private func jumpToSection(_ sourceBook: Int) async {
        guard let entry = try? await repository.firstEntry(
            bookID: book.id, sourceBook: sourceBook
        ) else { return }
        jump(to: entry)
    }

    private func dismissCoverAndShowContents() {
        withAnimation(.easeOut(duration: 0.35)) { showsCover = false }
        guard initialHadith == nil else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(380))
            showsContents = true
        }
    }

    /// Opening at a narration (a tapped search result, or where the reader
    /// left the collection) starts the listing on the page that holds it and
    /// scrolls there; only a tapped one is highlighted.
    private func loadFirstPage(target: String?, highlights: Bool) async {
        guard entries.isEmpty else { return }
        if let target,
           let index = try? await repository.readingIndex(bookID: book.id, canonicalID: target) {
            await loadWindow(startingAt: max(0, index - 6))
            // The target is a canonicalID, which is exactly what each row's
            // scroll id is — scrollTo used to be handed the printed number
            // here, which matches no row, so the jump silently did nothing.
            if highlights {
                pendingScrollTarget = target
            } else {
                anchorAfterPrepend = target
            }
            return
        }
        await loadWindow(startingAt: 0)
    }

    /// Loads a page beginning at `offset` and sets paging to continue from its
    /// end. Rows before `offset` load when the reader scrolls up to them.
    private func loadWindow(startingAt offset: Int) async {
        let page = (try? await repository.entries(
            bookID: book.id, limit: Self.pageSize, offset: offset
        )) ?? []
        entries = page
        firstOffset = offset
        nextOffset = offset + page.count
        isSearchResults = false
        reachedEnd = page.count < Self.pageSize
        isLoading = false
        refreshHeadings()
    }

    /// Clearing the search box returns to the ordinary paged listing.
    private func restorePagedListing() async {
        if let saved = HadithReadingPosition.load(bookID: book.id),
           let index = try? await repository.readingIndex(bookID: book.id, canonicalID: saved) {
            await loadWindow(startingAt: max(0, index - 6))
            anchorAfterPrepend = saved
            return
        }
        await loadWindow(startingAt: 0)
    }

    private func loadMore() async {
        guard !isLoadingMore, !reachedEnd, !isSearchResults else { return }
        isLoadingMore = true
        let next = (try? await repository.entries(
            bookID: book.id, limit: Self.pageSize, offset: nextOffset
        )) ?? []
        if next.isEmpty || next.count < Self.pageSize { reachedEnd = true }
        let known = Set(entries.map(\.id))
        entries.append(contentsOf: next.filter { !known.contains($0.id) })
        nextOffset += next.count
        isLoadingMore = false
        refreshHeadings()
    }

    /// The narrations before the first one loaded, added above it while the
    /// reader stays on the row they were reading.
    private func loadEarlier() async {
        guard !isLoadingEarlier, firstOffset > 0, !isSearchResults, let anchor = entries.first?.id else { return }
        isLoadingEarlier = true
        let start = max(0, firstOffset - Self.pageSize)
        let earlier = (try? await repository.entries(
            bookID: book.id, limit: firstOffset - start, offset: start
        )) ?? []
        let known = Set(entries.map(\.id))
        entries.insert(contentsOf: earlier.filter { !known.contains($0.id) }, at: 0)
        firstOffset = start
        isLoadingEarlier = false
        refreshHeadings()
        anchorAfterPrepend = anchor
    }
}

/// Where the reader left each collection, so it reopens on that narration
/// rather than at the cover. Small, and private to the device.
enum HadithReadingPosition {
    private static func key(_ bookID: String) -> String { "hadith.position.\(bookID)" }

    static func save(_ canonicalID: String, bookID: String) {
        UserDefaults.standard.set(canonicalID, forKey: key(bookID))
    }

    static func load(bookID: String) -> String? {
        UserDefaults.standard.string(forKey: key(bookID))
    }
}

/// Identifiable wrapper so a tapped narrator id can drive a `.sheet(item:)`.
private struct NarratorRef: Identifiable { let id: Int }

/// A native, searchable table of contents for every collection. Section titles
/// come from the bundled catalogue; no website handoff or remote page is used.
private struct HadithContentsView: View {
    let book: HadithBook
    let languageCode: String
    let select: (HadithSection?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var sections: [HadithSection] {
        let all = book.sections ?? []
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.displayNumber.localizedCaseInsensitiveContains(needle) ||
            $0.titleEnglish.localizedCaseInsensitiveContains(needle) ||
            $0.titleArabic.localizedCaseInsensitiveContains(needle) ||
            ($0.titleUrdu ?? "").localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        select(nil)
                    } label: {
                        Label("Start from the beginning", systemImage: "text.book.closed")
                    }
                }

                if sections.isEmpty, !(book.sections ?? []).isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if (book.sections ?? []).isEmpty {
                    ContentUnavailableView(
                        "Contents unavailable",
                        systemImage: "list.bullet.rectangle",
                        description: Text("This collection does not contain sourced book divisions.")
                    )
                } else {
                    Section("Books") {
                        ForEach(sections) { section in
                            Button {
                                select(section)
                            } label: {
                                HStack(alignment: .top, spacing: DISpacing.sm) {
                                    // No "0" beside an unnumbered opening book.
                                    Text(verbatim: section.isUnnumbered ? "" : section.displayNumber)
                                        .font(.caption.monospacedDigit().weight(.bold))
                                        .foregroundStyle(DIColor.accent)
                                        .frame(minWidth: 28, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(verbatim: section.title(languageCode: languageCode))
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(DIColor.textPrimary)
                                            .multilineTextAlignment(.leading)
                                        if languageCode != "ur", !section.titleArabic.isEmpty,
                                           section.titleArabic != section.title(languageCode: languageCode) {
                                            Text(verbatim: section.titleArabic)
                                                .font(DIFont.quranArabic(scale: 0.65))
                                                .foregroundStyle(DIColor.textMuted)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .environment(\.layoutDirection, .rightToLeft)
                                        }
                                        Text("\(section.hadithCount) narrations")
                                            .font(.caption)
                                            .foregroundStyle(DIColor.textMuted)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search books")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
