import SwiftUI

/// Reports & analytics: every Halqah's sessions and attendance over a period,
/// for the Silsila Markaz's officers. The period, the Halqahs it covers and
/// the kind of session are chosen at the top; everything under them follows.
@MainActor
struct MarkazAnalyticsView: View {
    let service: MemberGroupService
    let access: MarkazAccess

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @State private var period: MarkazPeriod = .days30
    @State private var scope = "all"
    @State private var kind: MarkazKind = .all
    @State private var analytics: MarkazAnalytics?
    @State private var loading = false
    @State private var failure: String?
    @State private var generation = 0
    /// Regions and Halqahs to narrow to, from the last answer for all.
    @State private var regionOptions: [MarkazScopeOption] = []
    @State private var halqahOptions: [MarkazScopeOption] = []
    @State private var showsAllSessions = false
    @State private var route: Route?
    @State private var exporting = false
    @State private var shared: MarkazSharedItem?
    @State private var exportError: String?

    enum Route: String, Hashable, Identifiable {
        case daily, monthly, computers
        var id: String { rawValue }
    }

    private struct LoadKey: Equatable {
        let period: MarkazPeriod
        let scope: String
        let kind: MarkazKind
    }

    private var markaz: MarkazService { MarkazService(groups: service) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                header
                    .diAppear()
                controls
                if let analytics {
                    if loading {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    if let failure {
                        MarkazStateCard(failure: failure, loading: loading) { Task { await load() } }
                    }
                    report(analytics)
                } else {
                    MarkazStateCard(failure: failure, loading: loading || failure == nil) { Task { await load() } }
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .navigationTitle("Reports & analytics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DIColor.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { toolbarMenu } }
        .task(id: LoadKey(period: period, scope: scope, kind: kind)) { await load() }
        .refreshable { await Task { await load() }.value }
        .navigationDestination(item: $route) { route in
            switch route {
            case .daily: MarkazDailyReportView(service: service)
            case .monthly: MarkazMonthlyReportView(service: service)
            case .computers: MarkazComputerSignInView(service: service)
            }
        }
        .sheet(item: $shared) { item in
            ShareSheet(items: item.items)
                .presentationDetents([.medium, .large])
        }
        .alert("Could not complete action", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: { Text(verbatim: exportError ?? "") }
    }

    // MARK: Top

    private var header: some View {
        HalqahGlassHeader {
            VStack(alignment: .leading, spacing: DISpacing.xs) {
                Label {
                    Text("Silsila Markaz")
                } icon: {
                    Image(systemName: "chart.xyaxis.line")
                }
                .diInterfaceFont(.caption, weight: .semibold)
                .foregroundStyle(DIColor.goldGlow)
                Text(verbatim: scopeName)
                    .diInterfaceFont(.title2, weight: .semibold, design: .serif)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let range = analytics?.range, !range.from.isEmpty {
                    Text(verbatim: MarkazText.dayTitle(range.from, locale: locale) + " \u{2013} " + MarkazText.dayTitle(range.to, locale: locale))
                        .diInterfaceFont(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.82))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var scopeName: String {
        if scope == "all" { return String(localized: "All Halqahs") }
        if let option = (regionOptions + halqahOptions).first(where: { $0.id == scope }) { return option.name }
        return analytics?.scope?.name ?? String(localized: "All Halqahs")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DIChipTabs(items: MarkazPeriod.allCases, title: { $0.title }, selection: $period)
                .padding(.horizontal, -DISpacing.md)
            HStack(spacing: DISpacing.sm) {
                scopeMenu
                Spacer(minLength: 0)
            }
            DISegmentedControl(items: MarkazKind.allCases, title: { $0.title }, selection: $kind)
        }
    }

    private var scopeMenu: some View {
        Menu {
            Picker(selection: $scope) {
                Text("All Halqahs").tag("all")
                if !regionOptions.isEmpty {
                    Section("Regions") {
                        ForEach(regionOptions) { option in Text(verbatim: option.name).tag(option.id) }
                    }
                }
                if !halqahOptions.isEmpty {
                    Section("Halqahs") {
                        ForEach(halqahOptions) { option in Text(verbatim: option.name).tag(option.id) }
                    }
                }
            } label: {
                Text("Halqahs")
            }
        } label: {
            HStack(spacing: DISpacing.xs) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .accessibilityHidden(true)
                Text(verbatim: scopeName)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .diInterfaceFont(.caption2, weight: .bold)
                    .accessibilityHidden(true)
            }
            .diInterfaceFont(.subheadline, weight: .semibold)
            .foregroundStyle(DIColor.actionForeground)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(DIColor.sandstone.opacity(0.55)))
            .overlay(Capsule().stroke(DIColor.border, lineWidth: 1))
        }
        .accessibilityLabel(Text("Which Halqahs"))
        .accessibilityValue(Text(verbatim: scopeName))
    }

    private var toolbarMenu: some View {
        Menu {
            Section("Share as a spreadsheet") {
                Button { Task { await export("sessions") } } label: { Label("Sessions", systemImage: "calendar") }
                Button { Task { await export("attendance") } } label: { Label("Attendance", systemImage: "person.3") }
                Button { Task { await export("halqahs") } } label: { Label("Halqahs", systemImage: "building.2") }
                Button { Task { await export("people") } } label: { Label("People", systemImage: "person.crop.rectangle.stack") }
            }
            Section {
                Button { route = .daily } label: { Label("Daily report", systemImage: "sun.max") }
                Button { route = .monthly } label: { Label("Monthly report", systemImage: "calendar.badge.clock") }
                Button { route = .computers } label: { Label("Sign in on a computer", systemImage: "desktopcomputer") }
            }
        } label: {
            if exporting {
                ProgressView()
            } else {
                Image(systemName: "ellipsis.circle")
            }
        }
        .accessibilityLabel(Text("Share and more reports"))
        .disabled(exporting)
    }

    // MARK: Report

    @ViewBuilder
    private func report(_ analytics: MarkazAnalytics) -> some View {
        MarkazFigureGrid(figures: analytics.summary.figures(previous: analytics.previous))
            .diAppear(delay: 0.04)
        MarkazCard(titleKey: "Attendance trend", systemImage: "chart.line.uptrend.xyaxis") {
            MarkazTrendChart(daily: analytics.daily)
        }
        MarkazCard(titleKey: "When people come", systemImage: "square.grid.3x3.fill") {
            MarkazHeatmap(cells: analytics.weekdayHour)
        }
        if !analytics.halqahs.isEmpty {
            MarkazCard(titleKey: "Halqahs", systemImage: "chart.bar.xaxis", tint: DIColor.accent) {
                MarkazHalqahBars(halqahs: analytics.halqahs)
                halqahRows(analytics.halqahs)
            }
        }
        MarkazCard(titleKey: "App or website", systemImage: "iphone.and.arrow.forward") {
            MarkazViaDonut(app: analytics.summary.appAttendance, web: analytics.summary.webAttendance)
        }
        if !analytics.insights.isEmpty {
            MarkazCard(titleKey: "Insights", systemImage: "lightbulb.fill", tint: DIColor.accent) {
                ForEach(Array(analytics.insights.enumerated()), id: \.offset) { _, insight in
                    if let halqahID = insight.halqahID, !halqahID.isEmpty {
                        Button { scope = "halqah:" + halqahID } label: { MarkazInsightRow(insight: insight) }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("Shows this Halqah only."))
                    } else {
                        MarkazInsightRow(insight: insight)
                    }
                }
            }
        }
        if !analytics.regulars.isEmpty {
            MarkazCard(titleKey: "Regulars", systemImage: "star.fill", tint: DIColor.accent) {
                ForEach(analytics.regulars) { regular in
                    personLink(memberID: regular.memberID, name: regular.name) {
                        MarkazRow(title: regular.name,
                                  detail: regular.halqahs.joined(separator: " \u{00b7} "),
                                  value: String(localized: "\(regular.sessions) sessions"),
                                  showsChevron: regular.memberID != nil)
                    }
                }
            }
        }
        if !analytics.needsCare.isEmpty {
            MarkazCard(titleKey: "Needs care", systemImage: "heart.text.square.fill", tint: DIColor.danger) {
                Text("They came often before, and not in the last three weeks.")
                    .diInterfaceFont(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                ForEach(analytics.needsCare) { person in
                    personLink(memberID: person.memberID, name: person.name) {
                        MarkazRow(title: person.name,
                                  detail: needsCareLine(person),
                                  value: nil,
                                  showsChevron: person.memberID != nil)
                    }
                }
            }
        }
        MarkazCard(titleKey: "Sessions", systemImage: "list.bullet.rectangle") {
            if analytics.sessions.isEmpty {
                Text("No sessions in this period.")
                    .diInterfaceFont(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
            }
            let shown = showsAllSessions ? analytics.sessions : Array(analytics.sessions.prefix(25))
            ForEach(shown) { session in
                NavigationLink {
                    MarkazSessionView(service: service, session: session)
                } label: {
                    MarkazSessionRow(session: session)
                }
                .buttonStyle(.plain)
            }
            if !showsAllSessions && analytics.sessions.count > 25 {
                Button("Show all \(analytics.sessions.count)") { showsAllSessions = true }
                    .buttonStyle(DICompactButtonStyle())
            }
        }
    }

    private func halqahRows(_ halqahs: [MarkazHalqahStat]) -> some View {
        VStack(spacing: 0) {
            ForEach(halqahs.sorted { $0.attendance > $1.attendance }) { halqah in
                Button {
                    scope = "halqah:" + halqah.id
                } label: {
                    HStack(spacing: DISpacing.sm) {
                        MarkazStatusDot(status: halqah.status)
                        MarkazRow(title: halqah.name, detail: halqahLine(halqah), value: "\(halqah.attendance)")
                        if let change = halqah.change {
                            MarkazChangeBadge(change: change)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows this Halqah only."))
                HalqahRowDivider()
            }
        }
    }

    private func halqahLine(_ halqah: MarkazHalqahStat) -> String {
        var parts = [String(localized: "\(halqah.sessions) sessions"),
                     String(localized: "Average \(MarkazText.decimal(halqah.averageAttendance))")]
        if let rate = halqah.attendanceRate {
            let share = "\(Int((rate * 100).rounded()))%"
            parts.append(String(localized: "Members who came: \(share)"))
        }
        if let last = halqah.lastSessionAt {
            parts.append(String(localized: "Last: \(GroupInvitationDate.text(last, locale: locale))"))
        }
        return parts.joined(separator: " \u{00b7} ")
    }

    private func needsCareLine(_ person: MarkazNeedsCare) -> String {
        var parts: [String] = []
        if let halqah = person.halqah, !halqah.isEmpty { parts.append(halqah) }
        if let seen = person.lastSeenAt {
            parts.append(String(localized: "Last came \(GroupInvitationDate.text(seen, locale: locale))"))
        }
        parts.append(String(localized: "\(person.sessionsBefore) sessions before"))
        return parts.joined(separator: " \u{00b7} ")
    }

    /// A person's row opens their history when the report says who they are.
    @ViewBuilder
    private func personLink<RowLabel: View>(memberID: String?, name: String, @ViewBuilder label: () -> RowLabel) -> some View {
        if let memberID, !memberID.isEmpty {
            NavigationLink {
                MarkazPersonView(service: service, memberID: memberID, name: name)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            label()
        }
    }

    // MARK: Loading

    private func load() async {
        generation += 1
        let mine = generation
        loading = true
        defer { if mine == generation { loading = false } }
        let range = period.range()
        do {
            let answer = try await markaz.analytics(from: range.from, to: range.to, scope: scope, kind: kind.rawValue)
            guard mine == generation, !Task.isCancelled else { return }
            analytics = answer
            failure = nil
            showsAllSessions = false
            if scope == "all" { rememberScopes(answer) }
        } catch is CancellationError {
            return
        } catch {
            guard mine == generation, !Task.isCancelled else { return }
            failure = MarkazText.loadFailure(error)
        }
    }

    private func rememberScopes(_ answer: MarkazAnalytics) {
        let regions = answer.regions.map(\.name).filter { !$0.isEmpty }
        regionOptions = regions.map { MarkazScopeOption(id: "region:" + $0, name: $0) }
        halqahOptions = answer.halqahs
            .filter { !$0.id.isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { MarkazScopeOption(id: "halqah:" + $0.id, name: $0.name) }
    }

    private func export(_ type: String) async {
        guard !exporting else { return }
        exporting = true
        defer { exporting = false }
        let range = period.range()
        do {
            let url = try await markaz.export(type: type, from: range.from, to: range.to, scope: scope)
            shared = MarkazSharedItem(items: [url])
        } catch is CancellationError {
            return
        } catch {
            exportError = MemberGroupError.actionDescription(for: error)
        }
    }
}

// MARK: - Session

/// One session: who came, from where and for how long, the stages called,
/// and the dua requests sent.
@MainActor
struct MarkazSessionView: View {
    let service: MemberGroupService
    let session: MarkazSession

    @Environment(\.locale) private var locale
    @State private var detail: MarkazSessionDetail?
    @State private var loading = false
    @State private var failure: String?

    private var shown: MarkazSession { detail?.session ?? session }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                HalqahGlassHeader {
                    VStack(alignment: .leading, spacing: DISpacing.xs) {
                        if let group = shown.groupName, !group.isEmpty {
                            Text(verbatim: group)
                                .diInterfaceFont(.caption, weight: .semibold)
                                .foregroundStyle(DIColor.goldGlow)
                        }
                        Text(verbatim: title)
                            .diInterfaceFont(.title2, weight: .semibold, design: .serif)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if let start = shown.startedAt {
                            Text(verbatim: GroupInvitationDate.text(start, locale: locale, includesTime: true))
                                .diInterfaceFont(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.82))
                        }
                        if let by = shown.startedBy, !by.isEmpty {
                            Text("Started by \(by)")
                                .diInterfaceFont(.footnote)
                                .foregroundStyle(Color.white.opacity(0.82))
                        } else if shown.automated {
                            Text("Started by itself")
                                .diInterfaceFont(.footnote)
                                .foregroundStyle(Color.white.opacity(0.82))
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                MarkazFigureGrid(figures: figures)
                MarkazStateCard(failure: failure, loading: loading && detail == nil) { Task { await load() } }
                if let detail {
                    if !detail.stages.isEmpty {
                        MarkazCard(titleKey: "Stages called", systemImage: "list.number", tint: DIColor.accent) {
                            ForEach(Array(detail.stages.enumerated()), id: \.offset) { _, stage in
                                MarkazRow(title: stage.title,
                                          value: stage.at.map { GroupInvitationDate.clock($0, locale: locale) })
                            }
                        }
                    }
                    MarkazCard(titleKey: "Who came", systemImage: "person.3.fill") {
                        if detail.attendees.isEmpty {
                            Text("No one was recorded in this session.")
                                .diInterfaceFont(.subheadline)
                                .foregroundStyle(DIColor.textMuted)
                        }
                        ForEach(Array(detail.attendees.enumerated()), id: \.offset) { _, attendee in
                            MarkazAttendeeRow(attendee: attendee)
                            HalqahRowDivider()
                        }
                    }
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await Task { await load() }.value }
    }

    private var title: String {
        if let title = shown.title, !title.isEmpty { return title }
        return shown.isMeeting ? String(localized: "Group meeting") : String(localized: "Halqah Zikr")
    }

    private var figures: [MarkazFigure] {
        var list = [
            MarkazFigure(id: "attendance", titleKey: "Attendance", value: "\(shown.attendance)", systemImage: "person.3.fill"),
            MarkazFigure(id: "minutes", titleKey: "Minutes", value: "\(shown.minutes)", systemImage: "clock.fill")
        ]
        if let app = shown.app {
            list.append(MarkazFigure(id: "app", titleKey: "In the app", value: "\(app)", systemImage: "iphone"))
        }
        if let web = shown.web {
            list.append(MarkazFigure(id: "web", titleKey: "On the website", value: "\(web)", systemImage: "globe"))
        }
        if let detail {
            list.append(MarkazFigure(id: "duas", titleKey: "Dua requests", value: "\(detail.duaRequests)", systemImage: "hands.sparkles"))
        }
        return list
    }

    private func load() async {
        guard !loading, !session.id.isEmpty else { return }
        loading = true
        defer { loading = false }
        do {
            detail = try await MarkazService(groups: service).session(session.id)
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { failure = MarkazText.loadFailure(error) }
        }
    }
}

// MARK: - Person

/// One person's coming: their Halqahs, how often, and each session.
@MainActor
struct MarkazPersonView: View {
    let service: MemberGroupService
    let memberID: String
    let name: String

    @Environment(\.locale) private var locale
    @State private var person: MarkazPerson?
    @State private var loading = false
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                HalqahGlassHeader {
                    VStack(alignment: .leading, spacing: DISpacing.xs) {
                        Text(verbatim: person?.name.isEmpty == false ? (person?.name ?? name) : name)
                            .diInterfaceFont(.title2, weight: .semibold, design: .serif)
                            .foregroundStyle(.white)
                            .accessibilityAddTraits(.isHeader)
                        if let email = person?.email, !email.isEmpty {
                            Text(verbatim: email)
                                .diInterfaceFont(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.82))
                                .textSelection(.enabled)
                        }
                        if let halqahs = person?.halqahs, !halqahs.isEmpty {
                            Text(verbatim: halqahs.map(\.name).joined(separator: " \u{00b7} "))
                                .diInterfaceFont(.footnote)
                                .foregroundStyle(DIColor.goldGlow)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                MarkazStateCard(failure: failure, loading: loading && person == nil) { Task { await load() } }
                if let person {
                    MarkazFigureGrid(figures: [
                        MarkazFigure(id: "sessions", titleKey: "Sessions", value: "\(person.sessions)", systemImage: "calendar"),
                        MarkazFigure(id: "90", titleKey: "In the last 90 days", value: "\(person.last90Days)", systemImage: "chart.bar.fill"),
                        MarkazFigure(id: "streak", titleKey: "Days in a row", value: "\(person.currentStreakDays)", systemImage: "flame.fill")
                    ])
                    MarkazCard(titleKey: "Seen", systemImage: "eye.fill") {
                        if let first = person.firstSeenAt {
                            MarkazRow(title: String(localized: "First came"), value: GroupInvitationDate.text(first, locale: locale))
                        }
                        if let last = person.lastSeenAt {
                            MarkazRow(title: String(localized: "Last came"), value: GroupInvitationDate.text(last, locale: locale))
                        }
                    }
                    MarkazCard(titleKey: "History", systemImage: "clock.arrow.circlepath") {
                        if person.history.isEmpty {
                            Text("No sessions yet.")
                                .diInterfaceFont(.subheadline)
                                .foregroundStyle(DIColor.textMuted)
                        }
                        ForEach(Array(person.history.enumerated()), id: \.offset) { _, entry in
                            MarkazRow(title: entry.title ?? String(localized: "Halqah Zikr"),
                                      detail: historyLine(entry),
                                      value: entry.minutes.map { String(localized: "\($0) min") })
                            HalqahRowDivider()
                        }
                    }
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .navigationTitle(Text(verbatim: name))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await Task { await load() }.value }
    }

    private func historyLine(_ entry: MarkazHistoryEntry) -> String {
        var parts: [String] = []
        if let moment = entry.moment {
            parts.append(GroupInvitationDate.text(moment, locale: locale, includesTime: entry.date.count > 10))
        } else if !entry.date.isEmpty {
            parts.append(entry.date)
        }
        if let group = entry.groupName, !group.isEmpty { parts.append(group) }
        return parts.joined(separator: " \u{00b7} ")
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            person = try await MarkazService(groups: service).person(memberID)
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { failure = MarkazText.loadFailure(error) }
        }
    }
}
