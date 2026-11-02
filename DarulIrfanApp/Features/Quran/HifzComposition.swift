import AVFoundation

/// A finite practice item whose recall gaps advance on the player's media
/// clock. The owning audio session can keep it playing without a view timer.
@MainActor
enum HifzComposition {
    enum Failure: Error { case unavailableAudio, invalidSourceDuration }

    /// Missing local downloads cannot recover by buffering. Reject them before
    /// entering AVFoundation, whose asset-loading failure may be delayed.
    static func requireReadableLocalAudio(_ url: URL) throws {
        guard url.isFileURL else { return }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory),
              !directory.boolValue, FileManager.default.isReadableFile(atPath: url.path) else {
            throw Failure.unavailableAudio
        }
    }

    static func make(asset: AVAsset, timeline: HifzPlaybackTimeline) async throws -> AVMutableComposition {
        try Task.checkCancellation()
        if let source = asset as? AVURLAsset { try requireReadableLocalAudio(source.url) }
        guard let source = try await asset.loadTracks(withMediaType: .audio).first else {
            throw Failure.unavailableAudio
        }
        let duration = try await asset.load(.duration)
        guard duration.isNumeric, duration.seconds.isFinite, duration.seconds > 0 else {
            throw Failure.invalidSourceDuration
        }
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Failure.unavailableAudio
        }
        for (index, segment) in timeline.segments.enumerated() {
            if index.isMultiple(of: 64) { await Task.yield() }
            try Task.checkCancellation()
            let at = CMTime(value: segment.startMs, timescale: 1000)
            let length = CMTime(value: segment.durationMs, timescale: 1000)
            if let offset = segment.sourceStartMs {
                let start = CMTime(value: Int64(offset), timescale: 1000)
                guard CMTimeCompare(CMTimeAdd(start, length), duration) <= 0 else {
                    throw Failure.invalidSourceDuration
                }
                try track.insertTimeRange(CMTimeRange(start: start, duration: length), of: source, at: at)
            } else {
                composition.insertEmptyTimeRange(CMTimeRange(start: at, duration: length))
            }
        }
        return composition
    }
}
