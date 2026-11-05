import SwiftUI

// The Markaz's daily and monthly reports: a day's sessions in every Halqah
// with who came, and a month's figures, trend and people. Both share as
// text or as a spreadsheet.

// MARK: - Daily

@MainActor
struct MarkazDailyReportView: View {
    let service: MemberGroupService

    @Environment(\.locale) private var locale
    @State private var day: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var report: MarkazDailyReport?
    @State private var loading = false
    @State private var failure: String?
    @State private var generation = 0
    @State private var shared: MarkazSharedItem?
    @State private var exporting = false
    @State private var exportError: String?

    private var dayText: String { MarkazDay.string(day) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
                    .diInterfaceFont(.subheadline, weight: .semibold)
                    .tint(DIColor.primary)
                    .halqahCard()
                if let report {
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    if let failure {
                        MarkazStateCard(failure: failure, loading: loading) { Task { await load() } }
                    }
                    content(report)
                } else {
                    MarkazStateCard(failure: failure, loading: loading || failure == nil) { Task { await load() } }
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .navigationTitle("Daily report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { shareMenu } }
        .task(id: dayText) { await load() }
        .refreshable { await Task { await load() }.value }
        .sheet(item: $shared) { item in
            ShareSheet(items: item.items).presentationDetents([.medium, .large])
        }
        .alert("Could not complete action", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: { Text(verbatim: exportError ?? "") }
    }

    private var shareMenu: some View {
        Menu {
            Button { if let report { shared = MarkazSharedItem(items: [shareText(report)]) } } label: {
                Label("Share as text", systemImage: "text.alignleft")
            }
            .disabled(report == nil)
            Button { Task { await exportCSV() } } label: {
                Label("Share as a spreadsheet", systemImage: "tablecells")
            }
        } label: {
            if exporting { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
        }
        .accessibilityLabel(Text("Share"))
        .disabled(exporting)
    }

    @ViewBuilder
    private func content(_ report: MarkazDailyReport) -> some View {
        MarkazFigureGrid(figures: dayFigures(report))
        if !report.insights.isEmpty {
            MarkazCard(titleKey: "Insights", systemImage: "lightbulb.fill", tint: DIColor.accent) {
                ForEach(Array(report.insights.enumerated()), id: \.offset) { _, insight in
                    MarkazInsightRow(insight: insight)
                }
            }
        }
        if report.halqahs.isEmpty {
            DICard {
                Text("No sessions on this day.")
                    .diInterfaceFont(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
        ForEach(report.halqahs) { halqah in
            MarkazCard(titleKey: LocalizedStringKey(halqah.name), systemImage: "person.3.fill") {
                if let region = halqah.region, !region.isEmpty {
                    Text(verbatim: region)
                        .diInterfaceFont(.caption, weight: .semibold)
                        .foregroundStyle(HalqahInk.goldText)
                }
                ForEach(halqah.sessions) { session in
                    MarkazDailySessionBlock(session: session)
                }
            }
        }
        if !report.noSession.isEmpty {
            MarkazCard(titleKey: "No session", systemImage: "moon.zzz.fill", tint: DIColor.danger) {
                Text("These Halqahs had a zikr time on this day and no session.")
                    .diInterfaceFont(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                ForEach(report.noSession) { halqah in
                    MarkazRow(title: halqah.name)
                }
            }
        }
    }

    private func dayFigures(_ report: MarkazDailyReport) -> [MarkazFigure] {
        let summary = report.summary
        let before = report.previousDay
        return [
            MarkazFigure(id: "sessions", titleKey: "Sessions", value: "\(summary.sessions)", systemImage: "calendar",
                         change: MarkazText.change(Double(summary.sessions), before?.sessions.map { Double($0) })),
            MarkazFigure(id: "attendance", titleKey: "Attendance", value: "\(summary.attendance)", systemImage: "person.3.fill",
                         change: MarkazText.change(Double(summary.attendance), before?.attendance.map { Double($0) })),
            MarkazFigure(id: "unique", titleKey: "Different people", value: "\(summary.uniqueAttendees)", systemImage: "person.crop.circle"),
            MarkazFigure(id: "web", titleKey: "Website visitors", value: "\(summary.webAttendance)", systemImage: "globe"),
            MarkazFigure(id: "length", titleKey: "Average length (minutes)", value: MarkazText.decimal(summary.averageMinutes), systemImage: "clock.fill"),
            MarkazFigure(id: "active", titleKey: "Active Halqahs", value: "\(summary.activeHalqahs) / \(summary.totalHalqahs)",
                         systemImage: "dot.radiowaves.left.and.right")
        ]
    }

    private func shareText(_ report: MarkazDailyReport) -> String {
        var lines: [String] = []
        lines.append(String(localized: "Daily report") + ": " + MarkazText.dayTitle(report.date.isEmpty ? dayText : report.date, locale: locale))
        lines.append(String(localized: "Sessions") + ": \(report.summary.sessions)")
        lines.append(String(localized: "Attendance") + ": \(report.summary.attendance)")
        lines.append(String(localized: "Different people") + ": \(report.summary.uniqueAttendees)")
        for halqah in report.halqahs {
            lines.append("")
            lines.append(halqah.name)
            for session in halqah.sessions {
                var line = "- " + (session.title ?? String(localized: "Halqah Zikr"))
                if let start = session.startedAt { line += " (" + GroupInvitationDate.clock(start, locale: locale) + ")" }
                line += ": \(session.attendance)"
                lines.append(line)
            }
        }
        if !report.noSession.isEmpty {
            lines.append("")
            lines.append(String(localized: "No session") + ": " + report.noSession.map(\.name).joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    private func load() async {
        generation += 1
        let mine = generation
        loading = true
        defer { if mine == generation { loading = false } }
        do {
            let answer = try await MarkazService(groups: service).dailyReport(date: dayText)
            guard mine == generation, !Task.isCancelled else { return }
            report = answer
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            guard mine == generation, !Task.isCancelled else { return }
            failure = MarkazText.loadFailure(error)
        }
    }

    private func exportCSV() async {
        guard !exporting else { return }
        exporting = true
        defer { exporting = false }
        do {
            let url = try await MarkazService(groups: service).export(type: "attendance", from: dayText, to: dayText)
            shared = MarkazSharedItem(items: [url])
        } catch is CancellationError {
            return
        } catch {
            exportError = MemberGroupError.actionDescription(for: error)
        }
    }
}

/// One session of a daily report, with who came folded beneath it.
private struct MarkazDailySessionBlock: View {
    let session: MarkazSession
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MarkazSessionRow(session: session, showsChevron: false)
            if !session.attendees.isEmpty {
                DisclosureGroup(isExpanded: $expanded) {
                    VStack(spacing: 0) {
                        ForEach(Array(session.attendees.enumerated()), id: \.offset) { _, attendee in
                            MarkazAttendeeRow(attendee: attendee)
                            HalqahRowDivider()
                        }
                    }
                } label: {
                    Text("Who came: \(session.attendees.count)")
                        .diInterfaceFont(.footnote, weight: .semibold)
                        .foregroundStyle(DIColor.actionForeground)
                }
                .tint(DIColor.primary)
            }
        }
        .padding(DISpacing.sm)
        .background(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous).fill(DIColor.sandstone.opacity(0.45)))
    }
}

// MARK: - Monthly

@MainActor
struct MarkazMonthlyReportView: View {
    let service: MemberGroupService

    @Environment(\.locale) private var locale
    @State private var month: String = MarkazMonthlyReportView.lastMonth()
    @State private var report: MarkazMonthlyReport?
    @State private var loading = false
    @State private var failure: String?
    @State private var generation = 0
    @State private var showsEveryone = false
    @State private var shared: MarkazSharedItem?
    @State private var exporting = false
    @State private var exportError: String?

    /// The last 24 months, newest first ("2026-10").
    private nonisolated static func months(now: Date = Date()) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return (0..<24).compactMap { back in
            calendar.date(byAdding: .month, value: -back, to: start).map { MarkazDay.month($0) }
        }
    }

    nonisolated static func lastMonth() -> String {
        let list = months()
        return list.count > 1 ? list[1] : (list.first ?? "")
    }

    private func monthTitle(_ month: String) -> String {
        guard let date = MarkazDay.date(month + "-01") else { return month }
        var components = Locale.Components(locale: locale)
        components.numberingSystem = Locale.NumberingSystem("latn")
        return date.formatted(Date.FormatStyle(locale: Locale(components: components)).month(.wide).year())
    }

    /// The month's first and last day.
    private var monthRange: (from: String, to: String) {
        guard let start = MarkazDay.date(month + "-01") else { return (month, month) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let next = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        let end = calendar.date(byAdding: .day, value: -1, to: next) ?? start
        return (MarkazDay.string(start), MarkazDay.string(end))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                Picker(selection: $month) {
                    ForEach(Self.months(), id: \.self) { value in
                        Text(verbatim: monthTitle(value)).tag(value)
                    }
                } label: {
                    Text("Month")
                }
                .pickerStyle(.menu)
                .tint(DIColor.actionForeground)
                .halqahCard()
                if let report {
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    if let failure {
                        MarkazStateCard(failure: failure, loading: loading) { Task { await load() } }
                    }
                    content(report)
                } else {
                    MarkazStateCard(failure: failure, loading: loading || failure == nil) { Task { await load() } }
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .navigationTitle("Monthly report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { shareMenu } }
        .task(id: month) { await load() }
        .refreshable { await Task { await load() }.value }
        .sheet(item: $shared) { item in
            ShareSheet(items: item.items).presentationDetents([.medium, .large])
        }
        .alert("Could not complete action", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: { Text(verbatim: exportError ?? "") }
    }

    private var shareMenu: some View {
        Menu {
            Button { if let report { shared = MarkazSharedItem(items: [shareText(report)]) } } label: {
                Label("Share as text", systemImage: "text.alignleft")
            }
            .disabled(report == nil)
            Button { Task { await exportCSV("people") } } label: {
                Label("People (spreadsheet)", systemImage: "tablecells")
            }
            Button { Task { await exportCSV("halqahs") } } label: {
                Label("Halqahs (spreadsheet)", systemImage: "tablecells")
            }
            Button { Task { await exportCSV("sessions") } } label: {
                Label("Sessions (spreadsheet)", systemImage: "tablecells")
            }
        } label: {
            if exporting { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
        }
        .accessibilityLabel(Text("Share"))
        .disabled(exporting)
    }

    @ViewBuilder
    private func content(_ report: MarkazMonthlyReport) -> some View {
        MarkazFigureGrid(figures: report.summary.figures(previous: report.previous))
        MarkazCard(titleKey: "Attendance trend", systemImage: "chart.line.uptrend.xyaxis") {
            MarkazTrendChart(daily: report.daily)
        }
        if !report.insights.isEmpty {
            MarkazCard(titleKey: "Insights", systemImage: "lightbulb.fill", tint: DIColor.accent) {
                ForEach(Array(report.insights.enumerated()), id: \.offset) { _, insight in
                    MarkazInsightRow(insight: insight)
                }
            }
        }
        if !report.halqahs.isEmpty {
            MarkazCard(titleKey: "Halqahs", systemImage: "tablecells", tint: DIColor.accent) {
                ForEach(report.halqahs.sorted { $0.attendance > $1.attendance }) { halqah in
                    HStack(spacing: DISpacing.sm) {
                        MarkazStatusDot(status: halqah.status)
                        MarkazRow(title: halqah.name,
                                  detail: String(localized: "\(halqah.sessions) sessions") + " \u{00b7} "
                                    + String(localized: "Average \(MarkazText.decimal(halqah.averageAttendance))"),
                                  value: "\(halqah.attendance)")
                        if let change = halqah.change { MarkazChangeBadge(change: change) }
                    }
                    HalqahRowDivider()
                }
            }
        }
        if !report.attendanceByPerson.isEmpty {
            MarkazCard(titleKey: "Attendance by person", systemImage: "person.text.rectangle") {
                let shown = showsEveryone ? report.attendanceByPerson : Array(report.attendanceByPerson.prefix(30))
                ForEach(shown) { person in
                    personRow(person)
                    HalqahRowDivider()
                }
                if !showsEveryone && report.attendanceByPerson.count > 30 {
                    Button("Show all \(report.attendanceByPerson.count)") { showsEveryone = true }
                        .buttonStyle(DICompactButtonStyle())
                }
            }
        }
        if !report.newMembers.isEmpty {
            MarkazCard(titleKey: "New members", systemImage: "person.badge.plus") {
                ForEach(Array(report.newMembers.enumerated()), id: \.offset) { _, member in
                    MarkazRow(title: member.name,
                              detail: member.halqah,
                              value: member.joinedAt.map { GroupInvitationDate.text($0, locale: locale) })
                }
            }
        }
        if !report.needsCare.isEmpty {
            MarkazCard(titleKey: "Needs care", systemImage: "heart.text.square.fill", tint: DIColor.danger) {
                ForEach(report.needsCare) { person in
                    if let memberID = person.memberID, !memberID.isEmpty {
                        NavigationLink {
                            MarkazPersonView(service: service, memberID: memberID, name: person.name)
                        } label: {
                            MarkazRow(title: person.name, detail: careLine(person), showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        MarkazRow(title: person.name, detail: careLine(person))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func personRow(_ person: MarkazPersonAttendance) -> some View {
        let detail = ([person.via == "web" ? String(localized: "Website") : String(localized: "App"),
                       String(localized: "\(person.days) days")] + person.halqahs).joined(separator: " \u{00b7} ")
        if let memberID = person.memberID, !memberID.isEmpty {
            NavigationLink {
                MarkazPersonView(service: service, memberID: memberID, name: person.name)
            } label: {
                MarkazRow(title: person.name, detail: detail, value: "\(person.sessions)", showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            MarkazRow(title: person.name, detail: detail, value: "\(person.sessions)")
        }
    }

    private func careLine(_ person: MarkazNeedsCare) -> String {
        var parts: [String] = []
        if let halqah = person.halqah, !halqah.isEmpty { parts.append(halqah) }
        if let seen = person.lastSeenAt {
            parts.append(String(localized: "Last came \(GroupInvitationDate.text(seen, locale: locale))"))
        }
        return parts.joined(separator: " \u{00b7} ")
    }

    private func shareText(_ report: MarkazMonthlyReport) -> String {
        let summary = report.summary
        var lines: [String] = [String(localized: "Monthly report") + ": " + monthTitle(report.month.isEmpty ? month : report.month)]
        lines.append(String(localized: "Sessions") + ": \(summary.sessions)")
        lines.append(String(localized: "Attendance") + ": \(summary.attendance)")
        lines.append(String(localized: "Different people") + ": \(summary.uniqueAttendees)")
        lines.append(String(localized: "Average per session") + ": " + MarkazText.decimal(summary.averageAttendance))
        lines.append(String(localized: "New members") + ": \(summary.newMembers)")
        if !report.halqahs.isEmpty {
            lines.append("")
            for halqah in report.halqahs.sorted(by: { $0.attendance > $1.attendance }) {
                lines.append("- \(halqah.name): \(halqah.sessions) / \(halqah.attendance)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func load() async {
        generation += 1
        let mine = generation
        loading = true
        defer { if mine == generation { loading = false } }
        do {
            let answer = try await MarkazService(groups: service).monthlyReport(month: month)
            guard mine == generation, !Task.isCancelled else { return }
            report = answer
            failure = nil
            showsEveryone = false
        } catch is CancellationError {
            return
        } catch {
            guard mine == generation, !Task.isCancelled else { return }
            failure = MarkazText.loadFailure(error)
        }
    }

    private func exportCSV(_ type: String) async {
        guard !exporting else { return }
        exporting = true
        defer { exporting = false }
        let range = monthRange
        do {
            let url = try await MarkazService(groups: service).export(type: type, from: range.from, to: range.to)
            shared = MarkazSharedItem(items: [url])
        } catch is CancellationError {
            return
        } catch {
            exportError = MemberGroupError.actionDescription(for: error)
        }
    }
}

// MARK: - From the digest

/// The daily or monthly report the officers' digest notification opens.
/// Anyone else, or a phone no longer signed in, is told and sent nowhere.
@MainActor
struct MarkazReportLinkView: View {
    let monthly: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var service = MemberGroupService()
    @State private var access: MarkazAccess?

    var body: some View {
        Group {
            if let access {
                if access.canReport {
                    if monthly {
                        MarkazMonthlyReportView(service: service)
                    } else {
                        MarkazDailyReportView(service: service)
                    }
                } else {
                    DIEmptyState(systemImage: "lock.fill",
                                 titleKey: "Reports are for the officers of the Silsila Markaz.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .diScreenBackground()
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .diScreenBackground()
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
                    .buttonStyle(DICompactButtonStyle())
            }
        }
        .task { access = await MarkazAccessCache.access(using: service) }
    }
}
