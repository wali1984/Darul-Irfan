import SwiftUI

/// A native, read-only presentation of an official update. `sourceURL` remains
/// transport/provenance metadata and is deliberately not exposed as a handoff.
struct OfficialFeedDetailView: View {
    let item: OfficialFeedItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DISpacing.md) {
                    if let imageURL = item.imageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFit()
                            case .failure: artwork
                            default: ProgressView().frame(maxWidth: .infinity, minHeight: 180)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous))
                    }

                    HStack {
                        Label(sourceName, systemImage: sourceIcon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DIColor.primary)
                        Spacer()
                        Text(item.publishedAt, format: .dateTime.day().month().year())
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                    }

                    Text(item.title)
                        .font(DIFont.heading)
                        .foregroundStyle(DIColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let body = item.body, !body.isEmpty, body != item.title {
                        DICard(padding: DISpacing.lg) {
                            Text(body)
                                .font(.body)
                                .foregroundStyle(DIColor.textPrimary)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(DISpacing.md)
            }
            .diScreenBackground()
            .navigationTitle("Official Update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var artwork: some View {
        ZStack {
            DIGradient.emerald
            Image(systemName: sourceIcon).font(.largeTitle).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var sourceName: LocalizedStringKey {
        switch item.source {
        case .youtube: return "YouTube"
        case .facebook: return "Facebook"
        case .website: return "Article"
        case .announcement: return "Announcement"
        case .event: return "Event"
        }
    }

    private var sourceIcon: String {
        switch item.source {
        case .youtube: return "play.rectangle.fill"
        case .facebook: return "person.2.fill"
        case .website: return "doc.text.fill"
        case .announcement: return "megaphone.fill"
        case .event: return "calendar"
        }
    }
}
