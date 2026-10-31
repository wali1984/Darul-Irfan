import SwiftUI

/// Reads a book's OCR'd text, one printed page at a time.
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
/// A page re-read from the scan is set out as it was read: headings,
/// paragraphs, poetry line by line, Arabic quotations, tables and captions,
/// with its footnotes at the foot of the page, in Urdu or English as each
/// block is written. A page still in its original OCR is laid out from its
/// text when it is Urdu and shown as it is otherwise.
///
/// Pages still in their original OCR (`machineProvisional`: OCR arbitration
/// plus a visual cross-check, no human proofreading) are announced once at the
/// top - how many of the book's pages they are - and, in a book that mixes
/// them with pages re-read from the scan (`claudeTranscribed`), each such page
/// is marked; the re-read pages carry no notice. Any page the validator could
/// not fully settle is marked too. Arabic is set as Qur'an only where the
/// mushaf confirms it; other quotations are the book's own text.
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

    @State private var pages: [BookPage] = []
    /// Pages set out into headings, paragraphs, poetry and quotations.
    @State private var formatted: [String: BookPageFormatter.Page] = [:]
    @State private var isLoading = true
    @State private var hasScrolledToStart = false
    /// The printed page at the top of the screen.
    @State private var topPage: Int?
    @State private var showsGoToPage = false
    @State private var goToPageText = ""
    @State private var pendingPage: Int?

    private var unresolvedPageCount: Int {
        pages.filter { $0.isMachineProvisional && !$0.isFullyResolved }.count
    }

    /// Pages still in their original OCR; the notice is about these only.
    private var machineReadPageCount: Int {
        pages.filter(\.isMachineProvisional).count
    }

    /// Some pages re-read from the scan and some not: each original OCR page
    /// is then marked, so the reader can tell which is which.
    private var mixesReviewStates: Bool {
        machineReadPageCount > 0 && machineReadPageCount < pages.count
    }

    var body: some View {
        Group {
            if isLoading && pages.isEmpty {
                ProgressView()
                    .tint(DIColor.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if pages.isEmpty {
                DIEmptyState(
                    systemImage: "text.book.closed",
                    titleKey: "No text for this book yet",
                    messageKey: "This work is available as a PDF. Its text has not been added yet."
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DISpacing.lg) {
                            if machineReadPageCount > 0 {
                                provenanceNote
                            }
                            ForEach(pages, id: \.page) { page in
                                pageView(page)
                                    .id(page.page)
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
                        // Scans skip blank pages: the nearest page at or after.
                        if let target = pages.first(where: { $0.page >= requested }) ?? pages.last {
                            proxy.scrollTo(target.page, anchor: .top)
                            BookReadingPosition.save(page: target.page, bookID: item.id)
                            session?.currentPage = target.page
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
            if session == nil && pages.count > 1 {
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
            if let first = pages.first?.page, let last = pages.last?.page {
                Text("Pages \(first) to \(last)")
            }
        }
        // A page the reader's bars asked for, once the pages are here; one
        // asked for before they load is taken by `scrollToStartIfNeeded`.
        .onChange(of: session?.requestedPage) { _, requested in
            guard let requested, !pages.isEmpty else { return }
            pendingPage = requested
            session?.requestedPage = nil
        }
        .task {
            await load()
        }
    }

    /// Stated once at the top of the work, not repeated per page.
    private var provenanceNote: some View {
        DICard(background: DIColor.sandstone) {
            VStack(alignment: .leading, spacing: DISpacing.xs) {
                Label {
                    Text("Machine-read text — pending proofreading")
                        .font(.caption.weight(.semibold))
                } icon: {
                    Image(systemName: "info.circle")
                }
                .foregroundStyle(DIColor.textPrimary)
                if mixesReviewStates {
                    Text("\(machineReadPageCount) of \(pages.count) pages are still machine-read and have not been checked by a person; they are marked. Read the PDF for the authoritative text.")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                } else {
                    Text("Scanned and machine-corrected from the printed book. It has not been checked by a person. Read the PDF for the authoritative text.")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                if unresolvedPageCount > 0 {
                    Text("\(unresolvedPageCount) of \(pages.count) pages have passages the checker could not settle; those are marked.")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
        }
    }

    /// One printed page on its sheet: the marks a page carries (still
    /// machine-read in a book that mixes the two; passages the checker could
    /// not settle), its text, and its number at the foot.
    @ViewBuilder
    private func pageView(_ page: BookPage) -> some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            if carriesMarks(page) {
                pageMarks(page)
            }
            if let formattedPage = formatted[page.id] {
                FormattedBookPage(page: formattedPage, scale: fontScale)
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

    private func carriesMarks(_ page: BookPage) -> Bool {
        (mixesReviewStates && page.isMachineProvisional)
            || (page.isMachineProvisional && !page.isFullyResolved)
    }

    private func pageMarks(_ page: BookPage) -> some View {
        HStack(spacing: DISpacing.sm) {
            if mixesReviewStates && page.isMachineProvisional {
                Label {
                    Text("machine-read, not yet proofread")
                        .font(.caption2)
                } icon: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .foregroundStyle(DIColor.textMuted)
            }
            if page.isMachineProvisional && !page.isFullyResolved {
                Label {
                    Text("unchecked passages")
                        .font(.caption2)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(DIColor.accent)
                .accessibilityLabel(Text("This page has \(page.unresolvedBlocks) passages the checker could not settle"))
            }
            Spacer(minLength: 0)
        }
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
        guard !hasScrolledToStart, !pages.isEmpty else { return }
        let requested = session?.requestedPage
        guard let wanted = requested ?? startPage ?? BookReadingPosition.page(bookID: item.id) else { return }
        hasScrolledToStart = true
        if requested != nil { session?.requestedPage = nil }
        // The nearest page at or after the requested one: scans skip blank
        // pages, so the exact number is not always present.
        guard let target = pages.first(where: { $0.page >= wanted }) ?? pages.last else { return }
        session?.currentPage = target.page
        DispatchQueue.main.async {
            proxy.scrollTo(target.page, anchor: .top)
        }
    }

    private func load() async {
        isLoading = true
        let loaded = (try? await dependencies.contentRepository.bookPages(bookID: item.id)) ?? []
        let language = item.language
        formatted = await Task.detached(priority: .userInitiated) {
            // A re-read page is set out from its own layout in either script;
            // an original OCR page is laid out only when it is Urdu.
            BookPageFormatter.format(pages: loaded.filter {
                BookPageFormatter.laidOutParts(of: $0) != nil
                    || ScriptDirection.isRightToLeft($0.text, fallbackLanguage: language)
            })
        }.value
        // A cover or blank page re-read from the scan carries no text.
        pages = loaded.filter { !$0.text.isEmpty }
        session?.pageNumbers = pages.map(\.page)
        if let first = pages.first?.page {
            session?.currentPage = first
        }
        isLoading = false
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

    var body: some View {
        BookReaderScreen(
            item: item,
            dependencies: dependencies,
            mode: .text,
            startPage: startPage,
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
    @State private var showsContents = false
    @ScaledMetric(relativeTo: .body) private var bodyBaseSize: CGFloat = 17

    var body: some View {
        Group {
            if page.isContents {
                DisclosureGroup(isExpanded: $showsContents) {
                    if let text = contentsText {
                        Text(verbatim: text)
                            .font(DIFont.urduBody(scale: 0.85 * scale))
                            .foregroundStyle(DIColor.textMuted)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else {
                        blockList
                    }
                } label: {
                    Label("Contents page", systemImage: "list.bullet")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DIColor.textMuted)
                }
                .tint(DIColor.primary)
            } else {
                blockList
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
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
            ForEach(Array(page.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
            if !page.footnotes.isEmpty {
                footnoteList
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: BookPageFormatter.Block) -> some View {
        switch block {
        case .heading(let text):
            heading(text)
        case .paragraph(let runs):
            paragraph(runs)
        case .quran(let text):
            Text(verbatim: text)
                .font(DIFont.quranArabic(scale: 0.8 * scale))
                .foregroundStyle(DIColor.scripture)
                .lineSpacing(8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(DISpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                        .fill(DIColor.primary.opacity(0.07))
                )
                .textSelection(.enabled)
        case .arabic(let text):
            arabicQuotation(text)
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
        return Text(verbatim: text)
            .font(face(rightToLeft, size: 1.1).weight(.semibold))
            .foregroundStyle(DIColor.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DISpacing.xs)
            .environment(\.layoutDirection, rightToLeft ? LayoutDirection.rightToLeft : .leftToRight)
    }

    private func paragraph(_ runs: [BookPageFormatter.Run]) -> some View {
        let rightToLeft = isRightToLeft(plainText(runs))
        return prose(runs)
            .font(face(rightToLeft))
            .foregroundStyle(DIColor.textPrimary)
            .lineSpacing(CGFloat((rightToLeft ? 10 : 5) * scale))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, rightToLeft ? LayoutDirection.rightToLeft : .leftToRight)
            .textSelection(.enabled)
    }

    /// Arabic the mushaf does not confirm - a hadith, a du'a, a saying - set
    /// apart in the Arabic face, without the Qur'an's colour and panel.
    private func arabicQuotation(_ text: String) -> some View {
        Text(verbatim: text)
            .font(DIFont.quranArabic(scale: 0.75 * scale))
            .foregroundStyle(DIColor.scripture)
            .lineSpacing(CGFloat(8 * scale))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DISpacing.xs)
            .environment(\.layoutDirection, .rightToLeft)
            .textSelection(.enabled)
    }

    /// A couplet or stanza: each printed line on a line of its own, centred
    /// as Urdu books set their verse.
    private func verse(_ text: String) -> some View {
        let rightToLeft = isRightToLeft(text)
        return Text(verbatim: text)
            .font(face(rightToLeft))
            .foregroundStyle(DIColor.textPrimary)
            .lineSpacing(CGFloat((rightToLeft ? 12 : 6) * scale))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .environment(\.layoutDirection, rightToLeft ? LayoutDirection.rightToLeft : .leftToRight)
            .textSelection(.enabled)
    }

    /// A table as printed: its cells in columns, a rule between the rows. A
    /// row with fewer cells than the widest leaves the rest of its columns
    /// empty.
    private func table(_ rows: [[String]]) -> some View {
        let columns = max(1, rows.map(\.count).max() ?? 1)
        let rightToLeft = isRightToLeft(rows.joined().joined(separator: " "))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider().overlay(DIColor.border)
                }
                HStack(alignment: .top, spacing: DISpacing.sm) {
                    ForEach(0..<columns, id: \.self) { column in
                        Text(verbatim: column < row.count ? row[column] : "")
                            .font(face(rightToLeft, size: 0.85))
                            .foregroundStyle(DIColor.textPrimary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
        .textSelection(.enabled)
    }

    private func caption(_ text: String) -> some View {
        let rightToLeft = isRightToLeft(text)
        return Text(verbatim: text)
            .font(face(rightToLeft, size: 0.8))
            .foregroundStyle(DIColor.textMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .environment(\.layoutDirection, rightToLeft ? LayoutDirection.rightToLeft : .leftToRight)
            .textSelection(.enabled)
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
        return Text(verbatim: text)
            .font(face(rightToLeft, size: 0.8))
            .foregroundStyle(DIColor.textMuted)
            .lineSpacing(CGFloat((rightToLeft ? 6 : 3) * scale))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, rightToLeft ? LayoutDirection.rightToLeft : .leftToRight)
            .textSelection(.enabled)
    }

    /// Prose, with a short Qur'anic quotation kept inline in the Qur'an face
    /// and a printed line break kept where the paragraph had one.
    private func prose(_ runs: [BookPageFormatter.Run]) -> Text {
        var text = Text(verbatim: "")
        for (index, run) in runs.enumerated() {
            if index > 0 { text = text + Text(verbatim: run.startsLine ? "\n" : " ") }
            if run.isQuranic {
                text = text + Text(verbatim: run.text)
                    .font(DIFont.quranArabic(scale: 0.72 * scale))
                    .foregroundStyle(DIColor.scripture)
            } else {
                text = text + Text(verbatim: run.text)
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
