import SwiftUI

/// Discover › Bayans (the Media tab before): Continue listening, the lecture
/// tiles, the channel's recent bayans and the archive by year. One name
/// everywhere: Bayans. The Daily Zikr live card is on the Zikr tab.
@MainActor
struct BayansSection: View {
    let media: MediaViewModel
    let feed: BayansFeedModel
    let dependencies: AppDependencies
    @State private var presentedVideo: BayanVideo? = nil

    private let tileColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    /// Categories with something in them. Most of the catalogue's are empty,
    /// and a tile saying "No items yet" looked broken.
    private var shownCategories: [MediaCategory] {
        MediaCategory.allCases.filter { (media.categoryCounts[$0] ?? 0) > 0 }
    }

    /// The catalogue has been read, or could not be.
    private var showsCatalogue: Bool {
        !media.isLoading && (media.hasLoadedOnce || media.loadErrorMessage != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            if let message = media.loadErrorMessage {
                loadErrorCard(message)
            }
            continueListening
            catalogue
            recentOnYouTube
            if showsCatalogue && !(media.isEmpty && media.loadErrorMessage == nil) {
                browseByYear
                    .diAppear(delay: 0.15)
            }
        }
        .task { await media.loadIfNeeded() }
        .task { await feed.loadIfNeeded() }
        .sheet(item: $presentedVideo) { video in
            YouTubePlayerSheet(videoID: video.id, title: video.title)
        }
    }

    // MARK: Continue listening

    @ViewBuilder
    private var continueListening: some View {
        if let latest = media.resumeEntries.first {
            BayansContinueHero(entry: latest) { media.resume(latest) }
                .diAppear()
            let others = Array(media.resumeEntries.dropFirst())
            if !others.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: DISpacing.sm) {
                        ForEach(others) { entry in
                            BayansResumeCard(entry: entry) { media.resume(entry) }
                        }
                    }
                    .padding(.vertical, DISpacing.xs)
                }
                .diAppear(delay: 0.05)
            }
        }
    }

    // MARK: Lectures

    @ViewBuilder
    private var catalogue: some View {
        if !showsCatalogue {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(DISpacing.lg)
        } else if media.isEmpty && media.loadErrorMessage == nil {
            DIEmptyState(
                systemImage: "waveform",
                titleKey: "Preparing the bayans…",
                messageKey: "Lectures and programs will appear here after the first content sync. Pull down to refresh."
            )
            .diOctagramWatermark(size: 260, opacity: 0.05)
        } else if !shownCategories.isEmpty {
            LazyVGrid(columns: tileColumns, alignment: .leading, spacing: 10) {
                ForEach(Array(shownCategories.enumerated()), id: \.element) { index, category in
                    NavigationLink {
                        MediaItemListView(filter: .category(category), dependencies: dependencies)
                    } label: {
                        BayansTile(category: category, count: media.categoryCounts[category] ?? 0, gold: index % 3 == 1)
                    }
                    .buttonStyle(DIPressableStyle())
                    .simultaneousGesture(TapGesture().onEnded { DIHaptics.light() })
                    .diAppear(delay: 0.08 + Double(index) * 0.04)
                }
            }
        }
    }

    // MARK: Recent on YouTube

    @ViewBuilder
    private var recentOnYouTube: some View {
        if !feed.videos.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent on YouTube")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(DIColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: DISpacing.sm)
                NavigationLink {
                    BayanVideosListView(model: feed)
                } label: {
                    Text("See all")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.primary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.top, DISpacing.xs)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(Array(feed.videos.prefix(BayansFeedModel.carouselCount))) { item in
                        Button {
                            play(item)
                        } label: {
                            BayanVideoCard(item: item)
                        }
                        .buttonStyle(DIPressableStyle())
                        .accessibilityHint(Text("Plays in Darul Irfan"))
                    }
                }
                .padding(.vertical, DISpacing.xs)
            }
            .diAppear(delay: 0.12)
        }
    }

    private func play(_ item: OfficialFeedItem) {
        guard let videoID = item.videoID else { return }
        DIHaptics.light()
        presentedVideo = BayanVideo(id: videoID, title: item.title)
    }

    // MARK: Browse by year

    private var browseByYear: some View {
        NavigationLink {
            ArchiveBrowserView(dependencies: dependencies, category: nil)
        } label: {
            DiscoverLinkRow(
                systemImage: "calendar",
                title: Text("Browse by year"),
                subtitle: Text("Every bayan, by year and month")
            )
        }
        .buttonStyle(DIPressableStyle())
        .simultaneousGesture(TapGesture().onEnded { DIHaptics.light() })
    }

    // MARK: Error

    private func loadErrorCard(_ message: String) -> some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Label {
                    Text(LocalizedStringKey(message))
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textPrimary)
                } icon: {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(DIColor.danger)
                }
                Button {
                    Task { await media.load() }
                } label: {
                    Text("Try Again")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.primary)
                }
            }
        }
    }
}

// MARK: - Continue listening hero

/// The most recent bayan, on the emerald hero: its title, the speaker as
/// the catalogue gives it, the time left, and a gold play button.
private struct BayansContinueHero: View {
    let entry: MediaResumeEntry
    let onPlay: () -> Void

    private var percent: Int { Int(entry.progress.fractionCompleted * 100) }

    /// Whole minutes still to play, when the length is known.
    private var minutesLeft: Int? {
        let duration = entry.progress.durationSeconds
        guard duration > 0 else { return nil }
        let remaining = max(0, duration - entry.progress.positionSeconds)
        return Int((remaining / 60).rounded(.up))
    }

    var body: some View {
        Button {
            DIHaptics.soft()
            onPlay()
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    DiscoverCaption(key: "Continue Listening")
                    MediaTitleText(item: entry.item, latinFont: .headline, lineLimit: 2, color: .white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    detailLine
                    BayansProgressBar(fraction: entry.progress.fractionCompleted)
                        .padding(.top, 6)
                }
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: 0x064B34))
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(DiscoverStyle.goldButton))
                    .shadow(color: DIColor.goldGlow.opacity(0.55), radius: 11)
                    .accessibilityHidden(true)
            }
            .padding(DISpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DIHeroBackground(cornerRadius: 26))
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(DIPressableStyle())
        .accessibilityLabel(Text("Resume \(entry.item.title), \(percent) percent played"))
    }

    private var detailLine: some View {
        HStack(spacing: 4) {
            if let speaker = entry.item.speaker, !speaker.isEmpty {
                Text(verbatim: speaker)
                    .lineLimit(1)
                Text(verbatim: "·")
            }
            if let minutesLeft {
                Text("\(minutesLeft) min left")
                    .lineLimit(1)
            } else {
                Text("\(percent)% played")
                    .lineLimit(1)
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Color.white.opacity(0.85))
    }
}

/// The hero's thin gold bar of what has played.
private struct BayansProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color(hex: 0xFFE9A8), DIColor.goldGlow],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
                    .shadow(color: DIColor.goldGlow.opacity(0.8), radius: 5)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

/// Another bayan to resume, after the most recent one.
private struct BayansResumeCard: View {
    let entry: MediaResumeEntry
    let onPlay: () -> Void

    var body: some View {
        Button {
            DIHaptics.soft()
            onPlay()
        } label: {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(alignment: .top) {
                    MediaIconMedallion(category: entry.item.category, diameter: 34, glyph: "waveform")
                    Spacer(minLength: 0)
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DIColor.primary)
                        .accessibilityHidden(true)
                }
                MediaTitleText(item: entry.item, latinFont: .subheadline.weight(.semibold), lineLimit: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                ProgressView(value: min(max(entry.progress.fractionCompleted, 0), 1))
                    .tint(DIColor.accent)
            }
            .padding(14)
            .frame(width: 200, alignment: .leading)
            .frame(minHeight: 132, alignment: .top)
            .diGlassPanel(cornerRadius: 22)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(DIPressableStyle())
        .accessibilityLabel(Text("Resume \(entry.item.title), \(Int(entry.progress.fractionCompleted * 100)) percent played"))
    }
}

// MARK: - Tiles

/// A lecture category as a glass tile: its orb, its name and its count.
private struct BayansTile: View {
    let category: MediaCategory
    let count: Int
    let gold: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: MediaStyle.icon(category))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DiscoverStyle.orbInk(gold: gold))
                .frame(width: 40, height: 40)
                .background(Circle().fill(DiscoverStyle.orb(gold: gold)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(category.englishName))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(count, format: .number)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .diGlassPanel(cornerRadius: 22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Videos

private struct BayanVideo: Identifiable {
    let id: String
    let title: String
}

/// A bayan on YouTube as a wide card: its picture with the name over it and
/// a glass play button, then the rest of its title and its day.
private struct BayanVideoCard: View {
    let item: OfficialFeedItem

    var body: some View {
        let title = BayanVideoTitle.split(item.title)
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                BayanThumbnail(url: item.imageURL, width: 236, height: 132)
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                Text(verbatim: title.headline)
                    .font(.callout.weight(.heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
            .frame(width: 236, height: 132)
            .overlay(alignment: .center) {
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1))
                    .offset(y: -14)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: DIColor.primaryDeep.opacity(0.13), radius: 13, y: 12)
            VStack(alignment: .leading, spacing: 2) {
                if let detail = title.detail {
                    Text(verbatim: detail)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DIColor.textPrimary)
                        .lineLimit(1)
                }
                Text(item.publishedAt, format: .dateTime.day().month(.wide))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: 236, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A video's still, or an emerald field with the octagram when there is none.
private struct BayanThumbnail: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x0B7250), Color(hex: 0x03261A)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            DIOctagram(innerRatio: 0.5)
                .stroke(DIColor.goldGlow, lineWidth: 1)
                .frame(width: width * 0.85, height: width * 0.85)
                .opacity(0.18)
                .offset(x: width * 0.34, y: -height * 0.38)
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .accessibilityHidden(true)
    }
}

/// Every recent bayan on the channel the feed has reached, read further as
/// the list is scrolled.
struct BayanVideosListView: View {
    let model: BayansFeedModel
    @State private var presentedVideo: BayanVideo? = nil

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(model.videos) { item in
                    Button {
                        guard let videoID = item.videoID else { return }
                        DIHaptics.light()
                        presentedVideo = BayanVideo(id: videoID, title: item.title)
                    } label: {
                        BayanVideoRow(item: item)
                    }
                    .buttonStyle(DIPressableStyle())
                    .accessibilityHint(Text("Plays in Darul Irfan"))
                    .task {
                        if item.id == model.videos.last?.id, model.nextCursor != nil {
                            await model.loadMore()
                        }
                    }
                }
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(DISpacing.md)
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .navigationTitle("Recent on YouTube")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $presentedVideo) { video in
            YouTubePlayerSheet(videoID: video.id, title: video.title)
        }
    }
}

/// One bayan in the full list: its still and its whole title.
private struct BayanVideoRow: View {
    let item: OfficialFeedItem

    var body: some View {
        HStack(spacing: DISpacing.md) {
            ZStack {
                BayanThumbnail(url: item.imageURL, width: 104, height: 62)
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 4)
                    .accessibilityHidden(true)
            }
            .frame(width: 104, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DIColor.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text(item.publishedAt, format: .dateTime.day().month(.wide).year())
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DISpacing.sm)
        .diGlassPanel(cornerRadius: 20)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
