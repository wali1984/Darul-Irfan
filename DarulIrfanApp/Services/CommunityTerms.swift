import UIKit

/// The community terms a person accepts before taking part in Halqahs, the
/// live stage and their chat, which are for adults.
///
/// The server decides when they are needed: it answers 403 with the code
/// `community_consent_required`. The app then asks the person once, over
/// whatever is on screen, and sends the request again with their agreement.
/// Reading, and listening without a profile, never need them.
enum CommunityTerms {
    /// The version of the terms the server expects.
    static let version = "2026-11-06"
    /// Where the terms can be read.
    static let address = URL(string: "https://oursheikh.wajidali.us/community-terms")

    /// What a person reads when they chose not to accept.
    static var declinedMessage: String {
        String(localized: "Community access is for adults. Accept the community terms to continue.")
    }

    /// True when a server answer is its request for the terms.
    static func isRequested(status: Int, body: Data) -> Bool {
        guard status == 403,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return false }
        return json["code"] as? String == "community_consent_required"
    }

    private enum Answer { case agreed, notNow, reading }

    @MainActor private static var isAsking = false
    @MainActor private static var declinedAt: Date?
    @MainActor private static var waiting: [CheckedContinuation<Bool, Never>] = []

    /// Asks the person to confirm they are an adult and accept the terms.
    /// Requests that arrive while the question is on screen share its answer.
    /// After "Not now", requests the app makes by itself do not ask again for
    /// two minutes; `always` is for something the person has just tapped.
    @MainActor
    static func ask(always: Bool = false) async -> Bool {
        if isAsking {
            return await withCheckedContinuation { waiting.append($0) }
        }
        if !always, let declinedAt, Date().timeIntervalSince(declinedAt) < 120 { return false }
        guard let presenter = topViewController() else { return false }
        isAsking = true
        let answer = await withCheckedContinuation { (continuation: CheckedContinuation<Answer, Never>) in
            let alert = UIAlertController(
                title: String(localized: "Community terms"),
                message: String(localized: "Halqahs, the live stage and their chat are for adults. By continuing you confirm that you are 18 or older and agree to the community terms."),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "Agree and continue"), style: .default) { _ in
                continuation.resume(returning: .agreed)
            })
            if address != nil {
                alert.addAction(UIAlertAction(title: String(localized: "Read the terms"), style: .default) { _ in
                    continuation.resume(returning: .reading)
                })
            }
            alert.addAction(UIAlertAction(title: String(localized: "Not now"), style: .cancel) { _ in
                continuation.resume(returning: .notNow)
            })
            presenter.present(alert, animated: true)
        }
        isAsking = false
        switch answer {
        case .agreed: declinedAt = nil
        case .notNow: declinedAt = Date()
        case .reading:
            declinedAt = nil
            if let address { UIApplication.shared.open(address, options: [:], completionHandler: nil) }
        }
        let agreed = answer == .agreed
        let others = waiting
        waiting = []
        for other in others { other.resume(returning: agreed) }
        return agreed
    }

    /// The screen on top, so the question shows over a sheet as well.
    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
