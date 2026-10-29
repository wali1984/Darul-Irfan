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

/// GET /v1/app/releases: the newest build out to the external testers, per
/// platform. `{}` until a release has been announced.
struct PublishedReleases: Decodable, Sendable {
    struct Build: Decodable, Sendable {
        let version: String
        let build: Int
    }

    struct Platform: Decodable, Sendable {
        let testflight: Build?
    }

    let ios: Platform?
}

/// Finding a release newer than this build.
///
/// TestFlight has no lookup an app can ask, so the release script on the
/// team's PC (`Tools/Release/testflight.py announce`) writes the newest build
/// Apple has passed for the external testers to the server, and a TestFlight
/// copy compares its build number with that. An App Store copy asks Apple's
/// own lookup for the version in the store.
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
            guard let latest = await latestTestFlight() else { return nil }
            return newerTestFlight(latest, thanBuild: build)
        }
        guard let latest = await latestAppStore() else { return nil }
        return isNewer(latest.version, than: version) ? latest : nil
    }

    /// The TestFlight build to offer, when it is later than this one.
    static func newerTestFlight(_ latest: PublishedReleases.Build, thanBuild current: Int) -> AppRelease? {
        guard latest.build > current else { return nil }
        return AppRelease(channel: .testFlight, version: latest.version, build: latest.build, url: testFlightURL)
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

    private static func latestTestFlight() async -> PublishedReleases.Build? {
        let url = OfficialPlatformConfiguration.baseURL.appendingPathComponent("v1/app/releases")
        guard let data = await fetch(url) else { return nil }
        return (try? JSONDecoder().decode(PublishedReleases.self, from: data))?.ios?.testflight
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

/// Whether Today shows the update banner.
///
/// The release is checked when the app is opened and each time it comes back
/// from the background (at most every ten minutes; the server caches five).
/// Close and Cancel hide the banner only until the app is next opened: back
/// from the background, it shows again while the newer release is out.
@Observable
@MainActor
final class AppUpdateChecker {
    static let shared = AppUpdateChecker()

    private(set) var available: AppRelease?
    private(set) var isDismissed = false
    @ObservationIgnored private var leftForBackground = false
    @ObservationIgnored private var lastChecked: Date?
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
    func appBecameActive() {
        if leftForBackground {
            leftForBackground = false
            isDismissed = false
        }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < 600 { return }
        guard !isChecking else { return }
        isChecking = true
        Task {
            await refresh()
            isChecking = false
        }
    }

    func refresh() async {
        available = await check()
        lastChecked = Date()
    }
}
