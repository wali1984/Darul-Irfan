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
    @State private var repeats = 3
    @State private var pauseSeconds = 1.5
    @State private var hidesText = false
    @State private var isRevealed = false
    @State private var isLoading = true

    init(surah: QuranSurah, dependencies: AppDependencies) {
        self.surah = surah
        self.repository = dependencies.quranRepository
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, DISpacing.lg)
                } else if recitation == nil {
                    DICard {
                        Text("This surah has no recitation audio in the app, so it cannot be practised yet.")
                            .font(.subheadline)
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
        .task { await load() }
        .onDisappear {
            player.stop()
            save()
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
                    Text(verbatim: "\(surah.nameTransliterated) \(surah.id):\(player.currentAyah ?? rangeStart)")
                        .font(.headline)
                    Spacer()
                    if player.isPlaying {
                        Text(verbatim: "\(player.repetition)/\(repeats)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Repetition \(player.repetition) of \(repeats)")
                    }
                }

                ayahText

                if player.phase == .pausing {
                    Label("Recall it now", systemImage: "ear")
                        .font(.footnote)
                        .foregroundStyle(DIColor.accent)
                } else if player.phase == .finished {
                    Label("Range complete", systemImage: "checkmark.seal")
                        .font(.footnote)
                        .foregroundStyle(DIColor.primary)
                }

                controls
            }
        }
    }

    @ViewBuilder
    private var ayahText: some View {
        let ayahNumber = player.currentAyah ?? rangeStart
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
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
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
            .buttonStyle(.bordered)
            .disabled((player.currentAyah ?? rangeStart) <= rangeStart)
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
            .buttonStyle(.borderedProminent)

            Button {
                step(by: 1)
            } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(.bordered)
            .disabled((player.currentAyah ?? rangeStart) >= rangeEnd)
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
                }
                .onChange(of: rangeStart) { _, value in
                    if rangeEnd < value { rangeEnd = value }
                    restartIfPlaying()
                }
                Stepper(value: $rangeEnd, in: 1...surah.ayahCount) {
                    Text("To ayah \(rangeEnd)")
                }
                .onChange(of: rangeEnd) { _, value in
                    if rangeStart > value { rangeStart = value }
                    restartIfPlaying()
                }
                Text("\(rangeEnd - rangeStart + 1) of \(surah.ayahCount) ayat")
                    .font(.caption)
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
                }
                Stepper(value: $pauseSeconds, in: 0...10, step: 0.5) {
                    Text("Pause \(pauseSeconds, specifier: "%.1f") seconds")
                }
                Toggle("Hide the text", isOn: $hidesText)
                    .onChange(of: hidesText) { _, _ in isRevealed = false }
                Text("Hiding the text lets you recite from memory; reveal it when you need to check.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Behaviour

    private func load() async {
        ayahs = (try? await repository.ayahs(inSurah: surah.id)) ?? []
        rangeEnd = surah.ayahCount
        if let saved = HifzProgress.load(surah: surah.id) {
            rangeStart = min(max(1, saved.start), surah.ayahCount)
            rangeEnd = min(max(rangeStart, saved.end), surah.ayahCount)
            repeats = saved.repeats
            pauseSeconds = saved.pauseSeconds
        }
        isLoading = false
    }

    private func save() {
        HifzProgress.save(
            surah: surah.id,
            ayah: player.currentAyah ?? rangeStart,
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
            player.start(
                recitation: recitation,
                range: rangeStart...rangeEnd,
                repeats: repeats,
                pauseSeconds: pauseSeconds
            )
        } else {
            player.resume()
        }
    }

    private func step(by offset: Int) {
        guard let recitation else { return }
        let target = (player.currentAyah ?? rangeStart) + offset
        guard target >= rangeStart, target <= rangeEnd else { return }
        isRevealed = false
        DIHaptics.light()
        if player.currentAyah == nil {
            player.start(recitation: recitation, range: rangeStart...rangeEnd, repeats: repeats, pauseSeconds: pauseSeconds)
        }
        player.practise(ayah: target)
    }

    /// A range change while practising takes effect immediately rather than at
    /// the next ayah, which is what someone narrowing their range expects.
    private func restartIfPlaying() {
        guard player.isPlaying, let recitation else { return }
        isRevealed = false
        player.start(
            recitation: recitation,
            range: rangeStart...rangeEnd,
            repeats: repeats,
            pauseSeconds: pauseSeconds
        )
    }
}
