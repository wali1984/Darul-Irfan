import Foundation
import Observation

/// Backs the daily companion cards at the top of the Today tab. Everything is
/// bundled and offline; selection is deterministic by date via `DailySelector`
/// so the whole ummah sees the same "today's ayah" and screenshots are clean.
@Observable
@MainActor
final class TodayDailyViewModel {
    private let appState: AppState
    private let quranRepository: (any QuranRepositoryProtocol)?

    /// The day's ayah as the reader shows it: the mushaf's own Arabic, the
    /// Silsila's Akram-ut-Tarajum in the reading language, a full reference,
    /// a short verbatim tafsir excerpt and any bayan on the verses.
    struct SilsilaAyah: Equatable {
        var arabic: String
        var translation: String?
        /// "Akram-ut-Tarajum" in the app language.
        var translationEdition: String
        /// e.g. "Surah Al-Baqarah (2), Ayat 255" in the app language.
        var reference: String
        var surahNameArabic: String
        var tafsirExcerpt: String?
        var tafsirTitle: String?
        var isUrdu: Bool
        var bayan: AyahBayanLink?
    }

    private(set) var silsilaAyah: SilsilaAyah?

    private(set) var ayah: DailyAyah?
    private(set) var dua: Dua?
    private(set) var name: NameOfAllah?
    private(set) var aqwal: DailyInspiration?
    private(set) var dhikr: DailyDhikr?
    private(set) var isLoaded = false
    /// The local day the cards were chosen for.
    private(set) var loadedDay: Int?

    init(appState: AppState, quranRepository: (any QuranRepositoryProtocol)? = nil) {
        self.appState = appState
        self.quranRepository = quranRepository
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
        loadedDay = DailySelector.epochDay(for: date)
        isLoaded = true
    }

    /// Chooses the day's cards again once the phone's local day has moved on:
    /// past midnight where the phone is, or into another time zone. The tab
    /// stays alive in memory, so this is what makes the cards change daily.
    func refreshIfNewDay(_ date: Date = Date()) async {
        guard DailySelector.epochDay(for: date) != loadedDay else { return }
        load(on: date)
        await loadSilsilaAyah()
    }

    /// Replaces the bundled list's generic translation with the Silsila's
    /// own, read from the Quran database exactly as the reader shows it.
    func loadSilsilaAyah() async {
        guard let ayah, let repository = quranRepository else { return }
        let language = appState.settings.language.contentLanguageCode
        let range = ayah.ayahStart...max(ayah.ayahStart, ayah.ayahEnd)

        let surah = (try? await repository.allSurahs())?.first { $0.id == ayah.surah }
        let mushaf = ((try? await repository.ayahs(inSurah: ayah.surah)) ?? [])
            .filter { range.contains($0.ayahNumber) }
            .sorted { $0.ayahNumber < $1.ayahNumber }
        let arabic = mushaf.isEmpty ? ayah.arabic : mushaf.map(\.textArabic).joined(separator: " ")

        let rows = ((try? await repository.translations(editionID: "akram-ut-tarajum-\(language)", surahNumber: ayah.surah)) ?? [])
            .filter { range.contains($0.ayahNumber) }
            .sorted { $0.ayahNumber < $1.ayahNumber }
        let translation = rows.isEmpty ? nil : rows.map { row in
            range.count > 1 ? "\(row.text) (\(row.ayahNumber))" : row.text
        }.joined(separator: " ")

        let name = surah?.nameTransliterated ?? ""
        let verses = range.count > 1 ? "\(range.lowerBound)-\(range.upperBound)" : "\(range.lowerBound)"
        let reference = range.count > 1
            ? String(localized: "Surah \(name) (\(ayah.surah)), Ayat \(verses)")
            : String(localized: "Surah \(name) (\(ayah.surah)), Ayah \(verses)")

        // A short, verbatim opening of the commentary, labelled with its
        // work: the Silsila's Akram-ut-Tafaseer in Urdu, Asrar-at-Tanzil in
        // English. Never summarised or rewritten.
        let tafsirEdition = language == "ur" ? "akram-ut-tafaseer-ur" : "asrar-at-tanzil-en"
        let tafsirRows = (try? await repository.tafsir(editionID: tafsirEdition, surahNumber: ayah.surah)) ?? []
        let entry = tafsirRows.first { $0.ayahStart <= range.lowerBound && range.lowerBound <= $0.ayahEnd }
        let excerpt = entry.flatMap { Self.commentaryOpening($0.text) }
        let tafsirTitle = language == "ur"
            ? QuranContentMode.akramTafaseer.localizedTitle
            : QuranContentMode.asrarTanzil.localizedTitle

        silsilaAyah = SilsilaAyah(
            arabic: arabic,
            translation: translation ?? ayah.translation(for: language == "ur" ? .urdu : .english),
            translationEdition: QuranContentMode.tarajum.localizedTitle,
            reference: reference,
            surahNameArabic: surah?.nameArabic ?? "",
            tafsirExcerpt: excerpt,
            tafsirTitle: excerpt == nil ? nil : tafsirTitle,
            isUrdu: language == "ur",
            bayan: AyahBayanLinkProvider.shared.links(surah: ayah.surah, ayah: range.lowerBound).first
        )
    }

    /// The first paragraph of prose in a tafsir entry, cut at a sentence
    /// near 320 characters. Skips the section's opening Arabic and numbered
    /// translation, which the card already shows.
    static func commentaryOpening(_ text: String) -> String? {
        let harakat = CharacterSet(charactersIn: "\u{064B}\u{064C}\u{064D}\u{064E}\u{064F}\u{0650}\u{0651}\u{0652}\u{0670}")
        for paragraph in text.components(separatedBy: "\n") {
            let line = paragraph.trimmingCharacters(in: .whitespaces)
            guard line.count >= 80, !line.contains("\u{FD3F}") else { continue }
            let marks = line.unicodeScalars.filter { harakat.contains($0) }.count
            guard Double(marks) < Double(line.count) * 0.05 else { continue }
            guard line.count > 340 else { return line }
            let head = String(line.prefix(340))
            if let stop = head.lastIndex(where: { "۔.!?؟".contains($0) }), head.distance(from: head.startIndex, to: stop) > 120 {
                return String(head[...stop])
            }
            return head + "…"
        }
        return nil
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
        if let silsila = silsilaAyah {
            return ShareableContent(badge: "Ayah of the Day", arabic: silsila.arabic,
                                    translation: silsila.translation,
                                    attribution: "\(silsila.reference) · \(silsila.translationEdition)")
        }
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
