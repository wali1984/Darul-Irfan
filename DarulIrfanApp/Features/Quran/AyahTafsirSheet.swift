import SwiftUI

/// The commentary on one ayah, opened from its card: either tafsir, in either
/// language, whatever the reader is showing under the ayat at the time.
///
/// Where a work has no verse-by-verse text for this ayah in the chosen
/// language (Asrar-ut-Tanzil in Urdu is kept as printed pages), the printed
/// volume opens where the surah begins. The last work and language chosen are
/// remembered, so a reader who studies one tafsir lands on it each time.
@MainActor
struct AyahTafsirSheet: View {
    let ayah: QuranAyah
    let viewModel: SurahReaderViewModel
    let dependencies: AppDependencies
    let fontScale: Double

    @Environment(\.dismiss) private var dismiss
    @AppStorage("ayahTafsir.work") private var workRaw = QuranContentMode.akramTafaseer.rawValue
    @AppStorage("ayahTafsir.language") private var language = "ur"

    private static let works: [QuranContentMode] = [.akramTafaseer, .asrarTanzil]

    private var work: QuranContentMode {
        QuranContentMode(rawValue: workRaw).flatMap { $0.isTafsir ? $0 : nil } ?? .akramTafaseer
    }

    private func entries(language: String) -> [QuranTafsir] {
        guard let prefix = work.tafsirEditionPrefix else { return [] }
        return viewModel.allTafsir(for: ayah.ayahNumber).filter {
            $0.editionID.hasPrefix(prefix) && viewModel.edition(id: $0.editionID)?.language == language
        }
    }

    private var volumes: [TafsirVolume] {
        guard let prefix = work.tafsirEditionPrefix else { return [] }
        return TafsirVolumeProvider.shared.volumes(surah: ayah.surahNumber, editionPrefix: prefix, language: language)
    }

    private var otherLanguage: String { language == "ur" ? "en" : "ur" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                Picker("Tafsir", selection: $workRaw) {
                    ForEach(Self.works) { mode in
                        Text(LocalizedStringKey(mode.shortTitle)).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Language", selection: $language) {
                    Text(verbatim: "اردو").tag("ur")
                    Text(verbatim: "English").tag("en")
                }
                .pickerStyle(.segmented)

                Text(ayah.textArabic)
                    .font(DIFont.quranArabic(scale: 0.85 * fontScale))
                    .foregroundStyle(DIColor.primaryDeep)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity)
                    .padding(DISpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                            .fill(DIColor.primary.opacity(0.07))
                    )
                    .environment(\.layoutDirection, .rightToLeft)

                let found = entries(language: language)
                if found.isEmpty {
                    emptyNote
                } else {
                    ForEach(found) { entry in entryView(entry) }
                }
                volumeLinks
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .navigationTitle(Text("Tafsir of \(ayah.surahNumber):\(ayah.ayahNumber)"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    @ViewBuilder
    private func entryView(_ entry: QuranTafsir) -> some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            if entry.ayahStart != entry.ayahEnd {
                Text("Commentary on ayat \(entry.ayahStart)–\(entry.ayahEnd)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DIColor.textMuted)
            }
            if language == "ur" {
                FormattedBookPage(page: BookPageFormatter.format(entry.text), scale: fontScale)
            } else {
                Text(verbatim: entry.text)
                    .font(.system(size: 17 * fontScale))
                    .lineSpacing(CGFloat(4 * fontScale))
                    .foregroundStyle(DIColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
    }

    @ViewBuilder
    private var emptyNote: some View {
        DICard(background: DIColor.sandstone) {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text(volumes.isEmpty
                     ? "This tafsir has no commentary on this ayah in this language."
                     : "This tafsir has no verse-by-verse commentary on this ayah in this language. The printed volume is below, opened where the surah begins.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textPrimary)
                if !entries(language: otherLanguage).isEmpty {
                    Button {
                        language = otherLanguage
                    } label: {
                        Label(otherLanguage == "ur" ? "Read it in Urdu" : "Read it in English", systemImage: "character.bubble")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var volumeLinks: some View {
        if !volumes.isEmpty {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("The full printed volume")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DIColor.textMuted)
                ForEach(volumes) { volume in
                    NavigationLink {
                        TafsirVolumeDestination(volume: volume, dependencies: dependencies)
                    } label: {
                        Label {
                            Text("Open at page \(volume.page)")
                        } icon: {
                            Image(systemName: "text.book.closed")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
