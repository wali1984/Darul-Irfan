import Foundation
import Observation
import UIKit
import UserNotifications

/// This phone's notification token, as the app delegate reports it.
///
/// A Halqah's notices reach only a phone the server has registered. That used
/// to happen only when official alerts were switched on, so members who had
/// not done that heard nothing from their Halqah. The Halqah page asks iOS for
/// the token itself; asking again is cheap and answers with the current one.
@MainActor
final class APNSTokenWatcher {
    static let shared = APNSTokenWatcher()

    private var latest: Data?
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .didReceiveAPNSToken, object: nil, queue: .main) { [weak self] notification in
            guard let token = notification.object as? Data else { return }
            Task { @MainActor in self?.latest = token }
        }
    }

    /// The token, or nil when iOS gives none within ten seconds (no network,
    /// or notifications not set up on this device).
    func token() async -> Data? {
        if let latest { return latest }
        UIApplication.shared.registerForRemoteNotifications()
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(250))
            if let latest { return latest }
        }
        return nil
    }
}

/// Whether iOS lets the app show notifications, and whether it may still ask.
enum NotificationPermission {
    case allowed, notAsked, denied

    static func current() async -> NotificationPermission {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .notDetermined: return .notAsked
        case .denied: return .denied
        @unknown default: return .denied
        }
    }
}

/// The member's Halqah notices on this phone: on, off, or blocked in iOS
/// Settings, and the switch that turns them on or off.
///
/// One model for both places the switch is shown: the member's Halqahs at
/// the top of the Halqah tab, and Settings > Notifications, which gathers
/// every alert and reminder. The tab hands its own model to Notifications,
/// so a change made in one shows in the other at once.
@MainActor
@Observable
final class HalqahNoticesModel {
    enum Status: Equatable { case on, off, blocked }

    private(set) var status: Status = .off
    private(set) var isChanging = false
    /// Registers the phone for the notices; set by the page.
    var platform: OfficialPlatformService?
    /// The Halqah page's own service; Settings, which has none, makes one
    /// only when the switch is used.
    private let service: MemberGroupService?
    private static var registeredThisRun = false

    init(service: MemberGroupService? = nil) {
        self.service = service
    }

    /// Turns the member's Halqah notices on or off on this phone. Off keeps
    /// them signed in and keeps any official alerts.
    func set(_ on: Bool) async {
        isChanging = true
        defer { isChanging = false }
        if on {
            HalqahNoticeChoice.isTurnedOff = false
            if await NotificationPermission.current() == .notAsked {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            }
            Self.registeredThisRun = false
            await follow()
        } else {
            HalqahNoticeChoice.isTurnedOff = true
            status = .off
            if let installation = SecureInstallationIdentity.load() {
                try? await (service ?? MemberGroupService()).unlinkNotifications(installationID: installation)
            }
        }
    }

    /// Keeps this phone set up for the member's Halqah notices while they
    /// want them and iOS allows them. They used to arrive only on phones that
    /// had also switched on official alerts, so most members heard nothing.
    func follow() async {
        guard !HalqahNoticeChoice.isTurnedOff else {
            status = .off
            return
        }
        switch await NotificationPermission.current() {
        case .allowed:
            status = .on
            if !Self.registeredThisRun, let platform, let token = await APNSTokenWatcher.shared.token(),
               (try? await platform.registerForHalqahNotices(token: token)) != nil {
                Self.registeredThisRun = true
            }
            await (service ?? MemberGroupService()).linkNotifications(installationID: SecureInstallationIdentity.loadOrCreate())
        case .notAsked:
            status = .off
        case .denied:
            status = .blocked
        }
    }

    /// Reads the state without asking anything of the server, for a screen
    /// that only shows the switch.
    func refreshState() async {
        let permission = await NotificationPermission.current()
        status = Self.shownStatus(turnedOff: HalqahNoticeChoice.isTurnedOff, permission: permission)
    }

    /// Signed out, or the account deleted: nothing is shown here any more.
    func reset() {
        status = .off
    }

    /// What the switch shows: off when the member turned it off or iOS has
    /// not been asked yet, blocked when iOS refuses, else on.
    static func shownStatus(turnedOff: Bool, permission: NotificationPermission) -> Status {
        if turnedOff { return .off }
        switch permission {
        case .allowed: return .on
        case .notAsked: return .off
        case .denied: return .blocked
        }
    }
}
