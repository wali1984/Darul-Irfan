import Observation
import SwiftUI

// MARK: - View model

@Observable
@MainActor
final class NamesOfAllahViewModel {
    private(set) var names: [NameOfAllah] = []
    private(set) var isLoaded = false

    func load() {
        guard !isLoaded else { return }
        names = SeedBundle.namesOfAllah()
        isLoaded = true
    }
}

// MARK: - Grid screen

/// The 99 Names of Allah (Asma-ul-Husna): a featured Name of the Day above an
/// adaptive grid of gilded cards, the Arabic set in the mushaf face with a
/// soft gold halo. Tapping a name opens an enlarged view for unhurried reading.
@MainActor
struct NamesOfAllahView: View {
    @State private var viewModel: NamesOfAllahViewModel
    @State private var selectedName: NameOfAllah?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: DISpacing.sm)]

    init() {
        _viewModel = State(initialValue: NamesOfAllahViewModel())
    }

    /// A gently rotating pick so the "Name of the Day" changes each day but is
    /// stable within a day. Purely presentational; the full list is unchanged.
    private var featuredName: NameOfAllah? {
        guard !viewModel.names.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let index = ((day - 1) % viewModel.names.count + viewModel.names.count) % viewModel.names.count
        return viewModel.names[index]
    }

    var body: some View {
        ScrollView {
            if viewModel.isLoaded && viewModel.names.isEmpty {
                DIElevatedCard {
                    DIEmptyState(
                        systemImage: "sparkles",
                        titleKey: "Names not available",
                        messageKey: "The 99 Names of Allah could not be loaded. Updating or reinstalling the app should restore them."
                    )
                    .diOctagramWatermark(size: 220, opacity: 0.06)
                }
                .padding(DISpacing.md)
            } else {
                VStack(spacing: DISpacing.md) {
                    if let featuredName {
                        FeaturedNameCard(name: featuredName) {
                            selectedName = featuredName
                        }
                        .diAppear()
                    }

                    LazyVGrid(columns: columns, spacing: DISpacing.sm) {
                        ForEach(Array(viewModel.names.enumerated()), id: \.element.id) { index, name in
                            Button {
                                selectedName = name
                            } label: {
                                NameOfAllahCell(name: name)
                            }
                            .buttonStyle(DIPressableStyle())
                            .diAppear(delay: 0.02 * Double(index % 12))
                        }
                    }
                }
                .padding(DISpacing.md)
            }
        }
        .navigationTitle("99 Names of Allah")
        .diScreenBackground()
        .task { viewModel.load() }
        .sheet(item: $selectedName) { name in
            NameOfAllahDetailView(name: name)
        }
    }
}

// MARK: - Featured "Name of the Day"

private struct FeaturedNameCard: View {
    let name: NameOfAllah
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                DIGradient.hero()
                    .diPatternOverlay(tint: .white, opacity: 0.07)
                    .overlay(alignment: .topTrailing) {
                        DIOctagram(innerRatio: 0.5)
                            .stroke(Color.white, lineWidth: 1.5)
                            .frame(width: 180, height: 180)
                            .opacity(0.07)
                            .offset(x: 50, y: -40)
                    }

                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    Text("Name of the Day")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DISpacing.sm)
                        .padding(.vertical, DISpacing.xs)
                        .background(Capsule().fill(Color.white.opacity(0.16)))

                    Text(verbatim: name.arabic)
                        .font(DIFont.quranArabic(scale: 1.5))
                        .foregroundStyle(.white)
                        .diGoldGlow(radius: 14, opacity: 0.6)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, DISpacing.xs)

                    Text(verbatim: name.transliteration)
                        .font(DIFont.subheading)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text(verbatim: name.meaningEnglish)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DISpacing.lg)
            }
            .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg + 6, style: .continuous))
            .shadow(color: DIColor.primaryDeep.opacity(0.35), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(DIPressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Name of the Day: \(name.transliteration), \(name.meaningEnglish)")
        .accessibilityHint("Shows the name enlarged")
    }
}

// MARK: - Grid cell

private struct NameOfAllahCell: View {
    let name: NameOfAllah

    var body: some View {
        DIElevatedCard {
            VStack(spacing: DISpacing.xs) {
                Text("\(name.id)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(DIColor.accent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(verbatim: name.arabic)
                    .font(DIFont.quranArabic())
                    .foregroundStyle(DIColor.primary)
                    .diGoldGlow(radius: 7, opacity: 0.3)
                    .multilineTextAlignment(.center)
                Text(verbatim: name.transliteration)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(verbatim: name.meaningEnglish)
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the name enlarged")
    }
}

// MARK: - Enlarged detail

private struct NameOfAllahDetailView: View {
    let name: NameOfAllah

    var body: some View {
        ScrollView {
            VStack(spacing: DISpacing.lg) {
                DIPillBadge(text: String(localized: "Name \(name.id) of 99"))

                ZStack {
                    Circle()
                        .fill(DIGradient.auraGold)
                        .frame(width: 240, height: 240)
                    Text(verbatim: name.arabic)
                        .font(DIFont.quranArabic(scale: 2.2))
                        .foregroundStyle(DIColor.primary)
                        .diGoldGlow(radius: 16, opacity: 0.5)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, DISpacing.sm)

                Text(verbatim: name.transliteration)
                    .font(DIFont.heading)
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.center)

                DIJaliDivider(height: 16, opacity: 0.4)
                    .padding(.horizontal, DISpacing.xl)

                Text(verbatim: name.meaningEnglish)
                    .font(.title3)
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let meaningUrdu = name.meaningUrdu {
                    Text(verbatim: meaningUrdu)
                        .font(DIFont.urduBody(scale: 1.2))
                        .foregroundStyle(DIColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(DISpacing.xl)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(DIColor.background)
    }
}
