import SwiftUI
import PDFKit

/// Premium in-app reader for the Silsila's books and tafseer. Tapping a work
/// opens its actual pages INSIDE the app — no external viewer, no "download
/// then open" step. The PDF is fetched once and cached for fully offline
/// reading, then rendered with PDFKit with live page tracking and share.
struct BookReaderView: View {
    let item: ContentItem
    let dependencies: AppDependencies

    @State private var phase: Phase = .preparing
    @State private var pageCount: Int = 0
    @State private var currentPage: Int = 1
    @State private var shareURL: URL?

    enum Phase: Equatable {
        case preparing
        case downloading
        case ready(URL)
        case unavailable
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
                if case .ready = phase, let shareURL {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: shareURL) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel(Text("Share"))
                    }
                }
            }
            .task { await prepare() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .preparing, .downloading:
            loadingView
        case .ready(let url):
            readerView(url: url)
        case .unavailable:
            DIEmptyState(
                systemImage: "wifi.exclamationmark",
                titleKey: "Couldn't open this work",
                messageKey: "The pages could not be loaded. Check your connection and try again — once opened, it stays available offline."
            )
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

    private func readerView(url: URL) -> some View {
        ZStack(alignment: .bottom) {
            PDFReaderKit(url: url, pageCount: $pageCount, currentPage: $currentPage)
                .ignoresSafeArea(edges: .bottom)

            if pageCount > 0 {
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
            phase = .unavailable; return
        }

        // Already cached? open instantly, fully offline.
        if let asset = try? await dependencies.downloadsRepository.asset(remoteUrl: urlString),
           let local = dependencies.downloadManager.localURL(for: asset) {
            shareURL = local
            phase = .ready(local)
            return
        }

        // Otherwise fetch once and cache.
        phase = .downloading
        do {
            let asset = try await dependencies.downloadManager.download(
                url: url, forContentItem: item.id, mediaItemID: nil
            )
            if let local = dependencies.downloadManager.localURL(for: asset) {
                shareURL = local
                phase = .ready(local)
            } else {
                phase = .unavailable
            }
        } catch {
            phase = .unavailable
        }
    }
}

/// PDFKit reader with live page tracking. Night mode is applied by the parent
/// as a `.difference` blend overlay (iOS-safe).
private struct PDFReaderKit: UIViewRepresentable {
    let url: URL
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
        if let document = PDFDocument(url: url) {
            view.document = document
            DispatchQueue.main.async { pageCount = document.pageCount }
        }
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged, object: view
        )
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}

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
