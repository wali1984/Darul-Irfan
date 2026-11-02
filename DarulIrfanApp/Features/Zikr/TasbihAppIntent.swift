import AppIntents
import Foundation

/// Uses the visible counter's existing persistence path, never a second writer.
@MainActor
enum TasbihShortcutTarget {
    private(set) static weak var counter: TasbihCounterViewModel?

    static func install(_ model: TasbihCounterViewModel) { counter = model }
    static func remove(_ model: TasbihCounterViewModel) {
        if counter === model { counter = nil }
    }

    static func increment() async throws {
        guard let model = counter else { throw TasbihShortcutError.openCounter }
        guard !model.saveFailed else { throw TasbihShortcutError.retrySave }
        model.increment()
        await model.persistOnExit().value
        if model.saveFailed { throw TasbihShortcutError.retrySave }
    }
}

private enum TasbihShortcutError: LocalizedError {
    case openCounter, retrySave
    var errorDescription: String? {
        switch self {
        case .openCounter: String(localized: "Open a Tasbih counter first, then run this shortcut.")
        case .retrySave: String(localized: "Your changes are still here. Please try saving again.")
        }
    }
}

struct AddTasbihCountIntent: AppIntent {
    static var title: LocalizedStringResource = "Add one Tasbih count"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try await TasbihShortcutTarget.increment()
        return .result()
    }
}

struct DarulIrfanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddTasbihCountIntent(),
                    phrases: ["Add a Tasbih count in \(.applicationName)"],
                    shortTitle: "Count Tasbih", systemImageName: "plus.circle")
    }
}
