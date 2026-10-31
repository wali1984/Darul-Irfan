import Observation
import SwiftUI

/// The running focus session, kept outside the screen. It used to live in
/// the screen's own state, so leaving the screen dropped a running session
/// while its end alert stayed scheduled, with no way left to cancel it.
/// Saved, so it also survives the app being closed.
@Observable
@MainActor
final class FocusSession {
    static let shared = FocusSession()

    private(set) var endsAt: Date?
    private(set) var pausedRemaining: TimeInterval?

    private enum Keys {
        static let endsAt = "focus.endsAt"
        static let pausedRemaining = "focus.pausedRemaining"
    }

    private init() {
        let defaults = UserDefaults.standard
        // A session that ended while the app was away is simply over.
        if let end = defaults.object(forKey: Keys.endsAt) as? Date, end > Date() {
            endsAt = end
        }
        pausedRemaining = defaults.object(forKey: Keys.pausedRemaining) as? Double
    }

    func start(endingAt end: Date) {
        endsAt = end
        pausedRemaining = nil
        save()
    }

    func pause() {
        guard let endsAt else { return }
        pausedRemaining = max(0, endsAt.timeIntervalSinceNow)
        self.endsAt = nil
        save()
    }

    func clear() {
        endsAt = nil
        pausedRemaining = nil
        save()
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(endsAt, forKey: Keys.endsAt)
        defaults.set(pausedRemaining, forKey: Keys.pausedRemaining)
    }
}

@MainActor
struct FocusTimerView: View {
    let dependencies: AppDependencies
    let appState: AppState
    var body: some View { PersonalZikrView() }
}
