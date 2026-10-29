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
    /// Narrations on the topic, by canonical id ("bukhari|52|52"), built by
    /// Tools/Library/build_topic_references.py from the chapters Imam
    /// an-Nawawi arranged by theme in Riyad as-Salihin and from the books of
    /// Sahih al-Bukhari. Absent from an older topics file.
    var hadithRefs: [String]? = nil

    /// The FTS query for related content (OR of the terms).
    var searchQuery: String { searchTerms.joined(separator: " ") }

    /// Localized display name: Urdu for Urdu content, which includes the
    /// default "System" setting on a phone set to Urdu.
    func name(for language: AppLanguage) -> String {
        if language.contentLanguageCode == "ur", let nameUrdu, !nameUrdu.isEmpty { return nameUrdu }
        return nameEnglish
    }
}

/// A parsed ayah reference (surah + inclusive ayah range).
struct AyahRef: Equatable {
    var surah: Int
    var start: Int
    var end: Int

    /// Parses "13:28" or "33:41-42". A reference that cannot name real ayat
    /// - a reversed range ("2:257-255"), ayah 0, a surah outside 1...114 - is
    /// rejected: topics can arrive remotely, and building a range from a
    /// reversed one stopped the app.
    init?(_ raw: String) {
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let surah = Int(parts[0]), (1...114).contains(surah) else { return nil }
        let ayahPart = parts[1]
        if let dash = ayahPart.firstIndex(of: "-") {
            guard let s = Int(ayahPart[ayahPart.startIndex..<dash]),
                  let e = Int(ayahPart[ayahPart.index(after: dash)...]),
                  s >= 1, e >= s else { return nil }
            self.surah = surah; self.start = s; self.end = e
        } else {
            guard let a = Int(ayahPart), a >= 1 else { return nil }
            self.surah = surah; self.start = a; self.end = a
        }
    }

    var reference: String {
        start == end ? String(localized: "Qur'an \(surah):\(start)") : String(localized: "Qur'an \(surah):\(start)-\(end)")
    }
}
