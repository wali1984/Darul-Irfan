import Foundation
import XCTest
@testable import DarulIrfan

/// Tests for `MediaRepository`: catalog filters, archive years, playback
/// progress, and "recently played" ordering against an in-memory store.
final class MediaRepositoryTests: XCTestCase {

    private var database: AppDatabase!
    private var repository: MediaRepository!

    override func setUp() async throws {
        database = try await AppDatabase.inMemory()
        repository = MediaRepository(database: database)
    }

    override func tearDown() {
        repository = nil
        database = nil
    }

    // MARK: - Fixtures

    private func makeItem(
        id: String,
        title: String,
        category: MediaCategory,
        year: Int?,
        date: Date? = nil
    ) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            language: "ur",
            speaker: "Hazrat Ameer Abdul Qadeer Awan (MZA)",
            date: date,
            durationSeconds: nil,
            mediaType: .audio,
            sourceUrl: "https://www.naqshbandiaowaisiah.org/lectures",
            streamUrl: "https://www.naqshbandiaowaisiah.org/uploads/\(id).mp3",
            downloadUrl: nil,
            youtubeId: nil,
            year: year,
            month: nil,
            category: category,
            transcriptUrl: nil,
            rightsStatus: .linkOnly
        )
    }

    // MARK: - Available years

    func testAvailableYearsAreDistinctNewestFirstAndSkipNilYears() async throws {
        try await repository.upsertItems([
            makeItem(id: "a", title: "Lecture A", category: .audioLectures, year: 2020),
            makeItem(id: "b", title: "Lecture B", category: .audioLectures, year: 2026),
            makeItem(id: "c", title: "Lecture C", category: .audioLectures, year: 2026),
            makeItem(id: "d", title: "Kalam D", category: .kalamESheikh, year: 1981),
            makeItem(id: "e", title: "Undated E", category: .audioLectures, year: nil),
        ])

        let allYears = try await repository.availableYears(category: nil)
        XCTAssertEqual(allYears, [2026, 2020, 1981])

        let lectureYears = try await repository.availableYears(category: .audioLectures)
        XCTAssertEqual(lectureYears, [2026, 2020])
    }

    // MARK: - Catalog filters

    func testItemsFilterByCategoryAndYear() async throws {
        try await repository.upsertItems([
            makeItem(id: "a", title: "Lecture A", category: .audioLectures, year: 2020),
            makeItem(id: "b", title: "Lecture B", category: .audioLectures, year: 2026),
            makeItem(id: "d", title: "Kalam D", category: .kalamESheikh, year: 2026),
        ])

        let lectures2026 = try await repository.items(
            category: .audioLectures, year: 2026, month: nil, limit: 50
        )
        XCTAssertEqual(lectures2026.map { $0.id }, ["b"])

        let kalam = try await repository.items(
            category: .kalamESheikh, year: nil, month: nil, limit: 50
        )
        XCTAssertEqual(kalam.map { $0.id }, ["d"])
    }

    func testItemByIDRoundtrip() async throws {
        let item = makeItem(
            id: "lecture-3725",
            title: "دعوت و تبلیغ کے اصول",
            category: .audioLectures,
            year: 2026,
            date: Date(timeIntervalSince1970: 1_767_312_000)
        )
        try await repository.upsertItems([item])

        let fetched = try await repository.item(id: "lecture-3725")
        XCTAssertEqual(fetched, item)

        let missing = try await repository.item(id: "nope")
        XCTAssertNil(missing)
    }

    // MARK: - Playback progress

    func testPlaybackProgressRoundtripAndOverwrite() async throws {
        let none = try await repository.playbackProgress(mediaItemID: "a")
        XCTAssertNil(none)

        let initial = PlaybackProgress(
            mediaItemID: "a",
            positionSeconds: 120,
            durationSeconds: 3600,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await repository.savePlaybackProgress(initial)
        let saved = try await repository.playbackProgress(mediaItemID: "a")
        XCTAssertEqual(saved, initial)

        let updated = PlaybackProgress(
            mediaItemID: "a",
            positionSeconds: 900,
            durationSeconds: 3600,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        try await repository.savePlaybackProgress(updated)
        let latest = try await repository.playbackProgress(mediaItemID: "a")
        XCTAssertEqual(latest?.positionSeconds ?? 0, 900, accuracy: 0.001)
    }

    // MARK: - Recently played

    func testRecentlyPlayedOrdersByProgressUpdateNewestFirst() async throws {
        let itemA = makeItem(id: "a", title: "Lecture A", category: .audioLectures, year: 2020)
        let itemB = makeItem(id: "b", title: "Lecture B", category: .audioLectures, year: 2026)
        try await repository.upsertItems([itemA, itemB])

        // A was played longer ago than B.
        try await repository.savePlaybackProgress(PlaybackProgress(
            mediaItemID: "a",
            positionSeconds: 60,
            durationSeconds: 1800,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        try await repository.savePlaybackProgress(PlaybackProgress(
            mediaItemID: "b",
            positionSeconds: 300,
            durationSeconds: 2400,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))

        let recent = try await repository.recentlyPlayed(limit: 10)
        XCTAssertEqual(recent.map { $0.item.id }, ["b", "a"])
        // The joined progress belongs to its item and keeps its own values
        // (the aliased progress duration must not be clobbered by the item's).
        XCTAssertEqual(recent[0].progress.mediaItemID, "b")
        XCTAssertEqual(recent[0].progress.positionSeconds, 300, accuracy: 0.001)
        XCTAssertEqual(recent[0].progress.durationSeconds, 2400, accuracy: 0.001)

        // Limit applies after ordering: only the most recent survives.
        let onlyOne = try await repository.recentlyPlayed(limit: 1)
        XCTAssertEqual(onlyOne.map { $0.item.id }, ["b"])
    }

    // MARK: - Media bookmarks

    func testMediaBookmarksPerItemOrderedByPosition() async throws {
        let late = MediaBookmark(
            id: UUID(),
            mediaItemID: "a",
            positionSeconds: 1200,
            note: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let early = MediaBookmark(
            id: UUID(),
            mediaItemID: "a",
            positionSeconds: 90,
            note: "Key point",
            createdAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        try await repository.addMediaBookmark(late)
        try await repository.addMediaBookmark(early)

        let bookmarks = try await repository.mediaBookmarks(mediaItemID: "a")
        // Per-item listing is position-ordered for in-player display.
        XCTAssertEqual(bookmarks.map { $0.id }, [early.id, late.id])

        try await repository.removeMediaBookmark(id: early.id)
        let remaining = try await repository.mediaBookmarks(mediaItemID: "a")
        XCTAssertEqual(remaining.map { $0.id }, [late.id])
    }

    // MARK: - Playlists

    func testPlaylistSaveUpdateAndDelete() async throws {
        let playlist = Playlist(
            id: UUID(),
            title: "Evening Listening",
            mediaItemIDs: ["a", "b"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await repository.savePlaylist(playlist)
        let playlists = try await repository.playlists()
        XCTAssertEqual(playlists, [playlist])

        var renamed = playlist
        renamed.title = "Morning Listening"
        renamed.updatedAt = Date(timeIntervalSince1970: 1_700_000_500)
        try await repository.savePlaylist(renamed)
        let updated = try await repository.playlists()
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated.first?.title, "Morning Listening")
        XCTAssertEqual(updated.first?.mediaItemIDs, ["a", "b"])

        try await repository.deletePlaylist(id: playlist.id)
        let empty = try await repository.playlists()
        XCTAssertTrue(empty.isEmpty)
    }
}
