import SwiftUI

/// One of the library's Akram-ut-Tarajum volumes (a parah, or several bound
/// together). Its text is the Urdu translation the Qur'an reader shows ayah
/// by ayah, so a volume opens there, at the first ayah of its first parah.
struct TarajumVolume: Equatable {
    /// The parah the volume begins at, 1...30.
    let parah: Int
    let surah: Int
    let ayah: Int

    /// Nil for anything else. The catalogue ids name their parahs
    /// ("...-Parah06.pdf", "...-Parah-16-to-30.pdf"): the first is where the
    /// volume begins.
    init?(_ item: ContentItem) {
        let id = item.id.lowercased()
        guard item.category == .quranTranslation,
              id.contains("tarajum"),
              let first = id.split(whereSeparator: { !$0.isNumber }).first,
              let parah = Int(first),
              (1...QuranDivisions.juzStarts.count).contains(parah) else { return nil }
        let start = QuranDivisions.juzStarts[parah - 1]
        self.parah = parah
        self.surah = start[0]
        self.ayah = start[1]
    }
}

/// How a volume is being read in the Qur'an reader, kept from one surah to
/// the next: in Urdu with the translation shown, until the reader says
/// otherwise there.
struct TarajumReading: Equatable {
    var language = "ur"
    /// Shows the translation although the Qur'an is otherwise read with the
    /// Arabic only.
    var showsTranslation = true
}

/// The Qur'an reader opened from a volume. It is pushed on the stack that
/// holds the volume's page (Books, Saved or Search, the last two in sheets
/// that would hide a change of tab), so Back returns to that page.
struct TarajumVolumeReader: View {
    let volume: TarajumVolume
    let dependencies: AppDependencies
    let appState: AppState

    @State private var surahs: [QuranSurah] = []
    @State private var shownSurah: QuranSurah?
    @State private var reading = TarajumReading()
    @State private var loadFailed = false
    @State private var attempt = 0

    var body: some View {
        // A stack, not a Group: a Group would hand the task to each branch
        // and cancel it as the branch changes.
        ZStack {
            if let shownSurah {
                SurahReaderView(
                    surah: shownSurah,
                    focusAyah: shownSurah.id == volume.surah ? volume.ayah : nil,
                    dependencies: dependencies,
                    appState: appState,
                    tarajumReading: $reading,
                    onRequestNextSurah: {
                        openNextSurah(after: shownSurah)
                    }
                )
                .id(shownSurah.id)
            } else if loadFailed {
                VStack(spacing: DISpacing.md) {
                    DIEmptyState(
                        systemImage: "book.closed",
                        titleKey: "This surah could not be opened",
                        messageKey: "Something went wrong while loading. Please go back and try again."
                    )
                    Button("Try Again") { attempt += 1 }
                        .buttonStyle(DISecondaryButtonStyle())
                        .padding(.horizontal, DISpacing.xl)
                }
            } else {
                ProgressView()
                    .tint(DIColor.primary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .diScreenBackground()
        .task(id: attempt) { await load() }
    }

    @MainActor
    private func load() async {
        guard shownSurah == nil else { return }
        loadFailed = false
        do {
            let all = try await dependencies.quranRepository.allSurahs()
            try Task.checkCancellation()
            surahs = all
            shownSurah = all.first { $0.id == volume.surah }
            loadFailed = shownSurah == nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            loadFailed = true
        }
    }

    /// The next surah takes the place of the one finished, as in the Qur'an's
    /// own stack; asked twice, it opens once.
    private func openNextSurah(after surah: QuranSurah) {
        guard shownSurah?.id == surah.id,
              let next = surahs.first(where: { $0.id == surah.id + 1 }) else { return }
        shownSurah = next
    }
}
