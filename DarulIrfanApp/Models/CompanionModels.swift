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
    /// Grouping key: "rabbana" | "masnoon" | "adhkarMorning" | "adhkarEvening".
    /// Optional so older seed rows without it still decode.
    var category: String?
    var rightsStatus: RightsStatus?

    /// Human-readable section title for the dua's category.
    var categoryTitle: String {
        switch category {
        case "rabbana": return "Rabbana Duas (from the Qur'an)"
        case "masnoon": return "Masnoon Duas"
        case "adhkarMorning": return "Morning Adhkar"
        case "adhkarEvening": return "Evening Adhkar"
        default: return "Duas"
        }
    }
}

/// One curated "ayah of the day" candidate. Bundled (daily_ayat.json) so the
/// Today card works fully offline; text is verbatim from api.alquran.cloud
/// (Arabic Uthmani + Pickthall English, both public domain) with Urdu where
/// licensing permits.
struct DailyAyah: Codable, Sendable, Identifiable, Equatable {
    /// "surah:ayah" or "surah:start-end".
    var id: String
    var surah: Int
    var ayahStart: Int
    var ayahEnd: Int
    var reference: String
    var arabic: String
    var english: String?
    var urdu: String?
    var theme: String?

    /// Localized translation for the reader's language, English fallback.
    func translation(for language: AppLanguage) -> String? {
        if language == .urdu, let urdu, !urdu.isEmpty { return urdu }
        return english
    }
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
