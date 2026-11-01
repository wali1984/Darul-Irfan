import SwiftUI

/// Memorisation practice for one surah: a chosen run of ayat, each repeated a
/// set number of times with a pause, and the text hidden when the listener is
/// ready to recall it rather than read it.
///
/// Practice is private and deliberately uncounted. There is no streak, no score
/// and nothing published: the only thing kept is where you left off, on this
/// device.
@MainActor
struct HifzView: View {
    let surah: QuranSurah
    private let repository: any QuranRepositoryProtocol

    @State private var player = HifzPlayer()
    @State private var ayahs: [QuranAyah] = []
    @State private var rangeStart = 1
    @State private var rangeEnd = 1
    @State private var selectedAyah = 1
    @State private var repeats = 3
    @State private var pauseSeconds = 1.5
    @State private var hidesText = false
    @State private var isRevealed = false
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var hasLoaded = false
    @State private var loadAttempt = 0

    init(surah: QuranSurah, dependencies: AppDependencies) {
        self.surah = surah
        self.repository = dependencies.quranRepository
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, DISpacing.lg)
                } else if loadFailed {
                    DICard {
                        VStack(spacing: DISpacing.sm) {
                            Text("The action could not be completed. Check your connection and try again.")
                                .diInterfaceFont(.callout)
                                .foregroundStyle(DIColor.textPrimary)
                            Button("Retry") { loadAttempt += 1 }
                                .buttonStyle(DICompactButtonStyle())
                                .disabled(isLoading)
                        }
                    }
                } else if recitation == nil {
                    DICard {
                        Text("This surah has no recitation audio in the app, so it cannot be practised yet.")
                            .diInterfaceFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    nowPractising
                    rangeCard
                    repetitionCard
                }
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .diPageHeading("Memorise")
        .task(id: loadAttempt) { await load() }
        .onChange(of: player.currentAyah) { _, ayah in
            if let ayah { selectedAyah = ayah }
            isRevealed = false
        }
        .onDisappear {
            save()
            player.stop()
        }
    }

    private var recitation: SurahRecitation? {
        RecitationProvider.shared.recitation(forSurah: surah.id)
    }

    // MARK: - Practice surface

    private var nowPractising: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack {
                    Text(verbatim: "\(surah.nameTransliterated) \(surah.id):\(player.currentAyah ?? selectedAyah)")
                        .diInterfaceFont(.headline)
                    Spacer()
                    if player.isPlaying {
                        Text(verbatim: "\(player.repetition)/\(repeats)")
                            .diInterfaceFont(.footnote, weight: .semibold)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Repetition \(player.repetition) of \(repeats)")
                    }
                }

                ayahText

                if player.phase == .pausing {
                    Label("Recall it now", systemImage: "ear")
                        .diInterfaceFont(.footnote)
                        .foregroundStyle(DIColor.accent)
                } else if player.phase == .finished {
                    Label("Range complete", systemImage: "checkmark.seal")
                        .diInterfaceFont(.footnote)
                        .foregroundStyle(DIColor.actionForeground)
                }

                controls
            }
        }
    }

    @ViewBuilder
    private var ayahText: some View {
        let ayahNumber = player.currentAyah ?? selectedAyah
        let text = ayahs.first { $0.ayahNumber == ayahNumber }?.textArabic
        if let text {
            if hidesText && !isRevealed {
                // Hidden on purpose: recalling from memory is the exercise. The
                // button is the only way back, so it cannot be revealed by a
                // stray scroll.
                Button {
                    isRevealed = true
                    DIHaptics.light()
                } label: {
                    Label("Reveal the text", systemImage: "eye")
                        .diInterfaceFont(.subheadline)
                }
                .buttonStyle(DICompactButtonStyle())
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, DISpacing.md)
            } else {
                Text(text)
                    .font(DIFont.quranArabic(scale: 1.15))
                    .foregroundStyle(DIColor.scripture)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .environment(\.layoutDirection, .rightToLeft)
                    .textSelection(.enabled)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: DISpacing.md) {
            Button {
                step(by: -1)
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(DICompactButtonStyle())
            .disabled((player.currentAyah ?? selectedAyah) <= rangeStart)
            .accessibilityLabel("Previous ayah")

            Button {
                togglePlayback()
            } label: {
                Label(
                    player.isPlaying ? "Pause" : "Start",
                    systemImage: player.isPlaying ? "pause.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(DIPrimaryButtonStyle())

            Button {
                step(by: 1)
            } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(DICompactButtonStyle())
            .disabled((player.currentAyah ?? selectedAyah) >= rangeEnd)
            .accessibilityLabel("Next ayah")
        }
    }

    // MARK: - Settings

    private var rangeCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                DISectionHeader(titleKey: "Range", systemImage: "text.line.first.and.arrowtriangle.forward")
                Stepper(value: $rangeStart, in: 1...surah.ayahCount) {
                    Text("From ayah \(rangeStart)")
                        .diInterfaceFont(.body)
                }
                .onChange(of: rangeStart) { _, value in
                    if rangeEnd < value { rangeEnd = value }
                    applyPracticeSettings()
                }
                Stepper(value: $rangeEnd, in: 1...surah.ayahCount) {
                    Text("To ayah \(rangeEnd)")
                        .diInterfaceFont(.body)
                }
                .onChange(of: rangeEnd) { _, value in
                    if rangeStart > value { rangeStart = value }
                    applyPracticeSettings()
                }
                Text("\(rangeEnd - rangeStart + 1) of \(surah.ayahCount) ayat")
                    .diInterfaceFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var repetitionCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                DISectionHeader(titleKey: "Repetition", systemImage: "repeat")
                Stepper(value: $repeats, in: 1...20) {
                    Text("Repeat each ayah \(repeats) times")
                        .diInterfaceFont(.body)
                }
                .onChange(of: repeats) { _, _ in applyPracticeSettings() }
                Stepper(value: $pauseSeconds, in: 0...10, step: 0.5) {
                    Text("Pause \(pauseSeconds, specifier: "%.1f") seconds")
                        .diInterfaceFont(.body)
                }
                .onChange(of: pauseSeconds) { _, _ in applyPracticeSettings() }
                Toggle("Hide the text", isOn: $hidesText)
                    .onChange(of: hidesText) { _, _ in isRevealed = false }
                Text("Hiding the text lets you recite from memory; reveal it when you need to check.")
                    .diInterfaceFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Behaviour

    private func load() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let loaded = try await repository.ayahs(inSurah: surah.id)
            let available = Set(loaded.filter { !$0.textArabic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.ayahNumber))
            guard surah.ayahCount > 0, (1...surah.ayahCount).allSatisfy({ available.contains($0) }) else {
                throw HifzLoadError.missingText
            }
            await RecitationProvider.warmUp()
            try Task.checkCancellation()
            ayahs = loaded
            rangeEnd = surah.ayahCount
            if let saved = HifzProgress.load(surah: surah.id) {
                rangeStart = min(max(1, saved.start), surah.ayahCount)
                rangeEnd = min(max(rangeStart, saved.end), surah.ayahCount)
                selectedAyah = min(max(saved.ayah, rangeStart), rangeEnd)
                repeats = min(max(1, saved.repeats), 20)
                pauseSeconds = saved.pauseSeconds.isFinite ? min(max(0, saved.pauseSeconds), 10) : 1.5
            }
            hasLoaded = true
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { loadFailed = true }
        }
    }

    private enum HifzLoadError: Error { case missingText }

    private func save() {
        guard hasLoaded else { return }
        HifzProgress.save(
            surah: surah.id,
            ayah: player.currentAyah ?? selectedAyah,
            repeats: repeats,
            pauseSeconds: pauseSeconds,
            start: rangeStart,
            end: rangeEnd
        )
    }

    private func togglePlayback() {
        DIHaptics.light()
        guard let recitation else { return }
        if player.isPlaying {
            player.pause()
            save()
        } else if player.currentAyah == nil || player.phase == .finished {
            isRevealed = false
            if player.phase == .finished { selectedAyah = rangeStart }
            player.start(
                recitation: recitation,
                range: rangeStart...rangeEnd,
                repeats: repeats,
                pauseSeconds: pauseSeconds,
                startingAyah: selectedAyah
            )
        } else {
            player.resume()
        }
    }

    private func step(by offset: Int) {
        guard let recitation else { return }
        let target = (player.currentAyah ?? selectedAyah) + offset
        guard target >= rangeStart, target <= rangeEnd else { return }
        isRevealed = false
        DIHaptics.light()
        selectedAyah = target
        if player.currentAyah == nil {
            player.start(recitation: recitation, range: rangeStart...rangeEnd, repeats: repeats, pauseSeconds: pauseSeconds, startingAyah: target)
        } else {
            player.practise(ayah: target)
        }
    }

    /// Apply every setting to the next verse attempt, including a paused session.
    private func applyPracticeSettings() {
        guard hasLoaded, !isLoading else { return }
        selectedAyah = min(max(player.currentAyah ?? selectedAyah, rangeStart), rangeEnd)
        isRevealed = false
        guard let recitation else { return }
        if player.isPlaying {
            player.start(
                recitation: recitation,
                range: rangeStart...rangeEnd,
                repeats: repeats,
                pauseSeconds: pauseSeconds,
                startingAyah: selectedAyah
            )
        } else {
            player.stop()
        }
        save()
    }
}
