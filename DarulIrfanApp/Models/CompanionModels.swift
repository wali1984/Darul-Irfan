import Foundation

// MARK: - Daily companion content

/// One of the 99 Names of Allah (Asma-ul-Husna). Factual religious content
/// bundled from a verified public source; see Resources/SeedData/names_of_allah.json.
struct NameOfAllah: Codable, Sendable, Identifiable, Equatable {
    /// 1...99.
    var id: Int
    var arabic: String
    var transliteration: String
    var meaningEnglish: String
    var meaningUrdu: String?
}

/// A dua with verified source (Quranic duas are public-domain Arabic text).
struct Dua: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var title: String
    var arabic: String
    var translationEnglish: String?
    var translationUrdu: String?
    /// e.g. "Quran 2:201" — always present; content must be source-verified.
    var source: String
}

/// The "daily inspiration" card: an ayah reference, tafsir excerpt, or
/// Aqwal-e-Sheikh quote (only where rights permit).
struct DailyInspiration: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var kind: Kind
    /// Arabic/Urdu/English primary text (short excerpt or reference).
    var text: String
    /// e.g. "Surah Al-Fatihah 1:5" or the book/page attribution.
    var attribution: String
    var sourceUrl: String?
    var rightsStatus: RightsStatus

    enum Kind: String, Codable, Sendable {
        case ayah
        case tafsirExcerpt
        case aqwalESheikh
        case dua
    }
}

// MARK: - Islamic calendar

/// A notable Islamic day (bundled, factual).
struct IslamicDay: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var title: String
    /// Hijri month 1...12.
    var hijriMonth: Int
    /// Hijri day of month.
    var hijriDay: Int
    var note: String?
}

/// User's Hijri display preferences.
struct HijriPreferences: Codable, Sendable, Equatable {
    /// Day offset applied to the Umm al-Qura calendar, -2...+2.
    var dayOffset: Int = 0
}

// MARK: - Ramadan

/// Fasting record for one Ramadan day.
struct FastingLogEntry: Codable, Sendable, Identifiable, Equatable {
    /// Civil day key "yyyy-MM-dd".
    var id: String { dayKey }
    var dayKey: String
    var fasted: Bool
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case dayKey, fasted, updatedAt
    }
}
