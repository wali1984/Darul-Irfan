import SwiftUI

/// The commentary on one ayah, opened from its card: either tafsir, in either
/// language, whatever the reader is showing under the ayat at the time.
///
/// Where a work has no verse-by-verse text for this ayah in the chosen
/// language (Asrar-at-Tanzil in Urdu is kept as printed pages), the printed
/// volume opens where the surah begins. The last work and language chosen are
/// remembered, so a reader who studies one tafsir lands on it each time;
/// until one is chosen, the sheet opens in the language being read.
@MainActor
struct AyahTafsirSheet: View {
    let ayah: QuranAyah
    let viewModel: SurahReaderViewModel
    let dependencies: AppDependencies
    let fontScale: Double

    @Environment(\.dismiss) private var dismiss
    /// Empty until the reader chooses; then the choice is kept.
    @AppStorage("ayahTafsir.work") private var storedWork = ""
    @AppStorage("ayahTafsir.language") private var storedLanguage = ""
    @ScaledMetric(relativeTo: .body) private var bodyBaseSize: CGFloat = 17

    private static let works: [QuranContentMode] = [.akramTafaseer, .asrarTanzil]

    /// The language chosen here, or the one the reader is reading in.
    private var language: String {
        storedLanguage.isEmpty ? viewModel.readingLanguage : storedLanguage
    }

    /// The work chosen here; at first the one with verse-by-verse text in
    /// the reader's language (Akram-ut-Tafaseer is Urdu, Asrar-at-Tanzil's
    /// per-ayah commentary English).
    private var work: QuranContentMode {
        if let chosen = QuranContentMode(rawValue: storedWork), chosen.isTafsir { return chosen }
        return language == "en" ? .asrarTanzil : .akramTafaseer
    }

    private var workBinding: Binding<String> {
        Binding(get: { work.rawValue }, set: { storedWork = $0 })
    }

    private var languageBinding: Binding<String> {
        Binding(get: { language }, set: { storedLanguage = $0 })
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
                Picker("Tafsir", selection: workBinding) {
                    ForEach(Self.works) { mode in
                        Text(LocalizedStringKey(mode.shortTitle)).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Language", selection: languageBinding) {
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
                FormattedBookPage(page: viewModel.formattedTafsir(entry), scale: fontScale)
            } else {
                Text(verbatim: entry.text)
                    .font(.system(size: bodyBaseSize * fontScale))
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
        let otherWork: QuranContentMode = work == .akramTafaseer ? .asrarTanzil : .akramTafaseer
        DICard(background: DIColor.sandstone) {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Group {
                    if work == .akramTafaseer && ayah.surahNumber >= 92 {
                        Text("Akram-ut-Tafaseer for this surah is in Parah 30, part 2, which is not in the app yet.")
                    } else if volumes.isEmpty {
                        Text("This tafsir has no commentary on this ayah in this language.")
                    } else {
                        Text("This tafsir has no verse-by-verse commentary on this ayah in this language. The printed volume is below, opened where the surah begins.")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(DIColor.textPrimary)
                if !entries(language: otherLanguage).isEmpty {
                    Button {
                        storedLanguage = otherLanguage
                    } label: {
                        Label(otherLanguage == "ur" ? "Read it in Urdu" : "Read it in English", systemImage: "character.bubble")
                    }
                    .buttonStyle(.bordered)
                }
                if hasEntries(of: otherWork) || !TafsirVolumeProvider.shared.volumes(
                    surah: ayah.surahNumber, editionPrefix: otherWork.tafsirEditionPrefix ?? "", language: language
                ).isEmpty {
                    Button {
                        storedWork = otherWork.rawValue
                    } label: {
                        Label {
                            Text("Read \(otherWork.localizedTitle)")
                        } icon: {
                            Image(systemName: "text.book.closed")
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    /// Whether another work has commentary on this ayah in this language.
    private func hasEntries(of other: QuranContentMode) -> Bool {
        guard let prefix = other.tafsirEditionPrefix else { return false }
        return viewModel.allTafsir(for: ayah.ayahNumber).contains {
            $0.editionID.hasPrefix(prefix) && viewModel.edition(id: $0.editionID)?.language == language
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
                        TafsirVolumeDestination(volume: volume, dependencies: dependencies, fontScale: fontScale)
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
