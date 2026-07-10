import SwiftUI

/// Personal tasbih counters plus the trailing-week daily zikr habit strip.
/// Reached from both the Zikr section and the Companion hub.
@MainActor
struct TasbihListView: View {
    @State private var viewModel: TasbihListViewModel
    @State private var isCreating = false
    @State private var editingCounter: TasbihCounter?
    @State private var counterPendingDeletion: TasbihCounter?
    private let trackerRepository: any TrackerRepositoryProtocol

    init(trackerRepository: any TrackerRepositoryProtocol) {
        self.trackerRepository = trackerRepository
        _viewModel = State(initialValue: TasbihListViewModel(trackerRepository: trackerRepository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                DISectionHeader(titleKey: "Daily Habit", systemImage: "calendar")
                ZikrHabitStripCard(days: viewModel.habitDays)

                DISectionHeader(titleKey: "Counters", systemImage: "hand.tap")
                if viewModel.isLoaded && viewModel.counters.isEmpty {
                    DIEmptyState(
                        systemImage: "hand.tap",
                        titleKey: "No counters yet",
                        messageKey: "Create a tasbih counter to begin counting your personal zikr. Tap the plus button above to add one."
                    )
                } else {
                    ForEach(viewModel.counters) { counter in
                        NavigationLink {
                            TasbihCounterView(counter: counter, trackerRepository: trackerRepository)
                        } label: {
                            TasbihCounterRow(counter: counter)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editingCounter = counter
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                counterPendingDeletion = counter
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(DISpacing.md)
        }
        .navigationTitle("Tasbih")
        .diScreenBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New counter")
            }
        }
        .onAppear {
            Task { await viewModel.load() }
        }
        .sheet(isPresented: $isCreating) {
            TasbihEditorView(counter: nil) { newCounter in
                Task { await viewModel.save(newCounter) }
            }
        }
        .sheet(item: $editingCounter) { counter in
            TasbihEditorView(counter: counter) { updated in
                Task { await viewModel.save(updated) }
            }
        }
        .confirmationDialog(
            "Delete this counter?",
            isPresented: deletionDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let counter = counterPendingDeletion {
                    Task { await viewModel.delete(counter) }
                }
                counterPendingDeletion = nil
            }
            Button("Keep", role: .cancel) {
                counterPendingDeletion = nil
            }
        } message: {
            Text("Its counts will be removed. This cannot be undone.")
        }
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { counterPendingDeletion != nil },
            set: { isPresented in
                if !isPresented { counterPendingDeletion = nil }
            }
        )
    }
}

// MARK: - Counter row

private struct TasbihCounterRow: View {
    let counter: TasbihCounter

    var body: some View {
        DICard {
            HStack(spacing: DISpacing.md) {
                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text(verbatim: counter.title)
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                    if let target = counter.target {
                        Text("Target: \(target)")
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                    } else {
                        Text("Open-ended")
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                    }
                    Text("Lifetime: \(counter.lifetimeCount + counter.count)")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                Spacer(minLength: 0)
                Text("\(counter.count)")
                    .font(.system(.title, design: .rounded).weight(.light).monospacedDigit())
                    .foregroundStyle(DIColor.primary)
                Image(systemName: "chevron.forward")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Habit strip

private struct ZikrHabitStripCard: View {
    let days: [ZikrHabitDayItem]

    var body: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Daily Zikr Habit")
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                HStack(spacing: DISpacing.sm) {
                    ForEach(days) { day in
                        VStack(spacing: DISpacing.xs) {
                            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2)
                                .foregroundStyle(DIColor.textMuted)
                            ZStack {
                                Circle()
                                    .fill(day.completedCount > 0 ? DIColor.primary : DIColor.border.opacity(0.5))
                                    .frame(width: 34, height: 34)
                                if day.completedCount > 0 {
                                    Text("\(day.completedCount)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(DIColor.onPrimary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(day.completedCount) completed"))
                    }
                }
                Text("Each time a counter reaches its target, that day is marked here.")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
