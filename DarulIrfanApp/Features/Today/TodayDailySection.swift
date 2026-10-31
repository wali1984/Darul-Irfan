import SwiftUI
import UIKit

/// Today's Light (board Main): any announcement, then the six daily cards
/// in one place, switched with one control (Ayah, Hadith, Saying, Dua,
/// Zikr, Name). Each card keeps its content and Share and gains one way on:
/// the ayah to the Qur'an, its Tafsir sheet and its bayan; the hadith to
/// the narration in full; the dua to Duas; the zikr to the Tasbih counters;
/// the Name to all 99. The cards are one height, so the page never jumps
/// when they are switched. A picture the Super admin published for a card
/// takes its content's place and keeps its way on; the day's quote opens
/// over the page once. Self-contained; embedded in the Today tab's scroll.
struct TodayDailySection: View {
    let appState: AppState
    private let dependencies: AppDependencies?
    @State private var viewModel: TodayDailyViewModel
    @State private var shareItem: ShareImageItem?
    @State private var popupItem: DailyMediaItem?
    @State private var selection: TodayLightKind = .ayah
    @State private var showsTafsir = false
    /// Pop-ups already shown, so each opens once.
    @AppStorage("today.seenPopups") private var seenPopups = ""
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(appState: AppState, dependencies: AppDependencies? = nil) {
        self.appState = appState
        self.dependencies = dependencies
        _viewModel = State(initialValue: TodayDailyViewModel(
            appState: appState,
            quranRepository: dependencies?.quranRepository,
            hadithRepository: dependencies?.hadithRepository
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            if viewModel.isLoaded {
                ForEach(viewModel.announcements) { item in
                    announcementCard(item)
                }
                TodaySectionTitle(titleKey: "Today's Light", systemImage: "sparkles")
                picker
                cards
                pageDots
            }
        }
        .task {
            viewModel.load()
            await viewModel.loadSilsilaAyah()
            await viewModel.loadHadith()
            await viewModel.loadMedia()
            showPopupIfDue()
        }
        .onChange(of: appState.settings.language) {
            Task {
                viewModel.load()
                await viewModel.loadSilsilaAyah()
                await viewModel.loadHadith()
            }
        }
        .onChange(of: viewModel.media) { showPopupIfDue() }
        .fullScreenCover(item: $popupItem) { item in DailyPictureViewer(item: item) }
        // A new day where the phone is: back in the app, local midnight
        // (iOS announces it), or a new time zone after travel.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refreshIfNewDay() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await viewModel.refreshIfNewDay() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            NSTimeZone.resetSystemTimeZone()
            Task { await viewModel.refreshIfNewDay() }
        }
        // While the page stays open across midnight.
        .task(id: viewModel.loadedDay) {
            guard let next = Calendar.autoupdatingCurrent.nextDate(
                after: Date(), matching: DateComponents(hour: 0, minute: 0, second: 5), matchingPolicy: .nextTime
            ) else { return }
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
            if !Task.isCancelled { await viewModel.refreshIfNewDay() }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image])
        }
        .sheet(isPresented: $showsTafsir) {
            if let ayah = viewModel.ayah, let dependencies {
                TodayAyahTafsirSheet(
                    surahNumber: ayah.surah,
                    ayahNumber: ayah.ayahStart,
                    dependencies: dependencies,
                    appState: appState
                )
            }
        }
    }

    // MARK: - Switch

    /// One switch for the six cards. When its six names do not fit at the
    /// text size in use, chips that scroll sideways take its place, so no
    /// name is cut short.
    private var picker: some View {
        ViewThatFits(in: .horizontal) {
            DISegmentedControl(items: TodayLightKind.allCases, title: { $0.segmentTitle }, selection: $selection)
            DIChipTabs(items: TodayLightKind.allCases, title: { $0.segmentTitle }, selection: $selection)
                .padding(.horizontal, -DISpacing.md)
        }
    }

    // MARK: - Cards

    /// All six cards share one frame, as tall as the tallest, and the one
    /// chosen rises into view. The others stay laid out but unseen, so the
    /// page keeps its length when the card changes.
    private var cards: some View {
        ZStack(alignment: .top) {
            ForEach(TodayLightKind.allCases) { kind in
                let shown = kind == selection
                card(kind)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown || reduceMotion ? 0 : 10)
                    .allowsHitTesting(shown)
                    .accessibilityHidden(!shown)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .background { TodayLightCardBackground() }
        .todayGlassChrome(cornerRadius: 28)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: selection)
    }

    @ViewBuilder
    private func card(_ kind: TodayLightKind) -> some View {
        switch kind {
        case .ayah:
            TodayAyahCard(
                ayah: viewModel.ayah,
                silsila: viewModel.silsilaAyah,
                fallbackTranslation: viewModel.ayahTranslation(),
                readsUrdu: viewModel.readsUrdu,
                picture: viewModel.picture(for: .ayah),
                onShare: viewModel.picture(for: .ayah) == nil ? shareAction(viewModel.ayahShare()) : nil,
                onTafsir: tafsirAction,
                onBayan: bayanAction
            )
        case .hadith:
            TodayHadithCard(
                hadith: viewModel.hadith,
                readsUrdu: viewModel.readsUrdu,
                picture: viewModel.picture(for: .hadith),
                onShare: viewModel.picture(for: .hadith) == nil ? shareAction(viewModel.hadithShare()) : nil,
                appState: appState,
                dependencies: dependencies
            )
        case .saying:
            TodaySayingCard(
                aqwal: viewModel.aqwal,
                picture: viewModel.picture(for: .aqwal),
                onShare: viewModel.picture(for: .aqwal) == nil ? shareAction(viewModel.aqwalShare()) : nil
            )
        case .dua:
            TodayDuaCard(
                dua: viewModel.dua,
                readsUrdu: viewModel.readsUrdu,
                translation: viewModel.duaTranslation(),
                onShare: shareAction(viewModel.duaShare())
            )
        case .zikr:
            TodayZikrCard(
                dhikr: viewModel.dhikr,
                onShare: shareAction(viewModel.dhikrShare()),
                dependencies: dependencies,
                isShown: selection == .zikr
            )
        case .name:
            TodayNameCard(
                name: viewModel.name,
                meaning: viewModel.nameMeaning(),
                onShare: shareAction(viewModel.nameShare()),
                isShown: selection == .name
            )
        }
    }

    /// Where the chosen card sits among the six; a picture of the switch,
    /// not a count.
    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(TodayLightKind.allCases) { kind in
                Capsule()
                    .fill(kind == selection ? AnyShapeStyle(dotGradient) : AnyShapeStyle(TodayPalette.pageDot))
                    .frame(width: kind == selection ? 22 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, -DISpacing.xs)
        .accessibilityHidden(true)
    }

    private var dotGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x13A06F), Color(hex: 0xE0B75F)], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Pictures and announcements

    private func showPopupIfDue() {
        let seen = Set(seenPopups.split(separator: ",").map(String.init))
        guard popupItem == nil, let item = viewModel.popup(seen: seen) else { return }
        popupItem = item
        // Remembered, and the list kept short.
        seenPopups = (Array(seen.suffix(40)) + [item.id]).joined(separator: ",")
    }

    private func announcementCard(_ item: DailyMediaItem) -> some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeaderInline(title: "Announcement", systemImage: "megaphone.fill")
            DailyPicture(item: item)
        }
        .padding(DISpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayGlass(cornerRadius: 22)
    }

    // MARK: - Actions

    /// Share as the card always has: the card rendered as an image.
    private func shareAction(_ content: ShareableContent?) -> (() -> Void)? {
        guard let content else { return nil }
        return {
            if let image = ShareCardRenderer.image(for: content) {
                shareItem = ShareImageItem(image: image)
            }
        }
    }

    /// Opens the ayah's Tafsir sheet, which needs the Qur'an repository.
    private var tafsirAction: (() -> Void)? {
        guard dependencies != nil else { return nil }
        return { showsTafsir = true }
    }

    /// Plays the bayan on the day's ayah, when the app has its dependencies.
    private var bayanAction: ((AyahBayanLink) -> Void)? {
        guard let dependencies else { return nil }
        return { link in play(link, dependencies: dependencies) }
    }

    /// Plays the bayan on these verses through the shared player, from the
    /// downloaded file when there is one so it also plays offline.
    private func play(_ link: AyahBayanLink, dependencies: AppDependencies) {
        Task {
            guard let item = try? await dependencies.mediaRepository.item(id: link.mediaID) else { return }
            let assets = (try? await dependencies.downloadsRepository.allAssets()) ?? []
            guard let playable = MediaPlayback.playableItem(
                for: item,
                asset: assets.first(where: { $0.mediaItemID == item.id }),
                downloadManager: dependencies.downloadManager
            ) else { return }
            dependencies.audioPlayer.play(playable, queue: [])
        }
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
