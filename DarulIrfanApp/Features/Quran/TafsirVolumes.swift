import Foundation

/// Where a surah's commentary begins in a printed tafsir volume.
///
/// The per-ayah tafsir tables hold what could be attributed to verses. The
/// volumes hold the whole work, so the reader can always offer the full
/// printed text - for ayat the per-ayah rows do not reach, and for
/// Asrar-at-Tanzil in Urdu, whose scan is not clean enough to key per ayah.
struct TafsirVolume: Codable, Sendable, Identifiable, Equatable {
    /// The tafsir edition this volume belongs to, e.g. `akram-ut-tafaseer-ur`.
    var edition: String
    /// The library item whose pages hold the text.
    var bookID: String
    /// The page the surah's commentary begins on.
    var page: Int

    var id: String { "\(edition)|\(bookID)|\(page)" }

    /// Language of the volume, read from the edition id's suffix.
    var language: String {
        edition.hasSuffix("-ur") ? "ur" : (edition.hasSuffix("-en") ? "en" : "")
    }
}

private struct TafsirVolumeFile: Codable, Sendable {
    var surahs: [String: [TafsirVolume]]
}

/// Reads the bundled `tafsir_volumes.json`, built by
/// `Tools/Library/segment_akram_tafaseer.py`. Like the bayan links it is a
/// small reader-only lookup read straight from the bundle; a missing file
/// only means no volume links are offered.
final class TafsirVolumeProvider: @unchecked Sendable {
    static let shared = TafsirVolumeProvider()
    private let bySurah: [Int: [TafsirVolume]]

    private init() {
        guard let url = SeedBundle.url(forFile: "tafsir_volumes"),
              let raw = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(TafsirVolumeFile.self, from: raw) else {
            bySurah = [:]
            return
        }
        var map: [Int: [TafsirVolume]] = [:]
        for (key, volumes) in file.surahs {
            if let surah = Int(key) { map[surah] = volumes }
        }
        bySurah = map
    }

    /// Volumes of one tafsir (by edition-id prefix) in one language for a
    /// surah, in reading order. A long surah spans several Akram parahs.
    func volumes(surah: Int, editionPrefix: String, language: String) -> [TafsirVolume] {
        (bySurah[surah] ?? []).filter { $0.edition.hasPrefix(editionPrefix) && $0.language == language }
    }
}
