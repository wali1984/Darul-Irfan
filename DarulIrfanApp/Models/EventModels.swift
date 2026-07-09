import Foundation

// MARK: - Community events

enum EventKind: String, Codable, Sendable, CaseIterable {
    case monthlyIjtema
    case salanaIjtema
    case ramadanAitekaaf
    case announcement
    case other
}

/// A community event at Dar-ul-Irfan or online. Mirrors `events.json` (v1);
/// server-configurable via the content manifest.
struct CommunityEvent: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var kind: EventKind
    var title: String
    var titleUrdu: String?
    var details: String?
    var startDate: Date?
    var endDate: Date?
    /// True when only a Hijri window is announced and Gregorian dates
    /// are approximate (e.g. Ramadan programs).
    var datesAreApproximate: Bool
    var venue: String?
    var sourceUrl: String?
    var updatedAt: Date?
}

/// A short announcement/news entry.
struct Announcement: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var title: String
    var body: String?
    var publishedAt: Date?
    var sourceUrl: String?
}

// MARK: - Dar-ul-Irfan place & contact

/// Static information about the headquarters, bundled in seed data and
/// updatable via the manifest.
struct DarulIrfanPlace: Codable, Sendable, Equatable {
    var name: String
    /// e.g. "Dar-ul-Irfan, Munara, District Chakwal, Punjab, Pakistan".
    var addressLines: [String]
    var latitude: Double?
    var longitude: Double?
    var phone: String?
    var email: String?
    var websiteUrl: String
}

/// A labeled inquiry route (e.g. "Bai'at inquiries", "Publications").
struct ContactChannel: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var title: String
    var email: String?
    var phone: String?
    var url: String?
}
