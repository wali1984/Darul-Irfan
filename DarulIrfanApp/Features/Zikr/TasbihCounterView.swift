import SwiftUI

/// One tasbih counter — the delightful centerpiece of the Zikr section: a
/// large tap ring with a breathing gold glow, a spring "pop" on every count,
/// a gradient progress arc toward the optional target, and gentle haptics.
/// The counting logic and persistence live in the view model, untouched.
@MainActor
struct TasbihCounterView: View {
    @State private var viewModel: TasbihCounterViewModel
    @State private var showResetDialog = false
    @State private var isEditing = false
    @State private var countBump: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        counter: TasbihCounter,
        trackerRepository: any TrackerRepositoryProtocol,
        devotionalMetrics: DevotionalMetricsSyncService
    ) {
        _viewModel = State(initialValue: TasbihCounterViewModel(
            counter: counter,
            trackerRepository: trackerRepository,
            devotionalMetrics: devotionalMetrics
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
                        Label("Target reached — Alhamdulillah", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DIColor.accent)
                            .diGoldGlow(radius: 8, opacity: 0.4)
                            .transition(.scale.combined(with: .opacity))
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

            controlBar
        }
        .navigationTitle(viewModel.counter.title)
        .navigationBarTitleDisplayMode(.inline)
        .diScreenBackground()
        .onChange(of: viewModel.counter.count) { _, _ in
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { countBump = 1.10 }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.6).delay(0.07)) { countBump = 1.0 }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.hasReachedTarget)
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

    // MARK: - Tap ring

    private var countingRing: some View {
        ZStack {
            // Soft aura that lifts the ring off the background.
            Circle()
                .fill(DIGradient.auraGold)
                .scaleEffect(0.96)
                .opacity(viewModel.hasReachedTarget ? 0.9 : 0.5)

            // Base track.
            Circle()
                .stroke(DIColor.border.opacity(0.7), lineWidth: 14)

            // Gradient progress arc toward the target.
            if viewModel.counter.target != nil {
                Circle()
                    .trim(from: 0, to: viewModel.progress)
                    .stroke(
                        AngularGradient(
                            colors: [Color(hex: 0xC6A253), Color(hex: 0xE9CE86), Color(hex: 0xFBCE54), Color(hex: 0xC6A253)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .diBreathingGlow(color: DIColor.goldGlow, maxRadius: 12)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.progress)
            } else {
                // Open-ended: a quiet emerald ring so the surface still feels alive.
                Circle()
                    .stroke(DIColor.primary.opacity(0.35), lineWidth: 3)
                    .padding(9)
            }

            VStack(spacing: DISpacing.xs) {
                Text("\(viewModel.counter.count)")
                    .font(.system(size: 74, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(DIColor.textPrimary)
                    .contentTransition(.numericText())
                    .scaleEffect(countBump)
                if let target = viewModel.counter.target {
                    Text("of \(target)")
                        .font(.title3)
                        .foregroundStyle(DIColor.textMuted)
                } else {
                    Image(systemName: "circle.hexagongrid")
                        .font(.subheadline)
                        .foregroundStyle(DIColor.accent.opacity(0.7))
                        .accessibilityHidden(true)
                }
            }
            .padding(DISpacing.lg)
        }
        .diBreathingGlow(color: viewModel.hasReachedTarget ? DIColor.goldGlow : DIColor.primary,
                         maxRadius: viewModel.hasReachedTarget ? 26 : 16)
        .padding(DISpacing.lg)
        .frame(maxWidth: 340)
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: DISpacing.md) {
            Button {
                viewModel.decrement()
            } label: {
                Image(systemName: "minus.circle")
                    .font(.title2)
                    .foregroundStyle(DIColor.textMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Remove one count")

            Spacer(minLength: 0)

            DIStatPill(icon: "infinity", value: "\(viewModel.lifetimeTotal)", label: "Lifetime")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Lifetime total \(viewModel.lifetimeTotal)")

            Spacer(minLength: 0)

            Button {
                showResetDialog = true
            } label: {
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(.title2)
                    .foregroundStyle(DIColor.textMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Reset count")
        }
        .padding(.horizontal, DISpacing.lg)
        .padding(.bottom, DISpacing.lg)
    }
}

// MARK: - Tap feedback style

private struct TasbihTapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
