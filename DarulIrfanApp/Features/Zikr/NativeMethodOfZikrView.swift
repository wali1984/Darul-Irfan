import SwiftUI

/// Native presentation of the verified illustrated Method of Zikr entry. The
/// repository may refresh its source metadata remotely, but the user remains
/// inside Darul Irfan for text and images.
struct NativeMethodOfZikrView: View {
    let repository: any ContentRepositoryProtocol
    @State private var item: ContentItem?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                if isLoading {
                    ProgressView("Preparing illustrated method…")
                        .frame(maxWidth: .infinity)
                        .padding(DISpacing.xl)
                } else if let item {
                    Text(verbatim: item.title)
                        .font(DIFont.heading)
                        .foregroundStyle(DIColor.textPrimary)

                    if let text = item.bodyPlainText, !text.isEmpty {
                        DICard(padding: DISpacing.lg) {
                            Text(verbatim: text)
                                .font(.body)
                                .foregroundStyle(DIColor.textPrimary)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ForEach(item.mediaUrls.compactMap { nativeURL($0) }, id: \.absoluteString) { url in
                        DICard(padding: DISpacing.sm) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image): image.resizable().scaledToFit()
                                case .failure:
                                    DIEmptyState(
                                        systemImage: "photo",
                                        titleKey: "Illustration unavailable",
                                        messageKey: "It will be restored automatically after a verified content refresh."
                                    )
                                default:
                                    ProgressView().frame(maxWidth: .infinity, minHeight: 220)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
                        }
                    }
                } else {
                    DIEmptyState(
                        systemImage: "book.pages",
                        titleKey: "Method of Zikr is being prepared",
                        messageKey: "The verified native guide will appear after the next content refresh."
                    )
                }
            }
            .padding(DISpacing.md)
        }
        .navigationTitle("Method of Zikr")
        .navigationBarTitleDisplayMode(.inline)
        .diScreenBackground()
        .task {
            item = try? await repository.item(id: "page-method-of-zikr")
            isLoading = false
        }
    }

    private func nativeURL(_ raw: String) -> URL? {
        URL(string: raw) ?? URL(string: raw.replacingOccurrences(of: " ", with: "%20"))
    }
}
