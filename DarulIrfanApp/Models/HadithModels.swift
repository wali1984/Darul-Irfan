import Foundation

/// One hadith collection (Sahih al-Bukhari, Sahih Muslim, …).
///
/// The corpus is the public-domain (Unlicense) `hadith-api` data set; every
/// bundled collection carries Arabic, English and Urdu.
struct HadithBook: Codable, Sendable, Identifiable, Equatable {
    /// Stable slug, e.g. "bukhari" — also the seed pack file name.
    var id: String
    var titleEnglish: String
    var titleUrdu: String
    var hadithCount: Int
    var hasArabic: Bool
    var hasEnglish: Bool
    var hasUrdu: Bool
    var sectionCount: Int

    /// Title for the reader's current language.
    func title(languageCode: String) -> String {
        languageCode == "ur" ? titleUrdu : titleEnglish
    }
}

/// The seed index file: the collections plus the provenance of the corpus.
struct HadithCatalog: Codable, Sendable, Equatable {
    var source: String?
    var license: String?
    var licenseUrl: String?
    var languages: [String]?
    var books: [HadithBook]
}

/// A single hadith, with each script kept in its own column so the reader can
/// show one, two or all three without re-parsing.
struct HadithEntry: Codable, Sendable, Identifiable, Equatable {
    var id: String { "\(bookID)|\(hadithNumber)" }

    var bookID: String
    var hadithNumber: Int
    var textArabic: String?
    var textEnglish: String?
    var textUrdu: String?
    /// Gradings as printed by the source (may be empty).
    var grades: [String]?
    /// Reference within the collection: book (chapter) and hadith number.
    var refBook: Int?
    var refHadith: Int?

    enum CodingKeys: String, CodingKey {
        case bookID
        case hadithNumber
        case textArabic = "text_ar"
        case textEnglish = "text_en"
        case textUrdu = "text_ur"
        case grades
        case refBook
        case refHadith
    }

    /// Text for a language, falling back to English then Arabic so a hadith is
    /// never shown blank when one script is missing.
    func text(languageCode: String) -> String? {
        let preferred: String?
        switch languageCode {
        case "ur": preferred = textUrdu
        case "ar": preferred = textArabic
        default: preferred = textEnglish
        }
        if let preferred, !preferred.isEmpty { return preferred }
        if let textEnglish, !textEnglish.isEmpty { return textEnglish }
        return textArabic
    }
}
