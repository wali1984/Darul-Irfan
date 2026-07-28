import SwiftUI

/// Events & Dar-ul-Irfan entry point, linked from the More tab: a living
/// gradient hero, upcoming programs as gradient event cards, the premium
/// Dar-ul-Irfan place card, and announcements as live panels.
@MainActor
struct EventsHomeView: View {
    @State private var viewModel: EventsHomeViewModel
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: EventsHomeViewModel(eventsRepository: dependencies.eventsRepository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                EventsHeroHeader(eventCount: viewModel.isLoaded ? viewModel.events.count : nil)
                    .diAppear()

                if !viewModel.isLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(DISpacing.xl)
                } else {
                    DISectionHeader(titleKey: "Programs & Events", systemImage: "calendar")
                    if viewModel.events.isEmpty {
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
                        ForEach(Array(viewModel.events.enumerated()), id: \.element.id) { index, event in
                            NavigationLink {
                                EventDetailView(event: event, notifications: dependencies.notifications)
                            } label: {
                                EventRowCard(event: event)
                            }
                            .buttonStyle(DIPressableStyle())
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
                            AnnouncementCard(announcement: announcement)
                                .diAppear(delay: 0.05 * Double(index))
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
                        Text("\(eventCount) upcoming \(eventCount == 1 ? "program" : "programs")")
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
        if let start = event.startDate, !event.datesAreApproximate {
            if let end = event.endDate, end > start {
                Label {
                    Text("\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))")
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(DIColor.primary)
            } else {
                Label {
                    Text(start.formatted(date: .abbreviated, time: .omitted))
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
