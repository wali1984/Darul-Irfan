import SwiftUI

/// Events & Dar-ul-Irfan entry point, linked from the More tab: a living
/// gradient hero, upcoming programs as gradient event cards, the premium
/// Dar-ul-Irfan place card, and announcements as live panels.
@MainActor
struct EventsHomeView: View {
    @State private var viewModel: EventsHomeViewModel
    /// A program a notification or a link named, opened over the list.
    @State private var linkedEvent: CommunityEvent?
    /// For an announcement that is a library item, opened in full.
    @State private var libraryViewModel: LibraryViewModel
    private let dependencies: AppDependencies
    private let appState: AppState
    /// Opens the program a link names. Only Discover's copy of this screen
    /// does, so the one under the Halqah tab does not take it as well.
    private let followsLinks: Bool

    init(dependencies: AppDependencies, appState: AppState, followsLinks: Bool = false) {
        self.dependencies = dependencies
        self.appState = appState
        self.followsLinks = followsLinks
        _viewModel = State(initialValue: EventsHomeViewModel(
            eventsRepository: dependencies.eventsRepository,
            contentRepository: dependencies.contentRepository
        ))
        _libraryViewModel = State(initialValue: LibraryViewModel(contentRepository: dependencies.contentRepository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                EventsHeroHeader(eventCount: viewModel.isLoaded ? viewModel.upcoming.count : nil)
                    .diAppear()

                if !viewModel.isLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(DISpacing.xl)
                } else {
                    // What is coming, when anything is, and the standing
                    // programs; what has taken place is listed further down.
                    DISectionHeader(titleKey: "Programs & Events", systemImage: "calendar")
                    if viewModel.upcoming.isEmpty && viewModel.regular.isEmpty {
                        DIElevatedCard {
                            DIEmptyState(
                                systemImage: "calendar",
                                titleKey: "No events right now",
                                messageKey: "Programs at Dar-ul-Irfan will appear here automatically when they are announced."
                            )
                            .diOctagramWatermark(size: 200, opacity: 0.06)
                        }
                        .diAppear(delay: 0.05)
                    } else {
                        ForEach(Array((viewModel.upcoming + viewModel.regular).enumerated()), id: \.element.id) { index, event in
                            eventLink(event, isPast: false)
                                .diAppear(delay: 0.05 + 0.05 * Double(index))
                        }
                    }

                    if let place = viewModel.place {
                        DISectionHeader(titleKey: "Dar-ul-Irfan", systemImage: "building.columns")
                        DarulIrfanCardView(place: place)
                            .diAppear(delay: 0.1)
                    }

                    DISectionHeader(titleKey: "Announcements", systemImage: "megaphone")
                    if viewModel.announcements.isEmpty {
                        DIElevatedCard {
                            DIEmptyState(
                                systemImage: "megaphone",
                                titleKey: "No announcements",
                                messageKey: "News and announcements from Dar-ul-Irfan will appear here."
                            )
                            .diOctagramWatermark(size: 200, opacity: 0.06)
                        }
                    } else {
                        ForEach(Array(viewModel.announcements.enumerated()), id: \.element.id) { index, announcement in
                            announcementRow(announcement)
                                .diAppear(delay: 0.05 * Double(index))
                        }
                    }

                    if !viewModel.past.isEmpty {
                        DISectionHeader(titleKey: "Past programs", systemImage: "clock.arrow.circlepath")
                        ForEach(viewModel.past) { event in
                            eventLink(event, isPast: true)
                        }
                    }
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diPageHeading("Events & Dar-ul-Irfan")
        .diScreenBackground()
        .task { await viewModel.load() }
        .onAppear(perform: openLinkedEvent)
        .onChange(of: viewModel.isLoaded) { _, _ in openLinkedEvent() }
        .onChange(of: DeepLinkRouter.shared.requestCount) { _, _ in openLinkedEvent() }
        .navigationDestination(isPresented: Binding(
            get: { linkedEvent != nil },
            set: { if !$0 { linkedEvent = nil } }
        )) {
            if let linkedEvent {
                EventDetailView(event: linkedEvent, notifications: dependencies.notifications)
            }
        }
    }

    @ViewBuilder
    private func announcementRow(_ announcement: Announcement) -> some View {
        if viewModel.libraryAnnouncementIDs.contains(announcement.id) {
            NavigationLink {
                ContentItemDetailView(
                    itemID: announcement.id,
                    dependencies: dependencies,
                    appState: appState,
                    libraryViewModel: libraryViewModel
                )
            } label: {
                AnnouncementCard(announcement: announcement)
            }
            .buttonStyle(DIPressableStyle())
        } else {
            AnnouncementCard(announcement: announcement)
        }
    }

    private func eventLink(_ event: CommunityEvent, isPast: Bool) -> some View {
        NavigationLink {
            EventDetailView(event: event, notifications: dependencies.notifications)
        } label: {
            EventRowCard(event: event, isPast: isPast)
        }
        .buttonStyle(DIPressableStyle())
    }

    /// A link to one program ("darulirfan://events/<id>") opens it once the
    /// programs are loaded.
    private func openLinkedEvent() {
        guard followsLinks, viewModel.isLoaded,
              let id = DeepLinkRouter.shared.take(\.eventID) else { return }
        linkedEvent = viewModel.allEvents.first { $0.id == id }
    }
}

// MARK: - Hero

private struct EventsHeroHeader: View {
    let eventCount: Int?

    var body: some View {
        ZStack(alignment: .topLeading) {
            DIGradient.hero()
                .diPatternOverlay(tint: .white, opacity: 0.07)
                .overlay(alignment: .topTrailing) {
                    DIOctagram(innerRatio: 0.5)
                        .stroke(Color.white, lineWidth: 1.5)
                        .frame(width: 240, height: 240)
                        .opacity(0.06)
                        .offset(x: 60, y: -60)
                }

            VStack(alignment: .leading, spacing: DISpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Events & Dar-ul-Irfan")
                            .font(DIFont.heading)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(DIBrand.tagline)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    DISealEmblem(diameter: 52, glow: true)
                        .diBreathingGlow(color: DIColor.goldGlow, maxRadius: 16)
                }

                if let eventCount, eventCount > 0 {
                    HStack(spacing: DISpacing.xs) {
                        Image(systemName: "calendar.badge.clock").font(.caption2)
                        Text("Upcoming programs: \(eventCount)")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, DISpacing.sm)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                }
            }
            .padding(DISpacing.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg + 6, style: .continuous))
        .shadow(color: DIColor.primaryDeep.opacity(0.35), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Event row

private struct EventRowCard: View {
    let event: CommunityEvent
    /// A program that has taken place shows its date, which approximate
    /// dates otherwise hide.
    var isPast = false

    var body: some View {
        DIElevatedCard(glow: event.kind.eventTint.opacity(0.7)) {
            HStack(alignment: .top, spacing: DISpacing.md) {
                ZStack {
                    Circle()
                        .fill(event.kind.eventTint.opacity(0.14))
                        .frame(width: 46, height: 46)
                    Image(systemName: event.kind.eventSymbolName)
                        .font(.title3)
                        .foregroundStyle(event.kind.eventTint)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    DIPillBadge(text: event.kind.eventDisplayName, color: event.kind.eventTint)
                    Text(verbatim: event.title)
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let venue = event.venue {
                        Label {
                            Text(verbatim: venue)
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                    }
                    eventDatesLine
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var eventDatesLine: some View {
        if let start = event.startDate, !event.datesAreApproximate || isPast {
            if let end = event.endDate, end > start {
                Label {
                    Text("\(CommunityEvent.dayText(start, .abbreviated)) – \(CommunityEvent.dayText(end, .abbreviated))")
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(DIColor.primary)
            } else {
                Label {
                    Text(CommunityEvent.dayText(start, .abbreviated))
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(DIColor.primary)
            }
        } else {
            Text("Dates announced by Dar-ul-Irfan")
                .font(.caption)
                .italic()
                .foregroundStyle(DIColor.textMuted)
        }
    }
}

// MARK: - Announcement card

private struct AnnouncementCard: View {
    let announcement: Announcement

    var body: some View {
        DIElevatedCard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(alignment: .top, spacing: DISpacing.sm) {
                    ZStack {
                        Circle()
                            .fill(DIColor.accent.opacity(0.16))
                            .frame(width: 38, height: 38)
                        Image(systemName: "megaphone.fill")
                            .font(.subheadline)
                            .foregroundStyle(DIColor.accent)
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DISpacing.xs) {
                        Text(verbatim: announcement.title)
                            .font(DIFont.subheading)
                            .foregroundStyle(DIColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let publishedAt = announcement.publishedAt {
                            Text(publishedAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(DIColor.textMuted)
                        }
                    }
                }
                if let body = announcement.body {
                    Text(verbatim: body)
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
