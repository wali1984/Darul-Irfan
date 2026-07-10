import SwiftUI

// MARK: - Optional repository injection

/// Optional environment slot for the media repository. `MiniPlayerBar`'s
/// contract-fixed initializer only receives the audio player, so the full
/// player sheet it presents can only offer lecture bookmarks when RootView
/// (or any ancestor) injects the repository:
///
///     MiniPlayerBar(audioPlayer: dependencies.audioPlayer)
///         .environment(\.diMediaRepository, dependencies.mediaRepository)
///
/// Without the injection the bar and sheet still work fully; only the
/// bookmarks section is omitted.
private struct DIMediaRepositoryKey: EnvironmentKey {
    static let defaultValue: (any MediaRepositoryProtocol)? = nil
}

extension EnvironmentValues {
    var diMediaRepository: (any MediaRepositoryProtocol)? {
        get { self[DIMediaRepositoryKey.self] }
        set { self[DIMediaRepositoryKey.self] = newValue }
    }
}

// MARK: - Mini player bar

/// Compact now-playing bar overlaid above the tab bar by RootView whenever
/// something is playing. Self-contained: tapping the title area presents the
/// full `PlayerSheetView` from within this view.
struct MiniPlayerBar: View {
    private let audioPlayer: any AudioPlayerServicing
    @State private var showsFullPlayer = false
    @Environment(\.diMediaRepository) private var mediaRepository

    init(audioPlayer: any AudioPlayerServicing) {
        self.audioPlayer = audioPlayer
    }

    var body: some View {
        // Poll twice a second so the play/pause icon and the progress line
        // stay fresh regardless of whether the player implementation is
        // observable.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            barContent
        }
        .sheet(isPresented: $showsFullPlayer) {
            PlayerSheetView(audioPlayer: audioPlayer, mediaRepository: mediaRepository)
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var barContent: some View {
        if let nowPlaying = audioPlayer.nowPlaying {
            VStack(spacing: 0) {
                progressLine
                HStack(spacing: DISpacing.sm) {
                    openPlayerButton(nowPlaying)
                    controlButton(
                        systemImage: "gobackward.15",
                        label: "Back 15 seconds"
                    ) {
                        audioPlayer.skipBackward(15)
                    }
                    Button {
                        audioPlayer.togglePlayPause()
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundStyle(DIColor.primary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(audioPlayer.isPlaying ? "Pause" : "Play"))
                    controlButton(
                        systemImage: "xmark",
                        label: "Stop playback"
                    ) {
                        audioPlayer.stop()
                    }
                }
                .padding(.horizontal, DISpacing.md)
                .padding(.vertical, DISpacing.sm)
            }
            .background(DIColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                    .stroke(DIColor.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 8, y: 2)
            .padding(.horizontal, DISpacing.sm)
        }
    }

    private func openPlayerButton(_ nowPlaying: AudioPlayableItem) -> some View {
        Button {
            showsFullPlayer = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DIColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle = nowPlaying.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(DIColor.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Now playing: \(nowPlaying.title)"))
        .accessibilityHint(Text("Opens the full player"))
    }

    private func controlButton(
        systemImage: String,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DIColor.textPrimary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    /// Thin elapsed-fraction line along the top edge of the bar. Fills from
    /// the leading edge, so it mirrors correctly under right-to-left layout.
    private var progressLine: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(DIColor.accent)
                .frame(width: max(0, proxy.size.width * progressFraction))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    private var progressFraction: CGFloat {
        let duration = audioPlayer.duration
        guard duration.isFinite, duration > 0 else { return 0 }
        let fraction = audioPlayer.currentTime / duration
        guard fraction.isFinite else { return 0 }
        return CGFloat(min(1, max(0, fraction)))
    }
}
