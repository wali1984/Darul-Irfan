import SwiftUI

/// Zikr section entry point, linked from the More tab: a living gradient hero
/// carrying the anchor verse of remembrance, the verified Method of Zikr, the
/// online zikr schedule as live session panels, and the personal tasbih.
@MainActor
struct ZikrHomeView: View {
    @State private var viewModel: ZikrHomeViewModel
    @State private var presentedVideo: ZikrPresentedVideo?
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: ZikrHomeViewModel(
            notifications: dependencies.notifications,
            platform: dependencies.officialPlatform,
            watchSync: dependencies.watchSync
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                ZikrHeroHeader()
                    .diAppear()
                    .diParallaxHero()

                DISectionHeader(titleKey: "Method of Zikr", systemImage: "heart")
                NavigationLink {
                    NativeMethodOfZikrView(repository: dependencies.contentRepository)
                } label: {
                    MethodOfZikrCard()
                }
                .buttonStyle(DIPressableStyle())
                    .diAppear(delay: 0.05)

                DISectionHeader(titleKey: "Live Zikr", systemImage: "dot.radiowaves.left.and.right")
                LiveBroadcastCard(broadcast: viewModel.live, audioPlayer: dependencies.audioPlayer)
                    .diAppear(delay: 0.08)

                DISectionHeader(titleKey: "Online Zikr", systemImage: "clock")
                if viewModel.isLoaded && viewModel.sessions.isEmpty {
                    DIElevatedCard {
                        DIEmptyState(
                            systemImage: "clock",
                            titleKey: "Schedule not available",
                            messageKey: "The online zikr schedule could not be loaded. Pull down later to check for a verified update."
                        )
                        .diOctagramWatermark(size: 200, opacity: 0.06)
                    }
                    .diAppear(delay: 0.1)
                } else {
                    ForEach(Array(viewModel.sessions.enumerated()), id: \.element.id) { index, session in
                        ZikrSessionCard(session: session, viewModel: viewModel)
                            .diAppear(delay: 0.1 + 0.05 * Double(index))
                    }
                }

                if !viewModel.recentBayans.isEmpty {
                    DISectionHeader(titleKey: "Recent Bayans", systemImage: "play.rectangle.on.rectangle")
                    ForEach(Array(viewModel.recentBayans.enumerated()), id: \.element.id) { index, item in
                        Button {
                            DIHaptics.light()
                            if let videoID = item.videoID {
                                presentedVideo = ZikrPresentedVideo(id: videoID, title: item.title)
                            }
                        } label: {
                            BayanRow(item: item)
                        }
                        .buttonStyle(DIPressableStyle())
                        .diAppear(delay: 0.12 + 0.04 * Double(index))
                    }
                }

                DISectionHeader(titleKey: "Tasbih", systemImage: "hand.tap")
                NavigationLink {
                    TasbihListView(
                        trackerRepository: dependencies.trackerRepository,
                        devotionalMetrics: dependencies.devotionalMetrics
                    )
                } label: {
                    tasbihEntryCard
                }
                .buttonStyle(DIPressableStyle())
                .diAppear(delay: 0.2)
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diPageHeading("Zikr")
        .diScreenBackground()
        .task { await viewModel.load() }
        .refreshable { await viewModel.load(forceRefresh: true) }
        .alert("Notifications are off", isPresented: $viewModel.showPermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To receive zikr reminders, please allow notifications for Darul Irfan in iOS Settings.")
        }
        .sheet(item: $presentedVideo) { video in
            YouTubePlayerSheet(videoID: video.id, title: video.title)
        }
    }

    // MARK: - Tasbih entry

    private var tasbihEntryCard: some View {
        DIElevatedCard(tint: DIColor.sandstone) {
            HStack(spacing: DISpacing.md) {
                ZStack {
                    Circle()
                        .fill(DIGradient.emerald)
                        .frame(width: 46, height: 46)
                    Image(systemName: "hand.tap.fill")
                        .font(.title3)
                        .foregroundStyle(DIColor.onPrimary)
                }
                .diGoldGlow(radius: 8, opacity: 0.3)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text("Tasbih Counters")
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                    Text("Count your personal zikr and build a gentle daily habit.")
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Hero

/// A living gradient header carrying Qur'an 13:28 — the verse of remembrance
/// that anchors the whole app and this section in particular.
private struct ZikrHeroHeader: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            DIGradient.hero()
                .diPatternOverlay(tint: .white, opacity: 0.07)
                .overlay(alignment: .topTrailing) {
                    DIOctagram(innerRatio: 0.5)
                        .stroke(Color.white, lineWidth: 1.5)
                        .frame(width: 260, height: 260)
                        .opacity(0.06)
                        .offset(x: 70, y: -70)
                }

            VStack(alignment: .leading, spacing: DISpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zikr Allah")
                            .font(DIFont.heading)
                            .foregroundStyle(.white)
                        Text("The remembrance of Allah")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    DILivingSealMark(diameter: 50)
                }

                VStack(alignment: .center, spacing: DISpacing.sm) {
                    Text(DIBrand.anchorVerseArabic)
                        .font(DIFont.quranArabic(scale: 0.78))
                        .foregroundStyle(.white)
                        .diGoldGlow(radius: 12, opacity: 0.5)
                        .environment(\.layoutDirection, .rightToLeft)
                        .multilineTextAlignment(.center)
                    Text(DIBrand.anchorVerseEnglish)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.88))
                        .multilineTextAlignment(.center)
                    Text(DIBrand.anchorVerseReference)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DIColor.goldGlow)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, DISpacing.xs)
            }
            .padding(DISpacing.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg + 6, style: .continuous))
        .shadow(color: DIColor.primaryDeep.opacity(0.35), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Method of Zikr

/// Verified description only — see Docs/RESEARCH_NOTES.md. The full
/// illustrated instructions are deliberately not reproduced here; they are
/// supplied through the verified content manifest.
private struct MethodOfZikrCard: View {
    var body: some View {
        DIElevatedCard(tint: DIColor.sandstone) {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) {
                    Image(systemName: "heart.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DIColor.primary)
                        .accessibilityHidden(true)
                    Text("Zikr-e Khafi Qalbi")
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                }
                DIJaliDivider(height: 14, opacity: 0.4)
                    .padding(.vertical, DISpacing.xs)
                Text("The method of zikr in the Naqshbandia Owaisiah order is Zikr-e Khafi Qalbi, practised with Pas Anfas — \"guarding every breath\".")
                    .font(.body)
                    .foregroundStyle(DIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A distinguishing feature of this order is spiritual bai'at directly at the hands of the holy Prophet ﷺ — the Owaisiah transmission.")
                    .font(.body)
                    .foregroundStyle(DIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The complete illustrated method is available natively in Darul Irfan.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Open Illustrated Method", systemImage: "book.pages")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DIColor.primary)
                    .padding(.top, DISpacing.xs)
            }
        }
    }
}

// MARK: - Online zikr session card

@MainActor
private struct ZikrSessionCard: View {
    let session: ZikrSession
    let viewModel: ZikrHomeViewModel

    var body: some View {
        DIElevatedCard(glow: DIColor.primary) {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) {
                    liveDot
                    Text(verbatim: session.title)
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                }

                HStack(spacing: DISpacing.sm) {
                    if ZikrScheduleMath.isDaily(session.weekdays) {
                        DIPillBadge(text: String(localized: "Daily"))
                    } else {
                        DIPillBadge(text: ZikrScheduleMath.shortWeekdaySymbols(for: session.weekdays).joined(separator: " · "))
                    }
                    if session.durationMinutes > 0 {
                        DIPillBadge(text: String(localized: "About \(session.durationMinutes) minutes"), color: DIColor.accent)
                    }
                }

                ZikrSessionCountdown(session: session)

                Text("Announced time: \(ZikrScheduleMath.announcedTimeText(for: session))")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)

                if let note = session.availabilityNote {
                    Text(verbatim: note)
                        .font(.footnote)
                        .italic()
                        .foregroundStyle(DIColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let instructions = session.instructions {
                    Text("How to join")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.textPrimary)
                        .padding(.top, DISpacing.xs)
                    Text(verbatim: instructions)
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let joinUrlString = session.joinUrl, let joinUrl = URL(string: joinUrlString) {
                    Link(destination: joinUrl) {
                        Label("Join Online Zikr", systemImage: "link")
                    }
                    .buttonStyle(DIPrimaryButtonStyle())
                    .padding(.top, DISpacing.xs)
                }

                Toggle(isOn: Binding(
                    get: { viewModel.isReminderEnabled(session.id) },
                    set: { newValue in
                        Task { await viewModel.setReminder(newValue, for: session) }
                    }
                )) {
                    Label("Remind me before each session", systemImage: "bell")
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textPrimary)
                }
                .tint(DIColor.primary)
                .padding(.top, DISpacing.xs)

            }
        }
    }

    private var liveDot: some View {
        Circle()
            .fill(DIColor.primary)
            .frame(width: 9, height: 9)
            .diBreathingGlow(color: DIColor.primary, maxRadius: 8)
            .accessibilityHidden(true)
    }
}

/// Battery-conscious live countdown: SwiftUI's timer text animates the digits
/// while the timeline reevaluates session state only every thirty seconds.
private struct ZikrSessionCountdown: View {
    let session: ZikrSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let start = ZikrScheduleMath.currentOrNextOccurrence(of: session, at: context.date) {
                let end = start.addingTimeInterval(TimeInterval(max(session.durationMinutes, 1) * 60))
                let active = start <= context.date && context.date < end

                HStack(spacing: DISpacing.md) {
                    ZStack {
                        Circle()
                            .fill(active ? DIColor.primary : DIColor.accent.opacity(0.18))
                            .frame(width: 42, height: 42)
                        Image(systemName: active ? "dot.radiowaves.left.and.right" : "timer")
                            .foregroundStyle(active ? Color.white : DIColor.primary)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(active ? "Zikr in progress" : "Zikr begins in")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(active ? DIColor.primary : DIColor.textMuted)
                        Text(active ? end : start, style: .timer)
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(DIColor.textPrimary)
                            .contentTransition(.numericText())
                        Text(start.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(DIColor.textMuted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(DISpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                        .fill(active ? DIColor.primary.opacity(0.10) : DIColor.accent.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                        .stroke(active ? DIColor.primary.opacity(0.42) : DIColor.accent.opacity(0.32), lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Recent bayans

private struct ZikrPresentedVideo: Identifiable {
    let id: String
    let title: String
}

/// A tappable video row — thumbnail with a play glyph + title. Opens the
/// in-app YouTube player, so watching a bayan never leaves the app.
private struct BayanRow: View {
    let item: OfficialFeedItem

    var body: some View {
        DICard(padding: DISpacing.sm) {
            HStack(spacing: DISpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous)
                        .fill(DIColor.primaryDeep.opacity(0.12))
                    if let imageURL = item.imageURL {
                        AsyncImage(url: imageURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.clear
                        }
                        .frame(width: 104, height: 62)
                        .clipped()
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 4)
                }
                .frame(width: 104, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous))

                Text(verbatim: item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DIColor.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: item.title))
        .accessibilityAddTraits(.isButton)
    }
}
