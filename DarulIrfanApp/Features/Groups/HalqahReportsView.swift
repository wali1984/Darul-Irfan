import SwiftUI

// A Halqah's own daily and monthly reports, for its admins (owner
// 2026-11-19: "Daily and monthly reporting for app and webpage admins").
// The server answers its Admins and Administrators only and leaves admins'
// test sessions out; every report is read in the phone's time zone.

// MARK: - What the server sends

/// GET /v1/groups/{id}/activity/daily.
struct HalqahDailyActivity: Decodable, Sendable, Equatable {
    var date: String
    var tz: String?
    var summary: MarkazSummary
    /// Each session with who came.
    var sessions: [MarkazSession]

    enum CodingKeys: String, CodingKey { case date, tz, summary, sessions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.markazString(.date) ?? ""
        tz = c.markazString(.tz)
        summary = c.markazObject(MarkazSummary.self, .summary) ?? MarkazSummary()
        sessions = c.markazList(MarkazSession.self, .sessions)
    }
}

/// GET /v1/groups/{id}/activity/monthly.
struct HalqahMonthlyActivity: Decodable, Sendable, Equatable {
    var month: String
    var tz: String?
    var summary: MarkazSummary
    var previous: MarkazPrevious?
    var daily: [MarkazDailyPoint]
    var sessions: [MarkazSession]
    var attendanceByPerson: [MarkazPersonAttendance]

    enum CodingKeys: String, CodingKey { case month, tz, summary, previous, daily, sessions, attendanceByPerson }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        month = c.markazString(.month) ?? ""
        tz = c.markazString(.tz)
        summary = c.markazObject(MarkazSummary.self, .summary) ?? MarkazSummary()
        previous = c.markazObject(MarkazPrevious.self, .previous)
        daily = c.markazList(MarkazDailyPoint.self, .daily)
        sessions = c.markazList(MarkazSession.self, .sessions)
        attendanceByPerson = c.markazList(MarkazPersonAttendance.self, .attendanceByPerson)
    }
}

// MARK: - Days and months

/// The report's day ("2026-11-19") and month ("2026-11"), in the phone's
/// time zone, and moving a day or a month back or forward. Never past today.
enum HalqahReportPeriod {
    static func today(now: Date = Date()) -> String { MarkazDay.string(now) }

    static func thisMonth(now: Date = Date()) -> String { MarkazDay.month(now) }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }

    static func day(_ day: String, moving days: Int) -> String {
        guard let date = MarkazDay.date(day), let moved = calendar.date(byAdding: .day, value: days, to: date) else { return day }
        return MarkazDay.string(moved)
    }

    static func month(_ month: String, moving months: Int) -> String {
        guard let date = MarkazDay.date(month + "-01"),
              let moved = calendar.date(byAdding: .month, value: months, to: date) else { return month }
        return MarkazDay.month(moved)
    }

    /// A later day can be shown: `day` is before today.
    static func canMoveForward(day: String, now: Date = Date()) -> Bool { day < today(now: now) }

    static func canMoveForward(month: String, now: Date = Date()) -> Bool { month < thisMonth(now: now) }
}

// MARK: - The screen

@MainActor
struct HalqahReportsView: View {
    let groupID: String
    let service: MemberGroupService

    private enum Tab: String, CaseIterable, Hashable {
        case daily = "Daily"
        case monthly = "Monthly"
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var tab: Tab = .daily
    @State private var day = HalqahReportPeriod.today()
    @State private var month = HalqahReportPeriod.thisMonth()
    @State private var daily: HalqahDailyActivity?
    @State private var monthly: HalqahMonthlyActivity?
    @State private var loading = false
    @State private var failure: String?
    @State private var generation = 0

    /// What is shown; a change loads it.
    private var asked: String { tab == .daily ? "day:" + day : "month:" + month }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                DISegmentedControl(items: Tab.allCases, title: { LocalizedStringKey($0.rawValue) }, selection: $tab)
                    .accessibilityIdentifier("halqah-reports-tab")
                periodBar
                    .halqahCard()
                if tab == .daily, let daily, daily.date == day {
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    if let failure { MarkazStateCard(failure: failure, loading: loading) { Task { await load() } } }
                    dailyContent(daily)
                } else if tab == .monthly, let monthly, monthly.month == month {
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    if let failure { MarkazStateCard(failure: failure, loading: loading) { Task { await load() } } }
                    monthlyContent(monthly)
                } else {
                    MarkazStateCard(failure: failure, loading: loading || failure == nil) { Task { await load() } }
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }.buttonStyle(DIToolbarButtonStyle())
            }
        }
        .task(id: asked) { await load() }
        .refreshable { await Task { await load() }.value }
    }

    // MARK: Day or month

    @ViewBuilder
    private var periodBar: some View {
        HStack(spacing: DISpacing.sm) {
            if tab == .daily {
                stepButton("chevron.backward", label: "Previous day") { day = HalqahReportPeriod.day(day, moving: -1) }
                Spacer(minLength: 0)
                DatePicker("Day", selection: Binding(
                    get: { MarkazDay.date(day) ?? Date() },
                    set: { day = MarkazDay.string($0) }
                ), in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .tint(DIColor.primary)
                Spacer(minLength: 0)
                stepButton("chevron.forward", label: "Next day") { day = HalqahReportPeriod.day(day, moving: 1) }
                    .disabled(!HalqahReportPeriod.canMoveForward(day: day))
            } else {
                stepButton("chevron.backward", label: "Previous month") { month = HalqahReportPeriod.month(month, moving: -1) }
                Spacer(minLength: 0)
                Text(verbatim: monthTitle(month))
                    .diInterfaceFont(.headline)
                    .foregroundStyle(DIColor.textPrimary)
                Spacer(minLength: 0)
                stepButton("chevron.forward", label: "Next month") { month = HalqahReportPeriod.month(month, moving: 1) }
                    .disabled(!HalqahReportPeriod.canMoveForward(month: month))
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func stepButton(_ icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .diInterfaceFont(.headline)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(DIColor.actionForeground)
        .accessibilityLabel(Text(label))
    }

    private func monthTitle(_ month: String) -> String {
        guard let date = MarkazDay.date(month + "-01") else { return month }
        var components = Locale.Components(locale: locale)
        components.numberingSystem = Locale.NumberingSystem("latn")
        return date.formatted(Date.FormatStyle(locale: Locale(components: components)).month(.wide).year())
    }

    // MARK: Daily

    @ViewBuilder
    private func dailyContent(_ report: HalqahDailyActivity) -> some View {
        MarkazFigureGrid(figures: Self.figures(report.summary, previous: nil))
        if report.sessions.isEmpty {
            DICard {
                Text("No Zikr held on this day.")
                    .diInterfaceFont(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
        ForEach(report.sessions) { session in
            MarkazCard(titleKey: "Halqah Zikr", systemImage: "person.3.fill") {
                MarkazSessionRow(session: Self.withoutHalqah(session), showsChevron: false)
                if !session.attendees.isEmpty {
                    Text("Who came: \(session.attendees.count)")
                        .diInterfaceFont(.footnote, weight: .semibold)
                        .foregroundStyle(DIColor.textMuted)
                    ForEach(Array(session.attendees.enumerated()), id: \.offset) { _, attendee in
                        MarkazAttendeeRow(attendee: attendee)
                        HalqahRowDivider()
                    }
                }
            }
        }
    }

    // MARK: Monthly

    @ViewBuilder
    private func monthlyContent(_ report: HalqahMonthlyActivity) -> some View {
        MarkazFigureGrid(figures: Self.figures(report.summary, previous: report.previous))
        if report.sessions.isEmpty {
            DICard {
                Text("No Zikr held this month.")
                    .diInterfaceFont(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
            }
        } else {
            MarkazCard(titleKey: "Sessions", systemImage: "calendar") {
                ForEach(report.sessions) { session in
                    MarkazSessionRow(session: Self.withoutHalqah(session), showsChevron: false)
                    HalqahRowDivider()
                }
            }
        }
        if !report.attendanceByPerson.isEmpty {
            MarkazCard(titleKey: "Attendance by person", systemImage: "person.text.rectangle") {
                ForEach(report.attendanceByPerson) { person in
                    MarkazRow(title: person.name.isEmpty ? String(localized: "Someone") : person.name,
                              detail: [person.via == "web" ? String(localized: "Website") : String(localized: "App"),
                                       String(localized: "\(person.days) days")].joined(separator: " \u{00b7} "),
                              value: "\(person.sessions)")
                    HalqahRowDivider()
                }
            }
        }
    }

    // MARK: Figures

    /// Sessions, attendance, people, app and website, and minutes; a month
    /// shows its change on the month before.
    nonisolated static func figures(_ summary: MarkazSummary, previous: MarkazPrevious?) -> [MarkazFigure] {
        [
            MarkazFigure(id: "sessions", titleKey: "Sessions", value: "\(summary.sessions)", systemImage: "calendar",
                         change: MarkazText.countChange(summary.sessions, previous?.sessions)),
            MarkazFigure(id: "attendance", titleKey: "Attendance", value: "\(summary.attendance)", systemImage: "person.3.fill",
                         change: MarkazText.countChange(summary.attendance, previous?.attendance)),
            MarkazFigure(id: "unique", titleKey: "Different people", value: "\(summary.uniqueAttendees)", systemImage: "person.crop.circle",
                         change: MarkazText.countChange(summary.uniqueAttendees, previous?.uniqueAttendees)),
            MarkazFigure(id: "app", titleKey: "In the app", value: "\(summary.appAttendance)", systemImage: "iphone"),
            MarkazFigure(id: "web", titleKey: "Website visitors", value: "\(summary.webAttendance)", systemImage: "globe",
                         change: MarkazText.countChange(summary.webAttendance, previous?.webAttendance)),
            MarkazFigure(id: "minutes", titleKey: "Minutes", value: "\(summary.totalMinutes)", systemImage: "clock.fill")
        ]
    }

    /// A session as this Halqah's own list shows it: its name is the page's.
    nonisolated static func withoutHalqah(_ session: MarkazSession) -> MarkazSession {
        var shown = session
        shown.groupName = nil
        return shown
    }

    // MARK: Loading

    private func load() async {
        generation += 1
        let mine = generation
        let tab = tab, day = day, month = month
        loading = true
        defer { if mine == generation { loading = false } }
        do {
            let reports = MarkazService(groups: service)
            if tab == .daily {
                let answer = try await reports.halqahDaily(groupID, date: day)
                guard mine == generation, !Task.isCancelled else { return }
                // The server's day is the one asked for; keep it matched.
                var shown = answer
                if shown.date.isEmpty { shown.date = day }
                daily = shown
            } else {
                let answer = try await reports.halqahMonthly(groupID, month: month)
                guard mine == generation, !Task.isCancelled else { return }
                var shown = answer
                if shown.month.isEmpty { shown.month = month }
                monthly = shown
            }
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            guard mine == generation, !Task.isCancelled else { return }
            failure = MarkazText.loadFailure(error)
        }
    }
}
