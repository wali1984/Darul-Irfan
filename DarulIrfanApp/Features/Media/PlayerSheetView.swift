import Foundation
import Observation
import SwiftUI

// MARK: - View model

/// Bookmark state for the full player sheet. Playback itself is driven
/// directly against `AudioPlayerServicing`; this model only manages the
/// lecture bookmarks, which need the media repository.
@Observable
@MainActor
final class PlayerSheetViewModel {
    private let audioPlayer: any AudioPlayerServicing
    private let mediaRepository: (any MediaRepositoryProtocol)?

    private(set) var bookmarks: [MediaBookmark] = []
    private(set) var pendingBookmarkPosition: Double = 0

    var noteDraft = ""
    var showsAddBookmarkPrompt = false
    var bookmarkErrorMessage: String?

    init(
        audioPlayer: any AudioPlayerServicing,
        mediaRepository: (any MediaRepositoryProtocol)?
    ) {
        self.audioPlayer = audioPlayer
        self.mediaRepository = mediaRepository
    }

    /// Bookmarks require both a repository and a catalog-backed item (the
    /// live stream has no `mediaItemID`, so it cannot be bookmarked).
    var supportsBookmarks: Bool {
        mediaRepository != nil && audioPlayer.nowPlaying?.mediaItemID != nil
    }

    func refreshBookmarks() async {
        guard let repository = mediaRepository,
              let mediaItemID = audioPlayer.nowPlaying?.mediaItemID else {
            bookmarks = []
            return
        }
        do {
            let loaded = try await repository.mediaBookmarks(mediaItemID: mediaItemID)
            bookmarks = loaded.sorted { $0.positionSeconds < $1.positionSeconds }
        } catch {
            bookmarks = []
        }
    }

    /// Captures the current position, then asks the view to prompt for an
    /// optional note (the position must not drift while the user types).
    func beginAddBookmark() {
        pendingBookmarkPosition = audioPlayer.currentTime
        noteDraft = ""
        showsAddBookmarkPrompt = true
    }

    func confirmAddBookmark() async {
        guard let repository = mediaRepository,
              let mediaItemID = audioPlayer.nowPlaying?.mediaItemID else { return }
        let trimmedNote = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmark = MediaBookmark(
            id: UUID(),
            mediaItemID: mediaItemID,
            positionSeconds: pendingBookmarkPosition,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            createdAt: Date()
        )
        do {
            try await repository.addMediaBookmark(bookmark)
            await refreshBookmarks()
        } catch {
            bookmarkErrorMessage = "The bookmark could not be saved. Please try again."
        }
    }

    func deleteBookmark(_ bookmark: MediaBookmark) async {
        guard let repository = mediaRepository else { return }
        do {
            try await repository.removeMediaBookmark(id: bookmark.id)
            await refreshBookmarks()
        } catch {
            bookmarkErrorMessage = "The bookmark could not be removed. Please try again."
        }
    }

    func jump(to bookmark: MediaBookmark) {
        audioPlayer.seek(to: bookmark.positionSeconds)
    }
}

// MARK: - Full player sheet

/// The full-screen player: title/speaker, seek slider, skip controls, speed
/// menu, queue, and lecture bookmarks. Presented from the mini player bar
/// (and available to any other presenter).
struct PlayerSheetView: View {
    private let audioPlayer: any AudioPlayerServicing
    @State private var viewModel: PlayerSheetViewModel
    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0
    @Environment(\.dismiss) private var dismiss

    init(
        audioPlayer: any AudioPlayerServicing,
        mediaRepository: (any MediaRepositoryProtocol)? = nil
    ) {
        self.audioPlayer = audioPlayer
        _viewModel = State(initialValue: PlayerSheetViewModel(
            audioPlayer: audioPlayer,
            mediaRepository: mediaRepository
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if audioPlayer.nowPlaying == nil {
                    DIEmptyState(
                        systemImage: "waveform",
                        titleKey: "Nothing is playing",
                        messageKey: "Choose a lecture from the Media tab to begin listening."
                    )
                    .diOctagramWatermark(size: 280, opacity: 0.05)
                } else {
                    // Poll playback time twice a second so the elapsed time,
                    // slider, and play/pause icon stay fresh regardless of
                    // whether the player implementation is observable.
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        playerContent
                    }
                }
            }
            .diScreenBackground()
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task(id: audioPlayer.nowPlaying?.mediaItemID) {
            await viewModel.refreshBookmarks()
        }
        .alert(
            "Add Bookmark",
            isPresented: Binding(
                get: { viewModel.showsAddBookmarkPrompt },
                set: { viewModel.showsAddBookmarkPrompt = $0 }
            )
        ) {
            TextField(
                "Note (optional)",
                text: Binding(
                    get: { viewModel.noteDraft },
                    set: { viewModel.noteDraft = $0 }
                )
            )
            Button("Save") {
                Task { await viewModel.confirmAddBookmark() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves a bookmark at \(MediaTimeFormat.duration(viewModel.pendingBookmarkPosition)).")
        }
        .alert(
            "Bookmark",
            isPresented: Binding(
                get: { viewModel.bookmarkErrorMessage != nil },
                set: { if !$0 { viewModel.bookmarkErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(viewModel.bookmarkErrorMessage ?? ""))
        }
    }

    // MARK: Live / accent skin

    /// True when the AlMurshid TV live stream is playing — drives the crimson skin.
    private var isLiveStream: Bool {
        audioPlayer.nowPlaying?.id == MediaPlayback.liveStreamID
    }

    private var accent: Color {
        isLiveStream ? DIColor.crimson : DIColor.primary
    }

    private var heroGradient: LinearGradient {
        isLiveStream ? MediaStyle.crimson : DIGradient.emerald
    }

    // MARK: Content

    private var playerContent: some View {
        ScrollView {
            VStack(spacing: DISpacing.lg) {
                header
                seekSection
                transportControls
                speedRow
                if viewModel.supportsBookmarks {
                    bookmarksSection
                }
                if audioPlayer.queue.count > 1 {
                    queueSection
                }
            }
            .padding(DISpacing.md)
        }
    }

    /// A living artwork hero: a gradient medallion with a breathing glow and a
    /// pierced-jali watermark, then the title and speaker.
    private var header: some View {
        VStack(spacing: DISpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DIRadius.lg + 4, style: .continuous)
                    .fill(heroGradient)
                DIOctagram(innerRatio: 0.5)
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: 200, height: 200)
                    .opacity(0.08)
                    .accessibilityHidden(true)
                Image(systemName: isLiveStream ? "dot.radiowaves.left.and.right" : "waveform")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.white)
                    .diBreathingGlow(color: isLiveStream ? DIColor.crimson : DIColor.goldGlow, maxRadius: 18)
            }
            .frame(height: 200)
            .frame(maxWidth: 260)
            .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg + 4, style: .continuous))
            .shadow(color: accent.opacity(0.30), radius: 18, y: 10)

            if isLiveStream {
                MediaLivePill()
            }

            Text(audioPlayer.nowPlaying?.title ?? "")
                .font(DIFont.heading)
                .foregroundStyle(DIColor.textPrimary)
                .multilineTextAlignment(.center)
            if let subtitle = audioPlayer.nowPlaying?.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DISpacing.sm)
    }

    // MARK: Seeking

    private var hasKnownDuration: Bool {
        audioPlayer.duration.isFinite && audioPlayer.duration > 0
    }

    private var seekSection: some View {
        VStack(spacing: DISpacing.xs) {
            if hasKnownDuration {
                Slider(
                    value: Binding(
                        get: {
                            if isScrubbing {
                                return scrubPosition
                            }
                            return min(max(0, audioPlayer.currentTime), audioPlayer.duration)
                        },
                        set: { scrubPosition = $0 }
                    ),
                    in: 0...max(audioPlayer.duration, 1),
                    onEditingChanged: { editing in
                        if editing {
                            scrubPosition = audioPlayer.currentTime
                            isScrubbing = true
                        } else {
                            audioPlayer.seek(to: scrubPosition)
                            isScrubbing = false
                        }
                    }
                )
                .tint(accent)
                .accessibilityLabel(Text("Playback position"))
                HStack {
                    Text(verbatim: MediaTimeFormat.duration(
                        isScrubbing ? scrubPosition : audioPlayer.currentTime
                    ))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DIColor.textMuted)
                    Spacer(minLength: 0)
                    Text(verbatim: MediaTimeFormat.duration(audioPlayer.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DIColor.textMuted)
                }
            } else {
                HStack(spacing: DISpacing.sm) {
                    MediaLivePill()
                    Text("Live stream — seeking is unavailable")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
        }
    }

    // MARK: Transport

    private var transportControls: some View {
        HStack(spacing: DISpacing.lg) {
            transportButton(
                systemImage: "gobackward.30",
                label: "Back 30 seconds"
            ) {
                audioPlayer.skipBackward(30)
            }
            transportButton(
                systemImage: "gobackward.15",
                label: "Back 15 seconds"
            ) {
                audioPlayer.skipBackward(15)
            }
            Button {
                DIHaptics.soft()
                audioPlayer.togglePlayPause()
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 68))
                    .foregroundStyle(accent)
                    .contentTransition(.symbolEffect(.replace))
                    .diBreathingGlow(color: accent.opacity(0.6), maxRadius: 12)
            }
            .buttonStyle(DIPressableStyle())
            .accessibilityLabel(Text(audioPlayer.isPlaying ? "Pause" : "Play"))
            transportButton(
                systemImage: "goforward.15",
                label: "Forward 15 seconds"
            ) {
                audioPlayer.skipForward(15)
            }
            transportButton(
                systemImage: "goforward.30",
                label: "Forward 30 seconds"
            ) {
                audioPlayer.skipForward(30)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func transportButton(
        systemImage: String,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(DIColor.textPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    // MARK: Speed

    private var speedRow: some View {
        HStack {
            Label("Playback speed", systemImage: "speedometer")
                .font(.subheadline)
                .foregroundStyle(DIColor.textMuted)
            Spacer(minLength: 0)
            Menu {
                ForEach(PlaybackSpeed.allCases) { speed in
                    Button {
                        audioPlayer.playbackSpeed = speed
                    } label: {
                        if audioPlayer.playbackSpeed == speed {
                            Label {
                                Text(verbatim: speed.label)
                            } icon: {
                                Image(systemName: "checkmark")
                            }
                        } else {
                            Text(verbatim: speed.label)
                        }
                    }
                }
            } label: {
                Text(verbatim: audioPlayer.playbackSpeed.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, DISpacing.md)
                    .padding(.vertical, DISpacing.xs)
                    .background(accent.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(accent.opacity(0.25), lineWidth: 1))
            }
            .accessibilityLabel(Text("Playback speed, currently \(audioPlayer.playbackSpeed.label)"))
        }
    }

    // MARK: Bookmarks

    private var bookmarksSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Bookmarks", systemImage: "bookmark")
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    Button {
                        DIHaptics.light()
                        viewModel.beginAddBookmark()
                    } label: {
                        Label("Add bookmark at current position", systemImage: "bookmark.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)

                    if viewModel.bookmarks.isEmpty {
                        Text("No bookmarks yet. Save a moment to return to it later.")
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                    } else {
                        ForEach(viewModel.bookmarks) { bookmark in
                            bookmarkRow(bookmark)
                        }
                    }
                }
            }
        }
    }

    private func bookmarkRow(_ bookmark: MediaBookmark) -> some View {
        HStack(spacing: DISpacing.sm) {
            Button {
                viewModel.jump(to: bookmark)
            } label: {
                HStack(spacing: DISpacing.sm) {
                    Text(verbatim: MediaTimeFormat.duration(bookmark.positionSeconds))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(accent)
                    if let note = bookmark.note {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(DIColor.textPrimary)
                            .lineLimit(2)
                    } else {
                        Text("Bookmark")
                            .font(.subheadline)
                            .foregroundStyle(DIColor.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Jump to \(MediaTimeFormat.duration(bookmark.positionSeconds))"))

            Button {
                Task { await viewModel.deleteBookmark(bookmark) }
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.danger)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Delete bookmark"))
        }
        .padding(.vertical, DISpacing.xs)
    }

    // MARK: Queue

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Queue", systemImage: "list.bullet")
            DICard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(audioPlayer.queue) { entry in
                        queueRow(entry)
                        if entry.id != audioPlayer.queue.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func queueRow(_ entry: AudioPlayableItem) -> some View {
        let isCurrent = audioPlayer.nowPlaying?.id == entry.id
        return Button {
            if !isCurrent {
                audioPlayer.play(entry, queue: audioPlayer.queue)
            }
        } label: {
            HStack(spacing: DISpacing.sm) {
                Image(systemName: isCurrent ? "waveform" : "music.note")
                    .font(.subheadline)
                    .foregroundStyle(isCurrent ? DIColor.accent : DIColor.textMuted)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(DIColor.textPrimary)
                        .lineLimit(1)
                    if let subtitle = entry.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(DIColor.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, DISpacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isCurrent ? "Now playing: \(entry.title)" : "Play \(entry.title)"))
    }
}
