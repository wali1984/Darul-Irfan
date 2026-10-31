import XCTest
@testable import DarulIrfan

/// Hadith search over the folded index: vowelled Arabic found as typed,
/// results led by Sahih al-Bukhari and Sahih Muslim rather than by whichever
/// collection sorts first by name, and the total known (HAD-009, HAD-010).
final class HadithSearchTests: XCTestCase {
    private var database: AppDatabase!
    private var repository: HadithRepository!

    override func setUp() async throws {
        try await super.setUp()
        database = try await AppDatabase.inMemory()
        repository = HadithRepository(database: database)
    }

    override func tearDown() async throws {
        repository = nil
        database = nil
        try await super.tearDown()
    }

    private func entry(
        _ book: String, _ sequence: Int, arabic: String = "", english: String = "",
        sourceBook: Int? = nil, urduReviewState: String? = nil, urduSource: String? = nil
    ) -> HadithEntry {
        HadithEntry(
            canonicalID: "\(book)|\(sequence)|\(sequence)",
            bookID: book,
            displayNumber: "\(sequence)",
            numberMajor: sequence,
            numberMinor: nil,
            sourceSequence: sequence,
            textArabic: arabic,
            textEnglish: english,
            textUrdu: nil,
            sourceBook: sourceBook,
            urduReviewState: urduReviewState,
            urduSource: urduSource
        )
    }

    private let niyyah = "إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ"

    func testReferenceSearchWorksBeforeIndexAndDoesNotMatchBodyDigits() async throws {
        try await repository.upsertEntries([
            entry("abudawud", 773, english: "Praise"),
            entry("abudawud", 774, english: "The number 773 in prose"),
            entry("bukhari", 773, english: "Another collection"),
            entry("abudawud", 1, english: "First narration"),
        ])
        let results = try await repository.search("#773", bookID: "abudawud", limit: 20)
        XCTAssertEqual(results.map(\.displayNumber), ["773"])
        let count = try await repository.searchCount("773", bookID: nil)
        XCTAssertEqual(count, 2)
        let first = try await repository.search("1", bookID: "abudawud", limit: 20)
        XCTAssertEqual(first.map(\.displayNumber), ["1"])
        XCTAssertEqual(HadithRepository.referenceNumber(" #119A "), "119a")
        XCTAssertNil(HadithRepository.referenceNumber("773 prayers"))
    }

    private func seedThreeCollections() async throws {
        try await repository.upsertEntries([
            entry("abudawud", 1, arabic: niyyah, english: "Actions are by intentions"),
            entry("abudawud", 2, arabic: "قَالَ رَسُولُ اللَّهِ", english: "Prayer"),
            entry("bukhari", 1, arabic: niyyah, english: "Actions are by intentions"),
            entry("muslim", 1, arabic: niyyah, english: "Actions are by intentions"),
        ])
        await LargeSearchIndexBuilder.shared.buildStaleIndexes(database: database)
    }

    func testUnvowelledArabicFindsVowelledText() async throws {
        try await seedThreeCollections()
        let results = try await repository.search("الاعمال", bookID: nil, limit: 100)
        XCTAssertEqual(results.count, 3)
    }

    func testCollectionsComeInReadingOrder() async throws {
        try await seedThreeCollections()
        let results = try await repository.search("intentions", bookID: nil, limit: 100)
        XCTAssertEqual(results.map(\.bookID), ["bukhari", "muslim", "abudawud"])
        let count = try await repository.searchCount("intentions", bookID: nil)
        XCTAssertEqual(count, 3)
        let inMuslim = try await repository.search("intentions", bookID: "muslim", limit: 100)
        XCTAssertEqual(inMuslim.map(\.canonicalID), ["muslim|1|1"])
    }

    /// Until the index is built the substring search answers, in the same order.
    func testSubstringSearchAnswersBeforeTheIndexIsBuilt() async throws {
        try await repository.upsertEntries([
            entry("abudawud", 1, english: "Actions are by intentions"),
            entry("bukhari", 1, english: "Actions are by intentions"),
        ])
        let results = try await repository.search("intentions", bookID: nil, limit: 100)
        XCTAssertEqual(results.map(\.bookID), ["bukhari", "abudawud"])
    }

    /// Contents opens a kitab where its run of narrations starts, not at a
    /// single mislabelled row inside another book (HAD-011).
    func testFirstEntryOfABookSkipsAStrayRow() async throws {
        var rows: [HadithEntry] = []
        for sequence in 1...5 { rows.append(entry("muslim", sequence, english: "faith", sourceBook: 1)) }
        rows.append(entry("muslim", 6, english: "stray", sourceBook: 43))
        for sequence in 7...10 { rows.append(entry("muslim", sequence, english: "faith", sourceBook: 1)) }
        for sequence in 11...14 { rows.append(entry("muslim", sequence, english: "virtues", sourceBook: 43)) }
        try await repository.upsertEntries(rows)
        let first = try await repository.firstEntry(bookID: "muslim", sourceBook: 43)
        XCTAssertEqual(first?.sourceSequence, 11)
    }

    /// The provenance of a provisional Urdu text survives the store, so its
    /// notice can show (HAD-013).
    func testProvisionalUrduKeepsItsReviewState() async throws {
        try await repository.upsertEntries([
            entry("mishkat", 1, english: "x", urduReviewState: "machine_provisional", urduSource: "ahlesunnatpak.com"),
        ])
        let stored = try await repository.entries(bookID: "mishkat", limit: 10, offset: 0)
        XCTAssertEqual(stored.first?.urduReviewState, "machine_provisional")
        XCTAssertEqual(stored.first?.urduSource, "ahlesunnatpak.com")
        XCTAssertEqual(stored.first?.isProvisional(languageCode: "ur"), true)
        XCTAssertEqual(stored.first?.isProvisional(languageCode: "en"), false)
    }

    /// The collection list leads with the two Sahihs, not the largest works.
    func testCollectionListLeadsWithTheSahihs() async throws {
        func book(_ id: String, _ count: Int) -> HadithBook {
            HadithBook(id: id, titleEnglish: id, titleUrdu: id, hadithCount: count, hasArabic: true,
                       hasEnglish: id != "abdurrazzaq", hasUrdu: false, sectionCount: 0, sections: nil)
        }
        try await repository.upsertBooks([book("abdurrazzaq", 15_088), book("muslim", 7_482), book("bukhari", 7_583)])
        let books = try await repository.books()
        XCTAssertEqual(books.map(\.id), ["bukhari", "muslim", "abdurrazzaq"])
    }
}
