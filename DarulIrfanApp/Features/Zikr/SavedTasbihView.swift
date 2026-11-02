import SwiftUI

/// A widget identifies an existing counter by ID, never by a stale count.
@MainActor
struct SavedTasbihView: View {
    let id: UUID
    let trackerRepository: any TrackerRepositoryProtocol
    let devotionalMetrics: DevotionalMetricsSyncService
    @State private var counter: TasbihCounter?
    @State private var loaded = false
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if let counter {
                TasbihCounterView(counter: counter, trackerRepository: trackerRepository, devotionalMetrics: devotionalMetrics)
            } else if loaded {
                // A widget can outlive a deleted counter. Never recreate it.
                TasbihListView(trackerRepository: trackerRepository, devotionalMetrics: devotionalMetrics)
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
            guard !loaded else { return }
            failed = false
            do {
                let counters = try await trackerRepository.tasbihCounters()
                guard !Task.isCancelled else { return }
                counter = counters.first { $0.id == id }
                loaded = true
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}
