import SwiftUI

/// Detail screen for one community event: a gradient crest header, full
/// details, add-to-calendar and reminder actions (only when concrete dates
/// exist), and the source link.
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
                    .diAppear()

                if let details = viewModel.event.details {
                    DIElevatedCard {
                        Text(verbatim: details)
                            .font(.body)
                            .foregroundStyle(DIColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .diAppear(delay: 0.05)
                }

                if viewModel.hasConcreteDates {
                    actionsCard
                        .diAppear(delay: 0.1)
                } else {
                    Text("Dates are announced by Dar-ul-Irfan closer to the time and may vary with moon sighting.")
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                        .padding(.horizontal, DISpacing.xs)
                        .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Header crest

    private var headerCard: some View {
        ZStack(alignment: .topLeading) {
            DIGradient.hero()
                .overlay(alignment: .topTrailing) {
                    DIOctagram(innerRatio: 0.5)
                        .stroke(Color.white, lineWidth: 1.5)
                        .frame(width: 200, height: 200)
                        .opacity(0.06)
                        .offset(x: 60, y: -50)
                }

            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.16))
                            .frame(width: 44, height: 44)
                        Image(systemName: viewModel.event.kind.eventSymbolName)
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)
                    Text(viewModel.event.kind.eventDisplayNameKey)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DISpacing.sm)
                        .padding(.vertical, DISpacing.xs)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                    Spacer(minLength: 0)
                }

                Text(verbatim: viewModel.event.title)
                    .font(DIFont.heading)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                if let titleUrdu = viewModel.event.titleUrdu {
                    Text(verbatim: titleUrdu)
                        .font(DIFont.urduBody())
                        .foregroundStyle(.white.opacity(0.92))
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
                    .foregroundStyle(.white.opacity(0.85))
                }

                datesLine
            }
            .padding(DISpacing.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg + 6, style: .continuous))
        .shadow(color: DIColor.primaryDeep.opacity(0.35), radius: 16, x: 0, y: 8)
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
                .foregroundStyle(DIColor.goldGlow)
            } else {
                Label {
                    Text(start.formatted(date: .long, time: .omitted))
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DIColor.goldGlow)
            }
        } else {
            Label {
                Text("Dates announced by Dar-ul-Irfan")
            } icon: {
                Image(systemName: "calendar")
            }
            .font(.subheadline)
            .italic()
            .foregroundStyle(.white.opacity(0.75))
        }
    }

    private var actionsCard: some View {
        DIElevatedCard {
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
