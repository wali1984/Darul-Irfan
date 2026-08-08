import SwiftUI

/// The two readers the Read tab offers. They are peers: neither is a section
/// of the other, and the interface never implies one contains the other.
enum ReadSection: String, CaseIterable, Hashable, Identifiable {
    case quran
    case hadith

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .quran: return "Quran"
        case .hadith: return "Hadith"
        }
    }

    var symbol: String {
        switch self {
        case .quran: return "book"
        case .hadith: return "book.closed"
        }
    }

    var blurb: LocalizedStringKey {
        switch self {
        case .quran: return "All 114 surahs with translation and tafsir"
        case .hadith: return "Seven collections in Arabic, English and Urdu"
        }
    }
}

/// Read tab: one tab holding two equal readers.
///
/// Why this exists: the app previously gave Quran and Hadith a top-level tab
/// each. That made six tabs, and iPhone collapses anything past the fifth into
/// a system "More" list — so Explore disappeared from the tab bar and sat
/// inside a More within a More. Pairing the two readers under Read brings the
/// shell back to five real tabs.
///
/// Both readers are kept alive side by side rather than swapped in and out, so
/// each keeps its own navigation history: go three levels into a surah, switch
/// to Hadith, come back, and the surah is still open. That is also exactly the
/// lifecycle they had as two sibling tabs, so nothing regresses.
struct ReadTabView: View {
    let dependencies: AppDependencies
    let appState: AppState

    /// nil while the landing screen is showing. Explicitly defaulted so the
    /// synthesized memberwise init stays internal.
    @State private var active: ReadSection? = nil
    /// Navigation history per reader, held here so switching cannot discard it.
    @State private var quranPath: [QuranRoute] = []
    @State private var hadithPath: [HadithRoute] = []
    /// Survives launches, so the tab reopens where the reader left off.
    @AppStorage("read.lastSection") private var lastSection: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let active {
                readers(active: active)
            } else {
                landing
            }
        }
        .onAppear(perform: restoreLastSection)
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveAppDeepLink)) { notification in
            if let path = notification.object as? String { open(deepLinkPath: path) }
        }
        // A Qur'an verse quoted inside a hadith was tapped: switch to the Quran
        // reader and open it at that ayah — all in-app, no external site.
        .onReceive(NotificationCenter.default.publisher(for: .openQuranAyah)) { notification in
            guard let link = notification.object as? QuranAyahLink else { return }
            Task { @MainActor in
                let surahs = (try? await dependencies.quranRepository.allSurahs()) ?? []
                guard let surah = surahs.first(where: { $0.id == link.surah }) else { return }
                select(.quran)
                quranPath = [.reader(surah: surah, focusAyah: link.ayah)]
            }
        }
    }

    // MARK: - Landing

    /// Two cards of equal weight. Hadith is not a footnote to the Quran here:
    /// same size, same treatment, same prominence, so it cannot be overlooked.
    private var landing: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                DISectionHeader(titleKey: "Read", systemImage: "books.vertical.fill")

                ForEach(Array(ReadSection.allCases.enumerated()), id: \.element) { index, section in
                    Button {
                        DIHaptics.soft()
                        select(section)
                    } label: {
                        card(for: section)
                    }
                    .buttonStyle(DIPressableStyle())
                    // Stable handle for the UI test that both destinations are
                    // offered, independent of language.
                    .accessibilityIdentifier("read.destination.\(section.rawValue)")
                    .diAppear(delay: 0.05 * Double(index))
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .diPageHeading("Read")
    }

    private func card(for section: ReadSection) -> some View {
        DIElevatedCard(glow: DIColor.accent) {
            HStack(spacing: DISpacing.md) {
                ZStack {
                    Circle().fill(DIGradient.emerald)
                    Image(systemName: section.symbol)
                        .font(.title3)
                        .foregroundStyle(DIColor.onPrimary)
                }
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text(section.title)
                        .font(DIFont.heading)
                        .foregroundStyle(DIColor.textPrimary)
                    Text(section.blurb)
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textMuted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.forward")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DIColor.accent)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, DISpacing.xs)
        }
    }

    // MARK: - Readers

    /// Both readers stay in the hierarchy; only the active one is visible and
    /// interactive. That is what preserves each one's navigation stack.
    ///
    /// The switch is handed down rather than applied here: each reader owns its
    /// own `NavigationStack`, and a `.toolbar` attached from outside would have
    /// no navigation bar to attach to.
    private func readers(active: ReadSection) -> some View {
        ZStack {
            keptAlive(isActive: active == .quran) {
                QuranTabView(
                    dependencies: dependencies,
                    appState: appState,
                    navigationPath: $quranPath,
                    readerSelection: selectionBinding,
                    onShowAllReaders: showLanding
                )
            }
            keptAlive(isActive: active == .hadith) {
                HadithTabView(
                    dependencies: dependencies,
                    appState: appState,
                    navigationPath: $hadithPath,
                    readerSelection: selectionBinding,
                    onShowAllReaders: showLanding
                )
            }
        }
    }

    private func keptAlive<Content: View>(
        isActive: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .zIndex(isActive ? 1 : 0)
    }

    private var selectionBinding: Binding<ReadSection> {
        Binding(
            get: { active ?? .quran },
            set: { select($0) }
        )
    }

    // MARK: - Selection

    private func select(_ section: ReadSection) {
        lastSection = section.rawValue
        // The switch itself may animate; the sacred text it reveals never does.
        if reduceMotion {
            active = section
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { active = section }
        }
    }

    private func showLanding() {
        DIHaptics.soft()
        if reduceMotion {
            active = nil
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { active = nil }
        }
    }

    private func restoreLastSection() {
        guard active == nil, let remembered = ReadSection(rawValue: lastSection) else { return }
        active = remembered
    }

    /// Deep links address a reader directly: neither is reachable only through
    /// the other, so `…/hadith` never has to travel via the Quran.
    func open(deepLinkPath path: String) {
        let lowered = path.lowercased()
        if lowered.contains("hadith") {
            select(.hadith)
        } else if lowered.contains("quran") || lowered.contains("surah") {
            select(.quran)
        }
    }
}

// MARK: - Reader switch

/// The compact switch shown once a reader is open, plus a way back to the two
/// cards. Lives in the navigation bar so the reading surface below it stays
/// calm and uninterrupted.
struct ReaderSwitch: ViewModifier {
    @Binding var selection: ReadSection
    let onShowAll: () -> Void

    func body(content: Content) -> some View {
        content
        // The switch occupies the title position, so the large title would
        // only compete with it. Applied here rather than on the readers
        // themselves, so a reader shown without the switch keeps its own
        // large-title treatment unchanged.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DISegmentedControl(
                    items: ReadSection.allCases,
                    title: { $0.title },
                    icon: { $0.symbol },
                    selection: $selection
                )
                .frame(maxWidth: 240)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onShowAll) {
                    Image(systemName: "square.grid.2x2")
                }
                .accessibilityLabel("Show both readers")
            }
        }
    }
}

extension View {
    func readerSwitch(
        selection: Binding<ReadSection>,
        onShowAll: @escaping () -> Void
    ) -> some View {
        modifier(ReaderSwitch(selection: selection, onShowAll: onShowAll))
    }
}
