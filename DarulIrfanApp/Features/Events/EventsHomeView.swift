import SwiftUI

/// Events & Dar-ul-Irfan as a page of its own (the Halqah tab's link to it).
/// Discover shows the same `EventsSection` under its switch.
@MainActor
struct EventsHomeView: View {
    @State private var viewModel: EventsHomeViewModel
    private let dependencies: AppDependencies
    private let appState: AppState
    /// Opens the programme a link names. Only Discover's copy does, so this
    /// page does not take it as well.
    private let followsLinks: Bool

    init(dependencies: AppDependencies, appState: AppState, followsLinks: Bool = false) {
        self.dependencies = dependencies
        self.appState = appState
        self.followsLinks = followsLinks
        _viewModel = State(initialValue: EventsHomeViewModel(eventsRepository: dependencies.eventsRepository))
    }

    var body: some View {
        ScrollView {
            EventsSection(viewModel: viewModel, dependencies: dependencies, appState: appState, followsLinks: followsLinks)
                .padding(DISpacing.md)
                .diResponsiveWidth()
        }
        .diPageHeading("Events & Dar-ul-Irfan")
        .diScreenBackground()
        .refreshable { await viewModel.load() }
    }
}

// MARK: - Section

/// Discover › Events: the programmes to come and the regular ones, the
/// Dar-ul-Irfan card with the Silsila's seal, and the past programmes
/// folded into one row. The announcements moved to Updates.
@MainActor
struct EventsSection: View {
    let viewModel: EventsHomeViewModel
    let dependencies: AppDependencies
    let appState: AppState
    var followsLinks = false
    /// A programme a notification or a link named, opened over the page.
    @State private var linkedEvent: CommunityEvent? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            if !viewModel.isLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(DISpacing.xl)
            } else {
                programmes
                if let place = viewModel.place {
                    DarulIrfanHeroCard(place: place)
                        .diAppear(delay: 0.08)
                }
                if !viewModel.past.isEmpty {
                    NavigationLink {
                        PastProgrammesView(events: viewModel.past, notifications: dependencies.notifications)
                    } label: {
                        DiscoverLinkRow(
                            systemImage: "clock.arrow.circlepath",
                            title: Text("Past programmes (\(viewModel.past.count))"),
                            subtitle: Text("Newest first")
                        )
                    }
                    .buttonStyle(DIPressableStyle())
                    .diAppear(delay: 0.12)
                }
            }
        }
        .task {
            if !viewModel.isLoaded { await viewModel.load() }
        }
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
    private var programmes: some View {
        if viewModel.upcoming.isEmpty && viewModel.regular.isEmpty {
            DIEmptyState(
                systemImage: "calendar",
                titleKey: "No events right now",
                messageKey: "Programs at Dar-ul-Irfan will appear here automatically when they are announced."
            )
            .diGlassPanel(cornerRadius: 24)
            .diAppear()
        } else {
            if !viewModel.upcoming.isEmpty {
                DiscoverSectionLabel(key: "Upcoming programmes")
                ProgrammeList(
                    events: viewModel.upcoming,
                    notifications: dependencies.notifications,
                    language: appState.settings.language
                )
                .diAppear()
            }
            if !viewModel.regular.isEmpty {
                DiscoverSectionLabel(key: "Regular programmes")
                ProgrammeList(
                    events: viewModel.regular,
                    notifications: dependencies.notifications,
                    language: appState.settings.language
                )
                .diAppear(delay: 0.04)
            }
        }
    }

    /// A link to one programme ("darulirfan://events/<id>") opens it once
    /// the programmes are loaded.
    private func openLinkedEvent() {
        guard followsLinks, viewModel.isLoaded,
              let id = DeepLinkRouter.shared.take(\.eventID) else { return }
        linkedEvent = viewModel.allEvents.first { $0.id == id }
    }
}

// MARK: - Programmes

/// Programmes in one glass list, each row opening its details.
private struct ProgrammeList: View {
    let events: [CommunityEvent]
    let notifications: any NotificationScheduling
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                if index > 0 {
                    Divider()
                        .overlay(DIColor.primary.opacity(0.08))
                        .padding(.leading, 62)
                }
                NavigationLink {
                    EventDetailView(event: event, notifications: notifications)
                } label: {
                    ProgrammeRow(event: event, language: language)
                }
                .buttonStyle(DIPressableStyle())
            }
        }
        .padding(6)
        .diGlassPanel(cornerRadius: 24)
    }
}

/// One programme: an emerald orb with its kind's glyph, its name in the
/// app's language, its dates when it has them, and a chevron.
private struct ProgrammeRow: View {
    let event: CommunityEvent
    let language: AppLanguage

    private var title: String {
        if language.contentLanguageCode == "ur", let urdu = event.titleUrdu, !urdu.isEmpty {
            return urdu
        }
        return event.title
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.kind.eventSymbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DiscoverStyle.orbInk(gold: false))
                .frame(width: 38, height: 38)
                .background(Circle().fill(DiscoverStyle.orb(gold: false)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if event.startDate != nil {
                    EventDatesLine(event: event, isPast: false)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.bold))
                .foregroundStyle(DIColor.textMuted)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A programme's day or days. Approximate dates are not shown before the
/// programme, only "Dates announced by Dar-ul-Irfan".
private struct EventDatesLine: View {
    @Environment(\.locale) private var locale
    let event: CommunityEvent
    /// A programme that has taken place shows its date, which approximate
    /// dates otherwise hide.
    var isPast = false

    var body: some View {
        if let start = event.startDate, !event.datesAreApproximate || isPast {
            if let end = event.endDate, end > start {
                Label {
                    Text("\(CommunityEvent.dayText(start, .abbreviated, locale: locale)) – \(CommunityEvent.dayText(end, .abbreviated, locale: locale))")
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(DIColor.primary)
            } else {
                Label {
                    Text(CommunityEvent.dayText(start, .abbreviated, locale: locale))
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

// MARK: - Past programmes

/// The programmes that have taken place, newest first, folded behind one
/// row of the Events section.
private struct PastProgrammesView: View {
    let events: [CommunityEvent]
    let notifications: any NotificationScheduling

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DISpacing.md) {
                ForEach(events) { event in
                    NavigationLink {
                        EventDetailView(event: event, notifications: notifications)
                    } label: {
                        EventRowCard(event: event, isPast: true)
                    }
                    .buttonStyle(DIPressableStyle())
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .navigationTitle("Past programmes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One past programme in full: its kind, title, venue and dates.
private struct EventRowCard: View {
    @Environment(\.locale) private var locale
    let event: CommunityEvent
    var isPast = false

    private var urduTitle: String? {
        guard locale.language.languageCode?.identifier == "ur",
              let title = event.titleUrdu, !title.isEmpty else { return nil }
        return title
    }

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
                    Text(verbatim: urduTitle ?? event.title)
                        .font(urduTitle == nil ? DIFont.subheading : DIFont.urduBody())
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
                    EventDatesLine(event: event, isPast: isPast)
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
}

// MARK: - Dar-ul-Irfan

/// The centre on the emerald hero: the Silsila's seal, its name and
/// address, and Directions, Call and Email. The name opens the full card,
/// with the map and the number and address to copy.
private struct DarulIrfanHeroCard: View {
    let place: DarulIrfanPlace

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink {
                DarulIrfanPlacePage(place: place)
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Map showing the location of Dar-ul-Irfan"))
            HStack(spacing: 10) {
                if let url = place.directionsURL {
                    Link(destination: url) { pill("Directions", gold: true) }
                }
                if let url = place.phoneURL {
                    Link(destination: url) { pill("Call", gold: false) }
                }
                if let url = place.emailURL {
                    Link(destination: url) { pill("Email", gold: false) }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DIHeroBackground(cornerRadius: 26))
        .overlay(alignment: .topTrailing) {
            DILivingSealMark(diameter: 48)
                .padding(14)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            DiscoverCaption(key: "The centre")
            HStack(spacing: 6) {
                Text(LocalizedStringKey(place.name))
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.white)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(place.addressLines.indices, id: \.self) { index in
                    Text(verbatim: place.addressLines[index])
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.white.opacity(0.88))
        }
        .padding(.trailing, 72)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func pill(_ title: LocalizedStringKey, gold: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(gold ? Color(hex: 0x064B34) : Color.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                Capsule().fill(gold ? AnyShapeStyle(DiscoverStyle.goldButton) : AnyShapeStyle(Color.white.opacity(0.14)))
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(gold ? 0 : 0.3), lineWidth: 1)
            )
    }
}

/// The full Dar-ul-Irfan card, with its map, behind the hero card's name.
private struct DarulIrfanPlacePage: View {
    let place: DarulIrfanPlace

    var body: some View {
        ScrollView {
            DarulIrfanCardView(place: place)
                .padding(DISpacing.md)
                .diResponsiveWidth()
        }
        .diScreenBackground()
        .navigationTitle("Dar-ul-Irfan")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension DarulIrfanPlace {
    /// Directions in Apple Maps, when the place has coordinates.
    var directionsURL: URL? {
        guard let latitude, let longitude else { return nil }
        return URL(string: "https://maps.apple.com/?daddr=\(latitude),\(longitude)")
    }

    /// A tel: link from the phone number's digits.
    var phoneURL: URL? {
        guard let phone else { return nil }
        let allowed = Set("+0123456789")
        let digits = String(phone.filter { allowed.contains($0) })
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    var emailURL: URL? {
        guard let email else { return nil }
        return URL(string: "mailto:\(email)")
    }
}
