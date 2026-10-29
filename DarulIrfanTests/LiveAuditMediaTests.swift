import Foundation
import XCTest
@testable import DarulIrfan

/// Video Lectures, the catalogue's container hint, and the zikr sessions'
/// Urdu wording (seeds track requests to the live track, 2026-10-29).
final class LiveAuditMediaTests: XCTestCase {

    private func lecture(_ id: String, category: MediaCategory, youtubeID: String? = nil) -> MediaItem {
        MediaItem(
            id: id, title: id, language: "ur", speaker: nil, date: nil, durationSeconds: nil,
            mediaType: category == .videoLectures ? .youtube : .audio,
            sourceUrl: "https://www.naqshbandiaowaisiah.org/lecture/\(id)",
            streamUrl: category == .videoLectures ? nil : "https://www.naqshbandiaowaisiah.org/uploads/\(id).mp3",
            downloadUrl: nil, youtubeId: youtubeID, year: 2016, month: 4, category: category,
            transcriptUrl: nil, rightsStatus: .linkOnly
        )
    }

    /// Video Lectures lists every lecture with a video: those only on video,
    /// and the audio lectures carrying their official recording.
    func testVideoLecturesListEveryLectureWithAVideo() async throws {
        let database = try await AppDatabase.inMemory()
        let repository = MediaRepository(database: database)
        try await repository.upsertItems([
            lecture("video-only", category: .videoLectures, youtubeID: "abcdefghijk"),
            lecture("audio-with-video", category: .audioLectures, youtubeID: "bcdefghijkl"),
            lecture("audio-only", category: .audioLectures),
        ])
        let videos = try await repository.items(category: .videoLectures, year: nil, month: nil, limit: 100)
        XCTAssertEqual(Set(videos.map(\.id)), ["video-only", "audio-with-video"])
        let audio = try await repository.items(category: .audioLectures, year: nil, month: nil, limit: 100)
        XCTAssertEqual(Set(audio.map(\.id)), ["audio-with-video", "audio-only"])
        let years = try await repository.availableYears(category: .videoLectures)
        XCTAssertEqual(years, [2016])
        XCTAssertTrue(MediaCategory.videoLectures.contains(lecture("x", category: .audioLectures, youtubeID: "cdefghijklm")))
        XCTAssertFalse(MediaCategory.videoLectures.contains(lecture("y", category: .audioLectures)))
        XCTAssertTrue(MediaListFilter.category(.videoLectures).opensVideosFirst)
        XCTAssertFalse(MediaListFilter.category(.audioLectures).opensVideosFirst)
    }

    /// The catalogue says which lectures are MPEG-4 audio under an .mp3 name.
    func testMediaItemReadsTheContainerHint() throws {
        let json = #"{"id":"lecture-3254","title":"Siraj-e-Moneera Conference London","language":"ur","mediaType":"audio","#
            + #""sourceUrl":"https://www.naqshbandiaowaisiah.org/lecture/3254","streamUrl":"https://www.naqshbandiaowaisiah.org/uploads/3254/Facebook_1745322084735.mp3","#
            + #""category":"audioLectures","rightsStatus":"linkOnly","mimeType":"audio/mp4"}"#
        let item = try JSONDecoder().decode(MediaItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.mimeType, "audio/mp4")
        let older = try JSONDecoder().decode(MediaItem.self, from: Data(json.replacingOccurrences(of: #","mimeType":"audio/mp4""#, with: "").utf8))
        XCTAssertNil(older.mimeType)
    }

    /// The Urdu wording shows in the Urdu interface once it is in the
    /// catalogue; until then the English stays.
    func testZikrSessionUrduWordingFallsBackToEnglish() {
        var session = ZikrSession(
            id: "zikr-tahajjud", title: "Tahajjud Zikr", weekdays: Array(1...7), startHour: 4, startMinute: 0,
            durationMinutes: 30, timeZoneIdentifier: "Asia/Karachi", joinUrl: nil, instructions: nil,
            availabilityNote: "Before Fajr, Pakistan time.", sourceUrl: nil
        )
        XCTAssertEqual(session.title(inUrdu: true), "Tahajjud Zikr")
        session.titleUrdu = "تہجد ذکر"
        XCTAssertEqual(session.title(inUrdu: true), "تہجد ذکر")
        XCTAssertEqual(session.title(inUrdu: false), "Tahajjud Zikr")
        XCTAssertEqual(session.availabilityNote(inUrdu: true), "Before Fajr, Pakistan time.")
    }
}
