#if DEBUG
import AVFoundation
import SwiftUI

/// Writes checkpoints without touching AVAudioSession, so a blocked audio
/// configuration call cannot also prevent the diagnostic from being saved.
enum QuranAudioAuditCheckpoint {
    private static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--uitesting-audio-transport") }
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio-follow-audit.jsonl")
    }
    static func reset() {
        guard enabled else { return }
        try? FileManager.default.removeItem(at: url)
        record(["checkpoint": "app-init"])
    }
    static func record(_ values: [String: Any]) {
        guard enabled else { return }
        var row = values
        row["timestamp"] = Date().timeIntervalSince1970
        guard var data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        data.append(0x0a)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let file = try FileHandle(forWritingTo: url)
                defer { try? file.close() }
                try file.seekToEnd(); try file.write(contentsOf: data)
            } else { try data.write(to: url, options: .atomic) }
        } catch { /* Diagnostic failure must not affect app launch. */ }
    }
}

/// Separates simulator audio-clock, production transport and reader layout failures.
/// Explicit test launch only; never installed as a user-facing route.
@MainActor
struct QuranAudioTransportAuditView: View {
    @State private var phase = "Starting"
    @State private var localPassed = false
    @State private var quranPassed = false
    @State private var localPlayer: AVPlayer?

    var body: some View {
        VStack(spacing: 20) {
            Text(phase).accessibilityIdentifier("transport-phase")
            Text(localPassed ? "PASS" : "FAIL").accessibilityIdentifier("transport-local")
            Text(quranPassed ? "PASS" : "FAIL").accessibilityIdentifier("transport-quran")
        }
        .task { await run() }
        .onDisappear { localPlayer?.pause(); QuranListenPlayer.shared.stop() }
    }

    private func record(_ values: [String: Any]) {
        var row = values
        row["probePhase"] = phase
        row["timestamp"] = Date().timeIntervalSince1970
        let session = AVAudioSession.sharedInstance()
        row["sampleRate"] = session.sampleRate
        row["outputLatency"] = session.outputLatency
        row["outputs"] = session.currentRoute.outputs.map { $0.portType.rawValue }
        QuranAudioAuditCheckpoint.record(row)
    }

    private func run() async {
        QuranAudioAuditCheckpoint.record(["checkpoint": "probe-task-entered"])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audio-clock-probe.wav")
        defer {
            localPlayer?.pause(); localPlayer = nil
            QuranListenPlayer.shared.stop()
            try? FileManager.default.removeItem(at: url)
        }
        do {
            // Real seven-second local PCM asset, no network or reader layout.
            let byteCount: UInt32 = 7 * 8000 * 2
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
            try data.write(to: url)
            QuranAudioAuditCheckpoint.record(["checkpoint": "local-pcm-written"])
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            QuranAudioAuditCheckpoint.record(["checkpoint": "audio-category-set"])
            try AVAudioSession.sharedInstance().setActive(true)
            QuranAudioAuditCheckpoint.record(["checkpoint": "audio-session-active"])
            phase = "Local clock"
            let player = AVPlayer(url: url)
            QuranAudioAuditCheckpoint.record(["checkpoint": "local-player-created"])
            localPlayer = player
            player.play()
            QuranAudioAuditCheckpoint.record(["checkpoint": "local-play-requested"])
            for _ in 0..<10 {
                try await Task.sleep(for: .seconds(1))
                let seconds = player.currentTime().seconds
                if seconds.isFinite && seconds > 1 { localPassed = true }
                QuranAudioAuditCheckpoint.record(["checkpoint": "local-time-read", "seconds": seconds.isFinite ? seconds : -1])
                record(["seconds": seconds.isFinite ? seconds : -1,
                        "rate": player.rate, "itemStatus": player.currentItem?.status.rawValue ?? -1,
                        "timeControlStatus": player.timeControlStatus.rawValue,
                        "itemErrorCode": (player.currentItem?.error as NSError?)?.code ?? 0])
            }
            player.pause(); localPlayer = nil
            phase = "Production transport without reader"
            QuranAudioAuditCheckpoint.record(["checkpoint": "before-recitation-warmup"])
            await RecitationProvider.warmUp()
            QuranAudioAuditCheckpoint.record(["checkpoint": "recitation-warmup-complete"])
            let quran = QuranListenPlayer.shared
            quran.start(from: ListenAyah(surah: 2, ayah: 142), content: .arabic, scope: .surah, translationEdition: nil)
            QuranAudioAuditCheckpoint.record(["checkpoint": "quran-start-returned"])
            for _ in 0..<90 {
                try await Task.sleep(for: .seconds(1))
                record(quran.playbackAuditSample())
                if let current = quran.current, current.surah == 2 && current.ayah >= 143 {
                    quranPassed = true
                    break
                }
            }
            phase = "Done"
            record(["localPassed": localPassed, "quranPassed": quranPassed])
        } catch {
            phase = "Error"
            record(["error": String(describing: error)])
        }
    }
}
#endif
