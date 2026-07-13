import SwiftUI
import PDFKit

/// Native viewer for downloaded PDFs (books, magazines, documents), pushed
/// from a content item's Files section.
struct PDFViewerView: View {
    let fileURL: URL
    let title: String

    @State private var document: PDFDocument? = nil
    @State private var didFinishLoading = false

    var body: some View {
        Group {
            if let document {
                PDFKitView(document: document)
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
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: fileURL) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(Text("Share file"))
            }
        }
        .task {
            if document == nil {
                document = PDFDocument(url: fileURL)
                didFinishLoading = true
            }
        }
    }
}

/// PDFKit PDFView wrapped for SwiftUI with continuous vertical scrolling.
struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document {
            uiView.document = document
        }
    }
}
