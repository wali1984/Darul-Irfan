import Foundation

/// Live SQLite-backed implementation of `TrackerRepositoryProtocol`.
/// Column names follow schema v1 in `AppDatabase.migrationV1` exactly.
///
/// Enum handling on read: a `prayer_log` row whose `prayer` or `completion`
/// raw value is unknown is skipped, so future values never crash old builds.
struct TrackerRepository: TrackerRepositoryProtocol {
    private let database: AppDatabase

    /// IN-clause chunk size, kept well under SQLite's parameter limit.
    private static let dayKeyChunkSize = 400

    init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Prayer log

    func prayerLog(dayKeys: [String]) async throws -> [PrayerLogEntry] {
        guard !dayKeys.isEmpty else { return [] }
        var entries: [PrayerLogEntry] = []
        for chunk in Self.chunked(dayKeys, size: Self.dayKeyChunkSize) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let rows = try await database.connection.query(
                """
                SELECT day_key, prayer, completion, updated_at
                FROM prayer_log
                WHERE day_key IN (\(placeholders))
                ORDER BY day_key ASC
                """,
                chunk.map { SQLValue.text($0) }
            )
            for row in rows {
                guard
                    let dayKey = row.text("day_key"),
                    let prayerRaw = row.text("prayer"),
                    let prayer = Prayer(rawValue: prayerRaw),
                    let completionRaw = row.text("completion"),
                    let completion = PrayerCompletion(rawValue: completionRaw),
                    let updatedAt = row.date("updated_at")
                else { continue }
                entries.append(
                    PrayerLogEntry(
                        dayKey: dayKey,
                        prayer: prayer,
                        completion: completion,
                        updatedAt: updatedAt
                    )
                )
            }
        }
        return entries
    }

    func savePrayerLog(_ entry: PrayerLogEntry) async throws {
        try await database.connection.execute(
            """
            INSERT INTO prayer_log (day_key, prayer, completion, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(day_key, prayer) DO UPDATE SET
                completion = excluded.completion,
                updated_at = excluded.updated_at
            """,
            [
                .text(entry.dayKey),
                .text(entry.prayer.rawValue),
                .text(entry.completion.rawValue),
                .date(entry.updatedAt),
            ]
        )
    }

    func streakSummary(endingAt endDayKey: String, windowDays: Int) async throws -> PrayerStreakSummary {
        let days = max(1, windowDays)
        let endDate = Self.date(fromDayKey: endDayKey) ?? Date()
        // Oldest first, ending at endDayKey.
        let keys = DayKey.trailing(days, endingAt: endDate)
        let entries = try await prayerLog(dayKeys: keys)

        var completionsByDay: [String: [Prayer: PrayerCompletion]] = [:]
        for entry in entries {
            completionsByDay[entry.dayKey, default: [:]][entry.prayer] = entry.completion
        }

        // A day is complete when all five obligatory prayers are marked
        // prayed or jamaat. A day with no marks is simply not complete.
        func isComplete(_ dayKey: String) -> Bool {
            guard let marks = completionsByDay[dayKey] else { return false }
            return Prayer.obligatory.allSatisfy { prayer in
                let completion = marks[prayer]
                return completion == .prayed || completion == .jamaat
            }
        }

        var bestStreak = 0
        var runningStreak = 0
        for key in keys {
            if isComplete(key) {
                runningStreak += 1
                if runningStreak > bestStreak {
                    bestStreak = runningStreak
                }
            } else {
                runningStreak = 0
            }
        }

        // Current streak counts back from the end day. If the end day is
        // today's still-in-progress civil day and not yet complete, it is a
        // grace day: skip it and keep counting from the previous day, so an
        // unfinished today never resets an otherwise unbroken run. Only an
        // incomplete day strictly before the end day breaks the streak.
        var currentStreak = 0
        let todayKey = DayKey.make(from: Date())
        var isEndDay = true
        for key in keys.reversed() {
            if isComplete(key) {
                currentStreak += 1
            } else if isEndDay && key == todayKey {
                // Grace day: today is not over yet; continue with yesterday.
            } else {
                break
            }
            isEndDay = false
        }

        var fulfilledCount = 0
        for entry in entries where entry.prayer.isObligatory {
            if entry.completion == .prayed || entry.completion == .jamaat {
                fulfilledCount += 1
            }
        }
        let totalSlots = Double(Prayer.obligatory.count * days)
        let completionRate: Double
        if totalSlots > 0 {
            completionRate = min(1.0, Double(fulfilledCount) / totalSlots)
        } else {
            completionRate = 0
        }

        return PrayerStreakSummary(
            currentStreakDays: currentStreak,
            bestStreakDays: bestStreak,
            completionRate: completionRate,
            windowDays: days
        )
    }

    // MARK: - Fasting log

    func fastingLog(dayKeys: [String]) async throws -> [FastingLogEntry] {
        guard !dayKeys.isEmpty else { return [] }
        var entries: [FastingLogEntry] = []
        for chunk in Self.chunked(dayKeys, size: Self.dayKeyChunkSize) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let rows = try await database.connection.query(
                """
                SELECT day_key, fasted, updated_at
                FROM fasting_log
                WHERE day_key IN (\(placeholders))
                ORDER BY day_key ASC
                """,
                chunk.map { SQLValue.text($0) }
            )
            for row in rows {
                guard
                    let dayKey = row.text("day_key"),
                    let updatedAt = row.date("updated_at")
                else { continue }
                entries.append(
                    FastingLogEntry(
                        dayKey: dayKey,
                        fasted: row.bool("fasted"),
                        updatedAt: updatedAt
                    )
                )
            }
        }
        return entries
    }

    func saveFastingLog(_ entry: FastingLogEntry) async throws {
        try await database.connection.execute(
            """
            INSERT INTO fasting_log (day_key, fasted, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(day_key) DO UPDATE SET
                fasted = excluded.fasted,
                updated_at = excluded.updated_at
            """,
            [
                .text(entry.dayKey),
                .bool(entry.fasted),
                .date(entry.updatedAt),
            ]
        )
    }

    // MARK: - Tasbih counters

    func tasbihCounters() async throws -> [TasbihCounter] {
        let rows = try await database.connection.query(
            """
            SELECT id, title, target, count, lifetime_count, updated_at
            FROM tasbih_counters
            ORDER BY updated_at DESC
            """
        )
        return rows.compactMap { row in
            guard
                let idText = row.text("id"),
                let id = UUID(uuidString: idText),
                let title = row.text("title"),
                let updatedAt = row.date("updated_at")
            else { return nil }
            return TasbihCounter(
                id: id,
                title: title,
                target: row.int("target"),
                count: row.int("count") ?? 0,
                lifetimeCount: row.int("lifetime_count") ?? 0,
                updatedAt: updatedAt
            )
        }
    }

    func saveTasbihCounter(_ counter: TasbihCounter) async throws {
        try await database.connection.execute(
            """
            INSERT INTO tasbih_counters (id, title, target, count, lifetime_count, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                target = excluded.target,
                count = excluded.count,
                lifetime_count = excluded.lifetime_count,
                updated_at = excluded.updated_at
            """,
            [
                .text(counter.id.uuidString),
                .text(counter.title),
                .optionalInt(counter.target),
                .int(counter.count),
                .int(counter.lifetimeCount),
                .date(counter.updatedAt),
            ]
        )
    }

    func deleteTasbihCounter(id: UUID) async throws {
        try await database.connection.execute(
            "DELETE FROM tasbih_counters WHERE id = ?",
            [.text(id.uuidString)]
        )
    }

    // MARK: - Zikr habit

    func zikrHabit(dayKeys: [String]) async throws -> [ZikrHabitEntry] {
        guard !dayKeys.isEmpty else { return [] }
        var entries: [ZikrHabitEntry] = []
        for chunk in Self.chunked(dayKeys, size: Self.dayKeyChunkSize) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let rows = try await database.connection.query(
                """
                SELECT day_key, completed_count, updated_at
                FROM zikr_habit
                WHERE day_key IN (\(placeholders))
                ORDER BY day_key ASC
                """,
                chunk.map { SQLValue.text($0) }
            )
            for row in rows {
                guard
                    let dayKey = row.text("day_key"),
                    let updatedAt = row.date("updated_at")
                else { continue }
                entries.append(
                    ZikrHabitEntry(
                        dayKey: dayKey,
                        completedCount: row.int("completed_count") ?? 0,
                        updatedAt: updatedAt
                    )
                )
            }
        }
        return entries
    }

    func saveZikrHabit(_ entry: ZikrHabitEntry) async throws {
        try await database.connection.execute(
            """
            INSERT INTO zikr_habit (day_key, completed_count, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(day_key) DO UPDATE SET
                completed_count = excluded.completed_count,
                updated_at = excluded.updated_at
            """,
            [
                .text(entry.dayKey),
                .int(entry.completedCount),
                .date(entry.updatedAt),
            ]
        )
    }

    // MARK: - Helpers

    /// Parses a "yyyy-MM-dd" day key back into a Date anchored at midday
    /// (midday keeps day arithmetic safe across DST transitions).
    private static func date(fromDayKey dayKey: String) -> Date? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: components)
    }

    private static func chunked(_ values: [String], size: Int) -> [[String]] {
        guard size > 0 else { return [values] }
        var chunks: [[String]] = []
        var index = 0
        while index < values.count {
            let end = min(index + size, values.count)
            chunks.append(Array(values[index..<end]))
            index = end
        }
        return chunks
    }
}
