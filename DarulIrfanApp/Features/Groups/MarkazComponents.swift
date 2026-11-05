import Charts
import SwiftUI

// The Markaz reports' shared pieces: the two cards that open them, the
// period and kind choices, the figure tiles with their change on the period
// before, the charts (Swift Charts, emerald and gold), and the rows for
// insights, people and sessions. Every chart is one VoiceOver element that
// says what it shows in a sentence.

// MARK: - Entry cards

/// Reports & analytics and Organisation, side by side: on the Super admin's
/// dashboard and at the top of the Silsila Markaz's admin section, for the
/// Markaz's officers only.
@MainActor
struct MarkazEntryCards: View {
    let service: MemberGroupService
    let access: MarkazAccess

    var body: some View {
        HalqahTilePair {
            NavigationLink {
                MarkazAnalyticsView(service: service, access: access)
            } label: {
                HalqahTileLabel(
                    titleKey: "Reports & analytics",
                    subtitle: Text("Sessions, attendance and trends"),
                    systemImage: "chart.xyaxis.line",
                    tint: DIColor.accent,
                    showsChevron: true
                )
            }
            .buttonStyle(HalqahTileButtonStyle())
            .halqahTileAccessibility(
                titleKey: "Reports & analytics",
                value: Text("Sessions, attendance and trends"),
                hintKey: "Opens the reports of every Halqah."
            )
        } trailing: {
            NavigationLink {
                MarkazOrganisationView(service: service, access: access)
            } label: {
                HalqahTileLabel(
                    titleKey: "Organisation",
                    subtitle: Text("Regions, Halqahs and their admins"),
                    systemImage: "building.columns.fill",
                    showsChevron: true
                )
            }
            .buttonStyle(HalqahTileButtonStyle())
            .halqahTileAccessibility(
                titleKey: "Organisation",
                value: Text("Regions, Halqahs and their admins"),
                hintKey: "Opens the regions and Halqahs of the Silsila."
            )
        }
    }
}

// MARK: - Choices

/// The periods a report covers.
enum MarkazPeriod: String, CaseIterable, Hashable {
    case days7, days30, days90, months12, thisMonth, lastMonth

    var title: LocalizedStringKey {
        switch self {
        case .days7: "7 days"
        case .days30: "30 days"
        case .days90: "90 days"
        case .months12: "12 months"
        case .thisMonth: "This month"
        case .lastMonth: "Last month"
        }
    }

    /// The first and last day, both included, in the phone's calendar.
    func range(now: Date = Date()) -> (from: String, to: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let today = calendar.startOfDay(for: now)
        func back(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: today) ?? today }
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        switch self {
        case .days7: return (MarkazDay.string(back(6)), MarkazDay.string(today))
        case .days30: return (MarkazDay.string(back(29)), MarkazDay.string(today))
        case .days90: return (MarkazDay.string(back(89)), MarkazDay.string(today))
        case .months12: return (MarkazDay.string(back(364)), MarkazDay.string(today))
        case .thisMonth: return (MarkazDay.string(monthStart), MarkazDay.string(today))
        case .lastMonth:
            let start = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
            let end = calendar.date(byAdding: .day, value: -1, to: monthStart) ?? monthStart
            return (MarkazDay.string(start), MarkazDay.string(end))
        }
    }
}

/// Zikr, meetings, or both.
enum MarkazKind: String, CaseIterable, Hashable {
    case all, zikr, meeting

    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .zikr: "Zikr"
        case .meeting: "Meetings"
        }
    }
}

/// A scope a report can be narrowed to.
struct MarkazScopeOption: Identifiable, Hashable {
    /// "all", "region:<name>" or "halqah:<id>".
    let id: String
    let name: String
}

// MARK: - Words

enum MarkazText {
    /// What a screen says when a report could not be loaded.
    static func loadFailure(_ error: Error) -> String {
        if let groupError = error as? MemberGroupError, case .server(let message) = groupError {
            if message == "Markaz access required" {
                return String(localized: "Reports are for the officers of the Silsila Markaz.")
            }
            return message
        }
        if let groupError = error as? MemberGroupError, case .notSignedIn = groupError {
            return groupError.localizedDescription
        }
        return String(localized: "The report could not be loaded. Check your connection and try again.")
    }

    /// A change as a whole percentage ("+13%", "-5%"), Western digits.
    static func percent(_ change: Double) -> String {
        let value = Int((change * 100).rounded())
        return value > 0 ? "+\(value)%" : "\(value)%"
    }

    /// One decimal at most ("14.9"), Western digits.
    static func decimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded))" }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }

    /// The change from `before` to `now`; nil when there is nothing before.
    static func change(_ now: Double, _ before: Double?) -> Double? {
        guard let before, before > 0 else { return nil }
        return (now - before) / before
    }

    /// `change` for counts; nil when there is nothing before.
    static func countChange(_ now: Int, _ before: Int?) -> Double? {
        guard let before else { return nil }
        return change(Double(now), Double(before))
    }

    static func dayTitle(_ text: String, locale: Locale) -> String {
        guard let date = MarkazDay.date(text) else { return text }
        return GroupInvitationDate.text(date, locale: locale)
    }

    /// A country's name from its two-letter code, in the app's language.
    static func country(_ code: String?, locale: Locale) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return locale.localizedString(forRegionCode: code) ?? code
    }

    /// Weekday 1 (Monday) to 7 (Sunday), short, in the app's language.
    static func weekday(_ weekday: Int, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let symbols = calendar.shortWeekdaySymbols
        guard symbols.count == 7 else { return "\(weekday)" }
        return symbols[((weekday % 7) + 7) % 7]
    }

    static func hour(_ hour: Int) -> String {
        hour < 10 ? "0\(hour):00" : "\(hour):00"
    }
}

// MARK: - Cards and figures

/// A report section on the Halqah glass card, under its heading.
struct MarkazCard<Content: View>: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    var tint: Color = DIColor.primary
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: titleKey, systemImage: systemImage)
            content()
        }
        .halqahCard(tint: tint)
    }
}

/// The change on the period before: green and up, red and down.
struct MarkazChangeBadge: View {
    let change: Double

    var body: some View {
        let percent = Int((change * 100).rounded())
        let color: Color = percent > 0 ? DIColor.primary : (percent < 0 ? DIColor.danger : DIColor.textMuted)
        let symbol = percent > 0 ? "arrow.up.right" : (percent < 0 ? "arrow.down.right" : "equal")
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .diInterfaceFont(.caption2, weight: .bold)
            Text(verbatim: MarkazText.percent(change))
                .font(.caption.weight(.bold).monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.12)))
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(percent > 0
                            ? Text("Up \(abs(percent)) percent on the period before")
                            : (percent < 0 ? Text("Down \(abs(percent)) percent on the period before")
                                           : Text("The same as the period before")))
    }
}

/// One figure of the report: its value, what it counts, and its change.
struct MarkazFigure: Identifiable {
    let id: String
    let titleKey: LocalizedStringKey
    let value: String
    let systemImage: String
    var change: Double? = nil
}

struct MarkazFigureTile: View {
    let figure: MarkazFigure

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.xs) {
            HStack(spacing: DISpacing.xs) {
                Image(systemName: figure.systemImage)
                    .diInterfaceFont(.caption, weight: .semibold)
                    .foregroundStyle(HalqahInk.goldText)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if let change = figure.change {
                    MarkazChangeBadge(change: change)
                }
            }
            Text(verbatim: figure.value)
                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(DIColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(figure.titleKey)
                .diInterfaceFont(.caption, weight: .medium)
                .foregroundStyle(DIColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DISpacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HalqahGlassSurface(tint: DIColor.accent, cornerRadius: DIRadius.md))
        .accessibilityElement(children: .combine)
    }
}

/// The figures two to a row; one to a row at the largest text sizes.
struct MarkazFigureGrid: View {
    let figures: [MarkazFigure]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: DISpacing.sm), GridItem(.flexible(), spacing: DISpacing.sm)]
        LazyVGrid(columns: columns, spacing: DISpacing.sm) {
            ForEach(figures) { MarkazFigureTile(figure: $0) }
        }
    }
}

extension MarkazSummary {
    /// The eight figures of the dashboard, with their change where the
    /// period before is known.
    func figures(previous: MarkazPrevious?) -> [MarkazFigure] {
        [
            MarkazFigure(id: "sessions", titleKey: "Sessions", value: "\(sessions)", systemImage: "calendar",
                         change: MarkazText.countChange(sessions, previous?.sessions)),
            MarkazFigure(id: "attendance", titleKey: "Attendance", value: "\(attendance)", systemImage: "person.3.fill",
                         change: MarkazText.countChange(attendance, previous?.attendance)),
            MarkazFigure(id: "unique", titleKey: "Different people", value: "\(uniqueAttendees)", systemImage: "person.crop.circle",
                         change: MarkazText.countChange(uniqueAttendees, previous?.uniqueAttendees)),
            MarkazFigure(id: "average", titleKey: "Average per session", value: MarkazText.decimal(averageAttendance),
                         systemImage: "chart.bar.fill",
                         change: MarkazText.change(averageAttendance, previous?.averageAttendance)),
            MarkazFigure(id: "web", titleKey: "Website visitors", value: "\(webAttendance)", systemImage: "globe",
                         change: MarkazText.countChange(webAttendance, previous?.webAttendance)),
            MarkazFigure(id: "length", titleKey: "Average length (minutes)", value: MarkazText.decimal(averageMinutes),
                         systemImage: "clock.fill",
                         change: MarkazText.change(averageMinutes, previous?.averageMinutes)),
            MarkazFigure(id: "active", titleKey: "Active Halqahs", value: "\(activeHalqahs) / \(totalHalqahs)",
                         systemImage: "dot.radiowaves.left.and.right",
                         change: MarkazText.countChange(activeHalqahs, previous?.activeHalqahs)),
            MarkazFigure(id: "new", titleKey: "New members", value: "\(newMembers)", systemImage: "person.badge.plus",
                         change: MarkazText.countChange(newMembers, previous?.newMembers))
        ]
    }
}

// MARK: - Status

/// A Halqah's status as a dot: active (a session in the last 7 days),
/// quiet (8-21 days) or inactive.
struct MarkazStatusDot: View {
    let status: String?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }

    private var color: Color {
        switch status {
        case "active": return Color(hex: 0x2FBF71)
        case "quiet": return DIColor.accent
        default: return DIColor.danger
        }
    }

    private var label: Text {
        switch status {
        case "active": return Text("Active")
        case "quiet": return Text("Quiet")
        default: return Text("Inactive")
        }
    }
}

// MARK: - Charts

/// One day of the trend, with its day read.
private struct MarkazTrendPoint: Identifiable {
    let id: String
    let day: Date
    let attendance: Int
    let sessions: Int
}

/// Attendance each day as an emerald area under a gold line, and the
/// sessions each day as bars beneath.
struct MarkazTrendChart: View {
    let daily: [MarkazDailyPoint]
    @Environment(\.locale) private var locale

    private var points: [MarkazTrendPoint] {
        daily.compactMap { point -> MarkazTrendPoint? in
            guard let day = point.day else { return nil }
            return MarkazTrendPoint(id: point.date, day: day, attendance: point.attendance, sessions: point.sessions)
        }
    }

    var body: some View {
        let trend = points
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            Chart {
                ForEach(trend) { point in
                    AreaMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Attendance", point.attendance)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(
                        colors: [DIColor.primary.opacity(0.45), DIColor.primary.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    LineMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Attendance", point.attendance)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(DIColor.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 180)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Attendance trend"))
            .accessibilityValue(Text(verbatim: attendanceSummary(trend)))

            Text("Sessions each day")
                .diInterfaceFont(.caption, weight: .semibold)
                .foregroundStyle(DIColor.textMuted)
            Chart {
                ForEach(trend) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Sessions", point.sessions)
                    )
                    .foregroundStyle(DIColor.primary.gradient)
                    .cornerRadius(2)
                }
            }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
            .frame(height: 80)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Sessions each day"))
            .accessibilityValue(Text(verbatim: sessionsSummary(trend)))
        }
    }

    private func attendanceSummary(_ points: [MarkazTrendPoint]) -> String {
        let total = points.reduce(0) { $0 + $1.attendance }
        guard let best = points.max(by: { $0.attendance < $1.attendance }), best.attendance > 0 else {
            return String(localized: "No one attended in this period.")
        }
        let day = GroupInvitationDate.text(best.day, locale: locale)
        return String(localized: "\(total) attended in all. The most, \(best.attendance), on \(day).")
    }

    private func sessionsSummary(_ points: [MarkazTrendPoint]) -> String {
        let total = points.reduce(0) { $0 + $1.sessions }
        let days = points.filter { $0.sessions > 0 }.count
        return String(localized: "\(total) sessions on \(days) days.")
    }
}

/// When people come: weekdays down, the hours with any session across,
/// darker where more people came.
struct MarkazHeatmap: View {
    let cells: [MarkazWeekdayHour]
    @Environment(\.locale) private var locale

    private struct Cell: Identifiable {
        let id: String
        let weekday: String
        let hour: String
        let attendance: Int
        let sessions: Int
    }

    var body: some View {
        let hours = Array(Set(cells.filter { $0.sessions > 0 }.map(\.hour))).sorted()
        let days = (1...7).map { MarkazText.weekday($0, locale: locale) }
        let peak = max(cells.map(\.attendance).max() ?? 0, 1)
        let grid: [Cell] = (1...7).flatMap { weekday in
            hours.map { hour -> Cell in
                let found = cells.first { $0.weekday == weekday && $0.hour == hour }
                return Cell(id: "\(weekday)-\(hour)", weekday: MarkazText.weekday(weekday, locale: locale),
                            hour: MarkazText.hour(hour), attendance: found?.attendance ?? 0, sessions: found?.sessions ?? 0)
            }
        }
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            if hours.isEmpty {
                Text("No sessions in this period.")
                    .diInterfaceFont(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
            } else {
                Chart {
                    ForEach(grid) { cell in
                        RectangleMark(
                            x: .value("Hour", cell.hour),
                            y: .value("Weekday", cell.weekday)
                        )
                        .foregroundStyle(fill(cell, peak: peak))
                        .cornerRadius(3)
                    }
                }
                .chartXScale(domain: hours.map { MarkazText.hour($0) })
                .chartYScale(domain: days)
                .frame(height: 230)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("When people come"))
                .accessibilityValue(Text(verbatim: summary(grid)))
                Text("Darker means more people came.")
                    .diInterfaceFont(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
    }

    /// Sand where there was no session; emerald, darker where more came.
    private func fill(_ cell: Cell, peak: Int) -> Color {
        guard cell.sessions > 0 else { return DIColor.sandstone.opacity(0.7) }
        let share: Double = Double(cell.attendance) / Double(peak)
        return DIColor.primary.opacity(0.18 + 0.82 * share)
    }

    private func summary(_ grid: [Cell]) -> String {
        guard let best = grid.max(by: { $0.attendance < $1.attendance }), best.attendance > 0 else {
            return String(localized: "No sessions in this period.")
        }
        let when = best.weekday + " " + best.hour
        return String(localized: "Most people come on \(when): \(best.attendance) in all.")
    }
}

/// Each Halqah's attendance as a gold bar, most first.
struct MarkazHalqahBars: View {
    let halqahs: [MarkazHalqahStat]
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 30

    var body: some View {
        let shown = Array(halqahs.sorted { $0.attendance > $1.attendance }.prefix(20))
        Chart {
            ForEach(shown) { halqah in
                BarMark(
                    x: .value("Attendance", halqah.attendance),
                    y: .value("Halqah", halqah.name)
                )
                .foregroundStyle(LinearGradient(colors: [Color(hex: 0xE0B75F), Color(hex: 0xC6A253)],
                                                startPoint: .leading, endPoint: .trailing))
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(verbatim: "\(halqah.attendance)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DIColor.textMuted)
                }
            }
        }
        .chartYScale(domain: shown.map(\.name))
        .chartXAxis(.hidden)
        .frame(height: max(rowHeight * CGFloat(shown.count), 60))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Attendance by Halqah"))
        .accessibilityValue(Text(verbatim: shown.prefix(5).map { "\($0.name): \($0.attendance)" }.joined(separator: ", ")))
    }
}

/// App or website: a donut of who came through which, with its key.
struct MarkazViaDonut: View {
    let app: Int
    let web: Int

    private struct Slice: Identifiable {
        let id: String
        let count: Int
        let color: Color
    }

    var body: some View {
        let total = app + web
        let slices = [
            Slice(id: "app", count: app, color: DIColor.primary),
            Slice(id: "web", count: web, color: DIColor.accent)
        ]
        if total == 0 {
            Text("No one attended in this period.")
                .diInterfaceFont(.subheadline)
                .foregroundStyle(DIColor.textMuted)
        } else {
            HStack(spacing: DISpacing.lg) {
                Chart {
                    ForEach(slices) { slice in
                        SectorMark(
                            angle: .value("People", slice.count),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .foregroundStyle(slice.color)
                    }
                }
                .frame(width: 120, height: 120)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    key(Text("In the app"), count: app, total: total, color: DIColor.primary)
                    key(Text("On the website"), count: web, total: total, color: DIColor.accent)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func key(_ label: Text, count: Int, total: Int, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DISpacing.sm) {
            Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                label
                    .diInterfaceFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DIColor.textPrimary)
                Text(verbatim: "\(count) \u{00b7} \(Int((Double(count) / Double(max(total, 1)) * 100).rounded()))%")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(DIColor.textMuted)
            }
        }
    }
}

// MARK: - Rows

/// An insight, coloured by its level.
struct MarkazInsightRow: View {
    let insight: MarkazInsight

    var body: some View {
        HStack(alignment: .top, spacing: DISpacing.sm) {
            Image(systemName: symbol)
                .diInterfaceFont(.subheadline, weight: .semibold)
                .foregroundStyle(color)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: insight.title)
                    .diInterfaceFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DIColor.textPrimary)
                if let detail = insight.detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .diInterfaceFont(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DISpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous).fill(color.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous).strokeBorder(color.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch insight.level {
        case "good": return DIColor.primary
        case "alert": return DIColor.danger
        default: return HalqahInk.goldText
        }
    }

    private var symbol: String {
        switch insight.level {
        case "good": return "checkmark.seal.fill"
        case "alert": return "exclamationmark.triangle.fill"
        default: return "eye.fill"
        }
    }
}

/// A row of a report list: a title, a line beneath, and a value at the end.
struct MarkazRow: View {
    let title: String
    var detail: String? = nil
    var value: String? = nil
    var showsChevron = false

    var body: some View {
        HStack(spacing: DISpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .diInterfaceFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DIColor.textPrimary)
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .diInterfaceFont(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DISpacing.sm)
            if let value {
                Text(verbatim: value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(HalqahInk.goldText)
            }
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .diInterfaceFont(.caption, weight: .bold)
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One person who attended: name, where from, how, when and how long.
struct MarkazAttendeeRow: View {
    let attendee: MarkazAttendee
    @Environment(\.locale) private var locale

    var body: some View {
        MarkazRow(title: attendee.name.isEmpty ? String(localized: "Someone") : attendee.name,
                  detail: detail,
                  value: attendee.minutes.map { String(localized: "\($0) min") })
    }

    private var detail: String {
        var parts: [String] = []
        let place = [attendee.city, MarkazText.country(attendee.country, locale: locale)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        if !place.isEmpty { parts.append(place) }
        parts.append(attendee.isWeb ? String(localized: "Website") : String(localized: "App"))
        if let joined = attendee.joinedAt {
            parts.append(String(localized: "Joined \(GroupInvitationDate.clock(joined, locale: locale))"))
        }
        return parts.joined(separator: " \u{00b7} ")
    }
}

/// One session in a list: its title, Halqah, time, and who came.
struct MarkazSessionRow: View {
    let session: MarkazSession
    var showsChevron = true
    @Environment(\.locale) private var locale

    var body: some View {
        MarkazRow(title: title, detail: detail, value: "\(session.attendance)", showsChevron: showsChevron)
    }

    private var title: String {
        if let title = session.title, !title.isEmpty { return title }
        return session.isMeeting ? String(localized: "Group meeting") : String(localized: "Halqah Zikr")
    }

    private var detail: String {
        var parts: [String] = []
        if let name = session.groupName, !name.isEmpty { parts.append(name) }
        if let start = session.startedAt { parts.append(GroupInvitationDate.text(start, locale: locale, includesTime: true)) }
        if session.minutes > 0 { parts.append(String(localized: "\(session.minutes) min")) }
        if session.automated { parts.append(String(localized: "Started by itself")) }
        return parts.joined(separator: " \u{00b7} ")
    }
}

/// A screen's loading, failure and empty states, as the Halqah screens show
/// them.
struct MarkazStateCard: View {
    let failure: String?
    let loading: Bool
    let retry: () -> Void

    var body: some View {
        if let failure {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    Text(verbatim: failure).diInterfaceFont(.subheadline)
                    Button("Try again", action: retry)
                        .buttonStyle(DISecondaryButtonStyle())
                        .disabled(loading)
                }
            }
        } else if loading {
            ProgressView().frame(maxWidth: .infinity).padding(.top, DISpacing.lg)
        }
    }
}

/// Something to hand to the share sheet: a spreadsheet's file or a text.
struct MarkazSharedItem: Identifiable {
    let id = UUID()
    let items: [Any]
}
