import SwiftUI
import UIKit

/// The daily spiritual companion cards shown at the top of the Today tab:
/// a branded hero with the anchor verse, then the day's ayah, Aqwal-e-Sheikh,
/// dua, dhikr, and Name of Allah. Self-contained; embedded in the Today tab's
/// scroll above the prayer content.
struct TodayDailySection: View {
    let appState: AppState
    @State private var viewModel: TodayDailyViewModel
    @State private var shareItem: ShareImageItem?

    init(appState: AppState) {
        self.appState = appState
        _viewModel = State(initialValue: TodayDailyViewModel(appState: appState))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            if viewModel.isLoaded {
                verseCard.diAppear(delay: 0.05)
                aqwalCard.diAppear(delay: 0.10)
                duaCard.diAppear(delay: 0.15)
                dhikrCard.diAppear(delay: 0.20)
                nameCard.diAppear(delay: 0.25)
            }
        }
        .task { viewModel.load() }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image])
        }
    }

    // MARK: - Verse of the day

    private var verseCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack {
                    DIPillBadge(text: String(localized: "Ayah of the Day"))
                    Spacer()
                    if let share = viewModel.ayahShare() {
                        shareButton(share)
                    }
                }
                if let ayah = viewModel.ayah {
                    Text(ayah.arabic)
                        .font(DIFont.quranArabic(scale: 1.05))
                        .foregroundStyle(DIColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .environment(\.layoutDirection, .rightToLeft)
                    Rectangle().fill(DIColor.accent).frame(height: 1).opacity(0.5)
                    if let translation = viewModel.ayahTranslation() {
                        Text(translation)
                            .font(.body)
                            .foregroundStyle(DIColor.textPrimary)
                    }
                    Text(ayah.reference)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DIColor.primary)
                }
            }
        }
    }

    // MARK: - Aqwal-e-Sheikh (the differentiator)

    @ViewBuilder
    private var aqwalCard: some View {
        if let aqwal = viewModel.aqwal {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    HStack {
                        DISectionHeaderInline(title: "Aqwal-e-Sheikh", systemImage: "quote.opening")
                        Spacer()
                        if let share = viewModel.aqwalShare() {
                            shareButton(share)
                        }
                    }
                    Text(aqwal.text)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(DIColor.textPrimary)
                        .italic()
                    Text(aqwal.attribution)
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
        }
    }

    // MARK: - Daily dua

    @ViewBuilder
    private var duaCard: some View {
        if let dua = viewModel.dua {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    DISectionHeaderInline(title: "Daily Dua", systemImage: "hands.sparkles")
                    Text(dua.title)
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                    Text(dua.arabic)
                        .font(DIFont.quranArabic(scale: 0.95))
                        .foregroundStyle(DIColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .environment(\.layoutDirection, .rightToLeft)
                    if let t = viewModel.duaTranslation() {
                        Text(t).font(.subheadline).foregroundStyle(DIColor.textPrimary)
                    }
                    Text(dua.source)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DIColor.primary)
                }
            }
        }
    }

    // MARK: - Daily dhikr

    @ViewBuilder
    private var dhikrCard: some View {
        if let dhikr = viewModel.dhikr {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    DISectionHeaderInline(title: "Daily Dhikr", systemImage: "circle.hexagongrid")
                    HStack(alignment: .firstTextBaseline) {
                        Text(dhikr.arabic)
                            .font(DIFont.quranArabic(scale: 0.95))
                            .foregroundStyle(DIColor.textPrimary)
                        Spacer()
                        DIPillBadge(text: "×\(dhikr.count)", color: DIColor.accent)
                    }
                    Text(dhikr.transliteration)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DIColor.textPrimary)
                    Text(dhikr.meaning)
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textMuted)
                    Text(dhikr.source)
                        .font(.caption2)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
        }
    }

    // MARK: - Name of Allah

    @ViewBuilder
    private var nameCard: some View {
        if let name = viewModel.name {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    DISectionHeaderInline(title: "Name of Allah", systemImage: "sparkle")
                    HStack {
                        Text(name.arabic)
                            .font(DIFont.quranArabic(scale: 1.1))
                            .foregroundStyle(DIColor.primary)
                            .diGoldGlow(radius: 8, opacity: 0.35)
                        Spacer()
                        Text(name.transliteration)
                            .font(DIFont.subheading)
                            .foregroundStyle(DIColor.textPrimary)
                    }
                    if let meaning = viewModel.nameMeaning() {
                        Text(meaning).font(.subheadline).foregroundStyle(DIColor.textMuted)
                    }
                }
            }
        }
    }

    // MARK: - Share

    private func shareButton(_ content: ShareableContent) -> some View {
        Button {
            if let image = ShareCardRenderer.image(for: content) {
                shareItem = ShareImageItem(image: image)
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.subheadline)
                .foregroundStyle(DIColor.primary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Share"))
    }
}

/// Identifiable wrapper so a rendered image can drive `.sheet(item:)`.
struct ShareImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// A compact inline section header used inside cards (distinct from the
/// standalone `DISectionHeader`).
struct DISectionHeaderInline: View {
    let title: LocalizedStringKey
    let systemImage: String
    var body: some View {
        HStack(spacing: DISpacing.xs) {
            Image(systemName: systemImage)
                .font(.footnote)
                .foregroundStyle(DIColor.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DIColor.textPrimary)
        }
        .accessibilityAddTraits(.isHeader)
    }
}
