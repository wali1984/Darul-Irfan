import Foundation

// Share for the daily cards that had none before the October 2026 redesign
// gave every card its Share: the hadith, the dua, the zikr and the Name.
// Each shares exactly what its card shows, as the ayah and the saying do;
// nothing here changes which content the day has.

extension TodayDailyViewModel {
    /// The day's hadith as its card shows it: the narration, its Arabic and
    /// its reference.
    func hadithShare() -> ShareableContent? {
        guard let hadith else { return nil }
        let title = hadith.book.map { readsUrdu ? $0.titleUrdu : $0.titleEnglish } ?? ""
        return ShareableContent(
            badge: String(localized: "Hadith of the Day"),
            arabic: hadith.arabic,
            translation: hadith.translation,
            attribution: "\(title) \(hadith.number)".trimmingCharacters(in: .whitespaces)
        )
    }

    /// The day's dua: its Arabic, its translation in the reading language,
    /// and its source.
    func duaShare() -> ShareableContent? {
        guard let dua else { return nil }
        return ShareableContent(
            badge: String(localized: "Dua of the Day"),
            arabic: dua.arabic,
            translation: duaTranslation(),
            attribution: DailyNoorText.reference(dua.source, urdu: readsUrdu)
        )
    }

    /// The day's zikr: the words, their transliteration and meaning, and
    /// the source.
    func dhikrShare() -> ShareableContent? {
        guard let dhikr else { return nil }
        return ShareableContent(
            badge: String(localized: "Zikr of the Day"),
            arabic: dhikr.arabic,
            translation: readsUrdu ? DailyNoorText.localized(dhikr.meaning, urdu: true) : "\(dhikr.transliteration)\n\(dhikr.meaning)",
            attribution: DailyNoorText.reference(dhikr.source, urdu: readsUrdu)
        )
    }

    /// The day's Name of Allah: the Name, its transliteration and meaning.
    func nameShare() -> ShareableContent? {
        guard let name else { return nil }
        let meaning = nameMeaning() ?? ""
        return ShareableContent(
            badge: String(localized: "Name of the Day"),
            arabic: name.arabic,
            translation: readsUrdu ? meaning : (meaning.isEmpty ? name.transliteration : "\(name.transliteration)\n\(meaning)"),
            attribution: String(localized: "99 Names")
        )
    }
}
