import Foundation

/// A private regional group of the silsila, as its own members see it.
///
/// The catalogue of groups is itself private: the backend only ever returns the
/// groups the signed-in member belongs to, so this is never a directory of
/// every group that exists.
struct MemberGroup: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var name: String
    var description: String?
    /// Meetings are hosted on the platform the silsila already uses rather than
    /// inside the app, so a group carries a join link instead of a call.
    var meetingURL: URL?
    var meetingNote: String?
}

enum MemberGroupPostKind: String, Codable, Sendable {
    case announcement
    /// A recorded zikr an admin chose for this group.
    case zikr
}

/// Something an admin published to one group. Members read; they never post,
/// so nothing here was written by another member.
struct MemberGroupPost: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var kind: MemberGroupPostKind
    var title: String
    var body: String?
    var youtubeVideoID: String?
    var linkURL: URL?
    var publishedAt: Date
}

struct MemberGroupList: Codable, Sendable {
    var groups: [MemberGroup]
}

struct MemberGroupPostList: Codable, Sendable {
    var groupID: String
    var posts: [MemberGroupPost]
}

struct MemberSession: Codable, Sendable {
    var token: String
    var expiresAt: Date
    var memberID: String
}
