import SwiftUI

/// One destination for links that already identify the text and target.
@MainActor
struct TasbihPresetView: View {
    let title: String
    let target: Int?
    let trackerRepository: any TrackerRepositoryProtocol
    let devotionalMetrics: DevotionalMetricsSyncService
    @State private var counter: TasbihCounter?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if let counter {
                TasbihCounterView(counter: counter, trackerRepository: trackerRepository, devotionalMetrics: devotionalMetrics, showFullText: true)
            } else {
                VStack(spacing: DISpacing.md) {
                    if failed {
                        Text("Unable to load counters").diInterfaceFont(.headline)
                        Button("Retry") { attempt += 1 }.buttonStyle(DISecondaryButtonStyle())
                    } else { ProgressView() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .diScreenBackground()
                .navigationTitle("Tasbih")
            }
        }
        .task(id: attempt) {
            guard counter == nil else { return }
            failed = false
            do { counter = try await TasbihPresetResolver.resolve(title: title, target: target, repository: trackerRepository) }
            catch { if !Task.isCancelled { failed = true } }
        }
    }
}

@MainActor
enum TasbihPresetResolver {
    private struct Key: Hashable { let title: String; let target: Int? }
    private static var pending: [Key: Task<TasbihCounter, Error>] = [:]

    static func resolve(title: String, target: Int?, repository: any TrackerRepositoryProtocol) async throws -> TasbihCounter {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let goal = target.flatMap { $0 > 0 ? $0 : nil }
        let key = Key(title: text, target: goal)
        if let task = pending[key] { return try await task.value }
        let task = Task { @MainActor in
            let counters = try await repository.tasbihCounters()
            if let existing = counters.filter({ $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == text && $0.target == goal })
                .max(by: { $0.updatedAt < $1.updatedAt }) { return existing }
            let created = TasbihCounter(id: UUID(), title: text, target: goal, count: 0, lifetimeCount: 0, updatedAt: Date())
            try await repository.saveTasbihCounter(created)
            return created
        }
        pending[key] = task
        defer { pending[key] = nil }
        return try await task.value
    }
}
