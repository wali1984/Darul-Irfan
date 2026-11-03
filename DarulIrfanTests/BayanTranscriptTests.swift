import XCTest
@testable import DarulIrfan

final class BayanTranscriptTests: XCTestCase {
    private let sample = """
    {"id":"lecture-1","title":"Surah Al-A'la","language":"ur","verification":"machine","segments":[
     {"s":0.0,"e":6.0,"t":"بِسْمِ اللهِ الرَّحْمٰنِ الرَّحِيْمِ","kind":"quran","ref":"1:1"},
     {"s":41.76,"e":44.88,"t":"وَالَّذِيْٓ اَخْرَجَ الْمَرْعٰى","kind":"quran","ref":"87:4"},
     {"s":82.02,"e":82.46,"kind":"arabicUnverified"},
     {"s":82.5,"e":84.0,"kind":"arabicUnverified","q":1},
     {"s":84.1,"e":85.0,"kind":"arabicUnverified"},
     {"s":95.73,"e":99.84,"t":"وہ وہ ذات ہے","kind":"speech"},
     {"s":100.0,"e":104.0,"t":"جو زمین سے سبزہ اگاتی ہے","kind":"speech","q":1},
     {"s":110.0,"e":112.0,"t":"أَنْ تَعْبُدَ اللَّهَ كَأَنَّكَ تَرَاهُ","kind":"hadith","ref":"muslim|93|94"},
     {"s":113.0,"e":114.0,"t":"اعوذ باللہ","kind":"dua","ref":"zikr:taawwudh"},
     {"s":115.0,"e":116.0,"t":"والصلوۃ","kind":"dua","ref":"book:uploads-books-kanooz-e-dil-urdu:12"},
     {"s":117.0,"e":118.0,"t":"text without a reference","kind":"quran"},
     {"s":119.0,"e":120.0,"kind":"speech"}
    ]}
    """

    private func decoded() throws -> BayanTranscript {
        try BayanTranscript.decode(Data(sample.utf8))
    }

    func testParsesEveryKindWithItsReference() throws {
        let transcript = try decoded()
        XCTAssertEqual(transcript.id, "lecture-1")
        XCTAssertEqual(transcript.lines.map(\.kind), [.quran, .quran, .arabicUnverified, .speech, .speech, .hadith, .dua, .dua, .arabicUnverified])
        XCTAssertEqual(transcript.lines[1].reference, "87:4")
        XCTAssertEqual(transcript.lines[1].start, 41.76)
        XCTAssertEqual(transcript.lines[5].reference, "muslim|93|94")
        XCTAssertEqual(transcript.lines.map(\.id), Array(0..<9))
    }

    func testSuspectLinesAreMarkedOnlyWhereFlagged() throws {
        let transcript = try decoded()
        XCTAssertFalse(transcript.lines[3].isSuspect)
        XCTAssertTrue(transcript.lines[4].isSuspect)
    }

    func testRecitationMarkersHaveNoTextAndConsecutiveOnesMerge() throws {
        let transcript = try decoded()
        let marker = transcript.lines[2]
        XCTAssertEqual(marker.kind, .arabicUnverified)
        XCTAssertNil(marker.text)
        XCTAssertEqual(marker.start, 82.02)
        XCTAssertEqual(marker.end, 85.0)
    }

    func testAQuranLineWithoutAReferenceNeverShowsItsText() throws {
        let last = try decoded().lines.last
        XCTAssertEqual(last?.kind, .arabicUnverified)
        XCTAssertNil(last?.text)
        XCTAssertNil(last?.reference)
    }

    func testMergingKeepsSeparatedMarkersApart() {
        let lines: [BayanTranscript.Line] = [
            .init(id: 0, start: 0, end: 1, kind: .arabicUnverified),
            .init(id: 0, start: 1, end: 2, kind: .speech, text: "ایک"),
            .init(id: 0, start: 2, end: 3, kind: .arabicUnverified),
            .init(id: 0, start: 3, end: 4, kind: .arabicUnverified),
        ]
        let merged = BayanTranscript.mergingRecitationMarkers(lines)
        XCTAssertEqual(merged.map(\.kind), [.arabicUnverified, .speech, .arabicUnverified])
        XCTAssertEqual(merged[2].start, 2)
        XCTAssertEqual(merged[2].end, 4)
        XCTAssertEqual(merged.map(\.id), [0, 1, 2])
    }

    func testTheActiveLineIsTheLastThatHasStarted() throws {
        let lines = try decoded().lines
        XCTAssertNil(BayanTranscript.activeIndex(in: lines, at: -1))
        XCTAssertEqual(BayanTranscript.activeIndex(in: lines, at: 0), 0)
        XCTAssertEqual(BayanTranscript.activeIndex(in: lines, at: 41.75), 0)
        XCTAssertEqual(BayanTranscript.activeIndex(in: lines, at: 41.76), 1)
        XCTAssertEqual(BayanTranscript.activeIndex(in: lines, at: 83), 2)
        XCTAssertEqual(BayanTranscript.activeIndex(in: lines, at: 99), 3)
        XCTAssertEqual(BayanTranscript.activeIndex(in: lines, at: 10_000), lines.count - 1)
        XCTAssertNil(BayanTranscript.activeIndex(in: [], at: 5))
        XCTAssertNil(BayanTranscript.activeIndex(in: lines, at: .nan))
    }

    func testSearchFindsTextAndSkipsMarkers() throws {
        let transcript = try decoded()
        XCTAssertEqual(transcript.lines(matching: "زمین").map(\.start), [100.0])
        XCTAssertEqual(transcript.lines(matching: "  ").count, transcript.lines.count)
        // Diacritics do not have to be typed.
        XCTAssertEqual(transcript.lines(matching: "الذي").map(\.start), [41.76])
    }

    func testReferencesAndSourceLabels() {
        XCTAssertEqual(QuranReference("87:4"), QuranReference("87:4-6"))
        XCTAssertEqual(QuranReference("87:4")?.surahNumber, 87)
        XCTAssertNil(QuranReference("115:1"))
        XCTAssertNil(QuranReference("2"))
        XCTAssertNil(QuranReference("muslim|93|94"))
        XCTAssertEqual(TranscriptSourceLabel.source(of: "muslim|93|94")?.id, "muslim")
        XCTAssertEqual(TranscriptSourceLabel.source(of: "book:uploads-books-kanooz-e-dil-urdu:12#2")?.id, "uploads-books-kanooz-e-dil-urdu")
        XCTAssertEqual(TranscriptSourceLabel.source(of: "book:uploads-books-kanooz-e-dil-urdu:12")?.isBook, true)
        XCTAssertNil(TranscriptSourceLabel.source(of: "zikr:taawwudh"))

        var titles = TranscriptSourceLabel.Titles()
        titles.collections["muslim"] = ("Sahih Muslim", "صحیح مسلم")
        let hadith = BayanTranscript.Line(id: 0, start: 0, end: 1, kind: .hadith, text: "x", reference: "muslim|93|94")
        XCTAssertEqual(TranscriptSourceLabel.title(for: hadith, titles: titles, urdu: false), "Sahih Muslim")
        XCTAssertEqual(TranscriptSourceLabel.title(for: hadith, titles: titles, urdu: true), "صحیح مسلم")
        let zikr = BayanTranscript.Line(id: 0, start: 0, end: 1, kind: .dua, text: "x", reference: "zikr:taawwudh")
        XCTAssertNil(TranscriptSourceLabel.title(for: zikr, titles: titles, urdu: false))
    }

    func testTimesAreWholeSecondsWithWesternDigits() {
        XCTAssertEqual(BayanTranscript.timeLabel(41.76), "0:41")
        XCTAssertEqual(BayanTranscript.timeLabel(3725.9), "1:02:05")
        XCTAssertEqual(BayanTranscript.timeLabel(-3), "0:00")
    }

    func testOnlyCatalogueIdsBecomeFiles() {
        XCTAssertTrue(BayanTranscriptStore.isMediaID("lecture-1-2017-01-02-surah-al-a-la-ayat-4-to-8"))
        XCTAssertFalse(BayanTranscriptStore.isMediaID("../x"))
        XCTAssertFalse(BayanTranscriptStore.isMediaID("Lecture"))
        XCTAssertFalse(BayanTranscriptStore.isMediaID(""))
        XCTAssertNil(BayanTranscriptStore.fileURL(for: "a/b"))
    }

    func testKeptTranscriptsAreCountedAndCleared() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        BayanTranscriptStore.keep(Data(sample.utf8), for: "lecture-1", directory: directory)
        XCTAssertEqual(BayanTranscriptStore.kept("lecture-1", directory: directory)?.data, Data(sample.utf8))
        XCTAssertEqual(BayanTranscriptStore.kept("lecture-1", directory: directory)?.stale, false)
        XCTAssertEqual(BayanTranscriptStore.kept("lecture-1", directory: directory, now: Date().addingTimeInterval(8 * 24 * 3600))?.stale, true)
        XCTAssertEqual(BayanTranscriptStore.cacheSummary(directory: directory).files, 1)
        XCTAssertEqual(BayanTranscriptStore.clearCache(directory: directory), 0)
        XCTAssertNil(BayanTranscriptStore.kept("lecture-1", directory: directory))
    }

    func testAnEmptyTranscriptIsRefused() {
        XCTAssertThrowsError(try BayanTranscript.decode(Data(#"{"id":"x","segments":[]}"#.utf8)))
        XCTAssertThrowsError(try BayanTranscript.decode(Data("not json".utf8)))
    }
}
