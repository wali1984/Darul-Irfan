import Foundation

// MARK: - The official schedule

/// The official online zikr sessions as the app last knew them: the schedule
/// the administrators publish when there is one, otherwise the bundled one.
///
/// The Zikr tab loads the published schedule and hands it on (through
/// `WatchSyncService.updateZikrSessions`); remembering it here lets the
/// reminders, the widgets and Today's "Upcoming" card follow the same sessions
/// without each going to the network, including on a fresh install before
/// the Zikr tab has ever been opened.
enum OfficialZikrSchedule {
    private static let storageKey = "zikr.officialSessions"

    static func sessions() -> [ZikrSession] {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([ZikrSession].self, from: data),
           !stored.isEmpty {
            return stored
        }
        return SeedBundle.zikrSessions()
    }

    static func remember(_ sessions: [ZikrSession]) {
        guard !sessions.isEmpty, let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

// MARK: - Occurrences

enum ZikrOccurrences {
    /// The next `count` starts of `session` after `reference`, in order.
    ///
    /// A session announced against a prayer time (after Isha, before Fajr) is
    /// resolved for each day at Dar-ul-Irfan, since those times move by about
    /// a minute a day; without a calculator it keeps the time it was last
    /// resolved to.
    static func starts(
        of session: ZikrSession,
        after reference: Date,
        count: Int,
        calculator: (any PrayerCalculationServicing)?
    ) -> [Date] {
        var starts: [Date] = []
        var cursor = reference
        while starts.count < count {
            let next: Date?
            if session.zikrAnchor != nil, let calculator {
                next = ZikrAnchorResolver.nextStart(for: session, after: cursor, calculator: calculator)
            } else {
                next = ZikrScheduleMath.nextOccurrence(of: session, after: cursor)
            }
            guard let next, next >= cursor else { break }
            starts.append(next)
            cursor = next.addingTimeInterval(60)
        }
        return starts
    }

    /// The concrete occurrences the widgets and the Watch show: any session
    /// in progress at `reference`, then the next ones, `perSession` each.
    static func widgetSessions(
        for sessions: [ZikrSession],
        reference: Date,
        perSession: Int,
        calculator: (any PrayerCalculationServicing)?
    ) -> [WidgetZikrSession] {
        var occurrences: [WidgetZikrSession] = []
        for session in sessions {
            let duration = TimeInterval(max(session.durationMinutes, 1) * 60)
            // Start one session-length back so one already under way counts.
            let lookback = reference.addingTimeInterval(-TimeInterval(max(session.durationMinutes, 0) * 60))
            for start in starts(of: session, after: lookback, count: perSession, calculator: calculator) {
                let end = start.addingTimeInterval(duration)
                guard end > reference else { continue }
                occurrences.append(WidgetZikrSession(
                    id: "\(session.id)|\(Int(start.timeIntervalSince1970))",
                    title: session.title,
                    startsAt: start,
                    endsAt: end
                ))
            }
        }
        return occurrences.sorted { $0.startsAt < $1.startsAt }
    }
}

// MARK: - Reminders

/// Reminders before online zikr sessions.
///
/// Each used to be a single notification for the next session, set again
/// only when the Zikr tab (or a halqah's page) loaded, so a reminder fired
/// once and then stayed silent until the tab was opened again. A session now
/// keeps its next week of reminders scheduled, refreshed with the prayer
/// alerts (launch, foreground, settings changes) and whenever it is switched on.
enum ZikrReminders {
    /// Minutes before the start that a reminder fires.
    static let leadMinutes = 10

    /// Upcoming starts each session keeps a reminder for.
    static let occurrencesPerSession = 7

    /// The UserDefaults key and reminder id the Zikr tab keeps for an
    /// official session.
    static func reminderID(forSession sessionID: String) -> String {
        "zikrReminder.\(sessionID)"
    }

    /// The Tahajjud zikr is joined in the Paltalk room; Daily Zikr is
    /// followed inside the app.
    static func isTahajjud(_ session: ZikrSession) -> Bool {
        switch session.zikrAnchor {
        case .beforeFajr, .tahajjud:
            return true
        case .afterIsha, nil:
            return session.id == "zikr-tahajjud"
        }
    }

    /// What an official session's reminder says.
    static func body(for session: ZikrSession) -> String {
        if isTahajjud(session) {
            return String(localized: "Tahajjud Zikr begins soon. Join it on Paltalk from Darul Irfan.")
        }
        if session.id == "zikr-after-isha" {
            return String(localized: "Daily Zikr begins soon. Open Darul Irfan to join it live.")
        }
        return String(localized: "\(session.title) begins soon. Open Darul Irfan to join it live.")
    }

    /// When the reminders fire: `leadMinutes` before each start, or at the
    /// start itself once that earlier moment has passed.
    static func fireDates(forStarts starts: [Date], now: Date) -> [Date] {
        starts.compactMap { start in
            let early = start.addingTimeInterval(-TimeInterval(leadMinutes * 60))
            if early > now { return early }
            return start > now ? start : nil
        }
    }

    /// Schedules the next week of reminders for one session under `id` (an
    /// official session's key, or a halqah's), replacing any it had.
    static func schedule(
        _ session: ZikrSession,
        id: String,
        body: String,
        notifications: any NotificationScheduling,
        calculator: (any PrayerCalculationServicing)?,
        now: Date = Date()
    ) async {
        let starts = ZikrOccurrences.starts(
            of: session,
            after: now,
            count: occurrencesPerSession,
            calculator: calculator
        )
        await notifications.scheduleReminders(
            id: id,
            title: session.title,
            body: body,
            at: fireDates(forStarts: starts, now: now)
        )
    }

    /// Re-plans the reminders of the official sessions switched on in the
    /// Zikr tab, and clears those switched off.
    static func refreshOfficial(
        notifications: any NotificationScheduling,
        calculator: any PrayerCalculationServicing,
        now: Date = Date()
    ) async {
        for session in OfficialZikrSchedule.sessions() {
            let id = reminderID(forSession: session.id)
            if UserDefaults.standard.bool(forKey: id) {
                await schedule(
                    session,
                    id: id,
                    body: body(for: session),
                    notifications: notifications,
                    calculator: calculator,
                    now: now
                )
            } else {
                await notifications.cancelReminder(id: id)
            }
        }
    }
}
