import SwiftUI

/// Zikr section entry point, linked from the More tab: a living gradient hero
/// carrying the anchor verse of remembrance, the verified Method of Zikr, the
/// online zikr schedule as live session panels, and the personal tasbih.
@MainActor
struct ZikrHomeView: View {
    @State private var viewModel: ZikrHomeViewModel
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: ZikrHomeViewModel(
            notifications: dependencies.notifications,
            platform: dependencies.officialPlatform
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                ZikrHeroHeader()
                    .diAppear()

                DISectionHeader(titleKey: "Method of Zikr", systemImage: "heart")
                MethodOfZikrCard()
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
                            messageKey: "The online zikr schedule could not be loaded. Current timings are always announced on naqshbandiaowaisiah.org."
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

                DISectionHeader(titleKey: "Tasbih", systemImage: "hand.tap")
                NavigationLink {
                    TasbihListView(trackerRepository: dependencies.trackerRepository)
                } label: {
                    tasbihEntryCard
                }
                .buttonStyle(DIPressableStyle())
                .diAppear(delay: 0.2)
            }
            .padding(DISpacing.md)
        }
        .navigationTitle("Zikr")
        .diScreenBackground()
        .task { await viewModel.load() }
        .alert("Notifications are off", isPresented: $viewModel.showPermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To receive zikr reminders, please allow notifications for Darul Irfan in iOS Settings.")
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
                    DISealEmblem(diameter: 52, glow: true)
                        .diBreathingGlow(color: DIColor.goldGlow, maxRadius: 16)
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
/// taught on the official website.
private struct MethodOfZikrCard: View {
    private let methodOfZikrURL = URL(string: "https://www.naqshbandiaowaisiah.org/method-of-zikr.html")

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
                Text("The complete illustrated method of zikr is taught on the official website.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = methodOfZikrURL {
                    Link(destination: url) {
                        Label("Read the Method of Zikr", systemImage: "safari")
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(DIColor.primary)
                    .padding(.top, DISpacing.xs)
                }
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

                if let next = viewModel.nextOccurrence(forSessionID: session.id) {
                    HStack(spacing: DISpacing.sm) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.subheadline)
                            .foregroundStyle(DIColor.primary)
                            .accessibilityHidden(true)
                        Text("Next session: \(next.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DIColor.primary)
                    }
                    .padding(.horizontal, DISpacing.sm)
                    .padding(.vertical, DISpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous)
                            .fill(DIColor.primary.opacity(0.08))
                    )
                }

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

                if let sourceString = session.sourceUrl, let sourceUrl = URL(string: sourceString) {
                    Link("Schedule source: naqshbandiaowaisiah.org", destination: sourceUrl)
                        .font(.footnote)
                        .tint(DIColor.textMuted)
                }
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
