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
                let available = CMTimeSubtract(duration, start)
                let excess = CMTimeSubtract(length, available)
                // The bundled end markers include a short encoder/tail overhang
                // (up to ~2.91s in the current source). Never request samples
                // beyond EOF; retain the timeline with silence for that tail.
                guard CMTimeCompare(available, .zero) > 0, excess.seconds <= 5 else {
                    throw Failure.invalidSourceDuration
                }
                let playable = CMTimeMinimum(length, available)
                try track.insertTimeRange(CMTimeRange(start: start, duration: playable), of: source, at: at)
                if CMTimeCompare(playable, length) < 0 {
                    composition.insertEmptyTimeRange(CMTimeRange(start: CMTimeAdd(at, playable), duration: CMTimeSubtract(length, playable)))
                }
            } else {
                composition.insertEmptyTimeRange(CMTimeRange(start: at, duration: length))
            }
        }
        // AVFoundation excludes trailing empty segments from asset duration,
        // even when explicitly assigned to track.segments. Use actual silent
        // PCM samples at the end so repeat timing survives in AVPlayer. They
        // get their own track: the source is an MP3, never mixed with PCM.
        if let final = timeline.segments.last {
            let expectedEnd = CMTime(value: final.startMs + final.durationMs, timescale: 1000)
            let actualEnd = try await composition.load(.duration)
            if CMTimeCompare(actualEnd, expectedEnd) < 0 {
                let missing = CMTimeMinimum(CMTimeSubtract(expectedEnd, actualEnd), CMTime(value: 5, timescale: 1))
                await appendSilentTail(to: composition, at: actualEnd, duration: missing)
                try Task.checkCancellation()
            }
        }
        return composition
    }

    /// Every word of the recitation is already in place, so a failure here only
    /// ends the item slightly early. It must never cost the learner the verse.
    private static func appendSilentTail(to composition: AVMutableComposition, at start: CMTime, duration: CMTime) async {
        var tail: AVMutableCompositionTrack?
        do {
            let silence = AVURLAsset(url: try silenceURL())
            guard let silentTrack = try await silence.loadTracks(withMediaType: .audio).first else { return }
            tail = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try tail?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: silentTrack, at: start)
        } catch {
            if let tail { composition.removeTrack(tail) }
        }
    }

    /// A small shared PCM file must outlive the composition reading it. Store
    /// it in caches, never in user recordings or backup, and reuse valid bytes.
    private static func silenceURL() throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hifz-silence", isDirectory: true)
        let url = directory.appendingPathComponent("pcm-8000-mono-5s.wav")
        let byteCount: UInt32 = 5 * 8000 * 2
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); number(UInt32(36) + byteCount); text("WAVEfmt ")
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(8000)); number(UInt32(16000)); number(UInt16(2)); number(UInt16(16))
        text("data"); number(byteCount); data.append(Data(count: Int(byteCount)))
        if (try? Data(contentsOf: url)) != data {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        return url
    }
}
