import AVKit
import CoreTransferable
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Pictures and videos on Halqah posts: chosen or pasted in the composer, sent
// to the group's private storage, and shown and played on the post.

/// A picture or video waiting in the composer.
struct PostDraftAttachment: Identifiable {
    enum Content {
        case picture(Data)
        case video(URL)
    }

    let id = UUID()
    var content: Content
    var preview: UIImage?

    var isVideo: Bool {
        if case .video = content { return true }
        return false
    }
}

/// A video from Photos, copied to a file the app may read while it is sent.
struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension.lowercased()
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

enum PostMediaPreparation {
    /// A picture as a JPEG no larger than 2048 pixels across.
    static func picture(from image: UIImage) -> (Data, UIImage)? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 2048 / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return nil }
        return (data, resized)
    }

    /// The first frame of a video, for its tile in the composer.
    static func thumbnail(of url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        guard let frame = try? await generator.image(at: .zero).image else { return nil }
        return UIImage(cgImage: frame)
    }

    /// Loads what was chosen in Photos, pictures and videos alike.
    static func load(_ item: PhotosPickerItem) async -> PostDraftAttachment? {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            guard let video = try? await item.loadTransferable(type: PickedVideo.self) else { return nil }
            return PostDraftAttachment(content: .video(video.url), preview: await thumbnail(of: video.url))
        }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
              let prepared = picture(from: image) else { return nil }
        return PostDraftAttachment(content: .picture(prepared.0), preview: prepared.1)
    }

    static func videoType(_ url: URL) -> String {
        url.pathExtension.lowercased() == "mov" ? "video/quicktime" : "video/mp4"
    }
}

/// The composer's row of chosen pictures and videos, each removable.
struct PostAttachmentStrip: View {
    @Binding var attachments: [PostDraftAttachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DISpacing.sm) {
                ForEach(attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let preview = attachment.preview {
                                Image(uiImage: preview).resizable().scaledToFill()
                            } else {
                                DIColor.sandstone
                            }
                        }
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            if attachment.isVideo {
                                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.white).shadow(radius: 2)
                            }
                        }
                        Button {
                            attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.title3).symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.black.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .accessibilityLabel(Text("Remove"))
                    }
                }
            }
        }
    }
}

// MARK: - On the post

/// A post's pictures and videos: one shown whole, several to swipe through.
struct PostMediaView: View {
    let media: [PostAttachment]

    var body: some View {
        if media.count == 1, let only = media.first {
            tile(only)
        } else if !media.isEmpty {
            TabView {
                ForEach(media) { item in tile(item).padding(.bottom, 28) }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 300)
        }
    }

    @ViewBuilder
    private func tile(_ item: PostAttachment) -> some View {
        if item.kind == "video" {
            PostVideoTile(url: item.url)
        } else {
            AsyncImage(url: item.url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                case .failure:
                    Label("The picture could not be loaded. Pull down to refresh.", systemImage: "photo")
                        .font(.caption).foregroundStyle(DIColor.textMuted)
                default: ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
            .accessibilityLabel(Text("Picture"))
        }
    }
}

/// A video that loads only when tapped, so a page of posts stays light.
private struct PostVideoTile: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                Button {
                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                    let player = AVPlayer(url: url)
                    self.player = player
                    player.play()
                } label: {
                    ZStack {
                        Rectangle().fill(Color.black.opacity(0.85))
                        Label("Play the video", systemImage: "play.circle.fill")
                            .font(.headline).foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
        .onDisappear { player?.pause() }
    }
}
