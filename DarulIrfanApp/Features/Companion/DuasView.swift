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
        duas = SeedBundle.duas()
        isLoaded = true
    }
}

// MARK: - Screen

/// Source-verified duas: a featured Dua of the Day, then elegant Arabic /
/// translation cards grouped by category, each with its citation line
/// (e.g. "Quran 2:201"). Content comes from bundled seed data only.
@MainActor
struct DuasView: View {
    @State private var viewModel: DuasViewModel

    init() {
        _viewModel = State(initialValue: DuasViewModel())
    }

    /// Category-ordered grouping that preserves first appearance and shows all
    /// duas — purely a display arrangement, no content is altered or dropped.
    private var groups: [DuaGroup] {
        var order: [String] = []
        var map: [String: [Dua]] = [:]
        for dua in viewModel.duas {
            let key = dua.category ?? "duas"
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(dua)
        }
        return order.map { key in
            DuaGroup(id: key, title: map[key]?.first?.categoryTitle ?? "Duas", duas: map[key] ?? [])
        }
    }

    private var featuredDua: Dua? {
        guard !viewModel.duas.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let index = ((day - 1) % viewModel.duas.count + viewModel.duas.count) % viewModel.duas.count
        return viewModel.duas[index]
    }

    var body: some View {
        ScrollView {
            if viewModel.isLoaded && viewModel.duas.isEmpty {
                DIElevatedCard {
                    DIEmptyState(
                        systemImage: "hands.sparkles",
                        titleKey: "Duas not available",
                        messageKey: "The duas could not be loaded. Updating or reinstalling the app should restore them."
                    )
                    .diOctagramWatermark(size: 220, opacity: 0.06)
                }
                .padding(DISpacing.md)
            } else {
                VStack(alignment: .leading, spacing: DISpacing.lg) {
                    if let featuredDua {
                        FeaturedDuaCard(dua: featuredDua)
                            .diAppear()
                    }
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: DISpacing.sm) {
                            DuaGroupHeader(title: group.title)
                            ForEach(Array(group.duas.enumerated()), id: \.element.id) { index, dua in
                                DuaCard(dua: dua)
                                    .diAppear(delay: 0.04 * Double(index))
                            }
                        }
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

// MARK: - Grouping

private struct DuaGroup: Identifiable {
    let id: String
    let title: String
    let duas: [Dua]
}

// MARK: - Group header

private struct DuaGroupHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.xs) {
            HStack(spacing: DISpacing.sm) {
                Image(systemName: "hands.sparkles")
                    .foregroundStyle(DIColor.accent)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                Spacer(minLength: 0)
            }
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(DIGradient.goldSheen)
                .frame(width: 120, height: 1.5)
                .opacity(0.6)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, DISpacing.xs)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Featured "Dua of the Day"

private struct FeaturedDuaCard: View {
    let dua: Dua

    var body: some View {
        ZStack(alignment: .topLeading) {
            DIGradient.hero()
                .diPatternOverlay(tint: .white, opacity: 0.07)
                .overlay(alignment: .topTrailing) {
                    DIOctagram(innerRatio: 0.5)
                        .stroke(Color.white, lineWidth: 1.5)
                        .frame(width: 200, height: 200)
                        .opacity(0.06)
                        .offset(x: 60, y: -50)
                }

            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Dua of the Day")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DISpacing.sm)
                    .padding(.vertical, DISpacing.xs)
                    .background(Capsule().fill(Color.white.opacity(0.16)))

                Text(verbatim: dua.title)
                    .font(DIFont.subheading)
                    .foregroundStyle(.white)

                Text(verbatim: dua.arabic)
                    .font(DIFont.quranArabic(scale: 1.0))
                    .foregroundStyle(.white)
                    .diGoldGlow(radius: 12, opacity: 0.5)
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .environment(\.layoutDirection, .rightToLeft)

                if let english = dua.translationEnglish {
                    Text(verbatim: english)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(verbatim: dua.source)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DIColor.goldGlow)
            }
            .padding(DISpacing.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg + 6, style: .continuous))
        .shadow(color: DIColor.primaryDeep.opacity(0.35), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Dua card

private struct DuaCard: View {
    let dua: Dua

    var body: some View {
        DIElevatedCard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text(verbatim: dua.title)
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)

                Text(verbatim: dua.arabic)
                    .font(DIFont.quranArabic())
                    .foregroundStyle(DIColor.textPrimary)
                    .diGoldGlow(radius: 6, opacity: 0.22)
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, .rightToLeft)

                if dua.translationEnglish != nil || dua.translationUrdu != nil {
                    DIJaliDivider(height: 12, opacity: 0.35)
                        .padding(.vertical, DISpacing.xs)
                }

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

                DIPillBadge(text: dua.source, color: DIColor.accent)
            }
        }
    }
}
