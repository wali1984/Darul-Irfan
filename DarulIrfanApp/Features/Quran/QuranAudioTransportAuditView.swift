#if DEBUG
import AVFoundation
import SwiftUI

/// Separates simulator audio-clock, production transport and reader layout failures.
/// Explicit test launch only; never installed as a user-facing route.
@MainActor
struct QuranAudioTransportAuditView: View {
    @State private var phase = "Starting"
    @State private var localPassed = false
    @State private var quranPassed = false
    @State private var localPlayer: AVPlayer?
    @State private var samples = Data()

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
        if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) {
            samples.append(data); samples.append(0x0a)
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("audio-follow-audit.jsonl")
            try? samples.write(to: url, options: .atomic)
        }
    }

    private func run() async {
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
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            phase = "Local clock"
            let player = AVPlayer(url: url)
            localPlayer = player
            player.play()
            for _ in 0..<10 {
                try await Task.sleep(for: .seconds(1))
                let seconds = player.currentTime().seconds
                if seconds.isFinite && seconds > 1 { localPassed = true }
                record(["seconds": seconds.isFinite ? seconds : -1,
                        "rate": player.rate, "itemStatus": player.currentItem?.status.rawValue ?? -1,
                        "timeControlStatus": player.timeControlStatus.rawValue,
                        "itemErrorCode": (player.currentItem?.error as NSError?)?.code ?? 0])
            }
            player.pause(); localPlayer = nil
            phase = "Production transport without reader"
            await RecitationProvider.warmUp()
            let quran = QuranListenPlayer.shared
            quran.start(from: ListenAyah(surah: 2, ayah: 142), content: .arabic, scope: .surah, translationEdition: nil)
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
