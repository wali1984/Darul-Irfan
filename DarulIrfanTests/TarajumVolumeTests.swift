import XCTest
@testable import DarulIrfan

/// The Akram-ut-Tarajum volumes open as text: the Qur'an reader at the
/// volume's first ayah, with the Urdu translation.
final class TarajumVolumeTests: XCTestCase {

    func testAllThirtyThreeVolumesOpenAtTheirFirstAyah() throws {
        let items = SeedBundle.libraryItems().filter { $0.category == .quranTranslation }
        XCTAssertEqual(items.count, 33)
        var expected: [String: Int] = [
            "tarajum-Akram-ut-Tarajum-Parah-1-to-30.pdf": 1,
            "tarajum-Akram-ut-Tarajum-Parah-1-to-15.pdf": 1,
            "tarajum-Akram-ut-Tarajum-Parah-16-to-30.pdf": 16,
        ]
        for parah in 1...30 {
            let number = parah < 10 ? "0\(parah)" : "\(parah)"
            expected["tarajum-Akram-ut-Tarajum-Parah\(number).pdf"] = parah
        }
        XCTAssertEqual(Set(items.map(\.id)), Set(expected.keys))
        for item in items {
            let volume = try XCTUnwrap(TarajumVolume(item), item.id)
            let parah = try XCTUnwrap(expected[item.id], item.id)
            XCTAssertEqual(volume.parah, parah, item.id)
            XCTAssertEqual([volume.surah, volume.ayah], QuranDivisions.juzStarts[parah - 1], item.id)
            XCTAssertTrue(BookReadingHistory.hasPDF(item), "\(item.id) keeps its printed pages")
        }
    }

    func testAParahAndACombinedVolume() throws {
        let items = SeedBundle.libraryItems()
        let sixth = try XCTUnwrap(items.first { $0.id == "tarajum-Akram-ut-Tarajum-Parah06.pdf" })
        let secondHalf = try XCTUnwrap(items.first { $0.id == "tarajum-Akram-ut-Tarajum-Parah-16-to-30.pdf" })
        XCTAssertEqual(TarajumVolume(sixth)?.surah, 4)
        XCTAssertEqual(TarajumVolume(sixth)?.ayah, 148)
        XCTAssertEqual(TarajumVolume(secondHalf)?.surah, 18)
        XCTAssertEqual(TarajumVolume(secondHalf)?.ayah, 75)
    }

    func testEveryOtherWorkKeepsTheBookReader() {
        for item in SeedBundle.libraryItems() where item.category != .quranTranslation {
            XCTAssertNil(TarajumVolume(item), item.id)
        }
    }

    /// A volume's reader starts on the Urdu edition, whatever the app's
    /// language, and keeps it for the surahs that follow.
    @MainActor
    func testAVolumeShowsTheUrduEdition() async throws {
        let database = try await AppDatabase.inMemory()
        let repository = QuranRepository(database: database)
        let surah = QuranSurah(
            id: 1,
            nameArabic: "Fixture",
            nameTransliterated: "Al-Fatihah",
            nameEnglish: "The Opening",
            nameUrdu: nil,
            ayahCount: 7,
            revelationPlace: .makkah
        )
        try await repository.upsertSurahs([surah])
        try await repository.upsertAyahs([
            QuranAyah(surahNumber: 1, ayahNumber: 1, textArabic: "Volume reader fixture")
        ])
        let editions: [QuranEdition] = ["en", "ur"].map { language in
            QuranEdition(id: "akram-ut-tarajum-\(language)", title: "Akram-ut-Tarajum", kind: .translation,
                         language: language, author: nil, sourceUrl: nil, rightsStatus: nil, isAvailableOffline: true)
        }
        try await repository.upsertEditions(editions)
        let metrics = DevotionalMetricsSyncService(quranRepository: repository,
            trackerRepository: TrackerRepository(database: database), watchSync: WatchSyncService())
        let reading = TarajumReading()
        XCTAssertTrue(reading.showsTranslation)
        let model = SurahReaderViewModel(surah: surah, repository: repository, devotionalMetrics: metrics,
                                         preferredLanguageCode: reading.language)
        await model.load()
        XCTAssertEqual(model.translationEdition?.id, "akram-ut-tarajum-ur")
        XCTAssertEqual(model.contentMode, .tarajum)
    }
}
