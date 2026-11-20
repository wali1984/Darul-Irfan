import Foundation
import Observation

/// A build of the app newer than the one running, and where to get it.
struct AppRelease: Equatable, Sendable {
    enum Channel: Equatable, Sendable { case testFlight, appStore }

    let channel: Channel
    let version: String
    /// The TestFlight build number; the App Store shows versions only.
    let build: Int?
    let url: URL
}

/// GET /v1/app/releases: the newest build out to the external testers, and
/// the newest out to the internal testers only, per platform. `{}` until a
/// release has been announced.
struct PublishedReleases: Decodable, Sendable {
    struct Build: Decodable, Sendable {
        let version: String
        let build: Int
    }

    struct Platform: Decodable, Sendable {
        let testflight: Build?
        /// The newest build the internal testers have; nil until announced.
        let internalTesters: Build?

        private enum CodingKeys: String, CodingKey {
            case testflight
            case internalTesters = "internal"
        }
    }

    let ios: Platform?
}

/// Finding a release newer than this build.
///
/// TestFlight has no lookup an app can ask, so the release script on the
/// team's PC (`Tools/Release/testflight.py announce`) writes the newest build
/// Apple has passed for the external testers to the server, with the newest
/// uploaded for the internal testers, and a TestFlight copy compares its build
/// number with those. An App Store copy asks Apple's own lookup for the
/// version in the store.
enum AppReleaseCheck {
    /// The app's Apple ID in App Store Connect.
    static let appleID = "6789375037"
    /// The app's page in the TestFlight app; the web address opens it too.
    static let testFlightURL = URL(string: "itms-beta://beta.itunes.apple.com/v1/app/\(appleID)") ?? URL(fileURLWithPath: "/")
    static let testFlightWebURL = URL(string: "https://beta.itunes.apple.com/v1/app/\(appleID)") ?? URL(fileURLWithPath: "/")
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id\(appleID)") ?? URL(fileURLWithPath: "/")

    /// A TestFlight (or development) copy carries a sandbox receipt.
    static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// The newer release for this copy's channel, or nil when it is current
    /// or nothing could be read.
    static func newerRelease() async -> AppRelease? {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Int(info?["CFBundleVersion"] as? String ?? "") ?? 0
        if isTestFlight {
            guard let published = await publishedTestFlight() else { return nil }
            return newerTestFlight(published, thanBuild: build)
        }
        guard let latest = await latestAppStore() else { return nil }
        return isNewer(latest.version, than: version) ? latest : nil
    }

    /// The TestFlight build to offer, when it is later than this one.
    static func newerTestFlight(_ latest: PublishedReleases.Build, thanBuild current: Int) -> AppRelease? {
        guard latest.build > current else { return nil }
        return AppRelease(channel: .testFlight, version: latest.version, build: latest.build, url: testFlightURL)
    }

    /// The external testers' build when it is later than this one. Otherwise,
    /// on a build later than theirs, which only an internal tester can have,
    /// the internal testers' newest: an external tester is never offered a
    /// build they cannot install.
    static func newerTestFlight(_ published: PublishedReleases.Platform, thanBuild current: Int) -> AppRelease? {
        if let external = published.testflight, let offer = newerTestFlight(external, thanBuild: current) { return offer }
        guard let internalTesters = published.internalTesters, current > (published.testflight?.build ?? 0) else { return nil }
        return newerTestFlight(internalTesters, thanBuild: current)
    }

    /// Whether `candidate` is a later version than `current`, part by part:
    /// "1.12.0" follows "1.11.3", and "1.11" is the same as "1.11.0".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let new = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let old = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func publishedTestFlight() async -> PublishedReleases.Platform? {
        let url = OfficialPlatformConfiguration.baseURL.appendingPathComponent("v1/app/releases")
        guard let data = await fetch(url) else { return nil }
        return (try? JSONDecoder().decode(PublishedReleases.self, from: data))?.ios
    }

    private struct AppStoreLookup: Decodable {
        struct Result: Decodable {
            let version: String
            let trackViewUrl: URL?
        }

        let results: [Result]
    }

    /// The version in the App Store of the phone's own country.
    private static func latestAppStore() async -> AppRelease? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        var items = [URLQueryItem(name: "id", value: appleID)]
        if let region = Locale.current.region?.identifier {
            items.append(URLQueryItem(name: "country", value: region))
        }
        components?.queryItems = items
        guard let url = components?.url, let data = await fetch(url),
              let result = (try? JSONDecoder().decode(AppStoreLookup.self, from: data))?.results.first else { return nil }
        return AppRelease(channel: .appStore, version: result.version, build: nil, url: result.trackViewUrl ?? appStoreURL)
    }

    private static func fetch(_ url: URL) async -> Data? {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return result.0
    }
}

/// When the update check is due (owner 2026-11-19: the banner must appear
/// in real time, without closing the app). While the app is in front it is
/// checked every five minutes; coming to the front, when the last check is
/// more than two minutes old. The server caches the feed for a minute.
enum AppUpdateTiming {
    enum Event: Equatable, Sendable {
        /// The app came to the front (or finished launching).
        case foreground
        /// The five-minute tick while the app is in front.
        case tick
    }

    static let foregroundInterval: TimeInterval = 120
    static let tickInterval: TimeInterval = 300
    /// A tick a few seconds early still counts, so a timer that fires a
    /// little before the five minutes are up never skips a whole round.
    static let tickTolerance: TimeInterval = 10

    static func isDue(lastChecked: Date?, now: Date, event: Event) -> Bool {
        guard let lastChecked else { return true }
        let elapsed = now.timeIntervalSince(lastChecked)
        switch event {
        case .foreground: return elapsed >= foregroundInterval
        case .tick: return elapsed >= tickInterval - tickTolerance
        }
    }
}

/// Whether the update banner shows, over every main tab.
///
/// The release is checked when the app is opened, each time it comes back to
/// the front (when the last check is two minutes old), and every five
/// minutes while it stays in front (`runWhileActive`). Close and Cancel hide
/// the banner only until the app is next opened: back from the background,
/// it shows again while the newer release is out.
@Observable
@MainActor
final class AppUpdateChecker {
    static let shared = AppUpdateChecker()

    private(set) var available: AppRelease?
    private(set) var isDismissed = false
    @ObservationIgnored private var leftForBackground = false
    @ObservationIgnored private(set) var lastChecked: Date?
    @ObservationIgnored private var isChecking = false
    private let check: @Sendable () async -> AppRelease?

    init(check: @escaping @Sendable () async -> AppRelease? = { await AppReleaseCheck.newerRelease() }) {
        self.check = check
    }

    /// The release the banner offers now.
    var banner: AppRelease? { isDismissed ? nil : available }

    func dismiss() {
        isDismissed = true
    }

    func appEnteredBackground() {
        leftForBackground = true
    }

    /// The app is in front: opened from the background it shows the banner
    /// again, and the release is checked when it is due.
    func appBecameActive(now: Date = Date()) {
        if leftForBackground {
            leftForBackground = false
            isDismissed = false
        }
        checkIfDue(.foreground, now: now)
    }

    /// The five-minute tick while the app is in front.
    func tick(now: Date = Date()) {
        checkIfDue(.tick, now: now)
    }

    /// Ticks every five minutes until the task is cancelled, which the
    /// banner's view does when the app leaves the front.
    func runWhileActive() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(AppUpdateTiming.tickInterval))
            guard !Task.isCancelled else { return }
            tick()
        }
    }

    /// Starts a check when `event` makes one due and none is under way;
    /// whether it started.
    @discardableResult
    func checkIfDue(_ event: AppUpdateTiming.Event, now: Date = Date()) -> Bool {
        guard !isChecking, AppUpdateTiming.isDue(lastChecked: lastChecked, now: now, event: event) else { return false }
        isChecking = true
        Task {
            await refresh()
            isChecking = false
        }
        return true
    }

    func refresh() async {
        available = await check()
        lastChecked = Date()
    }
}
