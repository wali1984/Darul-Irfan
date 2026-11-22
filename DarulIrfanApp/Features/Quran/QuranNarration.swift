import Foundation
import AVFoundation
import Observation

// MARK: - Narration catalog

/// What `GET /v1/audio/quran/manifest` lists: which ayat and tafsir passages
/// have a narration, per edition, and the revision they are at.
struct NarrationManifest: Codable, Sendable, Equatable {
    struct Voice: Codable, Sendable, Equatable {
        var name: String
    }

    var version: Int
    /// Changes whenever narrations are re-made. A list kept on the phone from
    /// before the server sent one has none.
    var revision: String?
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
        let tag = Self.tag(for: manifest)
        let isNewRevision = tag != Self.voiceTag
        Self.voiceTag = tag
        var sets: [String: Set<String>] = [:]
        for (edition, kinds) in manifest.editions {
            for (kind, names) in kinds { sets["\(edition)/\(kind)"] = Set(names) }
        }
        available = sets
        if isNewRevision { Self.removeCopies(otherThan: tag) }
    }

    /// Copies kept under an earlier revision are never played again
    /// (`localURL` names the folder after the current one); they are removed
    /// rather than left filling the phone.
    private static func removeCopies(otherThan tag: String) {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("narration")
        Task.detached(priority: .background) {
            let fileManager = FileManager.default
            guard let folders = try? fileManager.contentsOfDirectory(atPath: root.path) else { return }
            for folder in folders where folder != tag {
                try? fileManager.removeItem(at: root.appendingPathComponent(folder))
            }
        }
    }

    static func name(surah: Int, start: Int, end: Int) -> String {
        let base = String(format: "%03d%03d", surah, start)
        return end == start ? base : base + String(format: "-%03d", end)
    }

    func has(edition: String, kind: String, surah: Int, start: Int, end: Int) -> Bool {
        available["\(edition)/\(kind)"]?.contains(Self.name(surah: surah, start: start, end: end)) ?? false
    }

    /// The file's address, carrying the narration revision. A re-made narration
    /// keeps its file name, and the server lets copies be cached for a week;
    /// with the revision in the address, a cache on the phone or on the way
    /// holds an old recording only under the old address.
    func remoteURL(edition: String, kind: String, name: String) -> URL {
        let file = OfficialPlatformConfiguration.baseURL
            .appendingPathComponent("v1/audio/quran/\(edition)/\(kind)/\(name).mp3")
        var components = URLComponents(url: file, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "v", value: Self.voiceTag)]
        return components?.url ?? file
    }

    /// The revision of the kept narrations. When it changes, earlier copies
    /// are no longer used, so nobody keeps hearing a withdrawn narration or an
    /// uncorrected ayah from their own cache.
    private static var voiceTag = "v0"

    /// The manifest's revision, used as written: the server works it out as
    /// the hash below, so the copies already kept stay in use. It names a
    /// folder that is later swept, so anything but a plain mark is not taken;
    /// then, as for a list without a revision, the hash of `voices` stands in.
    static func tag(for manifest: NarrationManifest) -> String {
        if let revision = manifest.revision,
           revision.range(of: #"^[0-9a-z]{1,13}\z"#, options: .regularExpression) != nil {
            return revision
        }
        let voices = manifest.voices
        let signature = voices.keys.sorted().map { "\($0)=\(voices[$0]?.name ?? "")" }.joined(separator: ";")
        // FNV-1a: stable across launches, unlike hashValue.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in signature.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 36)
    }

    /// Where a played narration is kept so it plays again offline.
    static func localURL(edition: String, kind: String, name: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("narration/\(voiceTag)/\(edition)/\(kind)/\(name).mp3")
    }
}

// MARK: - Narration player

/// Plays the narrated translation (or tafsir) of the ayah the reader chose,
/// then carries on ayah by ayah through the surah while narrations exist,
/// publishing the ayah being read so the reader can highlight it.
@Observable
@MainActor
final class TranslationSpeaker {
    private static weak var active: TranslationSpeaker?
    static func stopActive() { active?.stop() }
    private(set) var isSpeaking = false
    private(set) var currentSurah: Int?
    private(set) var currentAyah: Int?
    private(set) var currentEdition: String?
    private(set) var currentKind: String?

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var bayanObserver: NSObjectProtocol?
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
        if let previous = Self.active, previous !== self { previous.stop() }
        stop()
        Self.active = self
        let name = NarrationCatalog.name(surah: surah, start: start, end: end)
        let local = NarrationCatalog.localURL(edition: edition, kind: kind, name: name)
        let remote = NarrationCatalog.shared.remoteURL(edition: edition, kind: kind, name: name)
        let source = FileManager.default.fileExists(atPath: local.path) ? local : remote
        if source == remote { Self.keepForOffline(remote, at: local) }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        NotificationCenter.default.post(name: .quranAudioWillStart, object: nil)
        bayanObserver = NotificationCenter.default.addObserver(
            forName: .bayanAudioWillStart, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
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

    static func keepForOffline(_ remote: URL, at local: URL) {
        Task.detached(priority: .utility) {
            guard let (temporary, response) = try? await URLSession.shared.download(from: remote),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            try? FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: local)
            try? FileManager.default.moveItem(at: temporary, to: local)
        }
    }

    func stop() {
        if Self.active === self { Self.active = nil }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        if let bayanObserver { NotificationCenter.default.removeObserver(bayanObserver) }
        bayanObserver = nil
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
