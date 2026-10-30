import SwiftUI
import PDFKit

/// Premium in-app reader for the Silsila's books and tafseer. Tapping a work
/// opens its actual pages INSIDE the app — no external viewer, no "download
/// then open" step. The PDF is fetched once and cached for fully offline
/// reading, then rendered with PDFKit with live page tracking and share.
///
/// The page being read is kept, so the work reopens there; "Go to page"
/// jumps anywhere in it.
///
/// Inside the app's one reader (`BookReaderScreen`) the reader's own bars
/// turn the pages: this view then reports its page and its pages to
/// `session`, goes where the session asks, and leaves out its own page bar,
/// Go to page and Share.
struct BookReaderView: View {
    let item: ContentItem
    let dependencies: AppDependencies
    /// Set by `BookReaderScreen`; nil when the view stands alone.
    var session: BookReaderSession? = nil

    @State private var phase: Phase = .preparing
    @State private var document: PDFDocument?
    @State private var pageCount: Int = 0
    @State private var currentPage: Int = 1
    @State private var requestedPage: Int?
    @State private var shareURL: URL?
    @State private var showsGoToPage = false
    @State private var goToPageText = ""

    enum Phase: Equatable {
        case preparing
        case downloading
        case ready(URL)
        /// The source no longer has the file (HTTP 404/410), or what came
        /// back is not a readable PDF. Trying again will not help.
        case notAvailable
        /// The file could not be fetched; another try, online, may work.
        case connectionFailed
    }

    /// The work's PDF: the first `.pdf` download URL, else the first file.
    private var pdfURLString: String? {
        item.downloadUrls.first { $0.lowercased().hasSuffix(".pdf") } ?? item.downloadUrls.first
    }

    var body: some View {
        content
            .diScreenBackground()
            .navigationTitle(Text(verbatim: item.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // In the reader, its own bars carry Go to page and Share.
                if session == nil {
                    if case .ready = phase {
                        if pageCount > 1 {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    showsGoToPage = true
                                } label: {
                                    Image(systemName: "arrow.down.to.line")
                                }
                                .accessibilityLabel(Text("Go to page"))
                            }
                        }
                        if let shareURL {
                            ToolbarItem(placement: .topBarTrailing) {
                                ShareLink(item: shareURL) { Image(systemName: "square.and.arrow.up") }
                                    .accessibilityLabel(Text("Share"))
                            }
                        }
                    }
                }
            }
            .alert("Go to page", isPresented: $showsGoToPage) {
                TextField("Page number", text: $goToPageText)
                    .keyboardType(.numberPad)
                Button("Go") {
                    let digits = SearchNormalizer.normalize(goToPageText).trimmingCharacters(in: .whitespaces)
                    goToPageText = ""
                    if let number = Int(digits), (1...max(1, pageCount)).contains(number) {
                        requestedPage = number
                    }
                }
                Button("Cancel", role: .cancel) { goToPageText = "" }
            } message: {
                Text("Pages 1 to \(pageCount)")
            }
            .onChange(of: currentPage) { _, page in
                if case .ready = phase { PDFReadingPosition.save(page: page, itemID: item.id) }
                session?.currentPage = page
            }
            .onChange(of: pageCount) { _, count in
                session?.pageNumbers = count > 0 ? Array(1...count) : []
            }
            // A page the reader's bars asked for.
            .onChange(of: session?.requestedPage) { _, page in
                guard let page else { return }
                requestedPage = page
                session?.requestedPage = nil
            }
            .task { await prepare() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .preparing, .downloading:
            loadingView
        case .ready:
            if let document {
                readerView(document: document)
            } else {
                loadingView
            }
        case .notAvailable:
            DIEmptyState(
                systemImage: "doc.questionmark",
                titleKey: "This file is not available",
                messageKey: "The source no longer provides this file, or what it sends is not a readable PDF. Trying again will not bring it back."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .connectionFailed:
            VStack(spacing: DISpacing.md) {
                DIEmptyState(
                    systemImage: "wifi.exclamationmark",
                    titleKey: "Couldn't open this work",
                    messageKey: "The pages could not be loaded. Check your connection and try again — once opened, it stays available offline."
                )
                Button("Try Again") {
                    phase = .preparing
                    Task { await prepare() }
                }
                .buttonStyle(DISecondaryButtonStyle())
                .padding(.horizontal, DISpacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var loadingView: some View {
        VStack(spacing: DISpacing.md) {
            DISealEmblem(diameter: 76, glow: true).diBreathingGlow()
            ProgressView().tint(DIColor.primary)
            if phase == .downloading {
                Text("Preparing pages for offline reading…")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DISpacing.xl)
    }

    private func readerView(document: PDFDocument) -> some View {
        ZStack(alignment: .bottom) {
            PDFReaderKit(
                document: document,
                startPage: PDFReadingPosition.page(itemID: item.id) ?? 1,
                requestedPage: $requestedPage,
                pageCount: $pageCount,
                currentPage: $currentPage
            )
            // Alone, the pages run under the home indicator; in the reader
            // they stop above its floating bar.
            .ignoresSafeArea(edges: session == nil ? .bottom : [])

            if pageCount > 0 && session == nil {
                pageBar
            }
        }
    }

    private var pageBar: some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: "book.pages")
                .font(.caption)
                .foregroundStyle(DIColor.accent)
            Text("Page \(currentPage) of \(pageCount)")
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(DIColor.textPrimary)
        }
        .padding(.horizontal, DISpacing.md)
        .padding(.vertical, DISpacing.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(DIColor.accent.opacity(0.3), lineWidth: 1))
        .padding(.bottom, DISpacing.md)
        .accessibilityLabel(Text("Page \(currentPage) of \(pageCount)"))
    }

    // MARK: - Fetch + cache

    @MainActor
    private func prepare() async {
        guard case .preparing = phase else { return }
        guard let urlString = pdfURLString, let url = URL(string: urlString) else {
            phase = .notAvailable; return
        }

        // Already cached? Open instantly, fully offline - if it really is a
        // PDF. A copy that is not (cut short, or a captive portal's page
        // saved in its place) is removed and fetched again, instead of
        // opening as a blank screen every time.
        if let asset = try? await dependencies.downloadsRepository.asset(remoteUrl: urlString),
           let local = dependencies.downloadManager.localURL(for: asset) {
            if let opened = Self.openPDF(at: local) {
                show(opened, from: local)
                return
            }
            try? await dependencies.downloadManager.deleteAsset(asset)
        }

        // Otherwise fetch once and cache.
        phase = .downloading
        do {
            let asset = try await dependencies.downloadManager.download(
                url: url, forContentItem: item.id, mediaItemID: nil
            )
            guard let local = dependencies.downloadManager.localURL(for: asset) else {
                phase = .connectionFailed
                return
            }
            guard let opened = Self.openPDF(at: local) else {
                try? await dependencies.downloadManager.deleteAsset(asset)
                phase = .notAvailable
                return
            }
            show(opened, from: local)
        } catch let error as DownloadManagerError {
            switch error {
            // The source answered that the file is not there (404, 410) or
            // will not be given (other 4xx). Trying again will not help;
            // a timeout (408), a rate limit (429) or a server fault (5xx) may.
            case .serverError(let statusCode)
                where (400..<500).contains(statusCode) && statusCode != 408 && statusCode != 429:
                phase = .notAvailable
            default:
                phase = .connectionFailed
            }
        } catch {
            phase = .connectionFailed
        }
    }

    private func show(_ opened: PDFDocument, from local: URL) {
        document = opened
        shareURL = local
        session?.shareURL = local
        phase = .ready(local)
    }

    /// The document, when the file is a PDF that PDFKit can open.
    private static func openPDF(at url: URL) -> PDFDocument? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        let head = (try? handle.read(upToCount: 5)) ?? nil
        try? handle.close()
        guard head == Data("%PDF-".utf8) else { return nil }
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return nil }
        return document
    }
}

/// The page each PDF was left at, so it reopens there. Small, and private to
/// the device.
enum PDFReadingPosition {
    private static func key(_ itemID: String) -> String { "bookPDF.page.\(itemID)" }

    static func save(page: Int, itemID: String) {
        UserDefaults.standard.set(page, forKey: key(itemID))
    }

    static func page(itemID: String) -> Int? {
        let page = UserDefaults.standard.integer(forKey: key(itemID))
        return page > 0 ? page : nil
    }
}

/// PDFKit reader with live page tracking. Night mode is applied by the parent
/// as a `.difference` blend overlay (iOS-safe).
private struct PDFReaderKit: UIViewRepresentable {
    let document: PDFDocument
    /// 1-based page shown first.
    let startPage: Int
    /// A page to go to, set by "Go to page"; cleared once shown.
    @Binding var requestedPage: Int?
    @Binding var pageCount: Int
    @Binding var currentPage: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.usePageViewController(false)
        view.backgroundColor = .clear
        view.document = document
        let count = document.pageCount
        DispatchQueue.main.async { pageCount = count }
        if startPage > 1, let page = document.page(at: min(startPage, count) - 1) {
            DispatchQueue.main.async { view.go(to: page) }
        }
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged, object: view
        )
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard let requested = requestedPage else { return }
        if let page = document.page(at: max(1, min(requested, document.pageCount)) - 1) {
            view.go(to: page)
        }
        DispatchQueue.main.async { requestedPage = nil }
    }

    final class Coordinator: NSObject {
        let parent: PDFReaderKit
        init(_ parent: PDFReaderKit) { self.parent = parent }

        @objc func pageChanged(_ note: Notification) {
            guard let view = note.object as? PDFView,
                  let page = view.currentPage,
                  let index = view.document?.index(for: page) else { return }
            parent.currentPage = index + 1
        }
    }
}
