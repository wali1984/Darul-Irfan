import Foundation

// MARK: - Rights

/// Whether the app may store/display an item's full text or only link to it.
/// Official content is copyright-reserved; the owner granted content
/// permission on 2026-07-10, so ingested items are `permissionConfirmed`.
/// `linkOnly` remains valid for anything ingested without that grant.
enum RightsStatus: String, Codable, Sendable {
    /// Only metadata + source link may be shown; body must not be stored.
    case linkOnly
    /// Full text/asset use confirmed by the content owner.
    case permissionConfirmed
    /// Public-domain or app-original content (e.g. Quran Arabic text, UI copy).
    case publicDomain
}

// MARK: - Review state

/// How far a body of sacred text has got through review.
///
/// Internal metadata only. It gates what may ship in which channel; it is
/// never surfaced as a label on the text itself. Readers see the work, its
/// author and its source — not the pipeline that produced it. Provenance
/// belongs in Acknowledgements, not beside an ayah.
enum ReviewState: String, Codable, Sendable, CaseIterable {
    /// Incomplete or unreviewed. Ships to no channel.
    case draft
    /// Vision review, extracted-text review and the content validators all
    /// passed, with no known corruption, duplicate loss or schema fault.
    /// Line-by-line human proofreading is still outstanding.
    case testFlightApproved
    /// Additionally proofread by a person, or cross-verified line by line
    /// against independent authoritative sources.
    case publicApproved
    /// Found faulty; must not ship anywhere.
    case rejected

    /// TestFlight carries reviewed content as well as fully-approved content.
    var allowedOnTestFlight: Bool {
        self == .testFlightApproved || self == .publicApproved
    }

    /// The eventual App Store gate. Not enforced yet — see
    /// `Docs/CONTENT_REVIEW_STATES.md` for when it turns on.
    var allowedOnAppStore: Bool { self == .publicApproved }
}

// MARK: - Library content

/// Kind of library item in the verified content catalog.
enum ContentType: String, Codable, Sendable, CaseIterable {
    case article
    case book
    case booklet
    case magazine
    case document
    case announcement
    case pressRelease
    case poetry
    case page
}

/// Curated category taxonomy for the Naqshbandia Owaisiah library.
enum ContentCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case aboutSilsila
    case sheikhAbdulQadeerAwan
    case sheikhMuhammadAkramAwan
    case shajra
    case tasawwuf
    case tazkiyahNafs
    case zikrAllah
    case methodOfZikr
    case baiat
    case articles
    case books
    case booklets
    case sufiPoetry
    case trainingCourses
    case importantDocuments
    case alMurshidMagazine
    case pressReleases
    case announcements
    case featureArticles
    case aqwalESheikh

    var id: String { rawValue }
    var localizationKey: String { "library.category.\(rawValue)" }

    var englishName: String {
        switch self {
        case .aboutSilsila: return "About Silsila Naqshbandia Owaisiah"
        case .sheikhAbdulQadeerAwan: return "Hazrat Ameer Abdul Qadeer Awan"
        case .sheikhMuhammadAkramAwan: return "Hazrat Ameer Muhammad Akram Awan"
        case .shajra: return "Chain of Transmission / Shajra"
        case .tasawwuf: return "What is Tasawwuf"
        case .tazkiyahNafs: return "Tazkiyah-e-Nafs"
        case .zikrAllah: return "Zikr Allah"
        case .methodOfZikr: return "Method of Zikr"
        case .baiat: return "Bai'at"
        case .articles: return "Articles"
        case .books: return "Books"
        case .booklets: return "Booklets"
        case .sufiPoetry: return "Sufi Poetry"
        case .trainingCourses: return "Training Courses"
        case .importantDocuments: return "Important Documents"
        case .alMurshidMagazine: return "Al-Murshid Magazine"
        case .pressReleases: return "Press Releases"
        case .announcements: return "Announcements"
        case .featureArticles: return "Feature Articles"
        case .aqwalESheikh: return "Aqwal-e-Sheikh"
        }
    }
}

/// A single library item (article, book, magazine issue, document, ...).
/// Mirrors the ingest pipeline's `articles.json` / `documents.json` schema (v1).
struct ContentItem: Codable, Sendable, Identifiable, Equatable {
    /// Stable ID derived by the ingest tool from the source URL.
    var id: String
    var sourceUrl: String
    var type: ContentType
    var title: String
    var titleUrdu: String?
    /// BCP-47: "en", "ur", "ar".
    var language: String
    var author: String?
    var category: ContentCategory
    /// Sanitized HTML body; nil when rightsStatus is `linkOnly`.
    var bodyHtml: String?
    /// Plain-text body for search indexing; nil when `linkOnly`.
    var bodyPlainText: String?
    var excerpt: String?
    var publishedAt: Date?
    var updatedAt: Date?
    /// Remote images/audio referenced by the item.
    var mediaUrls: [String]
    /// Downloadable assets (PDFs etc.).
    var downloadUrls: [String]
    /// Ingest checksum for idempotent sync.
    var checksum: String?
    var rightsStatus: RightsStatus
}

/// A named, ordered grouping of content items (e.g. a magazine year, a course).
struct ContentCollection: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var title: String
    var category: ContentCategory
    var itemIDs: [String]
}

// MARK: - Downloads & favorites

enum DownloadState: String, Codable, Sendable {
    case notDownloaded
    case queued
    case downloading
    case downloaded
    case failed
}

/// A file downloaded for offline use (PDF, MP3, content pack).
struct DownloadedAsset: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var remoteUrl: String
    /// Path relative to the app's Application Support downloads directory.
    var relativeFilePath: String
    var byteSize: Int64
    var contentItemID: String?
    var mediaItemID: String?
    var downloadedAt: Date
}

/// User favorite/bookmark on a library or media item.
struct Favorite: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    /// Exactly one of these references is set.
    var contentItemID: String?
    var mediaItemID: String?
    var createdAt: Date
}

/// Reading progress within a long-form content item.
struct ContentReadingProgress: Codable, Sendable, Equatable {
    var contentItemID: String
    /// 0.0 ... 1.0 scroll fraction.
    var fraction: Double
    var updatedAt: Date
}
