import Foundation

/// Media-time schedule for persistent practice playback. Recall intervals are
/// finite parts of the practice, not UI timers or an indefinite keep-alive.
struct HifzPlaybackTimeline {
    struct Segment: Equatable {
        let ayah: Int
        let repetition: Int
        let sourceStartMs: Int? // nil is the learner's recall interval
        let startMs: Int64
        let durationMs: Int64
        var endMs: Int64 { startMs + durationMs }
    }

    enum Invalid: Error { case settings, timing }
    let segments: [Segment]
    var durationMs: Int64 { segments.last?.endMs ?? 0 }

    init(recitation: SurahRecitation, range: ClosedRange<Int>, repeats: Int,
         pauseSeconds: Double, startingAyah: Int? = nil) throws {
        guard range.lowerBound >= 1, range.upperBound <= 286, (1...20).contains(repeats),
              pauseSeconds.isFinite, (0...10).contains(pauseSeconds) else { throw Invalid.settings }
        let first = min(max(startingAyah ?? range.lowerBound, range.lowerBound), range.upperBound)
        let gap = Int64((pauseSeconds * 1000).rounded())
        var result: [Segment] = []
        var cursor: Int64 = 0
        for ayah in first...range.upperBound {
            // Summary duration is rounded/stale in the provider data. Precise
            // verse windows are authoritative; the player checks the actual asset.
            guard let verse = recitation.verse(ayah), verse.fromMs >= 0,
                  verse.toMs > verse.fromMs else { throw Invalid.timing }
            for repetition in 1...repeats {
                let duration = Int64(verse.toMs - verse.fromMs)
                result.append(Segment(ayah: ayah, repetition: repetition,
                    sourceStartMs: verse.fromMs, startMs: cursor, durationMs: duration))
                cursor += duration
                if gap > 0 && (ayah != range.upperBound || repetition != repeats) {
                    result.append(Segment(ayah: ayah, repetition: repetition,
                        sourceStartMs: nil, startMs: cursor, durationMs: gap))
                    cursor += gap
                }
            }
        }
        segments = result
    }

    /// Half-open bounds ensure the UI moves to the next segment at its start.
    func segment(at milliseconds: Int64) -> Segment? {
        guard milliseconds >= 0, milliseconds < durationMs else { return nil }
        var low = 0
        var high = segments.count
        while low < high {
            let middle = (low + high) / 2
            if segments[middle].endMs <= milliseconds { low = middle + 1 }
            else { high = middle }
        }
        return low < segments.count ? segments[low] : nil
    }
}
