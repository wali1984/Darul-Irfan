import UIKit
import UserNotifications

extension Notification.Name {
    static let didReceiveAPNSToken = Notification.Name("DarulIrfan.didReceiveAPNSToken")
    /// A screen asks for a place in the app by name ("quran", "zikr"). Object
    /// is the path. RootView hands it to `DeepLinkRouter`, which new code
    /// calls directly.
    static let didReceiveAppDeepLink = Notification.Name("DarulIrfan.didReceiveAppDeepLink")
    /// Posted when a Qur'an verse quoted inside a hadith is tapped, so the Read
    /// tab opens the app's own Quran reader at that ayah. Object is a
    /// `QuranAyahLink`. Entirely in-app — never opens an external site.
    static let openQuranAyah = Notification.Name("DarulIrfan.openQuranAyah")
}

/// Payload for `.openQuranAyah`: our own surah number (1-based) and the first
/// ayah to focus. Built from a hadith's stored `QuranRef`.
struct QuranAyahLink {
    let surah: Int
    let ayah: Int?
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: .didReceiveAPNSToken, object: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Local prayer notifications continue to work. Registration can be
        // retried from Official Alerts settings or at the next app launch.
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let path = response.notification.request.content.userInfo["path"] as? String {
            // Kept until the screen it opens exists: with the app closed, this
            // arrives during the splash, before any screen is listening.
            Task { @MainActor in DeepLinkRouter.shared.open(path: path) }
        }
        completionHandler()
    }
}
