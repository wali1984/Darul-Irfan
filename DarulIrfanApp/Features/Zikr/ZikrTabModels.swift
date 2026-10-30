import Foundation

// What the Zikr tab decides from data rather than draws: which official
// session each card shows, how a session is joined, the Daily Zikr card's
// headline and Join, the time line under a countdown, the ring's fill, the
// Reminders menu's summary and the Tasbih tile. Kept apart from the views so
// each rule has a test.

// MARK: - Which card shows which session

enum ZikrSessionRoles {
    /// Daily Zikr's own session in the bundled schedule.
    static let dailySessionID = "zikr-after-isha"

    /// Daily Zikr's session: the bundled "zikr-after-isha", or in a schedule
    /// the administrators publish, the first session that is not joined on
    /// Paltalk. The Daily Zikr card shows its countdown and reminder; the
    /// session itself stays in the schedule for reminders, widgets and Today.
    static func dailySession(in sessions: [ZikrSession]) -> ZikrSession? {
        sessions.first { $0.id == dailySessionID }
            ?? sessions.first { !ZikrSessionJoin.joinsOnPaltalk($0) }
    }

    /// Every other session, in schedule order: the Tahajjud zikr, and any
    /// further session the administrators publish.
    static func otherSessions(in sessions: [ZikrSession]) -> [ZikrSession] {
        guard let daily = dailySession(in: sessions) else { return sessions }
        return sessions.filter { $0.id != daily.id }
    }

    /// Where a link to a session ("zikr/tahajjud", or a session's id) scrolls:
    /// the Daily Zikr card for Daily Zikr's own session, that session's card
    /// for any other; nil when none matches.
    static func scrollTarget(forSessionNamed name: String, in sessions: [ZikrSession], dailyTarget: String) -> String? {
        let match = sessions.first { session in
            session.id == name || session.id.contains(name) || (name == "tahajjud" && ZikrReminders.isTahajjud(session))
        }
        guard let match else { return nil }
        return match.id == dailySession(in: sessions)?.id ? dailyTarget : match.id
    }
}

// MARK: - How a session is joined

enum ZikrSessionJoin {
    /// The Tahajjud zikr is held in the Paltalk room; Daily Zikr (and any
    /// other session) is joined through the channel's live video, in the app.
    static func joinsOnPaltalk(_ session: ZikrSession) -> Bool {
        session.zikrAnchor == .beforeFajr || session.zikrAnchor == .tahajjud || session.id.contains("tahajjud")
    }

    /// The room while it is open and it is before dawn in Pakistan, as the
    /// server names the session; the same room carries Daily Zikr in the
    /// evening, which is joined in the app instead.
    static func openRoom(for session: ZikrSession, live: LiveBroadcast, at now: Date) -> LiveRoom? {
        guard joinsOnPaltalk(session), let room = live.room, room.url != nil else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Karachi") ?? .current
        return calendar.component(.hour, from: now) < 7 ? room : nil
    }

    /// The channel's live video while it is on air, for a session joined in
    /// the app (never the Paltalk one).
    static func liveVideoID(for session: ZikrSession, live: LiveBroadcast) -> String? {
        guard !joinsOnPaltalk(session), live.state == .live else { return nil }
        return live.sources.first { $0.kind == .youtube && $0.videoID != nil }?.videoID
    }

    /// The line under a session's name: how it is announced ("Before Fajr at
    /// Dar-ul-Irfan"), or its days, then where it is joined ("on Paltalk"),
    /// or else how long it lasts.
    static func subtitle(for session: ZikrSession) -> String {
        var parts: [String] = []
        if let announcement = ZikrAnchorResolver.announcement(for: session) {
            parts.append(announcement)
        } else if ZikrScheduleMath.isDaily(session.weekdays) {
            parts.append(String(localized: "Daily"))
        } else {
            parts.append(ZikrScheduleMath.shortWeekdaySymbols(for: session.weekdays).joined(separator: " · "))
        }
        if joinsOnPaltalk(session) {
            parts.append(String(localized: "on Paltalk"))
        } else if session.durationMinutes > 0 {
            parts.append(String(localized: "About \(session.durationMinutes) minutes"))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - The Daily Zikr card

enum DailyZikrPresentation {
    /// The name the server gives the official broadcast
    /// (`OFFICIAL_LIVE_TITLE` in Server/src/sources.ts).
    static let officialTitle = "Online Zikr with Sheikh-ul-Mukarram Hazrat Ameer Abdul Qadeer Awan MZA"

    /// The details the server holds until an administrator writes their own.
    static let standingDetails = "Join the official live zikr when a broadcast is available."

    struct Headline: Equatable {
        let title: String
        /// Who leads it, on the line under the title; nil for a broadcast an
        /// administrator has named themselves.
        let host: String?
    }

    /// The official broadcast's name, split as the card shows it: the zikr,
    /// then its host. A broadcast an administrator has named shows that name
    /// as sent (or its catalogue translation), with no host line.
    static func headline(for broadcast: LiveBroadcast) -> Headline {
        let title = broadcast.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title == officialTitle || title == LiveBroadcast.offline.title {
            return Headline(
                title: String(localized: "Online Zikr with Sheikh-ul-Mukarram"),
                host: String(localized: "Hazrat Ameer Abdul Qadeer Awan MZA")
            )
        }
        // Looked up only when it cannot be read as a format.
        let shown = title.contains("%") ? title : String(localized: String.LocalizationValue(title))
        return Headline(title: shown, host: nil)
    }

    /// "Hazrat Ameer Abdul Qadeer Awan MZA · About 30 minutes"; nil when
    /// there is neither a host nor a length.
    static func subtitle(host: String?, durationMinutes: Int?) -> String? {
        var parts: [String] = []
        if let host, !host.isEmpty { parts.append(host) }
        if let durationMinutes, durationMinutes > 0 {
            parts.append(String(localized: "About \(durationMinutes) minutes"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// An administrator's note on the broadcast. The server's standing
    /// sentence is left out: the card says the same under Join.
    static func note(for broadcast: LiveBroadcast) -> String? {
        guard let details = broadcast.details?.trimmingCharacters(in: .whitespacesAndNewlines),
              !details.isEmpty, details != standingDetails else { return nil }
        return details
    }

    /// What Join plays, only while the broadcast is live: the channel's live
    /// video, or the room's sound when staff relay it. Never the Paltalk room.
    static func joinSource(for broadcast: LiveBroadcast) -> LiveSource? {
        guard broadcast.state == .live else { return nil }
        return broadcast.preferredSource
    }

    /// The status badge's catalogue key.
    static func statusKey(for state: LiveBroadcastState) -> String {
        switch state {
        case .offline: return "OFF AIR"
        case .scheduled: return "SCHEDULED"
        case .live: return "LIVE"
        case .ended: return "ENDED"
        }
    }

    /// Under "On air now": when it began, and that it plays in the app.
    static func onAirDetail(startedAt: Date?, now: Date = Date()) -> String {
        var parts: [String] = []
        if let startedAt, startedAt <= now {
            let began = startedAt.formatted(.relative(presentation: .named))
            parts.append(String(localized: "Began \(began)"))
        }
        parts.append(String(localized: "Plays here in the app"))
        return parts.joined(separator: " · ")
    }
}

// MARK: - Countdown

enum ZikrCountdown {
    /// One occurrence of a session: under way, or the next one.
    struct Window: Equatable {
        let start: Date
        let end: Date

        func isActive(at now: Date) -> Bool { start <= now && now < end }
    }

    /// The occurrence in progress, or else the next one.
    static func window(for session: ZikrSession, at now: Date) -> Window? {
        guard let start = ZikrScheduleMath.currentOrNextOccurrence(of: session, at: now) else { return nil }
        return Window(start: start, end: start.addingTimeInterval(TimeInterval(max(session.durationMinutes, 1) * 60)))
    }

    /// How far the ring has filled, 0 to 1: through the day before a start
    /// (empty a day out, full as it begins), then through the session.
    static func ringProgress(_ window: Window, at now: Date) -> Double {
        if window.start <= now {
            let span = window.end.timeIntervalSince(window.start)
            guard span > 0 else { return 1 }
            return min(max(now.timeIntervalSince(window.start) / span, 0), 1)
        }
        let remaining = window.start.timeIntervalSince(now)
        return min(max(1 - remaining / 86_400, 0), 1)
    }
}

// MARK: - Your time and Pakistan's

enum ZikrTimeLine {
    /// "Your time: Fri 12:15 PM EDT · In Pakistan: 9:15 PM", the time the
    /// Silsila announces in after this phone's own. "about" for a session that
    /// follows a prayer time at Dar-ul-Irfan; only this phone's time when it
    /// already keeps Pakistan's.
    static func text(
        for start: Date,
        session: ZikrSession,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        let local = ZikrScheduleMath.localTimeText(start, timeZone: timeZone, locale: locale)
        let yours = String(localized: "Your time: \(local)")
        let announced = TimeZone(identifier: session.timeZoneIdentifier) ?? timeZone
        guard announced.secondsFromGMT(for: start) != timeZone.secondsFromGMT(for: start) else { return yours }
        let there = start.formatted(Date.FormatStyle(locale: locale, timeZone: announced).hour().minute())
        let pakistan = session.zikrAnchor == nil
            ? String(localized: "In Pakistan: \(there)")
            : String(localized: "In Pakistan: about \(there)")
        return [yours, pakistan].joined(separator: " · ")
    }
}

// MARK: - Reminders menu

enum ZikrReminderSummary {
    /// The Reminders menu's own line, saying what is switched on: "10 minutes
    /// before · When live", one of them, or "Off". `beforeEachSession` is nil
    /// when the schedule has no Daily Zikr session to remind before.
    static func text(beforeEachSession: Bool?, whenLive: Bool) -> String {
        var parts: [String] = []
        if beforeEachSession == true {
            parts.append(String(localized: "\(ZikrReminders.leadMinutes) minutes before"))
        }
        if whenLive {
            parts.append(String(localized: "When live"))
        }
        return parts.isEmpty ? String(localized: "Off") : parts.joined(separator: " · ")
    }
}

// MARK: - Tasbih tile

/// The counter used last, as the Tasbih tile shows it.
struct ZikrPracticeSummary: Equatable {
    let count: Int
    /// Towards its target, 0 to 1; nil for an open-ended counter.
    let progress: Double?

    static func latest(from counters: [TasbihCounter]) -> ZikrPracticeSummary? {
        guard let counter = counters.max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
        var progress: Double?
        if let target = counter.target, target > 0 {
            progress = min(1, Double(max(counter.count, 0)) / Double(target))
        }
        return ZikrPracticeSummary(count: counter.count, progress: progress)
    }
}
