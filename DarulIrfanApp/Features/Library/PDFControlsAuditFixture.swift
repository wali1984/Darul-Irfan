#if DEBUG
import SwiftUI
import UIKit

/// Local, nonreligious pages for exercising the production downloaded-file
/// viewer. Only reachable with the explicit UI-test launch argument.
struct PDFControlsAuditFixture: View {
    @State private var validURL: URL?
    @State private var damagedURL: URL?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let validURL {
                    NavigationLink {
                        PDFViewerView(fileURL: validURL, title: "PDF control audit")
                    } label: { Text(verbatim: "Open sample PDF") }
                    .accessibilityIdentifier("pdf-audit-valid")
                }
                if let damagedURL {
                    NavigationLink {
                        PDFViewerView(fileURL: damagedURL, title: "Damaged PDF audit")
                    } label: { Text(verbatim: "Open damaged PDF") }
                    .accessibilityIdentifier("pdf-audit-damaged")
                }
                if let failure { Text(verbatim: failure) }
            }
            .buttonStyle(DISecondaryButtonStyle())
            .padding()
            .navigationTitle(Text(verbatim: "PDF audit"))
            .diScreenBackground()
        }
        .task {
            guard validURL == nil else { return }
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-controls-audit", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let valid = folder.appendingPathComponent("sample.pdf")
                let damaged = folder.appendingPathComponent("damaged.pdf")
                let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800))
                let data = renderer.pdfData { context in
                    for page in 1...3 {
                        context.beginPage()
                        for line in 0..<12 {
                            let text = "PDF AUDIT | PAGE \(page) | LINE \(line + 1)"
                            (text as NSString).draw(at: CGPoint(x: 45, y: CGFloat(45 + line * 58)), withAttributes: [
                                .font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor.black
                            ])
                        }
                    }
                }
                try data.write(to: valid, options: .atomic)
                try Data("This is not a PDF".utf8).write(to: damaged, options: .atomic)
                validURL = valid
                damagedURL = damaged
            } catch { failure = error.localizedDescription }
        }
    }
}
#endif
