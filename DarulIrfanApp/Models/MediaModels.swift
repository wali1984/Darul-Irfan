import Foundation

// MARK: - Media catalog

enum MediaType: String, Codable, Sendable, CaseIterable {
    case audio
    case video
    case youtube
}

/// Curated media sections mirroring the website's multimedia library.
enum MediaCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case audioLectures
    case videoLectures
    case tafseerQuranVideos
    case alMurshidTV
    case alMurshidQA
    case shortClips
    case recommended
    case kalamESheikh

    var id: String { rawValue }
    var localizationKey: String { "media.category.\(rawValue)" }

    var englishName: String {
        switch self {
        case .audioLectures: return "Audio Lectures"
        case .videoLectures: return "Video Lectures"
        case .tafseerQuranVideos: return "Tafseer-e-Quran"
        case .alMurshidTV: return "AlMurshid TV"
        case .alMurshidQA: return "AlMurshid Q&A"
        case .shortClips: return "Short Clips"
        case .recommended: return "Recommended"
        case .kalamESheikh: return "Kalam-e-Sheikh"
        }
    }
}

/// One lecture/bayan/video. Mirrors the ingest pipeline's `media.json` schema (v1).
struct MediaItem: Codable, Sendable, Identifiable, Equatable {
    /// Stable ID derived by the ingest tool from the source URL.
    var id: String
    var title: String
    /// BCP-47: "ur", "en", "ar".
    var language: String
    var speaker: String?
    var date: Date?
    /// Duration in seconds where known.
    var durationSeconds: Double?
    var mediaType: MediaType
    /// The website page this item came from.
    var sourceUrl: String
    /// Directly streamable URL (MP3 etc.). WMA URLs are excluded at ingest —
    /// iOS cannot play WMA.
    var streamUrl: String?
    var downloadUrl: String?
    var youtubeId: String?
    var year: Int?
    var month: Int?
    var category: MediaCategory
    var transcriptUrl: String?
    var rightsStatus: RightsStatus

    /// Whether the item can be played natively in-app (vs. opened externally).
    var isNativelyPlayable: Bool {
        mediaType == .audio && streamUrl != nil
    }
}

// MARK: - Playback state

/// Saved position within a media item, for "continue listening".
struct PlaybackProgress: Codable, Sendable, Identifiable, Equatable {
    var id: String { mediaItemID }
    var mediaItemID: String
    var positionSeconds: Double
    var durationSeconds: Double
    var updatedAt: Date

    var fractionCompleted: Double {
        durationSeconds > 0 ? min(1.0, positionSeconds / durationSeconds) : 0
    }

    enum CodingKeys: String, CodingKey {
        case mediaItemID, positionSeconds, durationSeconds, updatedAt
    }
}

/// A timestamped bookmark inside a lecture.
struct MediaBookmark: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var mediaItemID: String
    var positionSeconds: Double
    var note: String?
    var createdAt: Date
}

/// A user-created ordered playlist.
struct Playlist: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var mediaItemIDs: [String]
    var createdAt: Date
    var updatedAt: Date
}

/// Playback speeds offered by the player.
enum PlaybackSpeed: Double, Codable, Sendable, CaseIterable, Identifiable {
    case slow = 0.75
    case normal = 1.0
    case fast = 1.25
    case faster = 1.5
    case fastest = 2.0

    var id: Double { rawValue }
    var label: String {
        switch self {
        case .slow: return "0.75×"
        case .normal: return "1×"
        case .fast: return "1.25×"
        case .faster: return "1.5×"
        case .fastest: return "2×"
        }
    }
}
