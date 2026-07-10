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

/// The 99 Names of Allah (Asma-ul-Husna) in an adaptive grid. Tapping a name
/// opens an enlarged view for unhurried reading.
@MainActor
struct NamesOfAllahView: View {
    @State private var viewModel: NamesOfAllahViewModel
    @State private var selectedName: NameOfAllah?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: DISpacing.sm)]

    init() {
        _viewModel = State(initialValue: NamesOfAllahViewModel())
    }

    var body: some View {
        ScrollView {
            if viewModel.isLoaded && viewModel.names.isEmpty {
                DIEmptyState(
                    systemImage: "sparkles",
                    titleKey: "Names not available",
                    messageKey: "The 99 Names of Allah could not be loaded. Updating or reinstalling the app should restore them."
                )
            } else {
                LazyVGrid(columns: columns, spacing: DISpacing.sm) {
                    ForEach(viewModel.names) { name in
                        Button {
                            selectedName = name
                        } label: {
                            NameOfAllahCell(name: name)
                        }
                        .buttonStyle(.plain)
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

// MARK: - Grid cell

private struct NameOfAllahCell: View {
    let name: NameOfAllah

    var body: some View {
        DICard {
            VStack(spacing: DISpacing.xs) {
                Text(verbatim: name.arabic)
                    .font(DIFont.quranArabic())
                    .foregroundStyle(DIColor.primary)
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
                Text(verbatim: name.arabic)
                    .font(DIFont.quranArabic(scale: 2.2))
                    .foregroundStyle(DIColor.primary)
                    .multilineTextAlignment(.center)
                Text(verbatim: name.transliteration)
                    .font(DIFont.heading)
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.center)
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
