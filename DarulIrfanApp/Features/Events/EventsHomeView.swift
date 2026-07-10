import SwiftUI

/// Events & Dar-ul-Irfan entry point, linked from the More tab: upcoming
/// programs, the Dar-ul-Irfan place card (map, directions, contact), and the
/// announcements feed.
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
                if !viewModel.isLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(DISpacing.xl)
                } else {
                    DISectionHeader(titleKey: "Programs & Events", systemImage: "calendar")
                    if viewModel.events.isEmpty {
                        DIEmptyState(
                            systemImage: "calendar",
                            titleKey: "No events right now",
                            messageKey: "Programs at Dar-ul-Irfan will appear here when they are announced. You can also check naqshbandiaowaisiah.org."
                        )
                    } else {
                        ForEach(viewModel.events) { event in
                            NavigationLink {
                                EventDetailView(event: event, notifications: dependencies.notifications)
                            } label: {
                                EventRowCard(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let place = viewModel.place {
                        DISectionHeader(titleKey: "Dar-ul-Irfan", systemImage: "building.columns")
                        DarulIrfanCardView(place: place)
                    }

                    DISectionHeader(titleKey: "Announcements", systemImage: "megaphone")
                    if viewModel.announcements.isEmpty {
                        DIEmptyState(
                            systemImage: "megaphone",
                            titleKey: "No announcements",
                            messageKey: "News and announcements from Dar-ul-Irfan will appear here."
                        )
                    } else {
                        ForEach(viewModel.announcements) { announcement in
                            AnnouncementCard(announcement: announcement)
                        }
                    }
                }
            }
            .padding(DISpacing.md)
        }
        .navigationTitle("Events & Dar-ul-Irfan")
        .diScreenBackground()
        .task { await viewModel.load() }
    }
}

// MARK: - Event row

private struct EventRowCard: View {
    let event: CommunityEvent

    var body: some View {
        DICard {
            HStack(alignment: .top, spacing: DISpacing.md) {
                Image(systemName: event.kind.eventSymbolName)
                    .font(.title3)
                    .foregroundStyle(DIColor.primary)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DISpacing.xs) {
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
                Text("\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DIColor.primary)
            } else {
                Text(start.formatted(date: .abbreviated, time: .omitted))
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
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text(verbatim: announcement.title)
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let publishedAt = announcement.publishedAt {
                    Text(publishedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                if let body = announcement.body {
                    Text(verbatim: body)
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let sourceString = announcement.sourceUrl, let sourceUrl = URL(string: sourceString) {
                    Link("Read on naqshbandiaowaisiah.org", destination: sourceUrl)
                        .font(.footnote.weight(.semibold))
                        .tint(DIColor.primary)
                }
            }
        }
    }
}
