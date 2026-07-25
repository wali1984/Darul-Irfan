import Foundation
import Observation

/// Backs the daily companion cards at the top of the Today tab. Everything is
/// bundled and offline; selection is deterministic by date via `DailySelector`
/// so the whole ummah sees the same "today's ayah" and screenshots are clean.
@Observable
@MainActor
final class TodayDailyViewModel {
    private let appState: AppState

    private(set) var ayah: DailyAyah?
    private(set) var dua: Dua?
    private(set) var name: NameOfAllah?
    private(set) var aqwal: DailyInspiration?
    private(set) var dhikr: DailyDhikr?
    private(set) var isLoaded = false

    init(appState: AppState) {
        self.appState = appState
    }

    var language: AppLanguage { appState.settings.language }

    func load(on date: Date = Date()) {
        let ayat = SeedBundle.dailyAyat()
        let duas = SeedBundle.duas()
        let names = SeedBundle.namesOfAllah()
        let quotes = SeedBundle.aqwalESheikh()

        ayah = DailySelector.pick(ayat, for: date, stream: .ayah)
        dua = DailySelector.pick(duas, for: date, stream: .dua)
        let nameNumber = DailySelector.nameNumber(for: date)
        name = names.first { $0.id == nameNumber } ?? names.first
        aqwal = DailySelector.pick(quotes, for: date, stream: .aqwal)
        dhikr = DailySelector.pick(DailyDhikr.all, for: date, stream: .dhikr)
        isLoaded = true
    }

    // MARK: - Display helpers

    func ayahTranslation() -> String? { ayah?.translation(for: language) }

    func duaTranslation() -> String? {
        guard let dua else { return nil }
        if language == .urdu, let ur = dua.translationUrdu, !ur.isEmpty { return ur }
        return dua.translationEnglish
    }

    func nameMeaning() -> String? {
        guard let name else { return nil }
        if language == .urdu, let ur = name.meaningUrdu, !ur.isEmpty { return ur }
        return name.meaningEnglish
    }

    // MARK: - Share content

    func ayahShare() -> ShareableContent? {
        guard let ayah else { return nil }
        return ShareableContent(badge: "Ayah of the Day", arabic: ayah.arabic,
                                translation: ayahTranslation(), attribution: ayah.reference)
    }

    func aqwalShare() -> ShareableContent? {
        guard let aqwal else { return nil }
        return ShareableContent(badge: "Aqwal-e-Sheikh", arabic: nil,
                                translation: aqwal.text, attribution: aqwal.attribution)
    }
}

/// A short daily dhikr with an authentic reference and a suggested count.
struct DailyDhikr: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var arabic: String
    var transliteration: String
    var meaning: String
    var count: Int
    var source: String

    /// Bundled in code (small, factual, well-known adhkar with references).
    static let all: [DailyDhikr] = [
        DailyDhikr(id: "subhanallah", arabic: "سُبْحَانَ اللهِ", transliteration: "SubhanAllah",
                   meaning: "Glory be to Allah", count: 33, source: "Sahih al-Bukhari 843"),
        DailyDhikr(id: "alhamdulillah", arabic: "الْحَمْدُ لِلّٰهِ", transliteration: "Alhamdulillah",
                   meaning: "All praise is for Allah", count: 33, source: "Sahih al-Bukhari 843"),
        DailyDhikr(id: "allahuakbar", arabic: "اللهُ أَكْبَرُ", transliteration: "Allahu Akbar",
                   meaning: "Allah is the Greatest", count: 34, source: "Sahih al-Bukhari 843"),
        DailyDhikr(id: "subhanallah-bihamdihi", arabic: "سُبْحَانَ اللهِ وَبِحَمْدِهِ",
                   transliteration: "SubhanAllahi wa bihamdihi", meaning: "Glory and praise be to Allah",
                   count: 100, source: "Sahih al-Bukhari 6405"),
        DailyDhikr(id: "istighfar", arabic: "أَسْتَغْفِرُ اللهَ وَأَتُوبُ إِلَيْهِ",
                   transliteration: "Astaghfirullaha wa atubu ilayh",
                   meaning: "I seek Allah's forgiveness and turn to Him", count: 100, source: "Sahih Muslim 2702"),
        DailyDhikr(id: "tahlil", arabic: "لَا إِلَٰهَ إِلَّا اللهُ",
                   transliteration: "La ilaha illa-Llah", meaning: "There is no god but Allah",
                   count: 100, source: "Sahih al-Bukhari 6403"),
        DailyDhikr(id: "salawat", arabic: "اللهُمَّ صَلِّ عَلَىٰ مُحَمَّدٍ",
                   transliteration: "Allahumma salli 'ala Muhammad",
                   meaning: "O Allah, send blessings upon Muhammad ﷺ", count: 100, source: "Sahih Muslim 408"),
    ]
}
