import Foundation

// MARK: - Quran structure

/// One of the 114 surahs. Structural metadata is factual and bundled for all 114.
struct QuranSurah: Codable, Sendable, Identifiable, Equatable, Hashable {
    /// Surah number 1...114.
    var id: Int
    /// Arabic name, e.g. "الفاتحة".
    var nameArabic: String
    /// Transliterated name, e.g. "Al-Fatihah".
    var nameTransliterated: String
    /// English meaning, e.g. "The Opening".
    var nameEnglish: String
    /// Urdu name where available.
    var nameUrdu: String?
    var ayahCount: Int
    var revelationPlace: RevelationPlace

    enum RevelationPlace: String, Codable, Sendable {
        case makkah
        case madinah
    }
}

/// A single ayah's Arabic text. Bundled only for surahs included in seed data;
/// additional surahs arrive via downloadable content packs.
struct QuranAyah: Codable, Sendable, Identifiable, Equatable {
    /// "surah:ayah", e.g. "1:1".
    var id: String { "\(surahNumber):\(ayahNumber)" }
    var surahNumber: Int
    var ayahNumber: Int
    /// Uthmani-script Arabic text.
    var textArabic: String

    enum CodingKeys: String, CodingKey {
        case surahNumber, ayahNumber, textArabic
    }
}

/// A translation of one ayah in one edition.
struct QuranTranslation: Codable, Sendable, Identifiable, Equatable {
    var id: String { "\(editionID)|\(surahNumber):\(ayahNumber)" }
    /// Edition identifier, e.g. "akram-ut-tarajum-ur".
    var editionID: String
    var surahNumber: Int
    var ayahNumber: Int
    var text: String

    enum CodingKeys: String, CodingKey {
        case editionID, surahNumber, ayahNumber, text
    }
}

/// Tafsir commentary attached to an ayah or ayah range.
struct QuranTafsir: Codable, Sendable, Identifiable, Equatable {
    var id: String { "\(editionID)|\(surahNumber):\(ayahStart)-\(ayahEnd)" }
    /// e.g. "asrar-at-tanzil-en", "akram-ut-tafasir-ur".
    var editionID: String
    var surahNumber: Int
    var ayahStart: Int
    var ayahEnd: Int
    var text: String
    /// Internal provenance URL used by the content synchronizer.
    var sourceUrl: String?

    enum CodingKeys: String, CodingKey {
        case editionID, surahNumber, ayahStart, ayahEnd, text, sourceUrl
    }
}

/// A translation or tafsir edition available to the reader.
struct QuranEdition: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var title: String
    /// "translation" or "tafsir".
    var kind: Kind
    /// BCP-47 language code: "ur", "en", "ar".
    var language: String
    var author: String?
    var sourceUrl: String?
    var rightsStatus: RightsStatus
    /// Whether the edition's text is bundled/downloaded and readable offline.
    var isAvailableOffline: Bool

    enum Kind: String, Codable, Sendable {
        case translation
        case tafsir
    }
}

// MARK: - Reader state

/// A user bookmark on an ayah.
struct QuranBookmark: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var surahNumber: Int
    var ayahNumber: Int
    var note: String?
    var createdAt: Date
}

/// Last-read position, one per surah plus a global "continue reading".
struct ReadingProgress: Codable, Sendable, Equatable {
    var surahNumber: Int
    var ayahNumber: Int
    var updatedAt: Date
}

/// What the reader shows beneath each ayah's Arabic. The Akram-ut-Tarajum
/// translation always shows; the two tafsir modes additionally reveal the
/// relevant commentary, expandable under the translation.
enum QuranContentMode: String, CaseIterable, Identifiable, Sendable {
    case tarajum
    case asrarTanzil
    case akramTafaseer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tarajum: return "Akram-ut-Tarajum"
        case .asrarTanzil: return "Asrar-at-Tanzil"
        case .akramTafaseer: return "Akram-ut-Tafaseer"
        }
    }

    /// Short label for the segmented selector.
    var shortTitle: String {
        switch self {
        case .tarajum: return "Tarajum"
        case .asrarTanzil: return "Asrar"
        case .akramTafaseer: return "Tafaseer"
        }
    }

    var isTafsir: Bool { self != .tarajum }

    /// Edition-id prefix whose tafsir this mode displays (nil for translation).
    var tafsirEditionPrefix: String? {
        switch self {
        case .tarajum: return nil
        case .asrarTanzil: return "asrar-at-tanzil"
        case .akramTafaseer: return "akram-ut-tafaseer"
        }
    }
}
