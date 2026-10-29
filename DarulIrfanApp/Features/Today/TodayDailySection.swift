import SwiftUI
import UIKit

/// The daily spiritual companion cards shown at the top of the Today tab:
/// any announcement, then the day's ayah, Aqwal-e-Sheikh, hadith, dua, dhikr,
/// and Name of Allah - with the picture the Super admin published for the
/// card that day, and the day's quote opening over the page once. Self-contained; embedded in the Today tab's
/// scroll above the prayer content.
struct TodayDailySection: View {
    let appState: AppState
    private let dependencies: AppDependencies?
    @State private var viewModel: TodayDailyViewModel
    @State private var shareItem: ShareImageItem?
    @State private var popupItem: DailyMediaItem?
    /// Pop-ups already shown, so each opens once.
    @AppStorage("today.seenPopups") private var seenPopups = ""
    @Environment(\.scenePhase) private var scenePhase

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
                verseCard.diAppear(delay: 0.05)
                aqwalCard.diAppear(delay: 0.10)
                hadithCard.diAppear(delay: 0.12)
                duaCard.diAppear(delay: 0.15)
                dhikrCard.diAppear(delay: 0.20)
                nameCard.diAppear(delay: 0.25)
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
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                DISectionHeaderInline(title: "Announcement", systemImage: "megaphone.fill")
                DailyPicture(item: item)
            }
        }
    }

    // MARK: - Hadith of the day

    /// A picture published for today takes the card's place; without one,
    /// the day's hadith from the app's own collections.
    @ViewBuilder
    private var hadithCard: some View {
        if let picture = viewModel.picture(for: .hadith) {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    DISectionHeaderInline(title: "Hadith of the Day", systemImage: "text.book.closed")
                    DailyPicture(item: picture)
                }
            }
        } else if let hadith = viewModel.hadith {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    DISectionHeaderInline(title: "Hadith of the Day", systemImage: "text.book.closed")
                    if let translation = hadith.translation {
                        translationText(translation, urdu: hadith.translationIsUrdu)
                            .lineLimit(10)
                    }
                    if let arabic = hadith.arabic, !arabic.isEmpty {
                        Text(verbatim: arabic)
                            .font(DIFont.quranArabic(scale: 0.7))
                            .foregroundStyle(DIColor.textMuted)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                    HStack {
                        let title = hadith.book.map { viewModel.readsUrdu ? $0.titleUrdu : $0.titleEnglish } ?? ""
                        Text(verbatim: "\(title) \(hadith.number)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DIColor.primary)
                        Spacer()
                        if let book = hadith.book, let dependencies {
                            NavigationLink {
                                HadithBookView(book: book, repository: dependencies.hadithRepository, appState: appState, initialHadith: hadith.id)
                            } label: {
                                Label("Read in full", systemImage: "arrow.up.forward.square")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Verse of the day

    private var verseCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack {
                    DIPillBadge(text: String(localized: "Ayah of the Day"))
                    Spacer()
                    if viewModel.picture(for: .ayah) == nil, let share = viewModel.ayahShare() {
                        shareButton(share)
                    }
                }
                // A picture published for today takes the verse's place;
                // without one, the day's ayah from the app's own Quran.
                if let picture = viewModel.picture(for: .ayah) {
                    DailyPicture(item: picture)
                } else if let ayah = viewModel.ayah {
                    let silsila = viewModel.silsilaAyah
                    Text(verbatim: silsila?.arabic ?? ayah.arabic)
                        .font(DIFont.quranArabic(scale: 1.05))
                        .foregroundStyle(DIColor.textPrimary)
                        .lineSpacing(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .rightToLeft)
                    Rectangle().fill(DIColor.accent).frame(height: 1).opacity(0.5)
                    if let translation = silsila?.translation ?? viewModel.ayahTranslation() {
                        translationText(translation, urdu: silsila?.isUrdu ?? viewModel.readsUrdu)
                    }
                    // Whose translation it is, and exactly where it is from.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: silsila?.reference ?? ayah.reference)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DIColor.primary)
                        if let silsila {
                            Text(verbatim: [silsila.surahNameArabic, silsila.translationEdition]
                                .filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(DIColor.textMuted)
                        }
                    }
                    if let excerpt = silsila?.tafsirExcerpt, let title = silsila?.tafsirTitle {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Label {
                                Text(verbatim: title)
                            } icon: {
                                Image(systemName: "text.book.closed")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DIColor.accent)
                            translationText(excerpt, urdu: silsila?.isUrdu ?? false, small: true)
                        }
                    }
                    HStack(spacing: DISpacing.sm) {
                        Button {
                            DIHaptics.soft()
                            DeepLinkRouter.shared.open(.quranAyah(surah: ayah.surah, ayah: ayah.ayahStart))
                        } label: {
                            Label("Open in the Quran", systemImage: "book.closed")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        if let bayan = silsila?.bayan, let dependencies {
                            Button {
                                DIHaptics.soft()
                                play(bayan, dependencies: dependencies)
                            } label: {
                                Label("Bayan", systemImage: "play.circle")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(Text(verbatim: bayan.title))
                        }
                    }
                }
            }
        }
    }

    /// Urdu in Nastaliq right to left, English left to right, whatever the
    /// app's own layout is.
    @ViewBuilder
    private func translationText(_ text: String, urdu: Bool, small: Bool = false) -> some View {
        if urdu {
            Text(verbatim: text)
                .font(DIFont.urduBody(scale: small ? 0.85 : 1.0))
                .foregroundStyle(DIColor.textPrimary)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .rightToLeft)
        } else {
            Text(verbatim: text)
                .font(small ? .subheadline : .body)
                .foregroundStyle(DIColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .leftToRight)
        }
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

    // MARK: - Aqwal-e-Sheikh (the differentiator)

    @ViewBuilder
    private var aqwalCard: some View {
        if let aqwal = viewModel.aqwal {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    HStack {
                        DISectionHeaderInline(title: "Aqwal-e-Sheikh", systemImage: "quote.opening")
                        Spacer()
                        if viewModel.picture(for: .aqwal) == nil, let share = viewModel.aqwalShare() {
                            shareButton(share)
                        }
                    }
                    // A picture published for today takes the saying's place.
                    if let picture = viewModel.picture(for: .aqwal) {
                        DailyPicture(item: picture)
                    } else {
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
    }

    // MARK: - Daily dua

    @ViewBuilder
    private var duaCard: some View {
        if let dua = viewModel.dua {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    DISectionHeaderInline(title: "Dua of the Day", systemImage: "hands.sparkles")
                    Text(verbatim: dua.displayTitle(urdu: viewModel.readsUrdu))
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
                    DISectionHeaderInline(title: "Zikr of the Day", systemImage: "circle.hexagongrid")
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
                    DISectionHeaderInline(title: "Name of the Day", systemImage: "sparkle")
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
