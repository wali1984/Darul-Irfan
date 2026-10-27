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
