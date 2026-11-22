import SwiftUI
import UIKit

/// Reads a book's text, one printed page at a time.
///
/// Distinct from `BookReaderView`, which renders the work's PDF through
/// PDFKit. This view shows the *text* layer: selectable, searchable, and
/// available with no download. A work can offer both.
///
/// Pages are rendered in a `LazyVStack` and stored one row per printed page
/// (largest ~10 KB). The library detail view builds its paragraphs eagerly,
/// which is what made a large body unrenderable; nothing here holds more than
/// the visible pages.
///
/// A page is set out as it is printed: headings, paragraphs, poetry line by
/// line, Arabic quotations, tables and captions, with its footnotes at the
/// foot of the page, in Urdu or English as each block is written. Arabic is
/// set as Qur'an only where the mushaf confirms it; other quotations are the
/// book's own text.
///
/// Where a page cites or quotes an ayah, quotes a narration or names a
/// narrator, those words open the ayah, the narration or the biography over
/// the page (`BookLinks.swift`).
///
/// A page number with no text keeps its place as a slim card that says so.
///
/// The page at the top of the screen is kept, so the book reopens there.
///
/// Each page is set on a softly lit sheet of paper (a warm dark page at
/// night) with its number at the foot between two gold rules. Inside the
/// app's one reader (`BookReaderScreen`), this view reports its pages and the
/// page on screen to `session` and goes where the session asks; the reader's
/// bars then carry Go to page.
struct BookTextPagesView: View {
    let item: ContentItem
    let dependencies: AppDependencies
    /// Page to open at, e.g. where a surah begins inside a parah volume when
    /// the Quran reader sends someone here. Nil opens where the reader left
    /// the book, or at the start.
    var startPage: Int?
    /// The reader's text size, as the article reader and the Quran use it.
    var fontScale: Double = 1
    /// Set by `BookReaderScreen`; nil when the view stands alone.
    var session: BookReaderSession? = nil
    /// Lets a reference in the text open over the page; nil leaves the text
    /// plain.
    var appState: AppState? = nil
    /// Turns the reader to one of the book's printed pages; nil where it has
    /// none to show.
    var onShowPrintedPage: ((Int) -> Void)? = nil

    /// The pages with text and, between them, those with none.
    @State private var entries: [BookTextEntry] = []
    /// Pages set out into headings, paragraphs, poetry and quotations.
    @State private var formatted: [String: BookPageFormatter.Page] = [:]
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var loadAttempt = 0
    @State private var hasScrolledToStart = false
    /// The printed page at the top of the screen.
    @State private var topPage: Int?
    @State private var showsGoToPage = false
    @State private var goToPageText = ""
    @State private var pendingPage: Int?
    /// The places on each printed page that open an ayah, a narration or a
    /// narrator's biography.
    @State private var links: [Int: [BookLink]] = [:]
    /// The reference a reader tapped, shown over the page.
    @State private var openedLink: BookLinkTarget?

    var body: some View {
        Group {
            if isLoading && entries.isEmpty {
                ProgressView()
                    .tint(DIColor.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadFailed {
                VStack(spacing: DISpacing.md) {
                    DIEmptyState(systemImage: "text.book.closed", titleKey: "Something went wrong",
                        messageKey: "The pages could not be loaded. Check your connection and try again — once opened, it stays available offline.")
                    Button("Try Again") { loadAttempt += 1 }
                        .buttonStyle(DICompactButtonStyle())
                }
            } else if entries.isEmpty {
                if session != nil && BookReadingHistory.hasPDF(item) {
                    // The reader is turning to the printed pages.
                    ProgressView()
                        .tint(DIColor.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    DIEmptyState(systemImage: "text.book.closed", titleKey: "This work could not be opened")
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DISpacing.lg) {
                            ForEach(entries) { entry in
                                entryView(entry)
                                    .id(entry.id)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(DISpacing.md)
                    }
                    .scrollPosition(id: $topPage, anchor: .top)
                    .onChange(of: topPage) { _, page in
                        if let page {
                            BookReadingPosition.save(page: page, bookID: item.id)
                            session?.currentPage = page
                        }
                    }
                    .onChange(of: pendingPage) { _, requested in
                        guard let requested else { return }
                        if let target = BookTextEntry.holding(requested, in: entries) {
                            proxy.scrollTo(target.id, anchor: .top)
                            BookReadingPosition.save(page: target.id, bookID: item.id)
                            session?.currentPage = target.id
                        }
                        pendingPage = nil
                    }
                    .onAppear { scrollToStartIfNeeded(proxy) }
                }
            }
        }
        .diScreenBackground()
        .navigationTitle(Text(verbatim: item.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // In the reader, its floating bar carries Go to page.
            if session == nil && entries.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsGoToPage = true
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                    }
                    .accessibilityLabel(Text("Go to page"))
                }
            }
        }
        .alert("Go to page", isPresented: $showsGoToPage) {
            TextField("Page number", text: $goToPageText)
                .keyboardType(.numberPad)
            Button("Go") {
                let digits = SearchNormalizer.normalize(goToPageText).trimmingCharacters(in: .whitespaces)
                goToPageText = ""
                if let number = Int(digits) { pendingPage = number }
            }
            Button("Cancel", role: .cancel) { goToPageText = "" }
        } message: {
            if let first = entries.first?.id, let last = entries.last?.lastPage {
                Text("Pages \(first) to \(last)")
            }
        }
        // A page the reader's bars asked for, once the pages are here; one
        // asked for before they load is taken by `scrollToStartIfNeeded`.
        .onChange(of: session?.requestedPage) { _, requested in
            guard let requested, !entries.isEmpty else { return }
            pendingPage = requested
            session?.requestedPage = nil
        }
        .task(id: loadAttempt) {
            await load()
        }
        // What a tapped reference opens: the ayah with its tafsir, the
        // narration in its collection, or the narrator's biography.
        .sheet(item: $openedLink) { target in
            if let appState {
                switch target {
                case .ayah(let surah, let ayah):
                    TodayAyahTafsirSheet(
                        surahNumber: surah,
                        ayahNumber: ayah,
                        dependencies: dependencies,
                        appState: appState
                    )
                case .hadith(let canonicalID):
                    BookHadithSheet(canonicalID: canonicalID, dependencies: dependencies, appState: appState)
                case .narrator(let id):
                    NarratorBioSheet(narratorId: id, repository: dependencies.hadithRepository, appState: appState)
                }
            }
        }
    }

    @ViewBuilder
    private func entryView(_ entry: BookTextEntry) -> some View {
        switch entry {
        case .page(let page):
            pageView(page)
        case .noText(let numbers):
            BookNoTextCard(pages: numbers, onShowPrintedPage: onShowPrintedPage)
        }
    }

    /// One printed page on its sheet: its text, and its number at the foot.
    @ViewBuilder
    private func pageView(_ page: BookPage) -> some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            if let formattedPage = formatted[page.id] {
                FormattedBookPage(
                    page: formattedPage,
                    scale: fontScale,
                    place: .book,
                    links: appState == nil ? [] : (links[page.page] ?? []),
                    // A sentence cut by the page break is shown whole here:
                    // its words keep the links of the page they are printed on.
                    carriedLinks: appState == nil || formattedPage.carried == nil ? [] : (links[page.page + 1] ?? []),
                    onLink: { link in openedLink = BookLinkTarget(link.t) }
                )
            } else {
                pageText(page.text)
            }
            BookPageFolio(number: page.page)
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .background(BookPaper())
    }

    /// Direction and face follow the page's own script, not a fixed Urdu
    /// layout: the English Asrar-at-Tanzil volumes used to open right-aligned
    /// in Nastaliq. Deciding per page (with the book's language as the tie
    /// breaker) also keeps an English book's Urdu quotation pages readable.
    @ViewBuilder
    private func pageText(_ text: String) -> some View {
        if ScriptDirection.isRightToLeft(text, fallbackLanguage: item.language) {
            Text(verbatim: text)
                .font(DIFont.urduBody(scale: fontScale))
                .foregroundStyle(DIColor.textPrimary)
                .lineSpacing(CGFloat(10 * fontScale))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .rightToLeft)
                .textSelection(.enabled)
        } else {
            Text(verbatim: text)
                .font(.system(size: bodyBaseSize * fontScale))
                .foregroundStyle(DIColor.textPrimary)
                .lineSpacing(CGFloat(5 * fontScale))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .leftToRight)
                .textSelection(.enabled)
        }
    }

    @ScaledMetric(relativeTo: .body) private var bodyBaseSize: CGFloat = 17

    /// Opens at the page asked for (by the reader's bars or search, or by
    /// whoever opened the book), else where the reader left the book.
    private func scrollToStartIfNeeded(_ proxy: ScrollViewProxy) {
        guard !hasScrolledToStart, !entries.isEmpty else { return }
        let requested = session?.requestedPage
        guard let wanted = requested ?? startPage ?? BookReadingPosition.page(bookID: item.id) else { return }
        hasScrolledToStart = true
        if requested != nil { session?.requestedPage = nil }
        guard let target = BookTextEntry.holding(wanted, in: entries) else { return }
        session?.currentPage = target.id
        DispatchQueue.main.async {
            proxy.scrollTo(target.id, anchor: .top)
        }
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        session?.hasNoPages = false
        defer { isLoading = false }
        do {
            let loaded = try await dependencies.contentRepository.bookPages(bookID: item.id)
            try Task.checkCancellation()
            let language = item.language
            let prepared = await Task.detached(priority: .userInitiated) {
                BookPageFormatter.format(pages: loaded.filter {
                    BookPageFormatter.laidOutParts(of: $0) != nil
                        || ScriptDirection.isRightToLeft($0.text, fallbackLanguage: language)
                })
            }.value
            try Task.checkCancellation()
            let bookID = item.id
            let found = await Task.detached(priority: .userInitiated) {
                BookLinkProvider.shared.links(bookID: bookID)
            }.value
            try Task.checkCancellation()
            links = found
            formatted = prepared
            entries = BookTextEntry.entries(of: loaded)
            session?.pageNumbers = entries.map(\.id)
            session?.lastPage = entries.last?.lastPage
            session?.hasNoPages = entries.isEmpty
            if let first = entries.first?.id { session?.currentPage = first }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            loadFailed = true
        }
    }

}

/// One place in a book's text: a page with its words, or neighbouring page
/// numbers that have none (an empty page, or no page at all).
enum BookTextEntry: Identifiable, Equatable {
    case page(BookPage)
    case noText(ClosedRange<Int>)

    /// The first page number it stands for.
    var id: Int {
        switch self {
        case .page(let page): return page.page
        case .noText(let numbers): return numbers.lowerBound
        }
    }

    var lastPage: Int {
        switch self {
        case .page(let page): return page.page
        case .noText(let numbers): return numbers.upperBound
        }
    }

    /// Every page number from 1 to the book's last, in order. Empty for a
    /// book with no text at all, which opens as its printed pages.
    static func entries(of pages: [BookPage]) -> [BookTextEntry] {
        let written = pages.filter { !$0.text.isEmpty }.sorted { $0.page < $1.page }
        guard !written.isEmpty, let last = pages.map(\.page).max() else { return [] }
        var entries: [BookTextEntry] = []
        var next = 1
        for page in written {
            if page.page > next { entries.append(.noText(next...(page.page - 1))) }
            entries.append(.page(page))
            next = page.page + 1
        }
        if next <= last { entries.append(.noText(next...last)) }
        return entries
    }

    /// The place that holds `number`, else the last one.
    static func holding(_ number: Int, in entries: [BookTextEntry]) -> BookTextEntry? {
        entries.first { $0.lastPage >= number } ?? entries.last
    }
}

/// The slim card that stands for pages without text, with the way to the
/// printed page where the book has one.
private struct BookNoTextCard: View {
    let pages: ClosedRange<Int>
    var onShowPrintedPage: ((Int) -> Void)?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
        VStack(alignment: .leading, spacing: DISpacing.xs) {
            number
                .diInterfaceFont(.footnote, weight: .heavy)
                .foregroundStyle(ReadPalette.goldLine)
            Text("This page has no text.")
                .diInterfaceFont(.footnote)
                .foregroundStyle(DIColor.textMuted)
            if let onShowPrintedPage {
                Button("See the printed page") { onShowPrintedPage(pages.lowerBound) }
                    .buttonStyle(DICompactButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, DISpacing.sm)
        .background(shape.fill(ReadPalette.paper))
        .overlay(shape.stroke(ReadPalette.paperEdge, lineWidth: 1))
    }

    private var number: Text {
        if pages.count == 1 {
            return Text("Page \(pages.lowerBound)")
        }
        return Text("Pages \(pages.lowerBound)–\(pages.upperBound)")
    }
}

/// Reads a book's text in the app's one reader, at a page when one is given.
/// Search results and the Quran reader's printed volumes open here; a work
/// that also has its PDF offers its printed pages beside the text.
struct BookTextReaderView: View {
    let item: ContentItem
    let dependencies: AppDependencies
    /// Page to open at; nil opens where the reader left the book.
    var startPage: Int?
    /// The reader's text size, as the article reader and the Quran use it.
    var fontScale: Double = 1
    /// Lets a reference in the text open over the page.
    var appState: AppState? = nil

    var body: some View {
        BookReaderScreen(
            item: item,
            dependencies: dependencies,
            mode: .text,
            startPage: startPage,
            appState: appState,
            fontScale: fontScale
        )
    }
}

/// The softly lit sheet a page of text is set on: paper by day, a warm dark
/// page at night, a little light at its head.
struct BookPaper: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(ReadPalette.paper)
            RadialGradient(
                colors: [ReadPalette.pageGlow, Color.clear],
                center: .top,
                startRadius: 0,
                endRadius: 240
            )
            .frame(height: 120)
        }
        .clipShape(shape)
        .overlay(shape.stroke(ReadPalette.paperEdge, lineWidth: 1))
        .shadow(color: ReadPalette.softShadow, radius: 22, y: 14)
        .accessibilityHidden(true)
    }
}

/// A page's number at its foot, between two short gold rules.
struct BookPageFolio: View {
    let number: Int

    var body: some View {
        HStack(spacing: 10) {
            LinearGradient(
                colors: [ReadPalette.goldLine.opacity(0), ReadPalette.goldLine],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            Text(verbatim: "\(number)")
                .font(.footnote.weight(.heavy).monospacedDigit())
                .foregroundStyle(ReadPalette.goldLine)
            LinearGradient(
                colors: [ReadPalette.goldLine, ReadPalette.goldLine.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
        }
        .padding(.top, DISpacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(number)"))
    }
}

/// The page each book's text was left at, so it reopens there. Small, and
/// private to the device.
enum BookReadingPosition {
    private static func key(_ bookID: String) -> String { "bookText.page.\(bookID)" }

    static func save(page: Int, bookID: String) {
        UserDefaults.standard.set(page, forKey: key(bookID))
    }

    static func page(bookID: String) -> Int? {
        let page = UserDefaults.standard.integer(forKey: key(bookID))
        return page > 0 ? page : nil
    }
}

/// Text as `BookPageFormatter` laid it out: a book page, or the tafsir under
/// an ayah.
///
/// Each block takes its direction and face from its own script, so a page can
/// hold both: Urdu right to left in the Urdu face, and the English column of
/// an Asrar page left to right in the system face.
struct FormattedBookPage: View {
    let page: BookPageFormatter.Page
    /// The reader's text size.
    var scale: Double = 1
    /// Where the text is shown: some display rules hold only for books.
    var place: BookTextPlace = .article
    /// The places in this page's text that open an ayah, a narration or a
    /// narrator's biography. Empty leaves the text plain.
    var links: [BookLink] = []
    /// The next page's, for the words carried from it to the last paragraph.
    var carriedLinks: [BookLink] = []
    /// Called with the link a reader tapped.
    var onLink: ((BookLink) -> Void)? = nil
    @State private var showsContents = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var bodyBaseSize: CGFloat = 17

    var body: some View {
        Group {
            if page.isContents {
                DisclosureGroup(isExpanded: $showsContents) {
                    if let text = contentsText {
                        words(shown(text, rightToLeft: true), urduSize: 0.85)
                            .font(DIFont.urduBody(scale: 0.85 * scale))
                            .foregroundStyle(DIColor.textMuted)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .modifier(selection(text, rightToLeft: true))
                    } else {
                        blockList
                    }
                } label: {
                    Label("Contents page", systemImage: "list.bullet")
                        .diInterfaceFont(.footnote, weight: .semibold)
                        .foregroundStyle(DIColor.textMuted)
                }
                .tint(DIColor.primary)
            } else {
                blockList
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .modifier(BookLinkTaps(links: links + carriedLinks, onLink: onLink))
    }

    /// The text of a contents page from the original OCR, which is one
    /// paragraph of rows. Nil for a page set out from its own layout, whose
    /// blocks are shown instead.
    private var contentsText: String? {
        guard page.blocks.count == 1, page.footnotes.isEmpty,
              case .paragraph(let runs)? = page.blocks.first else { return nil }
        return plainText(runs)
    }

    private var blockList: some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            if page.isPartlyUnreadable {
                unreadableNote
            }
            ForEach(Array(page.blocks.enumerated()), id: \.offset) { index, block in
                blockView(block, at: index)
            }
            if !page.footnotes.isEmpty {
                footnoteList
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: BookPageFormatter.Block, at index: Int) -> some View {
        switch block {
        case .heading(let text):
            heading(text)
        case .paragraph(let runs):
            paragraph(runs, carried: index == page.blocks.count - 1 ? page.carried : nil)
        case .quran(let text):
            linkedText(text, cutFrom: page.cutQuotation(at: index), rightToLeft: true, mushafScale: 0.8 * scale)
                .foregroundStyle(DIColor.scripture)
                .lineSpacing(8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(DISpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                        .fill(DIColor.primary.opacity(0.07))
                )
                .modifier(selection(text, rightToLeft: true))
        case .arabic(let text):
            arabicQuotation(text, cutFrom: page.cutQuotation(at: index))
        case .verse(let text):
            verse(text)
        case .table(let rows):
            table(rows)
        case .caption(let text):
            caption(text)
        }
    }

    private func heading(_ text: String) -> some View {
        let rightToLeft = isRightToLeft(text)
        return words(shown(text, rightToLeft: rightToLeft), urduSize: rightToLeft ? 1.1 : nil)
            .font(face(rightToLeft, size: 1.1).weight(.semibold))
            .foregroundStyle(DIColor.actionForeground)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DISpacing.xs)
            .environment(\.layoutDirection, rightToLeft ? LayoutDirection.rightToLeft : .leftToRight)
    }

    private func paragraph(_ runs: [BookPageFormatter.Run], carried: BookPageFormatter.Carried?) -> some View {
        let plain = plainText(runs)
        let rightToLeft = isRightToLeft(plain)
        return prose(runs, carried: carried)
            .font(face(rightToLeft))
            .foregroundStyle(DIColor.textPrimary)
            .lineSpacing(CGFloat((rightToLeft ? 10 : 5) * scale))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, rightToLeft ? LayoutDirection.rightToLeft : .leftToRight)
            .modifier(selection(plain, rightToLeft: rightToLeft, drawnIn: runs.map(\.text)))
    }

    /// Arabic the mushaf does not confirm - a hadith, a du'a, a saying - set
    /// apart in the Arabic face, without the Qur'an's colour and panel.
    private func arabicQuotation(_ text: String, cutFrom quotation: BookPageFormatter.CutQuotation?) -> some View {
        linkedText(text, cutFrom: quotation, rightToLeft: true, mushafScale: 0.75 * scale)
            .foregroundStyle(DIColor.scripture)
            .lineSpacing(CGFloat(8 * scale))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DISpacing.xs)
            .environment(\.layoutDirection, .rightToLeft)
            .modifier(selection(text, rightToLeft: true))
    }

    /// A couplet or stanza: each printed line on a line of its own, centred
    /// as Urdu books set their verse.
    private func verse(_ text: String) -> some View {
        let rightToLeft = isRightToLeft(text)
        return keepingWaqfMarks(shown(text, rightToLeft: rightToLeft), urduSize: rightToLeft ? 1 : nil)
            .font(face(rightToLeft))
            .foregroundStyle(DIColor.textPrimary)
            .lineSpacing(CGFloat((rightToLeft ? 12 : 6) * scale))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .environment(\.layoutDirection, rightToLeft ? LayoutDirection.rightToLeft : .leftToRight)
            .modifier(selection(text, rightToLeft: rightToLeft))
    }

    /// Words the reading could not make out are shown as "…"; a page with
    /// many (a handwritten letter, faint print) says so and points to the
    /// printed page.
    private var unreadableNote: some View {
        Label {
            Text("Some words on this page are shown as … — switch to Pages to see the printed page.")
                .diInterfaceFont(.footnote)
                .foregroundStyle(DIColor.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .foregroundStyle(DIColor.textMuted)
        }
        .padding(DISpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous)
                .fill(DIColor.sandstone.opacity(0.6))
        )
        .accessibilityElement(children: .combine)
    }

    /// A table as printed: its cells in columns that share the width by what
    /// they hold (numbers narrow, titles wide), none narrower than its
    /// longest word, a rule between the rows. Where those cannot fit, each
    /// row is stacked, one cell under another. The row naming the columns is
    /// set in bold; a row naming a section spans the width. A row with fewer
    /// cells leaves the rest of its columns empty.
    private func table(_ rows: [[String]]) -> some View {
        let columns = max(1, rows.map(\.count).max() ?? 1)
        let layout = BookPageFormatter.tableLayout(rows)
        let rightToLeft = isRightToLeft(rows.joined().joined(separator: " "))
        let minimums = BookTableMeasure.columnMinimums(
            rows,
            layout: layout,
            font: rightToLeft
                ? DIFont.urduBodyUIFont(scale: 0.85 * scale, typeSize: dynamicTypeSize)
                : UIFont.systemFont(ofSize: bodyBaseSize * CGFloat(0.85 * scale)),
            enlargesSalawat: rightToLeft && place.followsBookRules
        )
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider().overlay(DIColor.border)
                }
                Group {
                    if BookPageFormatter.isSectionRow(row, columns: columns) {
                        let name = row.first { !$0.isEmpty } ?? ""
                        words(shown(name, rightToLeft: rightToLeft), urduSize: rightToLeft ? 0.9 : nil)
                            .font(face(rightToLeft, size: 0.9))
                            .fontWeight(.semibold)
                            .foregroundStyle(DIColor.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .modifier(selection(name, rightToLeft: rightToLeft))
                    } else {
                        WeightedColumns(
                            layout: layout,
                            minimums: minimums,
                            filled: (0..<columns).map { $0 < row.count && !row[$0].isEmpty },
                            spacing: DISpacing.sm,
                            stackSpacing: DISpacing.xs
                        ) {
                            ForEach(0..<columns, id: \.self) { column in
                                let cell = column < row.count ? row[column] : ""
                                words(shown(cell, rightToLeft: rightToLeft), urduSize: rightToLeft ? 0.85 : nil)
                                    .font(face(rightToLeft, size: 0.85))
                                    .fontWeight(index == 0 && layout.hasHeaderRow ? .semibold : .regular)
                                    .foregroundStyle(index == 0 && layout.hasHeaderRow ? DIColor.textMuted : DIColor.textPrimary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .modifier(selection(cell, rightToLeft: rightToLeft))
                            }
                        }
                    }
                }
                .padding(.vertical, DISpacing.xs)
            }
        }
        .padding(DISpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous)
                .fill(DIColor.sandstone)
        )
        .environment(\.layoutDirection, rightToLeft ? LayoutDirection.rightToLeft : .leftToRight)
    }

    private func caption(_ text: String) -> some View {
        let rightToLeft = isRightToLeft(text)
        return words(shown(text, rightToLeft: rightToLeft), urduSize: rightToLeft ? 0.8 : nil)
            .font(face(rightToLeft, size: 0.8))
            .foregroundStyle(DIColor.textMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .environment(\.layoutDirection, rightToLeft ? LayoutDirection.rightToLeft : .leftToRight)
            .modifier(selection(text, rightToLeft: rightToLeft))
    }

    /// The page's footnotes after its text, small, under a short rule as a
    /// printed page sets them.
    private var footnoteList: some View {
        VStack(alignment: .leading, spacing: DISpacing.xs) {
            Rectangle()
                .fill(DIColor.border)
                .frame(width: 72, height: 1)
                .accessibilityHidden(true)
            ForEach(Array(page.footnotes.enumerated()), id: \.offset) { _, note in
                footnote(note)
            }
        }
        .padding(.top, DISpacing.xs)
    }

    private func footnote(_ text: String) -> some View {
        let rightToLeft = isRightToLeft(text)
        return linkedText(text, rightToLeft: rightToLeft, urduSize: rightToLeft ? 0.8 : nil)
            .font(face(rightToLeft, size: 0.8))
            .foregroundStyle(DIColor.textMuted)
            .lineSpacing(CGFloat((rightToLeft ? 6 : 3) * scale))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, rightToLeft ? LayoutDirection.rightToLeft : .leftToRight)
            .modifier(selection(text, rightToLeft: rightToLeft))
    }

    /// A stretch as it is drawn: in a right-to-left block of a book or an
    /// article, its dates, telephone numbers and references in isolates.
    private func shown(_ pieces: [String], rightToLeft: Bool) -> [String] {
        guard rightToLeft, place.followsBookRules else { return pieces }
        return BookTextDrawing.isolatingNumbers(pieces)
    }

    private func shown(_ text: String, rightToLeft: Bool) -> String {
        shown([text], rightToLeft: rightToLeft).joined()
    }

    /// `stretches` are what `shown` is given of the block, where that is not
    /// the whole of it: a number is looked for in each by itself, so that
    /// Copy never takes an isolate along.
    private func selection(_ text: String, rightToLeft: Bool, drawnIn stretches: [String]? = nil) -> BookTextSelection {
        BookTextSelection(
            text: text,
            isIsolated: rightToLeft && place.followsBookRules
                && (stretches ?? [text]).contains { !BookTextDrawing.numberTokens(in: $0).isEmpty }
        )
    }

    /// Words in a block's own face. In the Urdu face, `urduSize` times the
    /// reader's text size, the salawat sign is drawn as a book draws it.
    private func words(_ string: String, urduSize: Double?) -> Text {
        guard let urduSize, place.followsBookRules, BookTextDrawing.holdsSalawat(string) else {
            return Text(verbatim: string)
        }
        return Text(BookTextDrawing.enlargingSalawat(AttributedString(string), scale: urduSize * scale))
    }

    /// The mushaf's waqf signs are private-use characters only its font draws; a
    /// quotation that reached the prose or verse face keeps them in that font.
    private func keepingWaqfMarks(_ string: String, urduSize: Double?) -> Text {
        var text = Text(verbatim: "")
        var plain = String.UnicodeScalarView()
        for scalar in string.unicodeScalars {
            if (0xE000...0xF8FF).contains(scalar.value) {
                text = text + words(String(plain), urduSize: urduSize)
                plain = String.UnicodeScalarView()
                text = text + Text(verbatim: String(scalar)).font(DIFont.quranArabic(scale: (17.0 / 27.0) * scale))
            } else {
                plain.append(scalar)
            }
        }
        return text + words(String(plain), urduSize: urduSize)
    }

    /// The words of a link: tappable, underlined, in the tint the page gives
    /// its links.
    private func linkText(_ string: String, index: Int, mushafScale: Double?, urduSize: Double?) -> Text {
        var attributed = BookTextDrawing.link(string, index: index)
        guard let mushafScale else {
            if let urduSize, place.followsBookRules {
                attributed = BookTextDrawing.enlargingSalawat(attributed, scale: urduSize * scale)
            }
            return Text(attributed)
        }
        return Text.mushaf(attributed, scale: mushafScale, showsSmallHighZero: place.showsSmallHighZero)
    }

    /// Words as they are: in the mushaf face at `mushafScale`, or in the face
    /// around them.
    private func unlinkedText(_ string: String, mushafScale: Double?, urduSize: Double?) -> Text {
        guard let mushafScale else { return words(string, urduSize: urduSize) }
        return Text.mushaf(verbatim: string, scale: mushafScale, showsSmallHighZero: place.showsSmallHighZero)
    }

    /// A quotation or a footnote, tappable where one of the page's links
    /// names its words.
    private func linkedText(
        _ string: String,
        cutFrom quotation: BookPageFormatter.CutQuotation? = nil,
        rightToLeft: Bool,
        mushafScale: Double? = nil,
        urduSize: Double? = nil
    ) -> Text {
        // Links are found in the book's own words, without the isolates.
        let pieces = links.isEmpty ? [] : BookLinkMatcher.pieces(of: string, cutFrom: quotation, links: links)
        guard pieces.contains(where: { $0.link != nil }) else {
            return unlinkedText(shown(string, rightToLeft: rightToLeft), mushafScale: mushafScale, urduSize: urduSize)
        }
        var text = Text(verbatim: "")
        for (piece, drawn) in zip(pieces, shown(pieces.map(\.text), rightToLeft: rightToLeft)) {
            if let index = piece.link {
                text = text + linkText(drawn, index: index, mushafScale: mushafScale, urduSize: urduSize)
            } else {
                text = text + unlinkedText(drawn, mushafScale: mushafScale, urduSize: urduSize)
            }
        }
        // The empty first Text takes the quotation's face, as its words do.
        guard let mushafScale else { return text }
        return text.font(DIFont.quranArabic(scale: mushafScale))
    }

    /// Words of prose in the page's own face, the mushaf's waqf signs and the
    /// salutation sign kept in the face that draws them.
    private func plainProse(_ string: String, leftToRight: Bool) -> Text {
        guard leftToRight && string.contains("\u{FDFA}") else {
            return keepingWaqfMarks(string, urduSize: leftToRight ? nil : 1)
        }
        // Urdu locale's system fallback uses a tall Nastaliq ligature
        // that can collide with adjacent Latin lines. Keep the same
        // symbol, explicitly set in the bundled Arabic body face.
        var text = Text(verbatim: "")
        let parts = string.components(separatedBy: "\u{FDFA}")
        for (partIndex, part) in parts.enumerated() {
            if partIndex > 0 {
                text = text + Text(verbatim: "\u{FDFA}")
                    .font(DIFont.quranArabic(scale: (17.0 / 27.0) * scale))
            }
            text = text + Text(verbatim: part)
        }
        return text
    }

    /// A run that holds one of the page's links, cut at the link so that its
    /// words can be tapped; nil when the run holds none.
    private func linkedRun(_ run: BookPageFormatter.Run, pieces: [BookLinkMatcher.Piece], leftToRight: Bool) -> Text? {
        guard pieces.contains(where: { $0.link != nil }) else { return nil }
        let quoted = run.isQuranic || run.isArabic
        let mushafScale: Double? = quoted ? 0.72 * scale : nil
        var text = Text(verbatim: "")
        for (piece, drawn) in zip(pieces, shown(pieces.map(\.text), rightToLeft: !leftToRight)) {
            var part: Text
            if let index = piece.link {
                part = linkText(drawn, index: index, mushafScale: mushafScale, urduSize: leftToRight ? nil : 1)
            } else if quoted {
                part = unlinkedText(drawn, mushafScale: mushafScale, urduSize: nil)
            } else {
                part = plainProse(drawn, leftToRight: leftToRight)
            }
            if quoted {
                part = part.foregroundStyle(DIColor.scripture)
            }
            text = text + part
        }
        return text
    }

    /// Prose, with a short Qur'anic quotation kept inline in the Qur'an face
    /// and a printed line break kept where the paragraph had one.
    private func prose(_ runs: [BookPageFormatter.Run], carried: BookPageFormatter.Carried?) -> Text {
        let leftToRight = !isRightToLeft(plainText(runs))
        let linkedPieces: [[BookLinkMatcher.Piece]] = links.isEmpty && carriedLinks.isEmpty ? [] :
            BookLinkMatcher.pieces(ofParagraph: runs, carried: carried, links: links, carriedLinks: carriedLinks)
        var text = Text(verbatim: "")
        for (index, run) in runs.enumerated() {
            if index > 0 { text = text + Text(verbatim: run.startsLine ? "\n" : " ") }
            if index < linkedPieces.count,
               let linked = linkedRun(run, pieces: linkedPieces[index], leftToRight: leftToRight) {
                text = text + linked
                continue
            }
            let drawn = shown(run.text, rightToLeft: !leftToRight)
            if run.isQuranic || run.isArabic {
                text = text + Text.mushaf(verbatim: drawn, scale: 0.72 * scale, showsSmallHighZero: place.showsSmallHighZero)
                    .foregroundStyle(DIColor.scripture)
            } else {
                text = text + plainProse(drawn, leftToRight: leftToRight)
            }
        }
        return text
    }

    /// The runs' words as plain text, printed line breaks kept.
    private func plainText(_ runs: [BookPageFormatter.Run]) -> String {
        var text = ""
        for (index, run) in runs.enumerated() {
            if index > 0 { text += run.startsLine ? "\n" : " " }
            text += run.text
        }
        return text
    }

    /// The Urdu face for Arabic-script text, the system face for Latin text,
    /// at `size` times the reader's text size.
    private func face(_ rightToLeft: Bool, size: Double = 1) -> Font {
        rightToLeft
            ? DIFont.urduBody(scale: size * scale)
            : Font.system(size: bodyBaseSize * CGFloat(size * scale))
    }

    /// Arabic script reads right to left. Text with no letters (a row of
    /// numbers) follows the page, which is Urdu.
    private func isRightToLeft(_ text: String) -> Bool {
        ScriptDirection.isRightToLeft(text, fallbackLanguage: "ur")
    }
}

/// Decides reading direction from the text itself.
enum ScriptDirection {
    /// True when Arabic-script letters outnumber Latin ones. Ties and
    /// letterless text fall back to the language the content is labelled with.
    static func isRightToLeft(_ text: String, fallbackLanguage: String?) -> Bool {
        var arabic = 0
        var latin = 0
        for scalar in text.unicodeScalars.prefix(4000) {
            switch scalar.value {
            case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF:
                arabic += 1
            case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F:
                latin += 1
            default:
                break
            }
        }
        if arabic == latin {
            return fallbackLanguage == "ur" || fallbackLanguage == "ar"
        }
        return arabic > latin
    }
}


/// A row of a table's cells. Its columns share the proposed width by weight
/// (numbers narrow, titles wide), none narrower than its longest word; where
/// those do not fit, the cells stand one under another in their own order.
/// Every row is given the same minimums, so a table stacks as a whole. Placed
/// from the leading edge, so a right-to-left table runs from the right.
struct WeightedColumns: Layout {
    var layout: BookPageFormatter.TableLayout
    var minimums: [Double]
    /// The cells with words: an empty one takes no room in a stacked row.
    var filled: [Bool]
    var spacing: CGFloat
    var stackSpacing: CGFloat

    /// Nil where the row is stacked.
    private func widths(for total: CGFloat) -> [CGFloat]? {
        BookPageFormatter.tableWidths(
            available: Double(total),
            spacing: Double(spacing),
            minimums: minimums,
            layout: layout
        )?.map { CGFloat($0) }
    }

    private func height(of subview: LayoutSubview, width: CGFloat) -> CGFloat {
        subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposed = proposal.width ?? 320
        let width = proposed.isFinite ? max(0, proposed) : 320
        if let columns = widths(for: width) {
            let tallest = zip(subviews, columns).map { height(of: $0, width: $1) }.max() ?? 0
            return CGSize(width: width, height: tallest)
        }
        let heights = zip(subviews, filled).filter { $0.1 }.map { height(of: $0.0, width: width) }
        let gaps = stackSpacing * CGFloat(max(0, heights.count - 1))
        return CGSize(width: width, height: heights.reduce(0, +) + gaps)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if let columns = widths(for: bounds.width) {
            var x = bounds.minX
            for (subview, width) in zip(subviews, columns) {
                subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                              proposal: ProposedViewSize(width: width, height: nil))
                x += width + spacing
            }
            return
        }
        var y = bounds.minY
        for (subview, hasWords) in zip(subviews, filled) {
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: hasWords ? nil : 0))
            if hasWords { y += height(of: subview, width: bounds.width) + stackSpacing }
        }
    }
}
