import SwiftUI

// Pictures for the Today page, published by the Super admin for a local day:
// on the Ayah of the Day, Hadith of the Day and Aqwal-e-Sheikh cards, a daily
// quote that opens over the page, and announcements.

struct DailyMediaItem: Codable, Sendable, Identifiable, Equatable {
    enum Slot: String, Codable, Sendable, CaseIterable, Identifiable {
        case ayah, hadith, aqwal, quote, announcement
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .ayah: "Ayah of the Day"
            case .hadith: "Hadith of the Day"
            case .aqwal: "Aqwal-e-Sheikh"
            case .quote: "Daily quote"
            case .announcement: "Announcement"
            }
        }
    }

    var id: String
    /// Unknown places from a newer server are dropped, not failed.
    var slot: Slot?
    var day: String?
    var endDay: String?
    var caption: String?
    var popup: Bool
    var imageURL: URL?
    /// The Super admin's list only.
    var status: String?
    var source: String?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey { case id, slot, day, endDay, caption, popup, imageURL, status, source, createdAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        slot = (try? container.decode(String.self, forKey: .slot)).flatMap(Slot.init(rawValue:))
        day = try container.decodeIfPresent(String.self, forKey: .day)
        endDay = try container.decodeIfPresent(String.self, forKey: .endDay)
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        popup = (try? container.decode(Bool.self, forKey: .popup)) ?? false
        imageURL = try? container.decodeIfPresent(URL.self, forKey: .imageURL)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

struct DailyMediaList: Codable, Sendable {
    var items: [DailyMediaItem]
}

/// A published picture inside a Today card. Tapping opens it whole.
struct DailyPicture: View {
    let item: DailyMediaItem
    @State private var enlarged = false

    var body: some View {
        if let url = item.imageURL {
            Button { enlarged = true } label: {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        VStack(spacing: DISpacing.sm) {
                            Text("The picture could not be loaded. Please try again.")
                                .font(.footnote)
                                .foregroundStyle(DIColor.textMuted)
                            Label("Open", systemImage: "photo")
                                .foregroundStyle(DIColor.actionForeground)
                        }
                        .frame(maxWidth: .infinity, minHeight: 160)
                    default:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
            }
            .buttonStyle(DIPressableStyle())
            .accessibilityLabel(Text(verbatim: item.caption ?? String(localized: "Picture")))
            .fullScreenCover(isPresented: $enlarged) { DailyPictureViewer(item: item) }
        }
        if let caption = item.caption, !caption.isEmpty {
            Text(verbatim: caption)
                .font(.subheadline)
                .foregroundStyle(DIColor.textPrimary)
        }
    }
}

/// A picture whole, over everything: the daily quote's pop-up, and any
/// picture tapped on the Today page.
struct DailyPictureViewer: View {
    let item: DailyMediaItem
    @Environment(\.dismiss) private var dismiss
    @State private var imageAttempt = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DISpacing.md) {
                    if let url = item.imageURL {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFit()
                            } else if case .failure = phase {
                                VStack(spacing: DISpacing.md) {
                                    Text("The picture could not be loaded. Please try again.")
                                        .foregroundStyle(DIColor.textMuted)
                                    Button("Retry") { imageAttempt += 1 }
                                        .buttonStyle(DICompactButtonStyle())
                                }
                                .frame(maxWidth: .infinity, minHeight: 300)
                            } else {
                                ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                            }
                        }
                        .id(imageAttempt)
                        .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
                    }
                    if let caption = item.caption, !caption.isEmpty {
                        Text(verbatim: caption).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let url = item.imageURL {
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                            .buttonStyle(DICompactButtonStyle())
                    }
                }
                .padding(DISpacing.md)
            }
            .diScreenBackground()
            .navigationTitle(item.slot?.title ?? "Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .buttonStyle(DICompactButtonStyle())
                }
            }
        }
    }
}
