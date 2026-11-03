import Foundation
import WidgetKit

/// Writes the Ayah of the Day for the phone's next days into the widget
/// snapshot, exactly as Today shows it (TodayDailyViewModel): the same pick
/// (DailySelector, the phone's day), the mushaf's own Arabic, the Silsila's
/// Akram-ut-Tarajum in the reading language and the full reference. The
/// widgets cannot open the Quran database themselves.
@MainActor
enum WidgetAyahSync {
    /// Days written ahead: the nine the prayer snapshot covers.
    static let days = 9

    static func refresh(
        repository: any QuranRepositoryProtocol,
        language: String,
        reference: Date = Date(),
        phoneTimeZone: TimeZone = .autoupdatingCurrent
    ) async {
        let ayat = SeedBundle.dailyAyat()
        guard !ayat.isEmpty, let existing = PrayerWidgetSnapshot.load() else { return }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = phoneTimeZone
        let today = calendar.startOfDay(for: reference)
        var wanted: [(key: String, ayah: DailyAyah)] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day),
                  let ayah = DailySelector.pick(ayat, for: noon, stream: .ayah, timeZone: phoneTimeZone) else { continue }
            wanted.append((PrayerWidgetSnapshot.dayKey(for: noon, in: phoneTimeZone), ayah))
        }

        // Days already written in this language are kept; only the rest
        // are read from the database.
        let kept = (existing.dailyAyahs ?? [:]).filter { key, value in
            value.languageCode == language && wanted.contains { $0.key == key }
        }
        var resolved = kept
        let surahs = (try? await repository.allSurahs()) ?? []
        for (key, ayah) in wanted where resolved[key] == nil {
            resolved[key] = await resolve(ayah, language: language, repository: repository, surahs: surahs)
        }
        guard resolved != (existing.dailyAyahs ?? [:]) else { return }

        // Loaded again with nothing awaited before the save, so a snapshot
        // written meanwhile (a new place or method) is never overwritten.
        guard var snapshot = PrayerWidgetSnapshot.load() else { return }
        snapshot.dailyAyahs = resolved
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func resolve(
        _ ayah: DailyAyah,
        language: String,
        repository: any QuranRepositoryProtocol,
        surahs: [QuranSurah]
    ) async -> WidgetDailyAyah {
        let range = ayah.ayahStart...max(ayah.ayahStart, ayah.ayahEnd)
        let mushaf = ((try? await repository.ayahs(inSurah: ayah.surah)) ?? [])
            .filter { range.contains($0.ayahNumber) }
            .sorted { $0.ayahNumber < $1.ayahNumber }
        let arabic = mushaf.isEmpty ? ayah.arabic : mushaf.map(\.textArabic).joined(separator: " ")
        let rows = ((try? await repository.translations(editionID: "akram-ut-tarajum-\(language)", surahNumber: ayah.surah)) ?? [])
            .filter { range.contains($0.ayahNumber) }
            .sorted { $0.ayahNumber < $1.ayahNumber }
        let translation = rows.isEmpty
            ? ayah.translation(for: language == "ur" ? .urdu : .english)
            : rows.map { row in range.count > 1 ? "\(row.text) (\(row.ayahNumber))" : row.text }.joined(separator: " ")
        let surah = surahs.first { $0.id == ayah.surah }
        let name = (language == "ur" ? surah?.nameArabic : surah?.nameTransliterated) ?? ""
        let verses = range.count > 1 ? "\(range.lowerBound)-\(range.upperBound)" : "\(range.lowerBound)"
        let reference = range.count > 1
            ? String(localized: "Surah \(name) (\(ayah.surah)), Ayat \(verses)")
            : String(localized: "Surah \(name) (\(ayah.surah)), Ayah \(verses)")
        return WidgetDailyAyah(
            surah: ayah.surah,
            ayahStart: range.lowerBound,
            ayahEnd: range.upperBound,
            arabic: arabic,
            translation: translation,
            reference: reference,
            languageCode: language
        )
    }
}
