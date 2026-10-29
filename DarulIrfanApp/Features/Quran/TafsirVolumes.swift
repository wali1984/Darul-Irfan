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

/// One row of the bundled `book_pages_index.json`: a book and how many text
/// pages the bundle holds for it.
private struct BookPagesIndexEntry: Decodable {
    var bookID: String
    var pages: Int
}

/// Reads the bundled `tafsir_volumes.json`, built by
/// `Tools/Library/segment_akram_tafaseer.py`. Like the bayan links it is a
/// small reader-only lookup read straight from the bundle; a missing file
/// only means no volume links are offered.
final class TafsirVolumeProvider: @unchecked Sendable {
    static let shared = TafsirVolumeProvider()
    private let bySurah: [Int: [TafsirVolume]]
    /// The books the bundle holds text pages for, from
    /// `book_pages_index.json`; nil if that index cannot be read.
    private let booksWithPages: Set<String>?

    private init() {
        booksWithPages = TafsirVolumeProvider.loadBooksWithPages()
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
    /// A volume whose pages are not in the app is left out, so the reader
    /// shows "Tafsir availability" rather than a link to an empty book.
    func volumes(surah: Int, editionPrefix: String, language: String) -> [TafsirVolume] {
        (bySurah[surah] ?? []).filter {
            $0.edition.hasPrefix(editionPrefix) && $0.language == language && hasPages($0.bookID)
        }
    }

    /// Whether the bundle holds text pages for `bookID`. Every volume
    /// counts as having them when the index cannot be read, as before
    /// this check; the volume screen still checks the stored pages.
    func hasPages(_ bookID: String) -> Bool {
        booksWithPages?.contains(bookID) ?? true
    }

    private static func loadBooksWithPages() -> Set<String>? {
        guard let url = SeedBundle.url(forFile: "book_pages_index"),
              let raw = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([BookPagesIndexEntry].self, from: raw) else {
            return nil
        }
        return Set(entries.filter { $0.pages > 0 }.map(\.bookID))
    }
}
