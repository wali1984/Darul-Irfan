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
    /// Counted from the packaged records by `Tools/Hadith/build_hadith_packs.py`,
    /// never copied from upstream metadata, so it cannot over-claim.
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
    /// Review state of the corpus as a whole. Internal metadata, never a label
    /// shown beside a narration.
    var reviewState: ReviewState?
    var books: [HadithBook]
}

/// A single hadith, with each script kept in its own column so the reader can
/// show one, two or all three without re-parsing.
///
/// **Identifiers, not numbers.** A hadith number printed as `402.2` is a label,
/// not a quantity, so it is never stored as `Double`/`REAL`. `displayNumber`
/// holds the source's exact printed form; `numberMajor`/`numberMinor` exist for
/// lookup only. Two collections make the distinction load-bearing:
///
/// * Jami' at-Tirmidhi prints `3604.02 … 3604.09` then `3604.1`, where the last
///   one means sub-number **ten**. Sorted as a decimal it would land first.
/// * Muwatta Malik uses `.25` / `.5` / `.75` as insertion points between whole
///   numbers, so the minor part is not a counter at all.
///
/// Reading order therefore comes from ``sourceSequence`` — the narration's own
/// position in the source edition — which is right in both cases.
struct HadithEntry: Codable, Sendable, Identifiable, Equatable {
    var id: String { canonicalID }

    /// `bookID|displayNumber|sourceSequence`, e.g. `bukhari|402.2|403`.
    /// Primary key of `hadith_entries`; stable across content rebuilds.
    var canonicalID: String
    var bookID: String
    /// The number exactly as the source prints it: "402", "402.2", "3604.1".
    var displayNumber: String
    var numberMajor: Int
    var numberMinor: Int?
    /// 1-based position within the source edition. The reader's sort key.
    var sourceSequence: Int
    var textArabic: String?
    var textEnglish: String?
    var textUrdu: String?
    /// Gradings as printed by the source, "Grader: Grade" (may be empty).
    var grades: [String]?
    /// Reference within the collection: book (chapter) and hadith number.
    var sourceBook: Int?
    var sourceHadith: Int?

    enum CodingKeys: String, CodingKey {
        case canonicalID
        case bookID
        case displayNumber
        case numberMajor
        case numberMinor
        case sourceSequence
        case textArabic = "text_ar"
        case textEnglish = "text_en"
        case textUrdu = "text_ur"
        case grades
        case sourceBook
        case sourceHadith
    }

    /// Text in exactly the language asked for, or nil.
    ///
    /// Deliberately does **not** fall back to another language: showing English
    /// prose in the Urdu reader would render it in Nastaliq and right-to-left,
    /// and repeating the Arabic would present the source text as though it were
    /// its own translation. A missing translation is shown as missing instead —
    /// see `HadithBookView.missingTranslationNote`.
    func text(languageCode: String) -> String? {
        let value: String?
        switch languageCode {
        case "ur": value = textUrdu
        case "ar": value = textArabic
        default: value = textEnglish
        }
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// The best available text *together with the language it is actually in*.
    ///
    /// Used where something must be shown — a search result that matched on a
    /// script the reader is not currently in, say. Returning the language is the
    /// point: the view styles the text for the script it really is, so Urdu
    /// never gets Latin typography and English never gets Nastaliq and RTL.
    func availableText(preferring languageCode: String) -> (text: String, languageCode: String)? {
        let order: [String]
        switch languageCode {
        case "ur": order = ["ur", "en", "ar"]
        case "ar": order = ["ar", "en", "ur"]
        default: order = ["en", "ur", "ar"]
        }
        for code in order {
            if let value = text(languageCode: code) { return (value, code) }
        }
        return nil
    }
}
