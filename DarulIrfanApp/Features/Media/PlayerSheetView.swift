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
    private var pendingBookmarkMediaID: String?
    private var bookmarkLoadGeneration = 0
    private var displayedBookmarkMediaID: String?

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
        bookmarkLoadGeneration += 1
        let generation = bookmarkLoadGeneration
        guard let repository = mediaRepository,
              let mediaItemID = audioPlayer.nowPlaying?.mediaItemID else {
            bookmarks = []
            displayedBookmarkMediaID = nil
            return
        }
        if displayedBookmarkMediaID != mediaItemID { bookmarks = [] }
        displayedBookmarkMediaID = mediaItemID
        do {
            let loaded = try await repository.mediaBookmarks(mediaItemID: mediaItemID)
            guard generation == bookmarkLoadGeneration,
                  audioPlayer.nowPlaying?.mediaItemID == mediaItemID else { return }
            bookmarks = loaded.sorted { $0.positionSeconds < $1.positionSeconds }
        } catch {
            guard generation == bookmarkLoadGeneration else { return }
            bookmarks = []
        }
    }

    /// Captures the current position, then asks the view to prompt for an
    /// optional note (the position must not drift while the user types).
    func beginAddBookmark() {
        guard supportsBookmarks, let mediaID = audioPlayer.nowPlaying?.mediaItemID else { return }
        pendingBookmarkMediaID = mediaID
        pendingBookmarkPosition = audioPlayer.currentTime
        noteDraft = ""
        showsAddBookmarkPrompt = true
    }

    func confirmAddBookmark() async {
        guard let repository = mediaRepository,
              let mediaItemID = pendingBookmarkMediaID else { return }
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
        guard audioPlayer.nowPlaying?.mediaItemID == bookmark.mediaItemID else { return }
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
    @State private var transcript = BayanTranscriptModel()
    @State private var pane: PlayerPane = .audio
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
                    VStack(spacing: 0) {
                        if let error = audioPlayer.playbackError {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(LocalizedStringKey(error)).diInterfaceFont(.callout)
                                Button("Retry") { audioPlayer.togglePlayPause() }.buttonStyle(DICompactButtonStyle())
                            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                        } else if audioPlayer.isBuffering {
                            ProgressView("Buffering…").padding()
                        }
                        if showsTranscriptSwitch {
                            DISegmentedControl(
                                items: PlayerPane.allCases,
                                title: { LocalizedStringKey($0.rawValue) },
                                selection: $pane
                            )
                            .padding(.horizontal, DISpacing.md)
                            .padding(.top, DISpacing.sm)
                        }
                        if pane == .transcript && showsTranscriptSwitch {
                            transcriptPane
                        } else {
                            playerContent
                        }
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
        .task(id: audioPlayer.nowPlaying?.mediaItemID) {
            await transcript.load(mediaItemID: audioPlayer.nowPlaying?.mediaItemID)
        }
        .onChange(of: transcript.state) { _, state in
            // A bayan without a transcript has no switch: back to the player.
            if state == .unavailable || state == .idle { pane = .audio }
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

    // MARK: Transcript

    /// The switch shows once the bayan has a transcript, and stays while the
    /// next bayan's loads or fails on the Transcript pane.
    private var showsTranscriptSwitch: Bool {
        if transcript.transcript != nil { return true }
        return pane == .transcript && (transcript.state == .loading || transcript.state == .failed)
    }

    /// The title, position and transport above the transcript's lines.
    private var transcriptPane: some View {
        VStack(spacing: DISpacing.sm) {
            VStack(spacing: DISpacing.sm) {
                Text(audioPlayer.nowPlaying?.title ?? "")
                    .diInterfaceFont(.headline, weight: .semibold, design: .serif)
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let subtitle = audioPlayer.nowPlaying?.subtitle {
                    Text(subtitle)
                        .diInterfaceFont(.caption)
                        .foregroundStyle(DIColor.textMuted)
                        .lineLimit(1)
                }
                seekSection
                transportControls
            }
            .padding(.horizontal, DISpacing.md)
            .padding(.top, DISpacing.sm)
            BayanTranscriptView(model: transcript, audioPlayer: audioPlayer, onOpenQuran: { dismiss() })
        }
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
                .diInterfaceFont(.title2, weight: .semibold, design: .serif)
                .foregroundStyle(DIColor.textPrimary)
                .multilineTextAlignment(.center)
            if let subtitle = audioPlayer.nowPlaying?.subtitle {
                Text(subtitle)
                    .diInterfaceFont(.subheadline)
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
            } else if isLiveStream {
                HStack(spacing: DISpacing.sm) {
                    MediaLivePill()
                    Text("Live stream — seeking is unavailable")
                        .diInterfaceFont(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
            } else {
                // A lecture whose length has not loaded yet: the catalogue
                // carries no durations, so every lecture starts here.
                HStack(spacing: DISpacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading")
                        .diInterfaceFont(.caption)
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
            .accessibilityLabel(Text(audioPlayer.playbackError != nil ? "Retry" : (audioPlayer.isPlaying || audioPlayer.isBuffering) ? "Pause" : "Play"))
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
                .diInterfaceFont(.title2)
                .foregroundStyle(DIColor.textPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    // MARK: Speed

    private var speedRow: some View {
        HStack {
            Label("Playback speed", systemImage: "speedometer")
                .diInterfaceFont(.subheadline)
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
                    .diInterfaceFont(.subheadline, weight: .semibold)
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
                    }
                    .buttonStyle(DISecondaryButtonStyle())

                    if viewModel.bookmarks.isEmpty {
                        Text("No bookmarks yet. Save a moment to return to it later.")
                            .diInterfaceFont(.caption)
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
                            .diInterfaceFont(.subheadline)
                            .foregroundStyle(DIColor.textPrimary)
                            .lineLimit(2)
                    } else {
                        Text("Bookmark")
                            .diInterfaceFont(.subheadline)
                            .foregroundStyle(DIColor.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(DICompactButtonStyle(minimumHeight: 48))
            .accessibilityLabel(Text("Jump to \(MediaTimeFormat.duration(bookmark.positionSeconds))"))

            Button {
                Task { await viewModel.deleteBookmark(bookmark) }
            } label: {
                Image(systemName: "trash")
                    .diInterfaceFont(.subheadline)
                    .foregroundStyle(DIColor.danger)
            }
            .buttonStyle(DICompactButtonStyle(destructive: true, minimumHeight: 48))
            .accessibilityLabel(Text("Delete bookmark"))
        }
        .padding(.vertical, DISpacing.xs)
    }

    // MARK: Queue

    /// The rows the queue shows: the lecture playing and those after it. A
    /// category's queue holds hundreds, and this sheet is redrawn twice a
    /// second while audio plays.
    private var queueWindow: (rows: ArraySlice<AudioPlayableItem>, moreCount: Int) {
        let queue = audioPlayer.queue
        let current = queue.firstIndex { $0.id == audioPlayer.nowPlaying?.id } ?? 0
        let start = max(0, current - 2)
        let end = min(queue.count, start + 20)
        return (queue[start..<end], queue.count - (end - start))
    }

    private var queueSection: some View {
        let window = queueWindow
        return VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Queue", systemImage: "list.bullet")
            DICard {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(window.rows) { entry in
                        queueRow(entry)
                        if entry.id != window.rows.last?.id {
                            Divider()
                        }
                    }
                }
            }
            if window.moreCount > 0 {
                Text("\(window.moreCount) more in the queue")
                    .diInterfaceFont(.caption)
                    .foregroundStyle(DIColor.textMuted)
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
                    .diInterfaceFont(.subheadline)
                    .foregroundStyle(isCurrent ? DIColor.accent : DIColor.textMuted)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(DIColor.textPrimary)
                        .lineLimit(1)
                    if let subtitle = entry.subtitle {
                        Text(subtitle)
                            .diInterfaceFont(.caption2)
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
