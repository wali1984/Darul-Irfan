import Foundation

/// One hadith collection (Sahih al-Bukhari, Sahih Muslim, …).
///
/// The corpus is the public-domain (Unlicense) `hadith-api` data set; every
/// bundled collection carries Arabic, English and Urdu.
/// `Hashable` (which implies `Equatable`) so it can address a `HadithRoute`
/// in a navigation path.
struct HadithBook: Codable, Sendable, Identifiable, Hashable {
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
    /// The collection's books (kutub) — e.g. the 97 books of Sahih al-Bukhari,
    /// each with an English and Arabic title and the number of narrations it
    /// holds. `nil` for a collection whose structure has not been sourced yet,
    /// so the reader falls back to an unbroken listing.
    var sections: [HadithSection]?

    /// Title for the reader's current language.
    func title(languageCode: String) -> String {
        languageCode == "ur" ? titleUrdu : titleEnglish
    }

    /// The book (kitab) a narration belongs to, looked up by its number.
    func section(number: Int?) -> HadithSection? {
        guard let number, let sections else { return nil }
        return sections.first { $0.number == number }
    }
}

/// One book (kitab) within a collection. Sahih al-Bukhari has 97 of these;
/// the reader groups narrations under them.
struct HadithSection: Codable, Sendable, Identifiable, Hashable {
    /// Book number within the collection (1-based), matching the in-book
    /// reference's "Book N".
    var number: Int
    var titleEnglish: String
    var titleArabic: String
    /// Reviewed Urdu kitab title. Older packs omit it and continue to decode.
    var titleUrdu: String? = nil
    /// Narrations in this book, counted from the packaged records.
    var hadithCount: Int

    var id: Int { number }

    /// Title for the reader's current language (Arabic shown alongside).
    func title(languageCode: String) -> String {
        if languageCode == "ur", let titleUrdu, !titleUrdu.isEmpty { return titleUrdu }
        return languageCode == "ur" ? titleArabic : titleEnglish
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

    // MARK: Enriched presentation (schema v6; all optional, all additive)

    /// The Arabic split into ordered, typed spans so the reader can colour the
    /// chain of narration (isnad) and quoted verses distinctly from the matn,
    /// and make narrator names and verses tappable. `nil` until a collection is
    /// ingested with segmentation — the reader then falls back to ``textArabic``.
    var arabicSegments: [HadithSegment]?
    /// Every Qur'an passage this narration quotes, as our own surah:ayah — used
    /// to open the app's Quran reader. Redundant with the `.verse` segments but
    /// kept flat for quick lookup. Never a link to any external site.
    var quranRefs: [QuranRef]?
    /// The Urdu isnad and matn kept apart (sunnah.com serves them split), so the
    /// reader can style the chain and the text distinctly, mirroring the Arabic.
    var urduSanad: String?
    var urduText: String?
    /// The chapter (bab) within the book, finer than ``sourceBook`` (the kitab).
    var chapterNumber: Int?
    var chapterTitleEnglish: String?
    var chapterTitleArabic: String?
    var chapterTitleUrdu: String?

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
        case arabicSegments
        case quranRefs
        case urduSanad
        case urduText
        case chapterNumber
        case chapterTitleEnglish
        case chapterTitleArabic
        case chapterTitleUrdu
    }

    /// The Arabic as segments, always. When the pack has no segmentation yet,
    /// the whole Arabic body is returned as one matn span, so the reader has a
    /// single rendering path and simply shows no colours until data lands.
    func arabicDisplaySegments() -> [HadithSegment] {
        if let arabicSegments, !arabicSegments.isEmpty { return arabicSegments }
        guard let textArabic, !textArabic.isEmpty else { return [] }
        return [HadithSegment(kind: .matn, text: textArabic)]
    }

    /// Chapter (bab) title for the reader's language, if the pack carries it.
    func chapterTitle(languageCode: String) -> String? {
        switch languageCode {
        case "ur": return chapterTitleUrdu ?? chapterTitleEnglish
        case "ar": return chapterTitleArabic
        default: return chapterTitleEnglish
        }
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

/// What a span of Arabic hadith text *is*, so the reader can colour and link it
/// the way the printed/classical presentation does: the chain of narration
/// (isnad) and any quoted Qur'an distinct from the Prophet's words (matn).
enum HadithSegmentKind: String, Codable, Sendable {
    case isnad   // a narrator in the chain — tappable to their biography
    case matn    // the body / the Prophet's words ﷺ
    case verse   // a quoted Qur'an passage — tappable to our Quran reader
}

/// One typed span of the Arabic body. `.isnad` carries the narrator's id;
/// `.verse` carries our own surah:ayah so tapping opens the bundled Quran —
/// never an external link.
struct HadithSegment: Codable, Sendable, Equatable, Hashable {
    var kind: HadithSegmentKind
    var text: String
    var narratorId: Int?
    var surah: Int?
    var ayahStart: Int?
    var ayahEnd: Int?

    init(kind: HadithSegmentKind, text: String, narratorId: Int? = nil,
         surah: Int? = nil, ayahStart: Int? = nil, ayahEnd: Int? = nil) {
        self.kind = kind; self.text = text; self.narratorId = narratorId
        self.surah = surah; self.ayahStart = ayahStart; self.ayahEnd = ayahEnd
    }

    enum CodingKeys: String, CodingKey {
        case kind = "type"
        case text, narratorId, surah, ayahStart, ayahEnd
    }
}

/// A Qur'an passage a hadith quotes, in our own scheme (surah 1-based). Built
/// at ingest time from the source's `openquran(surahIndex,…)` (surahIndex + 1).
struct QuranRef: Codable, Sendable, Equatable, Hashable {
    var surah: Int
    var ayahStart: Int
    var ayahEnd: Int
}

/// A biography for a narrator in the chain, ingested from the source's people
/// database and bundled natively so the reader's tap-to-open bio never calls out
/// to any site. Carries an Arabic-English and an Arabic-Urdu pairing; where a
/// language is not yet available it is `nil` and `needsUrdu`/`needsEnglish`
/// flag it for a reviewed translation pass rather than being fabricated.
struct HadithNarrator: Codable, Sendable, Identifiable, Equatable {
    var id: Int
    var nameEnglish: String?
    var nameArabic: String?
    var nameUrdu: String?
    var kunya: String?
    var kunyaArabic: String?
    var generation: String?
    var generationArabic: String?
    var deathYear: String?
    var deathYearArabic: String?
    /// The narrator's laqab (title/byname), profession, madhhab and the
    /// source's short description — each language in its own key, extracted
    /// from the bio page's labelled pairs. Never cross-filled.
    var byname: String?
    var bynameArabic: String?
    var profession: String?
    var professionArabic: String?
    var madhhab: String?
    var madhhabArabic: String?
    var descriptionEnglish: String?
    var descriptionArabic: String?
    var gradeEnglish: String?
    var gradeArabic: String?
    var gradeUrdu: String?
    var lineageEnglish: String?
    var lineageArabic: String?
    var lineageUrdu: String?
    var cities: String?
    var citiesArabic: String?
    var affiliations: String?
    var affiliationsArabic: String?
    var hadithCount: Int?
    var teacherIds: [Int]?
    var studentIds: [Int]?
    var appraisals: [NarratorAppraisal]?
    /// Long-form biography prose, per language (may be nil).
    var bioEnglish: String?
    var bioUrdu: String?
    var needsEnglish: Bool?
    var needsUrdu: Bool?

    func name(languageCode: String) -> String {
        switch languageCode {
        case "ar": return nameArabic ?? nameEnglish ?? "#\(id)"
        case "ur": return nameUrdu ?? nameArabic ?? nameEnglish ?? "#\(id)"
        default: return nameEnglish ?? nameArabic ?? "#\(id)"
        }
    }
}

/// One scholar's appraisal (jarḥ wa-taʿdīl) of a narrator, Arabic with an
/// optional translation. Never machine-invented; a missing translation stays nil.
struct NarratorAppraisal: Codable, Sendable, Equatable, Hashable {
    var scholar: String?
    var scholarArabic: String?
    var textArabic: String?
    var textEnglish: String?
    var textUrdu: String?
}
