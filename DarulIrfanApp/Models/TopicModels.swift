import Foundation

/// A spiritual theme that cross-links content across the whole app: Quran
/// verses, tafseer, books, and audio bayans. Bundled (topics.json) and
/// extendable via the remote manifest.
struct Topic: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var nameEnglish: String
    var nameUrdu: String?
    /// SF Symbol used on the topic card.
    var systemIcon: String
    /// Terms used to find related library/media/event content via FTS search.
    var searchTerms: [String]
    /// Anchor Quran references, "surah:ayah" or "surah:start-end".
    var ayahRefs: [String]

    /// The FTS query for related content (OR of the terms).
    var searchQuery: String { searchTerms.joined(separator: " ") }

    /// Localized display name.
    func name(for language: AppLanguage) -> String {
        if language == .urdu, let nameUrdu, !nameUrdu.isEmpty { return nameUrdu }
        return nameEnglish
    }
}

/// A parsed ayah reference (surah + inclusive ayah range).
struct AyahRef: Equatable {
    var surah: Int
    var start: Int
    var end: Int

    /// Parses "13:28" or "33:41-42".
    init?(_ raw: String) {
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let surah = Int(parts[0]) else { return nil }
        let ayahPart = parts[1]
        if let dash = ayahPart.firstIndex(of: "-") {
            guard let s = Int(ayahPart[ayahPart.startIndex..<dash]),
                  let e = Int(ayahPart[ayahPart.index(after: dash)...]) else { return nil }
            self.surah = surah; self.start = s; self.end = e
        } else {
            guard let a = Int(ayahPart) else { return nil }
            self.surah = surah; self.start = a; self.end = a
        }
    }

    var reference: String {
        start == end ? "Qur'an \(surah):\(start)" : "Qur'an \(surah):\(start)-\(end)"
    }
}
