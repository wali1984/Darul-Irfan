import Foundation
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
