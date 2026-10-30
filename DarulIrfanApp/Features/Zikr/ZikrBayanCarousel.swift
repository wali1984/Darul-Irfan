import SwiftUI

/// The Recent Bayans as a row of video cards. Each plays in the app's own
/// YouTube player, so watching a bayan never leaves Darul Irfan.
struct ZikrBayanCarousel: View {
    let items: [OfficialFeedItem]
    let play: (OfficialFeedItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        DIHaptics.light()
                        play(item)
                    } label: {
                        ZikrBayanCard(item: item)
                    }
                    .buttonStyle(DIPressableStyle())
                    .accessibilityLabel(Text(verbatim: item.title))
                    .accessibilityHint(Text("Watch in Darul Irfan"))
                    .diAppear(delay: 0.05 * Double(index))
                }
            }
            .padding(.vertical, DISpacing.sm)
            .padding(.horizontal, DISpacing.xs)
        }
    }
}

/// One bayan: its thumbnail with a glass play mark, its title and its day.
private struct ZikrBayanCard: View {
    let item: OfficialFeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DIColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.publishedAt, format: .dateTime.day().month(.wide))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: 236, alignment: .leading)
    }

    private var thumbnail: some View {
        ZStack {
            LinearGradient(
                colors: [DIColor.primary, Color(hex: 0x03261A)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            ZikrOctagramOutline()
                .stroke(DIColor.goldGlow, lineWidth: 1.2)
                .frame(width: 200, height: 200)
                .opacity(0.18)
                .offset(x: 80, y: -50)
            if let imageURL = item.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.clear
                    }
                }
                .frame(width: 236, height: 132)
                .clipped()
            }
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.35)],
                startPoint: .center,
                endPoint: .bottom
            )
            playMark
        }
        .frame(width: 236, height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: DIColor.primaryDeep.opacity(0.16), radius: 13, y: 10)
        .accessibilityHidden(true)
    }

    private var playMark: some View {
        Image(systemName: "play.fill")
            .font(.subheadline)
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1))
            .shadow(color: DIColor.goldGlow.opacity(0.35), radius: 10)
    }
}
