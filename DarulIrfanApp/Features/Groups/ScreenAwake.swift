import SwiftUI

/// Keeps the phone from sleeping while anything in a live Halqah session
/// needs it: the Halqah's page while its session is live, its stage, the live
/// sound and the voice listener (owner 2026-11-18: "the phone needs to stay on
/// for both admin and end users"). Each holder has its own key, so one that
/// lets go (the stage closing) never lets the phone sleep while another (the
/// page, the session still live) holds on.
@MainActor
enum ScreenAwake {
    private static var holders = Set<String>()
    /// What the app had before the first holder, given back after the last.
    private static var before: Bool?
    /// The system switch; replaced in tests.
    static var setIdleTimerDisabled: (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }
    static var idleTimerDisabled: () -> Bool = { UIApplication.shared.isIdleTimerDisabled }

    static var isHeld: Bool { !holders.isEmpty }

    static func hold(_ key: String) {
        if holders.isEmpty { before = idleTimerDisabled() }
        holders.insert(key)
        setIdleTimerDisabled(true)
    }

    static func release(_ key: String) {
        guard holders.remove(key) != nil, holders.isEmpty else { return }
        setIdleTimerDisabled(before ?? false)
        before = nil
    }

    static func set(_ key: String, awake: Bool) {
        if awake { hold(key) } else { release(key) }
    }

    /// Tests only.
    static func reset() { holders = []; before = nil }
}

extension View {
    /// Keeps the phone awake while this view is on screen and `active` holds.
    func keepsScreenAwake(_ key: String, while active: Bool = true) -> some View {
        modifier(ScreenAwakeModifier(key: key, active: active))
    }
}

private struct ScreenAwakeModifier: ViewModifier {
    let key: String
    let active: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { ScreenAwake.set(key, awake: active) }
            .onChange(of: active) { _, now in ScreenAwake.set(key, awake: now) }
            .onDisappear { ScreenAwake.release(key) }
    }
}
