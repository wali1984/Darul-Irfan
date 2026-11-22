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
                            .diInterfaceFont(.caption, weight: .semibold)
                            .foregroundStyle(DIColor.primary)
                        Spacer()
                        Text(item.publishedAt, format: .dateTime.day().month().year())
                            .diInterfaceFont(.caption)
                            .foregroundStyle(DIColor.textMuted)
                    }

                    // A post's title is how its text begins: the text is
                    // shown alone, not its opening words twice.
                    if !item.titleRepeatsBody {
                        Text(item.title)
                            .diInterfaceFont(.title2, weight: .semibold, design: .serif)
                            .foregroundStyle(DIColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let body = item.body, !body.isEmpty, item.titleRepeatsBody || body != item.title {
                        DICard(padding: DISpacing.lg) {
                            Text(body)
                                .diInterfaceFont(.body)
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
            Image(systemName: sourceIcon).diInterfaceFont(.largeTitle).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var sourceName: LocalizedStringKey {
        switch item.source {
        case .youtube: return "Video"
        case .facebook: return "Post"
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

extension OfficialFeedItem {
    /// Whether the title only repeats how the text begins. A Facebook post
    /// has no headline, so its opening words stand as its title, ending in
    /// an ellipsis when the post goes on; the sheet then shows the text
    /// alone.
    var titleRepeatsBody: Bool {
        guard source == .facebook, let text = body, !text.isEmpty else { return false }
        var opening = Substring(title)
        while let last = opening.last, last == "…" || last.isWhitespace {
            opening.removeLast()
        }
        guard !opening.isEmpty else { return false }
        // By code point, so a title cut inside a letter and its marks
        // still counts as the start of the text.
        return text.unicodeScalars.starts(with: opening.unicodeScalars)
    }
}
