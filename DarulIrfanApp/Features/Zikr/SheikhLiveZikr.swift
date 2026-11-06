import Foundation

/// The Silsila's own live Zikr, held in Our Sheikh's Halqah (owner,
/// 2026-11-06: "we use our stream for daily zikr and our relay for tahajjud
/// zikr"). Both sessions happen in the same Paltalk room, which the relay
/// hears and feeds into the app's own live sound, so every Join - Today's
/// strip, the Zikr tab's cards, a Halqah's live card and the live-zikr
/// notifications - opens Our Sheikh's live stage with that sound: never the
/// Paltalk app, never the YouTube stream. Android SheikhLiveZikr.
struct SheikhLiveZikr: Equatable, Sendable {
    /// Which of the two sessions a live Zikr is.
    enum Session: Equatable, Sendable {
        case daily
        case tahajjud
    }

    /// When the Zikr began, as the server says.
    var startedAt: Date?
    /// The stage being followed now, as it was announced.
    var stageTitle: String?
    var stageTitleUr: String?
    var stageAt: Date?

    /// The session a live Zikr is at `now`: before 07:00 in Pakistan the
    /// Tahajjud zikr, otherwise Daily Zikr (the server's `zikrTitle`; the
    /// same room carries both).
    static func session(at now: Date) -> Session {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Karachi") ?? TimeZone(secondsFromGMT: 5 * 3600) ?? .current
        return calendar.component(.hour, from: now) < 7 ? .tahajjud : .daily
    }

    /// The session live now; nil while Our Sheikh's Zikr is not live.
    static func liveSession(_ live: SheikhLiveZikr?, at now: Date) -> Session? {
        live == nil ? nil : session(at: now)
    }

    /// The stage now, in the app's language; nil before the first one.
    func stage(urdu: Bool) -> String? {
        func clean(_ text: String?) -> String? {
            guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
            return trimmed
        }
        return urdu ? clean(stageTitleUr) ?? clean(stageTitle) : clean(stageTitle)
    }

    /// Our Sheikh's entry in `GET /v1/public/live?ids=our-sheikh` (the
    /// websites' route, no sign-in); nil while nothing is live. A test Zikr
    /// belongs to its admins (nobody is told of it), so it never makes the
    /// official Join live.
    static func parse(_ data: Data, decoder: JSONDecoder = .darulIrfanServer()) -> SheikhLiveZikr? {
        guard let response = try? decoder.decode(PublicLive.self, from: data),
              let sheikh = response.halqahs.first(where: { $0.id == HalqahStage.ourSheikhID }),
              let live = sheikh.live,
              live.kind == nil || live.kind == "zikr",
              live.isTest != true else { return nil }
        return SheikhLiveZikr(startedAt: live.startedAt, stageTitle: sheikh.stage?.title,
                              stageTitleUr: sheikh.stage?.titleUr, stageAt: sheikh.stage?.at)
    }

    private struct PublicLive: Decodable {
        let halqahs: [Halqah]
    }

    private struct Halqah: Decodable {
        let id: String
        let live: Live?
        let stage: Stage?
    }

    private struct Live: Decodable {
        let kind: String?
        let isTest: Bool?
        let startedAt: Date?
    }

    private struct Stage: Decodable {
        let title: String?
        let titleUr: String?
        let at: Date?
    }
}

extension AppRoute {
    /// Where a tapped notification goes. The official live-zikr notices
    /// ("Daily Zikr has started", a host's cue, "Tahajjud Zikr has started")
    /// open Our Sheikh's live stage, where the Zikr is heard in the app, and
    /// so do Our Sheikh's own Halqah notices (the Zikr has started, a stage, a
    /// notice: each sent only while its Zikr is live); every other notice goes
    /// where its path says.
    static func notification(path: String) -> AppRoute? {
        guard let route = AppRoute(path: path) else { return nil }
        if route == .live || route == .zikr(session: "tahajjud") || route == .group(id: HalqahStage.ourSheikhID) {
            return .sheikhStage
        }
        return route
    }
}

/// The Shajra on the live stage (cue "shajra", after Masjid-e-Nabawi and
/// before the Dua): its lines rise slowly through the stage card, from the
/// first to the last, and stop there, the whole roll in under a minute
/// (owner, 2026-11-06: "shajra should be shown in less than 60 sec rolling";
/// about 51 s, as the websites). Android ShajraStageScroll.
enum ShajraStageScroll {
    /// The first lines stay still this long before they begin to move.
    static let lead: TimeInterval = 2
    /// How long each line takes to pass.
    static let perLine: TimeInterval = 3.5

    /// The lines that pass: each link of the chain, then the closing dua.
    static var lineCount: Int { ShajraText.entries.count + 1 }

    /// How long the rise takes, from the first line to the last.
    static var duration: TimeInterval { perLine * Double(lineCount) }

    /// How far through the rise the stage is, 0 to 1, `elapsed` seconds after
    /// the Shajra was announced: a stage opened late joins it where it is,
    /// and one opened after the end shows the last line.
    static func progress(elapsed: TimeInterval) -> Double {
        guard elapsed.isFinite else { return 0 }
        return min(max((elapsed - lead) / duration, 0), 1)
    }

    /// Seconds of rise left at `elapsed`.
    static func remaining(elapsed: TimeInterval) -> TimeInterval {
        duration * (1 - progress(elapsed: elapsed))
    }

    /// Seconds the first lines still stay still at `elapsed`.
    static func stillLeft(elapsed: TimeInterval) -> TimeInterval {
        elapsed.isFinite ? max(lead - elapsed, 0) : lead
    }
}
