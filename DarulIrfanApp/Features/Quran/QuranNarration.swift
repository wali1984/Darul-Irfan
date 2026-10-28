import Foundation
import AVFoundation
import Observation

// MARK: - Narration catalog

/// What `GET /v1/audio/quran/manifest` lists: which ayat and tafsir passages
/// have a narration, per edition, and whose recordings each voice is modelled on.
struct NarrationManifest: Codable, Sendable, Equatable {
    struct Voice: Codable, Sendable, Equatable {
        /// The reader whose published recordings the voice is modelled on.
        var name: String
    }

    var version: Int
    /// Keyed by language ("ur", "en").
    var voices: [String: Voice]
    /// edition id -> kind ("translation" / "tafsir") -> file names
    /// ("SSSAAA", or "SSSAAA-EEE" for a passage spanning ayat).
    var editions: [String: [String: [String]]]
}

/// The Silsila's narrated translations and tafsir. One MP3 per ayah (or per
/// tafsir passage), so playback starts and stops on ayah ends. The manifest
/// is fetched from the server and kept on disk, so new narrations reach the
/// app without an update and the list still works offline.
@Observable
@MainActor
final class NarrationCatalog {
    static let shared = NarrationCatalog()

    private(set) var manifest: NarrationManifest?
    @ObservationIgnored private var available: [String: Set<String>] = [:]
    @ObservationIgnored private var loadedAt: Date?

    private static var cacheFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("narration-manifest.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.cacheFile),
           let saved = try? JSONDecoder().decode(NarrationManifest.self, from: data) {
            apply(saved)
        }
    }

    /// Refreshes the manifest at most every 15 minutes.
    func load() async {
        if let loadedAt, Date().timeIntervalSince(loadedAt) < 900 { return }
        let url = OfficialPlatformConfiguration.baseURL.appendingPathComponent("v1/audio/quran/manifest")
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let fresh = try? JSONDecoder().decode(NarrationManifest.self, from: data) else { return }
        loadedAt = Date()
        try? data.write(to: Self.cacheFile, options: .atomic)
        apply(fresh)
    }

    private func apply(_ manifest: NarrationManifest) {
        self.manifest = manifest
        var sets: [String: Set<String>] = [:]
        for (edition, kinds) in manifest.editions {
            for (kind, names) in kinds { sets["\(edition)/\(kind)"] = Set(names) }
        }
        available = sets
    }

    static func name(surah: Int, start: Int, end: Int) -> String {
        let base = String(format: "%03d%03d", surah, start)
        return end == start ? base : base + String(format: "-%03d", end)
    }

    func has(edition: String, kind: String, surah: Int, start: Int, end: Int) -> Bool {
        available["\(edition)/\(kind)"]?.contains(Self.name(surah: surah, start: start, end: end)) ?? false
    }

    func remoteURL(edition: String, kind: String, name: String) -> URL {
        OfficialPlatformConfiguration.baseURL
            .appendingPathComponent("v1/audio/quran/\(edition)/\(kind)/\(name).mp3")
    }

    /// Where a played narration is kept so it plays again offline.
    static func localURL(edition: String, kind: String, name: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("narration/\(edition)/\(kind)/\(name).mp3")
    }

    /// Credit for the voice reading a language, e.g. "Shamshad Ali Khan".
    func voiceName(language: String) -> String? {
        manifest?.voices[language]?.name
    }
}

// MARK: - Narration player

/// Plays the narrated translation (or tafsir) of the ayah the reader chose,
/// then carries on ayah by ayah through the surah while narrations exist,
/// publishing the ayah being read so the reader can highlight it.
@Observable
@MainActor
final class TranslationSpeaker {
    private(set) var isSpeaking = false
    private(set) var currentSurah: Int?
    private(set) var currentAyah: Int?
    private(set) var currentEdition: String?
    private(set) var currentKind: String?

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var passageEnd: Int?
    @ObservationIgnored private var lastAyahInSurah = 0

    /// Starts (or stops) narration at an ayah. `end` is the last ayah of a
    /// tafsir passage; a translation covers one ayah.
    func toggle(edition: String, kind: String = "translation", surah: Int, ayah: Int, end: Int? = nil, lastAyah: Int) {
        if isSounding(surah: surah, ayah: ayah) {
            stop()
        } else {
            lastAyahInSurah = lastAyah
            play(edition: edition, kind: kind, surah: surah, start: ayah, end: end ?? ayah)
        }
    }

    private func play(edition: String, kind: String, surah: Int, start: Int, end: Int) {
        stop()
        let name = NarrationCatalog.name(surah: surah, start: start, end: end)
        let local = NarrationCatalog.localURL(edition: edition, kind: kind, name: name)
        let remote = NarrationCatalog.shared.remoteURL(edition: edition, kind: kind, name: name)
        let source = FileManager.default.fileExists(atPath: local.path) ? local : remote
        if source == remote { Self.keepForOffline(remote, at: local) }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: source)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        currentSurah = surah
        currentAyah = start
        currentEdition = edition
        currentKind = kind
        passageEnd = end
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
        newPlayer.play()
        isSpeaking = true
    }

    /// Next ayah's translation, while one exists. A tafsir passage plays alone.
    private func advance() {
        guard let surah = currentSurah, let edition = currentEdition, currentKind == "translation",
              let end = passageEnd, end < lastAyahInSurah,
              NarrationCatalog.shared.has(edition: edition, kind: "translation", surah: surah, start: end + 1, end: end + 1)
        else {
            stop()
            return
        }
        play(edition: edition, kind: "translation", surah: surah, start: end + 1, end: end + 1)
    }

    private static func keepForOffline(_ remote: URL, at local: URL) {
        Task.detached(priority: .utility) {
            guard let (temporary, response) = try? await URLSession.shared.download(from: remote),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            try? FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: local)
            try? FileManager.default.moveItem(at: temporary, to: local)
        }
    }

    func stop() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
        isSpeaking = false
        currentSurah = nil
        currentAyah = nil
        currentEdition = nil
        currentKind = nil
        passageEnd = nil
    }

    /// True while this exact ayah (or the passage starting at it) is being read.
    func isSounding(surah: Int, ayah: Int) -> Bool {
        isSpeaking && currentSurah == surah && currentAyah == ayah
    }
}
