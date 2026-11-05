import Foundation

// What the Silsila Markaz's reports say, as the server sends them
// (Docs/MARKAZ_ANALYTICS_API.md). Every field is read forgivingly: a missing
// or unexpected value becomes empty or zero, a list entry that cannot be read
// is left out, and keys this build does not know are ignored, so a server
// that sends more never blanks a report. Times are read with `ServerDate`.

// MARK: - Forgiving reads

/// One list entry, or nothing when it cannot be read.
struct MarkazLenient<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

extension KeyedDecodingContainer {
    func markazString(_ key: Key) -> String? {
        try? decodeIfPresent(String.self, forKey: key)
    }

    /// A whole number, also when the server wrote it with a fraction.
    func markazInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite, abs(value) < 1e12 {
            return Int(value.rounded())
        }
        return nil
    }

    func markazDouble(_ key: Key) -> Double? {
        guard let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite else { return nil }
        return value
    }

    func markazBool(_ key: Key) -> Bool? {
        try? decodeIfPresent(Bool.self, forKey: key)
    }

    func markazDate(_ key: Key) -> Date? {
        guard let text = markazString(key) else { return nil }
        return ServerDate.date(from: text)
    }

    func markazList<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        guard let items = try? decodeIfPresent([MarkazLenient<T>].self, forKey: key) else { return [] }
        return items.compactMap(\.value)
    }

    func markazObject<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        try? decodeIfPresent(T.self, forKey: key)
    }
}

/// The report's calendar days ("2026-11-04"), read in the phone's time zone,
/// which is the zone every request sends as `tz`.
enum MarkazDay {
    private nonisolated(unsafe) static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private nonisolated(unsafe) static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    static func date(_ text: String) -> Date? {
        formatter.date(from: String(text.prefix(10)))
    }

    static func string(_ date: Date) -> String {
        formatter.string(from: date)
    }

    static func month(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }
}

// MARK: - Access

/// Whether this member sees the Markaz's reports.
struct MarkazAccess: Decodable, Sendable, Equatable {
    var canReport: Bool
    var isSuperAdmin: Bool
    var markazGroupID: String
    var markazRole: String?

    enum CodingKeys: String, CodingKey {
        case canReport, isSuperAdmin, markazGroupID, markazRole
    }

    init(canReport: Bool, isSuperAdmin: Bool, markazGroupID: String = MarkazAccess.markazID, markazRole: String? = nil) {
        self.canReport = canReport
        self.isSuperAdmin = isSuperAdmin
        self.markazGroupID = markazGroupID
        self.markazRole = markazRole
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canReport = c.markazBool(.canReport) ?? false
        isSuperAdmin = c.markazBool(.isSuperAdmin) ?? false
        markazGroupID = c.markazString(.markazGroupID) ?? MarkazAccess.markazID
        markazRole = c.markazString(.markazRole)
    }

    /// The Silsila Markaz group.
    static let markazID = "silsila-markaz"
    static let denied = MarkazAccess(canReport: false, isSuperAdmin: false)
}

// MARK: - Analytics

struct MarkazSummary: Decodable, Sendable, Equatable {
    var sessions = 0
    var zikrSessions = 0
    var meetings = 0
    var attendance = 0
    var uniqueAttendees = 0
    var appAttendance = 0
    var webAttendance = 0
    var averageAttendance = 0.0
    var averageMinutes = 0.0
    var totalMinutes = 0
    var activeHalqahs = 0
    var totalHalqahs = 0
    var members = 0
    var newMembers = 0
    var duaRequests = 0
    var stagesAnnounced = 0
    var chatMessages = 0
    var automatedStarts = 0

    enum CodingKeys: String, CodingKey {
        case sessions, zikrSessions, meetings, attendance, uniqueAttendees, appAttendance, webAttendance
        case averageAttendance, averageMinutes, totalMinutes, activeHalqahs, totalHalqahs, members, newMembers
        case duaRequests, stagesAnnounced, chatMessages, automatedStarts
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessions = c.markazInt(.sessions) ?? 0
        zikrSessions = c.markazInt(.zikrSessions) ?? 0
        meetings = c.markazInt(.meetings) ?? 0
        attendance = c.markazInt(.attendance) ?? 0
        uniqueAttendees = c.markazInt(.uniqueAttendees) ?? 0
        appAttendance = c.markazInt(.appAttendance) ?? 0
        webAttendance = c.markazInt(.webAttendance) ?? 0
        averageAttendance = c.markazDouble(.averageAttendance) ?? 0
        averageMinutes = c.markazDouble(.averageMinutes) ?? 0
        totalMinutes = c.markazInt(.totalMinutes) ?? 0
        activeHalqahs = c.markazInt(.activeHalqahs) ?? 0
        totalHalqahs = c.markazInt(.totalHalqahs) ?? 0
        members = c.markazInt(.members) ?? 0
        newMembers = c.markazInt(.newMembers) ?? 0
        duaRequests = c.markazInt(.duaRequests) ?? 0
        stagesAnnounced = c.markazInt(.stagesAnnounced) ?? 0
        chatMessages = c.markazInt(.chatMessages) ?? 0
        automatedStarts = c.markazInt(.automatedStarts) ?? 0
    }
}

/// The period before, to compare with; also a daily report's day before.
struct MarkazPrevious: Decodable, Sendable, Equatable {
    var from: String?
    var to: String?
    var sessions: Int?
    var attendance: Int?
    var uniqueAttendees: Int?
    var averageAttendance: Double?
    /// Not in the contract yet; shown as a change as soon as a server sends
    /// them.
    var webAttendance: Int?
    var averageMinutes: Double?
    var activeHalqahs: Int?
    var newMembers: Int?

    enum CodingKeys: String, CodingKey {
        case from, to, sessions, attendance, uniqueAttendees, averageAttendance
        case webAttendance, averageMinutes, activeHalqahs, newMembers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = c.markazString(.from)
        to = c.markazString(.to)
        sessions = c.markazInt(.sessions)
        attendance = c.markazInt(.attendance)
        uniqueAttendees = c.markazInt(.uniqueAttendees)
        averageAttendance = c.markazDouble(.averageAttendance)
        webAttendance = c.markazInt(.webAttendance)
        averageMinutes = c.markazDouble(.averageMinutes)
        activeHalqahs = c.markazInt(.activeHalqahs)
        newMembers = c.markazInt(.newMembers)
    }
}

struct MarkazRange: Decodable, Sendable, Equatable {
    var from: String
    var to: String
    var days: Int
    var tz: String?

    enum CodingKeys: String, CodingKey { case from, to, days, tz }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = c.markazString(.from) ?? ""
        to = c.markazString(.to) ?? ""
        days = c.markazInt(.days) ?? 0
        tz = c.markazString(.tz)
    }
}

struct MarkazScopeInfo: Decodable, Sendable, Equatable {
    var kind: String
    var id: String?
    var name: String?

    enum CodingKeys: String, CodingKey { case kind, id, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.markazString(.kind) ?? "all"
        id = c.markazString(.id)
        name = c.markazString(.name)
    }
}

/// One day of the period; every day is sent, zeros included.
struct MarkazDailyPoint: Decodable, Sendable, Equatable, Identifiable {
    var date: String
    var sessions: Int
    var attendance: Int
    var unique: Int

    var id: String { date }
    var day: Date? { MarkazDay.date(date) }

    enum CodingKeys: String, CodingKey { case date, sessions, attendance, unique }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.markazString(.date) ?? ""
        sessions = c.markazInt(.sessions) ?? 0
        attendance = c.markazInt(.attendance) ?? 0
        unique = c.markazInt(.unique) ?? 0
    }
}

/// Sessions and attendance by weekday (1 Monday ... 7 Sunday) and local hour.
struct MarkazWeekdayHour: Decodable, Sendable, Equatable, Identifiable {
    var weekday: Int
    var hour: Int
    var sessions: Int
    var attendance: Int

    var id: String { "\(weekday)-\(hour)" }

    enum CodingKeys: String, CodingKey { case weekday, hour, sessions, attendance }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weekday = c.markazInt(.weekday) ?? 0
        hour = c.markazInt(.hour) ?? 0
        sessions = c.markazInt(.sessions) ?? 0
        attendance = c.markazInt(.attendance) ?? 0
    }
}

/// One Halqah over the period.
struct MarkazHalqahStat: Decodable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var region: String?
    var kind: String?
    var sessions: Int
    var attendance: Int
    var averageAttendance: Double
    var uniqueAttendees: Int
    var members: Int
    /// Different people over members; nil when it has no members.
    var attendanceRate: Double?
    var lastSessionAt: Date?
    /// Attendance against the period before; nil when there was none before.
    var change: Double?
    /// active, quiet or inactive.
    var status: String?

    enum CodingKeys: String, CodingKey {
        case id, name, region, kind, sessions, attendance, averageAttendance, uniqueAttendees
        case members, attendanceRate, lastSessionAt, change, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.markazString(.id) ?? ""
        name = c.markazString(.name) ?? id
        region = c.markazString(.region)
        kind = c.markazString(.kind)
        sessions = c.markazInt(.sessions) ?? 0
        attendance = c.markazInt(.attendance) ?? 0
        averageAttendance = c.markazDouble(.averageAttendance) ?? 0
        uniqueAttendees = c.markazInt(.uniqueAttendees) ?? 0
        members = c.markazInt(.members) ?? 0
        attendanceRate = c.markazDouble(.attendanceRate)
        lastSessionAt = c.markazDate(.lastSessionAt)
        change = c.markazDouble(.change)
        status = c.markazString(.status)
    }
}

struct MarkazRegionStat: Decodable, Sendable, Equatable, Identifiable {
    var name: String
    var halqahs: Int
    var sessions: Int
    var attendance: Int
    var members: Int

    var id: String { name }

    enum CodingKeys: String, CodingKey { case name, halqahs, sessions, attendance, members }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.markazString(.name) ?? ""
        halqahs = c.markazInt(.halqahs) ?? 0
        sessions = c.markazInt(.sessions) ?? 0
        attendance = c.markazInt(.attendance) ?? 0
        members = c.markazInt(.members) ?? 0
    }
}

struct MarkazCountryStat: Decodable, Sendable, Equatable, Identifiable {
    var code: String
    var attendees: Int

    var id: String { code }

    enum CodingKeys: String, CodingKey { case code, attendees }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = c.markazString(.code) ?? ""
        attendees = c.markazInt(.attendees) ?? 0
    }
}

/// Someone who comes most often.
struct MarkazRegular: Decodable, Sendable, Equatable, Identifiable {
    var memberID: String?
    var name: String
    var sessions: Int
    var lastSeenAt: Date?
    var halqahs: [String]

    var id: String { memberID ?? name }

    enum CodingKeys: String, CodingKey { case memberID, name, sessions, lastSeenAt, halqahs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberID = c.markazString(.memberID)
        name = c.markazString(.name) ?? ""
        sessions = c.markazInt(.sessions) ?? 0
        lastSeenAt = c.markazDate(.lastSeenAt)
        halqahs = c.markazList(String.self, .halqahs)
    }
}

/// Someone who came three or more times before and not in the last three
/// weeks.
struct MarkazNeedsCare: Decodable, Sendable, Equatable, Identifiable {
    var memberID: String?
    var name: String
    var lastSeenAt: Date?
    var sessionsBefore: Int
    var halqah: String?

    var id: String { memberID ?? name }

    enum CodingKeys: String, CodingKey { case memberID, name, lastSeenAt, sessionsBefore, halqah }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberID = c.markazString(.memberID)
        name = c.markazString(.name) ?? ""
        lastSeenAt = c.markazDate(.lastSeenAt)
        sessionsBefore = c.markazInt(.sessionsBefore) ?? 0
        halqah = c.markazString(.halqah)
    }
}

/// Someone present in a session.
struct MarkazAttendee: Decodable, Sendable, Equatable {
    var name: String
    var city: String?
    var country: String?
    /// "app" or "web".
    var via: String?
    var joinedAt: Date?
    var minutes: Int?

    var isWeb: Bool { via == "web" }

    enum CodingKeys: String, CodingKey { case name, city, country, via, joinedAt, minutes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.markazString(.name) ?? ""
        city = c.markazString(.city)
        country = c.markazString(.country)
        via = c.markazString(.via)
        joinedAt = c.markazDate(.joinedAt)
        minutes = c.markazInt(.minutes)
    }
}

/// One session: in the analytics list, in a daily report (with its
/// attendees), and at the top of a session's detail.
struct MarkazSession: Decodable, Sendable, Equatable, Identifiable {
    var id: String
    var groupID: String?
    var groupName: String?
    /// "zikr" or "meeting".
    var kind: String?
    var title: String?
    var startedAt: Date?
    var endedAt: Date?
    var minutes: Int
    var attendance: Int
    var app: Int?
    var web: Int?
    var startedBy: String?
    var automated: Bool
    var attendees: [MarkazAttendee]

    var isMeeting: Bool { kind == "meeting" }

    enum CodingKeys: String, CodingKey {
        case id, groupID, groupName, kind, title, startedAt, endedAt, minutes, attendance, app, web
        case startedBy, automated, attendees
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.markazString(.id) ?? ""
        groupID = c.markazString(.groupID)
        groupName = c.markazString(.groupName)
        kind = c.markazString(.kind)
        title = c.markazString(.title)
        startedAt = c.markazDate(.startedAt)
        endedAt = c.markazDate(.endedAt)
        minutes = c.markazInt(.minutes) ?? 0
        attendance = c.markazInt(.attendance) ?? 0
        app = c.markazInt(.app)
        web = c.markazInt(.web)
        startedBy = c.markazString(.startedBy)
        automated = c.markazBool(.automated) ?? false
        attendees = c.markazList(MarkazAttendee.self, .attendees)
    }
}

/// Something worth noticing: good, to watch, or an alert.
struct MarkazInsight: Decodable, Sendable, Equatable {
    var level: String
    var title: String
    var detail: String?
    var halqahID: String?

    enum CodingKeys: String, CodingKey { case level, title, detail, halqahID }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = c.markazString(.level) ?? "watch"
        title = c.markazString(.title) ?? ""
        detail = c.markazString(.detail)
        halqahID = c.markazString(.halqahID)
    }
}

/// GET /v1/markaz/analytics.
struct MarkazAnalytics: Decodable, Sendable, Equatable {
    var range: MarkazRange?
    var scope: MarkazScopeInfo?
    var generatedAt: Date?
    var summary: MarkazSummary
    var previous: MarkazPrevious?
    var daily: [MarkazDailyPoint]
    var weekdayHour: [MarkazWeekdayHour]
    var halqahs: [MarkazHalqahStat]
    var regions: [MarkazRegionStat]
    var countries: [MarkazCountryStat]
    var regulars: [MarkazRegular]
    var needsCare: [MarkazNeedsCare]
    var sessions: [MarkazSession]
    var insights: [MarkazInsight]

    enum CodingKeys: String, CodingKey {
        case range, scope, generatedAt, summary, previous, daily, weekdayHour, halqahs, regions, countries
        case regulars, needsCare, sessions, insights
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        range = c.markazObject(MarkazRange.self, .range)
        scope = c.markazObject(MarkazScopeInfo.self, .scope)
        generatedAt = c.markazDate(.generatedAt)
        summary = c.markazObject(MarkazSummary.self, .summary) ?? MarkazSummary()
        previous = c.markazObject(MarkazPrevious.self, .previous)
        daily = c.markazList(MarkazDailyPoint.self, .daily)
        weekdayHour = c.markazList(MarkazWeekdayHour.self, .weekdayHour)
        halqahs = c.markazList(MarkazHalqahStat.self, .halqahs)
        regions = c.markazList(MarkazRegionStat.self, .regions)
        countries = c.markazList(MarkazCountryStat.self, .countries)
        regulars = c.markazList(MarkazRegular.self, .regulars)
        needsCare = c.markazList(MarkazNeedsCare.self, .needsCare)
        sessions = c.markazList(MarkazSession.self, .sessions)
        insights = c.markazList(MarkazInsight.self, .insights)
    }
}

// MARK: - Daily and monthly reports

struct MarkazHalqahRef: Decodable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String

    enum CodingKeys: String, CodingKey { case id, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.markazString(.id) ?? ""
        name = c.markazString(.name) ?? id
    }
}

/// One Halqah's day: its sessions, each with who came.
struct MarkazDailyHalqah: Decodable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var region: String?
    var sessions: [MarkazSession]

    enum CodingKeys: String, CodingKey { case id, name, region, sessions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.markazString(.id) ?? ""
        name = c.markazString(.name) ?? id
        region = c.markazString(.region)
        sessions = c.markazList(MarkazSession.self, .sessions)
    }
}

/// GET /v1/markaz/reports/daily.
struct MarkazDailyReport: Decodable, Sendable, Equatable {
    var date: String
    var tz: String?
    var summary: MarkazSummary
    var previousDay: MarkazPrevious?
    var halqahs: [MarkazDailyHalqah]
    /// Halqahs with a zikr time that day and no session.
    var noSession: [MarkazHalqahRef]
    var insights: [MarkazInsight]

    enum CodingKeys: String, CodingKey { case date, tz, summary, previousDay, halqahs, noSession, insights }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.markazString(.date) ?? ""
        tz = c.markazString(.tz)
        summary = c.markazObject(MarkazSummary.self, .summary) ?? MarkazSummary()
        previousDay = c.markazObject(MarkazPrevious.self, .previousDay)
        halqahs = c.markazList(MarkazDailyHalqah.self, .halqahs)
        noSession = c.markazList(MarkazHalqahRef.self, .noSession)
        insights = c.markazList(MarkazInsight.self, .insights)
    }
}

/// Everyone who came in the month, most first.
struct MarkazPersonAttendance: Decodable, Sendable, Equatable, Identifiable {
    var memberID: String?
    var name: String
    var via: String?
    var sessions: Int
    var days: Int
    var halqahs: [String]
    var lastSeenAt: Date?

    var id: String { memberID ?? name }

    enum CodingKeys: String, CodingKey { case memberID, name, via, sessions, days, halqahs, lastSeenAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberID = c.markazString(.memberID)
        name = c.markazString(.name) ?? ""
        via = c.markazString(.via)
        sessions = c.markazInt(.sessions) ?? 0
        days = c.markazInt(.days) ?? 0
        halqahs = c.markazList(String.self, .halqahs)
        lastSeenAt = c.markazDate(.lastSeenAt)
    }
}

struct MarkazNewMember: Decodable, Sendable, Equatable {
    var name: String
    var halqah: String?
    var joinedAt: Date?

    enum CodingKeys: String, CodingKey { case name, halqah, joinedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.markazString(.name) ?? ""
        halqah = c.markazString(.halqah)
        joinedAt = c.markazDate(.joinedAt)
    }
}

/// GET /v1/markaz/reports/monthly.
struct MarkazMonthlyReport: Decodable, Sendable, Equatable {
    var month: String
    var tz: String?
    var summary: MarkazSummary
    var previous: MarkazPrevious?
    var daily: [MarkazDailyPoint]
    var weekdayHour: [MarkazWeekdayHour]
    var halqahs: [MarkazHalqahStat]
    var regions: [MarkazRegionStat]
    var regulars: [MarkazRegular]
    var needsCare: [MarkazNeedsCare]
    var attendanceByPerson: [MarkazPersonAttendance]
    var newMembers: [MarkazNewMember]
    var insights: [MarkazInsight]

    enum CodingKeys: String, CodingKey {
        case month, tz, summary, previous, daily, weekdayHour, halqahs, regions, regulars, needsCare
        case attendanceByPerson, newMembers, insights
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        month = c.markazString(.month) ?? ""
        tz = c.markazString(.tz)
        summary = c.markazObject(MarkazSummary.self, .summary) ?? MarkazSummary()
        previous = c.markazObject(MarkazPrevious.self, .previous)
        daily = c.markazList(MarkazDailyPoint.self, .daily)
        weekdayHour = c.markazList(MarkazWeekdayHour.self, .weekdayHour)
        halqahs = c.markazList(MarkazHalqahStat.self, .halqahs)
        regions = c.markazList(MarkazRegionStat.self, .regions)
        regulars = c.markazList(MarkazRegular.self, .regulars)
        needsCare = c.markazList(MarkazNeedsCare.self, .needsCare)
        attendanceByPerson = c.markazList(MarkazPersonAttendance.self, .attendanceByPerson)
        newMembers = c.markazList(MarkazNewMember.self, .newMembers)
        insights = c.markazList(MarkazInsight.self, .insights)
    }
}

// MARK: - Session and person

struct MarkazStage: Decodable, Sendable, Equatable {
    var title: String
    var at: Date?

    enum CodingKeys: String, CodingKey { case title, at }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.markazString(.title) ?? ""
        at = c.markazDate(.at)
    }
}

/// GET /v1/markaz/sessions/{id}.
struct MarkazSessionDetail: Decodable, Sendable, Equatable {
    var session: MarkazSession?
    var attendees: [MarkazAttendee]
    var stages: [MarkazStage]
    var duaRequests: Int

    enum CodingKeys: String, CodingKey { case session, attendees, stages, duaRequests }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        session = c.markazObject(MarkazSession.self, .session)
        attendees = c.markazList(MarkazAttendee.self, .attendees)
        stages = c.markazList(MarkazStage.self, .stages)
        duaRequests = c.markazInt(.duaRequests) ?? 0
    }
}

struct MarkazPersonHalqah: Decodable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var role: String?

    enum CodingKeys: String, CodingKey { case id, name, role }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.markazString(.id) ?? ""
        name = c.markazString(.name) ?? id
        role = c.markazString(.role)
    }
}

struct MarkazHistoryEntry: Decodable, Sendable, Equatable {
    /// A calendar day, or a time; both are read.
    var date: String
    var groupName: String?
    var title: String?
    var minutes: Int?

    var moment: Date? { ServerDate.date(from: date) ?? MarkazDay.date(date) }

    enum CodingKeys: String, CodingKey { case date, groupName, title, minutes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.markazString(.date) ?? ""
        groupName = c.markazString(.groupName)
        title = c.markazString(.title)
        minutes = c.markazInt(.minutes)
    }
}

/// GET /v1/markaz/people/{id}.
struct MarkazPerson: Decodable, Sendable, Equatable {
    var memberID: String
    var name: String
    var email: String?
    var halqahs: [MarkazPersonHalqah]
    var firstSeenAt: Date?
    var lastSeenAt: Date?
    var sessions: Int
    var last90Days: Int
    var currentStreakDays: Int
    var history: [MarkazHistoryEntry]

    enum CodingKeys: String, CodingKey {
        case memberID, name, email, halqahs, firstSeenAt, lastSeenAt, sessions, last90Days, currentStreakDays, history
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberID = c.markazString(.memberID) ?? ""
        name = c.markazString(.name) ?? ""
        email = c.markazString(.email)
        halqahs = c.markazList(MarkazPersonHalqah.self, .halqahs)
        firstSeenAt = c.markazDate(.firstSeenAt)
        lastSeenAt = c.markazDate(.lastSeenAt)
        sessions = c.markazInt(.sessions) ?? 0
        last90Days = c.markazInt(.last90Days) ?? 0
        currentStreakDays = c.markazInt(.currentStreakDays) ?? 0
        history = c.markazList(MarkazHistoryEntry.self, .history)
    }
}

// MARK: - Organisation

/// One Halqah on the Organisation page.
struct MarkazOrgHalqah: Decodable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var kind: String?
    var city: String?
    var countryCode: String?
    var members: Int
    var administrators: [String]
    var admins: [String]
    var zikrTimes: Int
    var lastSessionAt: Date?
    var sessions30Days: Int
    var status: String?
    var isLive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, kind, city, countryCode, members, administrators, admins, zikrTimes
        case lastSessionAt, sessions30Days, status, isLive
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.markazString(.id) ?? ""
        name = c.markazString(.name) ?? id
        kind = c.markazString(.kind)
        city = c.markazString(.city)
        countryCode = c.markazString(.countryCode)
        members = c.markazInt(.members) ?? 0
        administrators = c.markazList(String.self, .administrators)
        admins = c.markazList(String.self, .admins)
        zikrTimes = c.markazInt(.zikrTimes) ?? 0
        lastSessionAt = c.markazDate(.lastSessionAt)
        sessions30Days = c.markazInt(.sessions30Days) ?? 0
        status = c.markazString(.status)
        isLive = c.markazBool(.isLive) ?? false
    }
}

struct MarkazOrgRegion: Decodable, Sendable, Equatable, Identifiable {
    var name: String
    var halqahs: [MarkazOrgHalqah]

    var id: String { name }

    enum CodingKeys: String, CodingKey { case name, halqahs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.markazString(.name) ?? ""
        halqahs = c.markazList(MarkazOrgHalqah.self, .halqahs)
    }
}

struct MarkazOrgMarkaz: Decodable, Sendable, Equatable {
    var id: String
    var members: Int
    var officers: Int

    enum CodingKeys: String, CodingKey { case id, members, officers }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.markazString(.id) ?? MarkazAccess.markazID
        members = c.markazInt(.members) ?? 0
        officers = c.markazInt(.officers) ?? 0
    }
}

/// A session live now, anywhere.
struct MarkazLiveNow: Decodable, Sendable, Equatable, Identifiable {
    var groupID: String
    var name: String
    var kind: String?
    var startedAt: Date?
    var listening: Int

    var id: String { groupID }

    enum CodingKeys: String, CodingKey { case groupID, name, kind, startedAt, listening }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groupID = c.markazString(.groupID) ?? ""
        name = c.markazString(.name) ?? groupID
        kind = c.markazString(.kind)
        startedAt = c.markazDate(.startedAt)
        listening = c.markazInt(.listening) ?? 0
    }
}

struct MarkazOrgTotals: Decodable, Sendable, Equatable {
    var halqahs = 0
    var members = 0
    var administrators = 0
    var admins = 0

    enum CodingKeys: String, CodingKey { case halqahs, members, administrators, admins }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        halqahs = c.markazInt(.halqahs) ?? 0
        members = c.markazInt(.members) ?? 0
        administrators = c.markazInt(.administrators) ?? 0
        admins = c.markazInt(.admins) ?? 0
    }
}

/// GET /v1/markaz/organization.
struct MarkazOrganization: Decodable, Sendable, Equatable {
    var regions: [MarkazOrgRegion]
    /// Halqahs not yet placed in a region.
    var unassigned: [MarkazOrgHalqah]
    var markaz: MarkazOrgMarkaz?
    var liveNow: [MarkazLiveNow]
    var totals: MarkazOrgTotals

    enum CodingKeys: String, CodingKey { case regions, unassigned, markaz, liveNow, totals }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        regions = c.markazList(MarkazOrgRegion.self, .regions)
        unassigned = c.markazList(MarkazOrgHalqah.self, .unassigned)
        markaz = c.markazObject(MarkazOrgMarkaz.self, .markaz)
        liveNow = c.markazList(MarkazLiveNow.self, .liveNow)
        totals = c.markazObject(MarkazOrgTotals.self, .totals) ?? MarkazOrgTotals()
    }

    /// Every Halqah, in its region's order, then those without one.
    var allHalqahs: [MarkazOrgHalqah] { regions.flatMap(\.halqahs) + unassigned }
}

// MARK: - Announcements, admins and computers

struct MarkazAnnounceResult: Decodable, Sendable, Equatable {
    var posted: Int
    var notified: Int

    enum CodingKeys: String, CodingKey { case posted, notified }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        posted = c.markazInt(.posted) ?? 0
        notified = c.markazInt(.notified) ?? 0
    }
}

struct MarkazSyncResult: Decodable, Sendable, Equatable {
    var added: Int
    var total: Int

    enum CodingKeys: String, CodingKey { case added, total }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        added = c.markazInt(.added) ?? 0
        total = c.markazInt(.total) ?? 0
    }
}

struct MarkazAnnouncement: Decodable, Sendable, Equatable, Identifiable {
    var id: String
    var title: String
    var body: String?
    /// "members" or "admins".
    var audience: String?
    var targets: [String]
    var sentBy: String?
    var sentAt: Date?
    var posted: Int

    enum CodingKeys: String, CodingKey { case id, title, body, audience, targets, sentBy, sentAt, posted }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.markazString(.id) ?? UUID().uuidString
        title = c.markazString(.title) ?? ""
        body = c.markazString(.body)
        audience = c.markazString(.audience)
        targets = c.markazList(String.self, .targets)
        sentBy = c.markazString(.sentBy)
        sentAt = c.markazDate(.sentAt)
        posted = c.markazInt(.posted) ?? 0
    }
}

struct MarkazAnnouncementList: Decodable, Sendable {
    var announcements: [MarkazAnnouncement]

    enum CodingKeys: String, CodingKey { case announcements }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        announcements = c.markazList(MarkazAnnouncement.self, .announcements)
    }
}

/// A computer signed in to the reporting website.
struct MarkazReportingSession: Decodable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String?
    var createdAt: Date?
    var lastSeenAt: Date?
    var expiresAt: Date?
    /// The computer this request came from; never true from the phone.
    var current: Bool

    enum CodingKeys: String, CodingKey { case id, name, createdAt, lastSeenAt, expiresAt, current }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.markazString(.id) ?? ""
        name = c.markazString(.name)
        createdAt = c.markazDate(.createdAt)
        lastSeenAt = c.markazDate(.lastSeenAt)
        expiresAt = c.markazDate(.expiresAt)
        current = c.markazBool(.current) ?? false
    }
}

struct MarkazReportingSessionList: Decodable, Sendable {
    var sessions: [MarkazReportingSession]

    enum CodingKeys: String, CodingKey { case sessions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessions = c.markazList(MarkazReportingSession.self, .sessions)
    }
}
