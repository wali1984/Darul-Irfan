import Foundation

/// Whether the private regional groups are reachable in this build.
///
/// Signing in needs the `com.apple.developer.applesignin` entitlement, and
/// under manual signing the distribution profile must already carry it, which
/// it cannot until Sign in with Apple is enabled on the App ID. Build 47 of
/// `ios-testflight` failed at the archive step for exactly that reason, while
/// `ios-verify` passed - an unsigned build needs no profile, so it can never
/// catch this.
///
/// Until the portal is updated the entitlement stays out of `project.yml` and
/// this stays `false`, so no tester is offered a sign-in button that cannot
/// work. The server side is deployed and tested either way. Flip this and the
/// entitlement together; `project.yml` carries the same note.
enum MemberGroupsFeature {
    /// On, because joining no longer depends on Apple. An administrator issues
    /// a single-use invitation code and the member redeems it, which needs no
    /// entitlement, no App ID capability and no change to signing - the three
    /// things that failed build 47.
    static let isEnabled = true

    /// Sign in with Apple stays off until `com.apple.developer.applesignin` is
    /// restored in project.yml AND the capability is enabled on the App ID.
    /// Showing the button without both would offer a member a sign-in that
    /// cannot succeed, so the invitation code is the only route meanwhile.
    static let appleSignInAvailable = false
}

/// A private regional group of the silsila, as its own members see it.
///
/// The catalogue of groups is itself private: the backend only ever returns the
/// groups the signed-in member belongs to, so this is never a directory of
/// every group that exists.
struct MemberGroup: Codable, Sendable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var description: String?
    /// An optional outside link an administrator may still set. Meetings and
    /// community zikr are joined inside the app; this is only a fallback.
    var meetingURL: URL?
    var meetingNote: String?
    /// Whether the signed-in member may publish and run sessions here.
    var canManage: Bool? = nil
    /// Whether a zikr or meeting is live in this group right now.
    var isLive: Bool? = nil
    var liveKind: String? = nil
}

/// A member's role in the groups. Admins run their own groups; the super
/// admin runs every group.
enum MemberRole: String, Codable, Sendable {
    case member
    case admin
    case superadmin
}

/// What is live in a group: a zikr or a meeting, watched and joined in the app.
struct GroupLive: Codable, Sendable, Equatable {
    var kind: String
    var title: String?
    /// A live video of the session, played in the app.
    var videoID: String?
    /// Whether there is a room to join together.
    var hasRoom: Bool
    var startedAt: Date?

    var isMeeting: Bool { kind == "meeting" }
}

/// A scheduled group meeting, joined in the app.
struct GroupMeeting: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var title: String
    var startsAt: Date
    var durationMinutes: Int

    /// The room opens ten minutes before the start and stays open half an
    /// hour past the planned end.
    func isOpen(at date: Date = Date()) -> Bool {
        date >= startsAt.addingTimeInterval(-600)
            && date <= startsAt.addingTimeInterval(TimeInterval(durationMinutes * 60 + 1_800))
    }
}

/// One group's page: its live session, zikr times and meetings.
struct GroupDetail: Codable, Sendable {
    struct Summary: Codable, Sendable {
        var id: String?
        var name: String?
        var description: String?
    }

    var group: Summary
    var canManage: Bool
    var live: GroupLive?
    /// The group's own zikr times, in the same shape as the public schedule,
    /// so the same countdown, local-time and reminder code serves both.
    var zikrSessions: [ZikrSession]
    var meetings: [GroupMeeting]
}

/// A participant's place in a room, and the in-app page that holds it.
struct GroupRoomPass: Codable, Sendable {
    var authToken: String
    var pageURL: URL
}

struct MemberProfile: Codable, Sendable {
    var memberID: String
    var role: MemberRole
    var displayName: String?
}

enum MemberGroupPostKind: String, Codable, Sendable {
    case announcement
    /// A recorded zikr an admin chose for this group.
    case zikr
}

/// Something a group admin published to one group - written in the app,
/// forwarded from WhatsApp, or shared from the official feed. Members read;
/// nothing here was written by another member.
struct MemberGroupPost: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var kind: MemberGroupPostKind
    var title: String
    var body: String?
    var youtubeVideoID: String?
    var linkURL: URL?
    /// A picture forwarded with the post, by an expiring private link.
    var imageURL: URL? = nil
    var publishedAt: Date
    /// Drafts are visible to the group's admins only, until published.
    var isDraft: Bool? = nil
    /// "admin", "whatsapp" or "feed": where a draft came from.
    var source: String? = nil
}

struct MemberGroupList: Codable, Sendable {
    var role: MemberRole? = nil
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
