import SwiftUI

/// Detail screen for one community event: full details, add-to-calendar and
/// reminder actions (only when concrete dates exist), and the source link.
@MainActor
struct EventDetailView: View {
    @State private var viewModel: EventDetailViewModel

    init(event: CommunityEvent, notifications: any NotificationScheduling) {
        _viewModel = State(initialValue: EventDetailViewModel(event: event, notifications: notifications))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                headerCard

                if let details = viewModel.event.details {
                    DICard {
                        Text(verbatim: details)
                            .font(.body)
                            .foregroundStyle(DIColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if viewModel.hasConcreteDates {
                    actionsCard
                } else {
                    Text("Dates are announced by Dar-ul-Irfan closer to the time and may vary with moon sighting.")
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                        .padding(.horizontal, DISpacing.xs)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let sourceString = viewModel.event.sourceUrl, let sourceUrl = URL(string: sourceString) {
                    Link(destination: sourceUrl) {
                        Label("View on naqshbandiaowaisiah.org", systemImage: "safari")
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(DIColor.primary)
                    .padding(.horizontal, DISpacing.xs)
                }
            }
            .padding(DISpacing.md)
        }
        .navigationTitle(viewModel.event.kind.eventDisplayNameKey)
        .navigationBarTitleDisplayMode(.inline)
        .diScreenBackground()
        .alert("Calendar access needed", isPresented: $viewModel.showCalendarDeniedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Calendar access is currently off for Darul Irfan. To add events, please allow calendar access in iOS Settings.")
        }
        .alert("Notifications are off", isPresented: $viewModel.showNotificationsDeniedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To receive event reminders, please allow notifications for Darul Irfan in iOS Settings.")
        }
    }

    // MARK: - Sections

    private var headerCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                DIPillBadge(text: viewModel.event.kind.eventDisplayName)
                Text(verbatim: viewModel.event.title)
                    .font(DIFont.heading)
                    .foregroundStyle(DIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let titleUrdu = viewModel.event.titleUrdu {
                    Text(verbatim: titleUrdu)
                        .font(DIFont.urduBody())
                        .foregroundStyle(DIColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                if let venue = viewModel.event.venue {
                    Label {
                        Text(verbatim: venue)
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
                }
                datesLine
            }
        }
    }

    @ViewBuilder
    private var datesLine: some View {
        if let start = viewModel.event.startDate, viewModel.hasConcreteDates {
            if let end = viewModel.event.endDate, end > start {
                Label {
                    Text("\(start.formatted(date: .long, time: .omitted)) – \(end.formatted(date: .long, time: .omitted))")
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DIColor.primary)
            } else {
                Label {
                    Text(start.formatted(date: .long, time: .omitted))
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DIColor.primary)
            }
        } else {
            Label {
                Text("Dates announced by Dar-ul-Irfan")
            } icon: {
                Image(systemName: "calendar")
            }
            .font(.subheadline)
            .italic()
            .foregroundStyle(DIColor.textMuted)
        }
    }

    private var actionsCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Button {
                    Task { await viewModel.addToCalendar() }
                } label: {
                    switch viewModel.calendarState {
                    case .added:
                        Label("Added to Calendar", systemImage: "checkmark.circle")
                    case .working:
                        Label("Adding to Calendar…", systemImage: "calendar.badge.plus")
                    case .idle, .failed:
                        Label("Add to Calendar", systemImage: "calendar.badge.plus")
                    }
                }
                .buttonStyle(DISecondaryButtonStyle())
                .disabled(viewModel.calendarState == .working || viewModel.calendarState == .added)

                if viewModel.calendarState == .failed {
                    Text("The event could not be added to your calendar. Please try again.")
                        .font(.footnote)
                        .foregroundStyle(DIColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if viewModel.canOfferReminder {
                    Button {
                        Task { await viewModel.toggleReminder() }
                    } label: {
                        if viewModel.isReminderScheduled {
                            Label("Cancel Reminder", systemImage: "bell.slash")
                        } else {
                            Label("Remind Me", systemImage: "bell")
                        }
                    }
                    .buttonStyle(DISecondaryButtonStyle())

                    if viewModel.isReminderScheduled, let fireDate = viewModel.reminderFireDate {
                        Text("You will be reminded on \(fireDate.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.footnote)
                            .foregroundStyle(DIColor.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
