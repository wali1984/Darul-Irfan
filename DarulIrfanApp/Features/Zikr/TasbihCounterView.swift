import SwiftUI

/// One tasbih counter: a large tap-anywhere counting surface with a progress
/// ring toward the optional target, gentle haptics, and reset into the
/// lifetime total.
@MainActor
struct TasbihCounterView: View {
    @State private var viewModel: TasbihCounterViewModel
    @State private var showResetDialog = false
    @State private var isEditing = false

    init(counter: TasbihCounter, trackerRepository: any TrackerRepositoryProtocol) {
        _viewModel = State(initialValue: TasbihCounterViewModel(
            counter: counter,
            trackerRepository: trackerRepository
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                viewModel.increment()
            } label: {
                VStack(spacing: DISpacing.lg) {
                    countingRing
                    if viewModel.hasReachedTarget {
                        Text("Target reached — Alhamdulillah")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DIColor.accent)
                    }
                    Text("Tap anywhere to count")
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(TasbihTapButtonStyle())
            .accessibilityLabel("Add one count")
            .accessibilityValue(Text("\(viewModel.counter.count)"))

            HStack(spacing: DISpacing.md) {
                Button {
                    viewModel.decrement()
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.title2)
                        .foregroundStyle(DIColor.textMuted)
                }
                .accessibilityLabel("Remove one count")

                Spacer(minLength: 0)

                VStack(spacing: DISpacing.xs) {
                    Text("Lifetime")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                    Text("\(viewModel.lifetimeTotal)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(DIColor.textPrimary)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 0)

                Button {
                    showResetDialog = true
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle")
                        .font(.title2)
                        .foregroundStyle(DIColor.textMuted)
                }
                .accessibilityLabel("Reset count")
            }
            .padding(.horizontal, DISpacing.lg)
            .padding(.bottom, DISpacing.lg)
        }
        .navigationTitle(viewModel.counter.title)
        .navigationBarTitleDisplayMode(.inline)
        .diScreenBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    isEditing = true
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            TasbihEditorView(counter: viewModel.counter) { updated in
                Task { await viewModel.apply(updated) }
            }
        }
        .confirmationDialog(
            "Reset this counter?",
            isPresented: $showResetDialog,
            titleVisibility: .visible
        ) {
            Button("Reset") {
                Task { await viewModel.reset() }
            }
            Button("Keep counting", role: .cancel) {}
        } message: {
            Text("Your current count will be added to the lifetime total.")
        }
        .onDisappear {
            viewModel.persistOnExit()
        }
    }

    private var countingRing: some View {
        ZStack {
            Circle()
                .stroke(DIColor.border, lineWidth: 12)
            if viewModel.counter.target != nil {
                Circle()
                    .trim(from: 0, to: viewModel.progress)
                    .stroke(DIColor.primary, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.2), value: viewModel.progress)
            }
            VStack(spacing: DISpacing.xs) {
                Text("\(viewModel.counter.count)")
                    .font(.system(size: 68, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(DIColor.textPrimary)
                    .contentTransition(.numericText())
                if let target = viewModel.counter.target {
                    Text("of \(target)")
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
            .padding(DISpacing.lg)
        }
        .padding(DISpacing.lg)
        .frame(maxWidth: 340)
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Tap feedback style

private struct TasbihTapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
