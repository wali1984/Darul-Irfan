import Foundation

/// A bayan the sheikh gave on a specific run of ayat.
///
/// Part of the lecture catalogue is verse-addressed - a 2017 series works
/// through the short surahs an ayah-group at a time - so those lectures can be
/// offered beside the verses they expound.
struct AyahBayanLink: Codable, Sendable, Identifiable, Equatable {
    var surah: Int
    var ayahStart: Int
    var ayahEnd: Int
    /// The lecture in the media catalogue. The stream URL is not copied here:
    /// the catalogue stays the one place a media item is described.
    var mediaID: String
    var title: String

    var id: String { "\(mediaID)#\(surah):\(ayahStart)-\(ayahEnd)" }

    /// The verses as a reader would write them, e.g. "90:8-13".
    var reference: String {
        ayahStart == ayahEnd ? "\(surah):\(ayahStart)" : "\(surah):\(ayahStart)-\(ayahEnd)"
    }

    func covers(ayah: Int) -> Bool { ayahStart <= ayah && ayah <= ayahEnd }
}

private struct AyahBayanLinkFile: Codable, Sendable {
    var generatedAt: String?
    var links: [AyahBayanLink]
}

/// Reads the bundled ayah-to-bayan index.
///
/// Bundled and read straight from the app, like the recitation timings, rather
/// than imported into the content database: it is a small reader-only lookup,
/// so it needs no table and no migration. An absent or unreadable file simply
/// means no bayans are offered, never a failure to open the Quran.
final class AyahBayanLinkProvider: @unchecked Sendable {
    static let shared = AyahBayanLinkProvider()
    private let bySurah: [Int: [AyahBayanLink]]

    private init() {
        guard let url = Bundle.main.url(forResource: "ayah_bayan_links", withExtension: "json"),
              let raw = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(AyahBayanLinkFile.self, from: raw) else {
            bySurah = [:]
            return
        }
        bySurah = Dictionary(grouping: file.links, by: \.surah)
    }

    /// Every bayan on this surah, in reading order.
    func links(surah: Int) -> [AyahBayanLink] {
        (bySurah[surah] ?? []).sorted {
            ($0.ayahStart, $0.ayahEnd) < ($1.ayahStart, $1.ayahEnd)
        }
    }

    /// Bayans covering one ayah, the narrowest range first so the most specific
    /// one is offered before a broader one.
    func links(surah: Int, ayah: Int) -> [AyahBayanLink] {
        (bySurah[surah] ?? [])
            .filter { $0.covers(ayah: ayah) }
            .sorted { ($0.ayahEnd - $0.ayahStart) < ($1.ayahEnd - $1.ayahStart) }
    }
}
