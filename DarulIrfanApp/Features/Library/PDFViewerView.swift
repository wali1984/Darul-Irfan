import SwiftUI
import PDFKit

/// Native viewer for downloaded PDFs (books, magazines, documents), pushed
/// from a content item's Files section.
struct PDFViewerView: View {
    let fileURL: URL
    let title: String

    @State private var document: PDFDocument? = nil
    @State private var didFinishLoading = false
    @State private var zoom = PDFZoomController()

    var body: some View {
        Group {
            if let document {
                VStack(spacing: 0) {
                    PDFZoomControls(controller: zoom)
                    PDFKitView(document: document, zoom: zoom)
                }
            } else if didFinishLoading {
                DIEmptyState(
                    systemImage: "doc.richtext",
                    titleKey: "Unable to open this file",
                    messageKey: "The file may be damaged or not a PDF. Try removing the download and downloading it again."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: DISpacing.md) {
                    DISealEmblem(diameter: 64, glow: true)
                        .diBreathingGlow()
                    ProgressView("Opening…")
                        .tint(DIColor.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .diScreenBackground()
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if document != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: fileURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(Text("Share file"))
                }
            }
        }
        .task {
            if document == nil {
                let opened = PDFDocument(url: fileURL)
                guard !Task.isCancelled else { return }
                document = opened.flatMap { $0.pageCount > 0 ? $0 : nil }
                didFinishLoading = true
            }
        }
    }
}

/// PDFKit PDFView wrapped for SwiftUI with continuous vertical scrolling.
struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    let zoom: PDFZoomController

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.backgroundColor = UIColor(DIColor.background)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        zoom.view = view
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.backgroundColor = UIColor(DIColor.background)
        if uiView.document !== document {
            uiView.document = document
        }
    }
}

/// Shared by downloaded-file and book readers. PDFKit retains its normal
/// pinch gestures; these controls also work with VoiceOver and Switch Control.
@MainActor
final class PDFZoomController {
    weak var view: PDFView?

    func enlarge() { change(by: 1.25) }
    func reduce() { change(by: 1 / 1.25) }
    private func change(by multiplier: CGFloat) {
        guard let view else { return }
        let fitted = view.scaleFactorForSizeToFit
        guard fitted.isFinite, fitted > 0 else { return }
        let target = min(fitted * 4, max(fitted, view.scaleFactor * multiplier))
        view.autoScales = false
        view.scaleFactor = target
    }
    func fit() {
        guard let view else { return }
        view.autoScales = true
        view.scaleFactor = view.scaleFactorForSizeToFit
    }
}

struct PDFZoomControls: View {
    let controller: PDFZoomController

    var body: some View {
        HStack(spacing: DISpacing.sm) {
            zoomButton("Zoom out", symbol: "minus.magnifyingglass", action: controller.reduce)
            zoomButton("Fit page", symbol: "arrow.up.left.and.arrow.down.right", action: controller.fit)
            zoomButton("Zoom in", symbol: "plus.magnifyingglass", action: controller.enlarge)
        }
        .padding(.horizontal, DISpacing.sm)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(DIColor.background)
    }

    private func zoomButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(DICompactButtonStyle())
        .accessibilityLabel(Text(title))
    }
}
