import SwiftUI

/// The day's ayah's Tafsir, opened from its card on Today: the Qur'an
/// reader's own Tafsir sheet (either work, either language, and the printed
/// volume where there is no verse-by-verse text), over the ayah's surah
/// loaded exactly as the reader loads it. Opening it records no reading
/// position.
@MainActor
struct TodayAyahTafsirSheet: View {
    let surahNumber: Int
    let ayahNumber: Int
    let dependencies: AppDependencies
    let appState: AppState

    @State private var reader: SurahReaderViewModel?
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let reader, let ayah = reader.ayahs.first(where: { $0.ayahNumber == ayahNumber }) {
            AyahTafsirSheet(
                ayah: ayah,
                viewModel: reader,
                dependencies: dependencies,
                fontScale: appState.settings.readerFontScale.rawValue
            )
        } else if failed {
            DIEmptyState(
                systemImage: "text.book.closed",
                titleKey: "This tafsir has no commentary on this ayah in this language."
            )
            .diScreenBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .diScreenBackground()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }

    private func load() async {
        guard reader == nil else { return }
        let surahs = (try? await dependencies.quranRepository.allSurahs()) ?? []
        guard let surah = surahs.first(where: { $0.id == surahNumber }) else {
            failed = true
            return
        }
        let model = SurahReaderViewModel(
            surah: surah,
            repository: dependencies.quranRepository,
            devotionalMetrics: dependencies.devotionalMetrics,
            preferredLanguageCode: SurahReaderViewModel.initialReadingLanguage(
                appLanguage: appState.settings.language.contentLanguageCode
            )
        )
        await model.load()
        if model.ayahs.contains(where: { $0.ayahNumber == ayahNumber }) {
            reader = model
        } else {
            failed = true
        }
    }
}
