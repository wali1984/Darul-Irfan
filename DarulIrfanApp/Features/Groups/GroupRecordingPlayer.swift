import AVKit
import SwiftUI

/// A recording playing to the group. Everyone hears the same part: pressing
/// play starts it where the group is now, not from the beginning. Audio plays
/// in the app's player, so it carries on from the lock screen and other pages.
@MainActor
struct GroupRecordingPlayer: View {
    let live: GroupLive
    let recording: GroupLiveRecording
    let groupName: String
    let audioPlayer: (any AudioPlayerServicing)?

    @State private var videoPlayer: AVPlayer?
    @State private var starting = false

    /// Stable across reloads; the link's signature changes, its path does not.
    private var itemID: String { "group-recording:\(recording.url.path)" }
    private var inAudioPlayer: Bool { audioPlayer?.nowPlaying?.id == itemID }

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            if let videoPlayer {
                VideoPlayer(player: videoPlayer)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
            }
            if finished {
                Text("The recording has finished.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
            } else if videoPlayer != nil || inAudioPlayer {
                Button {
                    Task { await catchUp() }
                } label: {
                    Label("Catch up with the group", systemImage: "arrow.uturn.forward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DISecondaryButtonStyle())
            } else {
                Button {
                    Task { await listen() }
                } label: {
                    Label(recording.isVideo ? "Watch together" : "Listen together", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DIPrimaryButtonStyle())
                .disabled(starting)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(progress(at: context.date))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(DIColor.textMuted)
            }
        }
        .onDisappear { videoPlayer?.pause() }
    }

    private var finished: Bool {
        guard let total = recording.durationSeconds else { return false }
        return live.playbackOffset() >= TimeInterval(total)
    }

    private func progress(at date: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        let elapsed = formatter.string(from: live.playbackOffset(at: date)) ?? ""
        if let total = recording.durationSeconds, let length = formatter.string(from: TimeInterval(total)) {
            return String(localized: "The group is at \(elapsed) of \(length)")
        }
        return String(localized: "The group is at \(elapsed)")
    }

    private func listen() async {
        starting = true
        defer { starting = false }
        if recording.isVideo || audioPlayer == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            let player = AVPlayer(url: recording.url)
            videoPlayer = player
            await seekWhenReady(player)
            player.play()
        } else if let audioPlayer {
            audioPlayer.play(
                AudioPlayableItem(id: itemID, title: recording.title, subtitle: groupName, url: recording.url, mediaItemID: nil),
                queue: []
            )
            await catchUp()
        }
    }

    /// Moves playback to where the group is now.
    private func catchUp() async {
        if let videoPlayer {
            await seekWhenReady(videoPlayer)
            videoPlayer.play()
        } else if let audioPlayer, inAudioPlayer {
            // The length is known once the file has opened; a seek before
            // then is clamped to nothing.
            var tries = 0
            while audioPlayer.duration <= 0 && tries < 40 {
                try? await Task.sleep(for: .milliseconds(250))
                tries += 1
            }
            audioPlayer.seek(to: live.playbackOffset())
            if !audioPlayer.isPlaying && !audioPlayer.isBuffering { audioPlayer.togglePlayPause() }
        }
    }

    private func seekWhenReady(_ player: AVPlayer) async {
        var tries = 0
        while player.currentItem?.status != .readyToPlay && tries < 40 {
            try? await Task.sleep(for: .milliseconds(250))
            tries += 1
        }
        _ = await player.seek(to: CMTime(seconds: live.playbackOffset(), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
