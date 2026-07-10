import Observation
import SwiftUI

// MARK: - View model

@Observable
@MainActor
final class DuasViewModel {
    private(set) var duas: [Dua] = []
    private(set) var isLoaded = false

    func load() {
        guard !isLoaded else { return }
        duas = (try? SeedBundle.duas()) ?? []
        isLoaded = true
    }
}

// MARK: - Screen

/// Source-verified duas: Arabic text, translations, and the citation line
/// (e.g. "Quran 2:201"). Content comes from bundled seed data only.
@MainActor
struct DuasView: View {
    @State private var viewModel: DuasViewModel

    init() {
        _viewModel = State(initialValue: DuasViewModel())
    }

    var body: some View {
        ScrollView {
            if viewModel.isLoaded && viewModel.duas.isEmpty {
                DIEmptyState(
                    systemImage: "hands.sparkles",
                    titleKey: "Duas not available",
                    messageKey: "The duas could not be loaded. Updating or reinstalling the app should restore them."
                )
            } else {
                VStack(spacing: DISpacing.md) {
                    ForEach(viewModel.duas) { dua in
                        DuaCard(dua: dua)
                    }
                }
                .padding(DISpacing.md)
            }
        }
        .navigationTitle("Duas")
        .diScreenBackground()
        .task { viewModel.load() }
    }
}

// MARK: - Dua card

private struct DuaCard: View {
    let dua: Dua

    var body: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text(verbatim: dua.title)
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)

                Text(verbatim: dua.arabic)
                    .font(DIFont.quranArabic())
                    .foregroundStyle(DIColor.textPrimary)
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, .rightToLeft)

                if let english = dua.translationEnglish {
                    Text(verbatim: english)
                        .font(.body)
                        .foregroundStyle(DIColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let urdu = dua.translationUrdu {
                    Text(verbatim: urdu)
                        .font(DIFont.urduBody())
                        .foregroundStyle(DIColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .rightToLeft)
                }

                Text(verbatim: dua.source)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DIColor.accent)
            }
        }
    }
}
