import SwiftUI

/// The full player's two panes: the player itself, and the bayan's transcript.
enum PlayerPane: String, CaseIterable, Hashable {
    case audio = "Audio"
    case transcript = "Transcript"
}

/// The bayan's transcript in the full player: its timed lines, the one being
/// spoken lit and followed, a tap seeking there, and a search within it.
/// Urdu speech is set right to left in the Urdu face; the Qur'an in the mushaf
/// face with its reference, which opens the ayah in the reader; a hadith or
/// dua in Arabic with its source; Arabic without a matched source as an
/// "Arabic recitation" marker with no text.
struct BayanTranscriptView: View {
    let model: BayanTranscriptModel
    let audioPlayer: any AudioPlayerServicing
    /// Called before the reader opens an ayah, so the sheet gets out of the way.
    let onOpenQuran: () -> Void

    @State private var query = ""
    @State private var following = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    var body: some View {
        switch model.state {
        case .loaded(let transcript):
            lines(transcript)
        case .failed:
            VStack(spacing: DISpacing.md) {
                Text("The transcript could not be loaded. Check your connection and try again.")
                    .diInterfaceFont(.callout)
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.center)
                Button("Try Again") { Task { await model.retry() } }
                    .buttonStyle(DICompactButtonStyle())
            }
            .padding(DISpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .idle, .loading, .unavailable:
            ProgressView("Loading transcript…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var readsUrdu: Bool { DIBrand.readsUrdu(locale) }

    // MARK: Lines

    private func lines(_ transcript: BayanTranscript) -> some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shown = searching ? transcript.lines(matching: query) : transcript.lines
        let active = transcript.activeIndex(at: audioPlayer.currentTime)
        return VStack(spacing: DISpacing.sm) {
            searchField
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if searching && shown.isEmpty {
                            Text("No lines match your search.")
                                .diInterfaceFont(.callout)
                                .foregroundStyle(DIColor.textMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DISpacing.lg)
                        }
                        ForEach(shown) { line in
                            TranscriptLineRow(
                                line: line,
                                isActive: line.id == active,
                                sourceTitle: TranscriptSourceLabel.title(for: line, titles: model.titles, urdu: readsUrdu),
                                onSeek: { seek(to: line) },
                                onOpenQuran: { reference in
                                    onOpenQuran()
                                    DeepLinkRouter.shared.open(.quranAyah(surah: reference.surahNumber, ayah: reference.ayahNumber))
                                }
                            )
                            .id(line.id)
                        }
                    }
                    .padding(.horizontal, DISpacing.md)
                    .padding(.bottom, DISpacing.lg)
                }
                // A reader scrolling the lines stops the follow until asked again.
                .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in
                    if following { following = false }
                })
                .overlay(alignment: .bottom) {
                    if !following && !searching, let active {
                        Button {
                            following = true
                            scroll(proxy, to: active)
                        } label: {
                            Label("Current line", systemImage: "arrow.down.to.line")
                                .diInterfaceFont(.subheadline, weight: .semibold)
                        }
                        .buttonStyle(DICompactButtonStyle())
                        .padding(.bottom, DISpacing.sm)
                    }
                }
                .onChange(of: active) { _, index in
                    guard following, !searching, let index else { return }
                    scroll(proxy, to: index)
                }
                .onAppear {
                    if let active { proxy.scrollTo(active, anchor: .center) }
                }
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to index: Int) {
        if reduceMotion {
            proxy.scrollTo(index, anchor: .center)
        } else {
            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(index, anchor: .center) }
        }
    }

    private func seek(to line: BayanTranscript.Line) {
        DIHaptics.light()
        following = true
        audioPlayer.seek(to: line.start)
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DIColor.textMuted)
                .accessibilityHidden(true)
            TextField("Search this bayan", text: $query)
                .diInterfaceFont(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(DIColor.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, DISpacing.md)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous).fill(DIColor.surface))
        .overlay(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous).stroke(DIColor.border, lineWidth: 1))
        .padding(.horizontal, DISpacing.md)
    }
}

// MARK: - One line

private struct TranscriptLineRow: View {
    let line: BayanTranscript.Line
    let isActive: Bool
    let sourceTitle: String?
    let onSeek: () -> Void
    let onOpenQuran: (QuranReference) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DISpacing.sm) {
            Text(verbatim: BayanTranscript.timeLabel(line.start))
                .font(.caption.monospacedDigit())
                .foregroundStyle(DIColor.textMuted)
                .frame(minWidth: 40, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Button(action: onSeek) { content }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityText)
                    .accessibilityHint(Text("Plays from here"))
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                source
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, DISpacing.sm)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                    .fill(DIColor.accent.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                        .stroke(DIColor.accent.opacity(0.45), lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch line.kind {
        case .arabicUnverified:
            Label("Arabic recitation", systemImage: "waveform")
                .diInterfaceFont(.subheadline)
                .foregroundStyle(DIColor.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        case .speech:
            rightToLeft(Text(verbatim: line.text ?? "").font(DIFont.urduBody()).lineSpacing(6))
        case .quran:
            rightToLeft(Text(verbatim: line.text ?? "").font(DIFont.quranArabic(scale: 0.85)).foregroundStyle(DIColor.scripture))
        case .hadith, .dua:
            rightToLeft(Text(verbatim: line.text ?? "").font(DIFont.quranArabic(scale: 0.75)))
        }
    }

    /// Urdu and Arabic always read right to left, in either interface language.
    private func rightToLeft(_ text: some View) -> some View {
        text
            .foregroundStyle(isActive ? DIColor.textPrimary : DIColor.textPrimary.opacity(line.isSuspect ? 0.72 : 0.92))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .rightToLeft)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var source: some View {
        switch line.kind {
        case .quran:
            if let reference = QuranReference(line.reference) {
                Button {
                    onOpenQuran(reference)
                } label: {
                    Text("Qur'an \(reference.surahNumber):\(reference.ayahNumber)")
                        .diInterfaceFont(.caption, weight: .semibold)
                        .foregroundStyle(DIColor.actionForeground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(DIColor.accent.opacity(0.14)))
                        .overlay(Capsule().stroke(DIColor.accent.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .frame(minHeight: 32)
                .accessibilityHint(Text("Opens this ayah in the Qur'an"))
            }
        case .hadith, .dua:
            Group {
                if let sourceTitle {
                    Text(verbatim: sourceTitle)
                } else if line.kind == .hadith {
                    Text("Hadith")
                } else {
                    Text("Dua")
                }
            }
            .diInterfaceFont(.caption, weight: .semibold)
            .foregroundStyle(DIColor.textMuted)
        case .speech, .arabicUnverified:
            EmptyView()
        }
    }

    private var accessibilityText: Text {
        let time = Text(verbatim: BayanTranscript.timeLabel(line.start))
        switch line.kind {
        case .arabicUnverified:
            return Text("Arabic recitation") + Text(verbatim: ", ") + time
        default:
            return Text(verbatim: (line.text ?? "") + ", ") + time
        }
    }
}
