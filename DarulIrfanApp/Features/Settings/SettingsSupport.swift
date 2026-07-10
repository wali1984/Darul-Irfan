import SwiftUI

/// Builds SwiftUI bindings whose writes flow through
/// `AppState.updateSettings`, so every settings mutation is persisted and
/// triggers the notification/widget side effects in one place.
enum SettingsBinding {
    @MainActor
    static func value<Value>(
        in appState: AppState,
        get: @escaping (AppSettings) -> Value,
        set: @escaping (inout AppSettings, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { get(appState.settings) },
            set: { newValue in
                Task { @MainActor in
                    await appState.updateSettings { settings in
                        set(&settings, newValue)
                    }
                }
            }
        )
    }
}
