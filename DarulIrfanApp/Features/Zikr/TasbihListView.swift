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
                    .diAppear()

                DISectionHeader(titleKey: "Counters", systemImage: "hand.tap")
                if viewModel.isLoaded && viewModel.counters.isEmpty {
                    DIElevatedCard {
                        DIEmptyState(
                            systemImage: "hand.tap",
                            titleKey: "No counters yet",
                            messageKey: "Create a tasbih counter to begin counting your personal zikr. Tap the plus button above to add one."
                        )
                        .diOctagramWatermark(size: 200, opacity: 0.06)
                    }
                    .diAppear(delay: 0.05)
                } else {
                    ForEach(Array(viewModel.counters.enumerated()), id: \.element.id) { index, counter in
                        NavigationLink {
                            TasbihCounterView(counter: counter, trackerRepository: trackerRepository)
                        } label: {
                            TasbihCounterRow(counter: counter)
                        }
                        .buttonStyle(DIPressableStyle())
                        .diAppear(delay: 0.05 + 0.05 * Double(index))
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

    private var progress: Double {
        guard let target = counter.target, target > 0 else { return 0 }
        return min(1.0, Double(counter.count) / Double(target))
    }

    var body: some View {
        DIElevatedCard {
            HStack(spacing: DISpacing.md) {
                countRing
                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text(verbatim: counter.title)
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                    if let target = counter.target {
                        DIPillBadge(text: String(localized: "Target \(target)"), color: DIColor.accent)
                    } else {
                        DIPillBadge(text: String(localized: "Open-ended"))
                    }
                    Text("Lifetime: \(counter.lifetimeCount + counter.count)")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var countRing: some View {
        ZStack {
            Circle()
                .stroke(DIColor.border.opacity(0.6), lineWidth: 4)
            if counter.target != nil {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(colors: [DIColor.accent, DIColor.goldGlow, DIColor.accent], center: .center),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            Text("\(counter.count)")
                .font(.system(.title3, design: .rounded).weight(.medium).monospacedDigit())
                .foregroundStyle(DIColor.primary)
        }
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)
    }
}

// MARK: - Habit strip

private struct ZikrHabitStripCard: View {
    let days: [ZikrHabitDayItem]

    /// Trailing consecutive days (ending today) with at least one completion.
    private var currentStreak: Int {
        var streak = 0
        for day in days.reversed() {
            if day.completedCount > 0 { streak += 1 } else { break }
        }
        return streak
    }

    private var weekTotal: Int {
        days.reduce(0) { $0 + $1.completedCount }
    }

    var body: some View {
        DIElevatedCard(tint: DIColor.sandstone) {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                HStack {
                    Text("Daily Zikr Habit")
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                    Spacer(minLength: 0)
                    DIStatPill(icon: "flame.fill", value: "\(currentStreak)", label: "Day streak")
                }

                HStack(spacing: DISpacing.sm) {
                    ForEach(days) { day in
                        VStack(spacing: DISpacing.xs) {
                            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2)
                                .foregroundStyle(DIColor.textMuted)
                            ZStack {
                                Circle()
                                    .fill(day.completedCount > 0
                                          ? AnyShapeStyle(DIGradient.emerald)
                                          : AnyShapeStyle(DIColor.border.opacity(0.4)))
                                    .frame(width: 36, height: 36)
                                if day.completedCount > 0 {
                                    Circle()
                                        .strokeBorder(DIColor.accent.opacity(0.6), lineWidth: 1)
                                        .frame(width: 36, height: 36)
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

                Text("\(weekTotal) completed this week. Each time a counter reaches its target, that day is marked here.")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
