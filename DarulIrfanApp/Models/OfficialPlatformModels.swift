import Foundation

enum OfficialFeedSource: String, Codable, Sendable, CaseIterable {
    case youtube
    case facebook
    case website
    case announcement
    case event
}

enum OfficialFeedKind: String, Codable, Sendable {
    case post
    case video
    case announcement
    case event
}

struct OfficialFeedItem: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var source: OfficialFeedSource
    var kind: OfficialFeedKind
    var title: String
    var body: String?
    var sourceURL: URL
    var imageURL: URL?
    var videoID: String?
    var publishedAt: Date
    var isFeatured: Bool
}

struct OfficialFeedPage: Codable, Sendable, Equatable {
    var items: [OfficialFeedItem]
    var nextCursor: String?
    /// Local transport metadata; the public API does not need to send it.
    var isFromCache: Bool

    init(items: [OfficialFeedItem], nextCursor: String?, isFromCache: Bool = false) {
        self.items = items
        self.nextCursor = nextCursor
        self.isFromCache = isFromCache
    }

    private enum CodingKeys: String, CodingKey { case items, nextCursor }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([OfficialFeedItem].self, forKey: .items)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
        isFromCache = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
        try container.encodeIfPresent(nextCursor, forKey: .nextCursor)
    }
}

enum LiveBroadcastState: String, Codable, Sendable {
    case offline
    case scheduled
    case live
    case ended
}

enum LiveSourceKind: String, Codable, Sendable {
    case youtube
    case paltalk
    case ownedStream
}

struct LiveSource: Codable, Sendable, Identifiable, Equatable {
    var kind: LiveSourceKind
    var url: URL
    var videoID: String?
    var supportsBackgroundAudio: Bool

    var id: String { "\(kind.rawValue)|\(url.absoluteString)" }
}

struct LiveBroadcast: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var state: LiveBroadcastState
    var title: String
    var details: String?
    var scheduledStart: Date?
    var startedAt: Date?
    var endedAt: Date?
    var sources: [LiveSource]
    var updatedAt: Date

    var preferredSource: LiveSource? {
        sources.first(where: { $0.kind == .ownedStream })
            ?? sources.first(where: { $0.kind == .youtube })
            ?? sources.first(where: { $0.kind == .paltalk })
    }

    static let offline = LiveBroadcast(
        id: "official-live",
        state: .offline,
        title: "Live Zikr",
        sources: [
            LiveSource(
                kind: .paltalk,
                url: URL(string: "https://www.paltalk.com") ?? URL(fileURLWithPath: "/"),
                supportsBackgroundAudio: false
            )
        ],
        updatedAt: .distantPast
    )
}

struct RemoteZikrSchedule: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var title: String
    var weekdays: [Int]
    var startHour: Int
    var startMinute: Int
    var durationMinutes: Int
    var timeZoneIdentifier: String
    var joinURL: URL?
    var instructions: String?
    var availabilityNote: String?
}

struct RemoteFeatureFlags: Codable, Sendable, Equatable {
    var officialFeed = false
    var liveHub = false
    var pushRegistration = false
    var diagnostics = false

    init(
        officialFeed: Bool = false,
        liveHub: Bool = false,
        pushRegistration: Bool = false,
        diagnostics: Bool = false
    ) {
        self.officialFeed = officialFeed
        self.liveHub = liveHub
        self.pushRegistration = pushRegistration
        self.diagnostics = diagnostics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        officialFeed = try container.decodeIfPresent(Bool.self, forKey: .officialFeed) ?? false
        liveHub = try container.decodeIfPresent(Bool.self, forKey: .liveHub) ?? false
        pushRegistration = try container.decodeIfPresent(Bool.self, forKey: .pushRegistration) ?? false
        diagnostics = try container.decodeIfPresent(Bool.self, forKey: .diagnostics) ?? false
    }
}

struct AppBootstrap: Codable, Sendable, Equatable {
    var schemaVersion: Int
    var generatedAt: Date
    var minimumSupportedVersion: String
    var featureFlags: RemoteFeatureFlags
    var officialLinks: [String: URL]
    var schedules: [RemoteZikrSchedule]
    var live: LiveBroadcast
    var contentVersions: [String: Int]

    static let offline = AppBootstrap(
        schemaVersion: 1,
        generatedAt: .distantPast,
        minimumSupportedVersion: "1.2.1",
        featureFlags: RemoteFeatureFlags(),
        officialLinks: [
            "website": URL(string: "https://www.naqshbandiaowaisiah.org/") ?? URL(fileURLWithPath: "/"),
            "youtube": URL(string: "https://www.youtube.com/channel/UCefP_tP1ROXmqu2miDVCtCg") ?? URL(fileURLWithPath: "/"),
            "facebook": URL(string: "https://www.facebook.com/oursheikh.official") ?? URL(fileURLWithPath: "/"),
            "paltalk": URL(string: "https://www.paltalk.com") ?? URL(fileURLWithPath: "/"),
        ],
        schedules: [],
        live: .offline,
        contentVersions: [:]
    )
}

enum PushTopic: String, Codable, Sendable, CaseIterable, Identifiable {
    case liveZikr
    case broadcasts
    case announcements
    case events

    var id: String { rawValue }
}

struct PushPreferences: Codable, Sendable, Equatable {
    // On by default: official alerts (live zikr, announcements, events) are a
    // core reason to install the app. Registration still only happens once the
    // user grants the system notification prompt, and it can be turned off in
    // More → Official Alerts.
    var isEnabled = true
    var topics: Set<PushTopic> = [.liveZikr, .announcements, .events]
}

enum DiagnosticsConsent: String, Codable, Sendable, CaseIterable, Identifiable {
    case notAsked
    case declined
    case granted

    var id: String { rawValue }
}

struct DeviceRegistration: Codable, Sendable {
    var installationID: UUID
    var apnsToken: String
    var locale: String
    var timeZone: String
    var topics: [PushTopic]
    var environment: String
    var appVersion: String
}
