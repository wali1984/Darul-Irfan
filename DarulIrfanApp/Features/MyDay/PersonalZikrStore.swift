import AVFoundation
import Foundation
import Observation
import UserNotifications

enum PersonalZikrStage: String, Codable, CaseIterable, Identifiable {
    case latifa1, latifa2, latifa3, latifa4, latifa5, latifa6, latifa7, raabta, ahadiyat, maiyyat, aqrabiyyat
    var id: String { rawValue }
    var title: String {
        switch self {
        case .latifa1: "1st Latifa"
        case .latifa2: "2nd Latifa"
        case .latifa3: "3rd Latifa"
        case .latifa4: "4th Latifa"
        case .latifa5: "5th Latifa"
        case .latifa6: "6th Latifa"
        case .latifa7: "7th Latifa"
        case .raabta: "Raabta"
        case .ahadiyat: "Muraqaba Ahadiyat"
        case .maiyyat: "Muraqaba Ma'iyyat"
        case .aqrabiyyat: "Muraqaba Aqrabiyyat"
        }
    }
}

struct PersonalZikrStep: Codable, Equatable, Identifiable {
    var stage: PersonalZikrStage
    var minutes = 1
    var customID: String?
    var customTitle: String?
    var id: String { customID ?? stage.rawValue }
    var title: String { customTitle ?? stage.title }
    var localizedTitle: String { customTitle ?? String(localized: String.LocalizationValue(stage.title)) }
}

enum PersonalZikrMath {
    static func valid(_ plan: [PersonalZikrStep]) -> Bool {
        guard !plan.isEmpty, plan.count <= 35, Set(plan.map(\.id)).count == plan.count,
              plan.allSatisfy({ (1...60).contains($0.minutes) && ($0.customID == nil || !($0.customTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }) else { return false }
        return zip(plan, plan.dropFirst()).allSatisfy { a, b in
            if b.customID != nil { return true }
            return a.customID == nil && PersonalZikrStage.allCases.firstIndex(of: a.stage)! < PersonalZikrStage.allCases.firstIndex(of: b.stage)!
        }
    }
    static func total(_ plan: [PersonalZikrStep]) -> TimeInterval { plan.reduce(0) { $0 + Double($1.minutes * 60) } }
    static func position(_ plan: [PersonalZikrStep], elapsed: TimeInterval) -> (index: Int, step: PersonalZikrStep, remaining: TimeInterval)? {
        guard valid(plan) else { return nil }
        var elapsed = max(0, elapsed)
        for (index, step) in plan.enumerated() {
            let duration = Double(step.minutes * 60)
            if elapsed < duration { return (index, step, duration - elapsed) }
            elapsed -= duration
        }
        return nil
    }
    static func text(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct PersonalZikrRun: Codable, Equatable {
    var id = UUID().uuidString
    var plan: [PersonalZikrStep]
    var firstStartedAt: Date
    var startedAt: Date?
    var elapsedBeforeRun: TimeInterval = 0
    func elapsed(at now: Date) -> TimeInterval {
        min(PersonalZikrMath.total(plan), max(0, elapsedBeforeRun + (startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)))
    }
    var endsAt: Date? { startedAt?.addingTimeInterval(PersonalZikrMath.total(plan) - elapsedBeforeRun) }
}

struct PersonalZikrEntry: Codable, Equatable, Identifiable {
    var id: String
    var startedAt: Date
    var endedAt: Date
    var duration: TimeInterval
}

struct PersonalZikrReminder: Codable, Equatable {
    var enabled = false
    var minuteOfDay: Int
}

enum PersonalZikrHistory {
    static func retained(_ entries: [PersonalZikrEntry], now: Date, calendar: Calendar = .current) -> [PersonalZikrEntry] {
        let cutoff = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        var seen = Set<String>()
        return entries.filter { $0.endedAt >= cutoff && $0.endedAt <= now && $0.duration > 0 && seen.insert($0.id).inserted }.sorted { $0.endedAt > $1.endedAt }
    }
}

@MainActor @Observable
final class PersonalZikrStore {
    static let shared = PersonalZikrStore()
    private(set) var plan = PersonalZikrStage.allCases.map { PersonalZikrStep(stage: $0) }
    private(set) var customs: [PersonalZikrStep] = []
    private(set) var run: PersonalZikrRun?
    private(set) var history: [PersonalZikrEntry] = []
    private(set) var reminders = [PersonalZikrReminder(minuteOfDay: 420), PersonalZikrReminder(minuteOfDay: 1200)]
    var screenActive = false
    private var chime: AVAudioPlayer?
    private var alertRevision = 0
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved: [PersonalZikrStep] = decode("personalZikr.plan"), saved.isEmpty || PersonalZikrMath.valid(saved) { plan = saved }
        customs = decode("personalZikr.customs") ?? []
        if let saved: PersonalZikrRun = decode("personalZikr.run"), PersonalZikrMath.valid(saved.plan), saved.elapsedBeforeRun >= 0 { run = saved }
        history = decode("personalZikr.history") ?? []
        if let saved: [PersonalZikrReminder] = decode("personalZikr.reminders"), saved.count == 2, saved.allSatisfy({ (0..<1440).contains($0.minuteOfDay) }) { reminders = saved }
        history = PersonalZikrHistory.retained(history, now: .now)
        if let current = run, let end = current.endsAt, end <= .now { record(current, at: end); run = nil }
        save()
    }

    private func decode<T: Decodable>(_ key: String) -> T? { defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) } }
    private func put<T: Encodable>(_ value: T, _ key: String) { defaults.set(try? JSONEncoder().encode(value), forKey: key) }
    private func save() {
        put(plan, "personalZikr.plan"); put(customs, "personalZikr.customs"); put(history, "personalZikr.history"); put(reminders, "personalZikr.reminders")
        if let run { put(run, "personalZikr.run") } else { defaults.removeObject(forKey: "personalZikr.run") }
    }
    func storedMinutes(_ stage: PersonalZikrStage) -> Int { max(1, min(60, defaults.integer(forKey: "personalZikr.minutes.\(stage.rawValue)"))) }
    func configure(_ step: PersonalZikrStep, enabled: Bool) {
        guard run == nil else { return }
        var safe = step; safe.minutes = min(60, max(1, safe.minutes))
        if safe.customID != nil { customs = customs.map { $0.id == safe.id ? safe : $0 } }
        else { defaults.set(safe.minutes, forKey: "personalZikr.minutes.\(safe.stage.rawValue)") }
        plan.removeAll { $0.id == safe.id }
        if enabled { plan.append(safe) }
        let builtins = plan.filter { $0.customID == nil }.sorted { PersonalZikrStage.allCases.firstIndex(of: $0.stage)! < PersonalZikrStage.allCases.firstIndex(of: $1.stage)! }
        plan = builtins + customs.filter { custom in plan.contains { $0.id == custom.id } }
        save()
    }
    func addCustom(_ title: String) {
        let title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard run == nil, !title.isEmpty, customs.count < 24 else { return }
        let step = PersonalZikrStep(stage: .aqrabiyyat, customID: UUID().uuidString, customTitle: title)
        customs.append(step); plan.append(step); save()
    }
    func removeCustom(_ id: String) {
        guard run == nil else { return }
        customs.removeAll { $0.id == id }; plan.removeAll { $0.id == id }; save()
    }
    func start(at now: Date = .now) {
        guard run != nil || PersonalZikrMath.valid(plan) else { return }
        if run == nil { run = PersonalZikrRun(plan: plan, firstStartedAt: now, startedAt: now) }
        else { run?.startedAt = now }
        FocusSession.shared.clear()
        save(); playChime(); refreshAlerts()
    }
    func pause(at now: Date = .now) {
        guard var current = run else { return }
        current.elapsedBeforeRun = current.elapsed(at: now); current.startedAt = nil; run = current
        save(); refreshAlerts()
    }
    func discard() { run = nil; save(); refreshAlerts() }
    func finish(at now: Date = .now) {
        guard let current = run else { return }
        record(current, at: min(now, current.endsAt ?? now)); run = nil; save(); refreshAlerts()
    }
    func settle(at now: Date = .now) {
        history = PersonalZikrHistory.retained(history, now: now)
        if let current = run, let end = current.endsAt, end <= now { finish(at: end) }
        save()
    }
    private func record(_ current: PersonalZikrRun, at now: Date) {
        let duration = current.elapsed(at: now)
        guard duration >= 1, !history.contains(where: { $0.id == current.id }) else { return }
        history.append(PersonalZikrEntry(id: current.id, startedAt: current.firstStartedAt, endedAt: now, duration: duration))
        history = PersonalZikrHistory.retained(history, now: .now)
    }
    func setReminder(_ index: Int, _ value: PersonalZikrReminder) { reminders[index] = value; save(); refreshAlerts() }
    func requestAlerts() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    func playChime() {
        guard let url = Bundle.main.url(forResource: "zikr_soft_chime", withExtension: "wav") else { return }
        chime = try? AVAudioPlayer(contentsOf: url); chime?.volume = 0.28; chime?.play()
    }
    func refreshAlerts() {
        alertRevision += 1
        let revision = alertRevision
        let current = run
        let reminders = reminders
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            guard revision == alertRevision else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("personal-zikr.") || $0 == "reminder|focus-session" })
            let title = String(localized: "Your Daily Personal Zikr")
            func content(_ body: String) -> UNMutableNotificationContent {
                let value = UNMutableNotificationContent(); value.title = title; value.body = body
                value.sound = UNNotificationSound(named: UNNotificationSoundName("zikr_soft_chime.wav"))
                value.userInfo = ["path": "personal-zikr"]
                return value
            }
            for (index, reminder) in reminders.enumerated() where reminder.enabled {
                guard revision == alertRevision else { return }
                let components = DateComponents(hour: reminder.minuteOfDay / 60, minute: reminder.minuteOfDay % 60)
                try? await center.add(UNNotificationRequest(identifier: "personal-zikr.daily.\(index)", content: content(title), trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
            }
            if let current, let start = current.startedAt {
                var elapsed: TimeInterval = 0
                for (index, step) in current.plan.enumerated() {
                    elapsed += Double(step.minutes * 60)
                    let at = start.addingTimeInterval(elapsed - current.elapsedBeforeRun)
                    guard at > Date() else { continue }
                    guard revision == alertRevision else { return }
                    let body = index + 1 < current.plan.count ? current.plan[index + 1].localizedTitle : String(localized: "Your personal Zikr session is complete.")
                    try? await center.add(UNNotificationRequest(identifier: "personal-zikr.stage.\(index)", content: content(body), trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, at.timeIntervalSinceNow), repeats: false)))
                }
            }
        }
    }
}
