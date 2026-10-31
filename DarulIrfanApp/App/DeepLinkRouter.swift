import Foundation
import Observation

// Where a notification, a widget, a link or another screen asks the app to go.
//
// A request used to travel as a single NotificationCenter post, heard only by
// the screens that already existed. Tapping a push while the app was closed,
// or a widget, posted it during the splash, before any screen was listening,
// so the app opened on Today; and the first "Open in the Quran" of a session
// switched to Read before the Read tab existed, so the ayah never opened. The
// router keeps each request until the screen that shows it takes it.
//
//     DeepLinkRouter.shared.open(.quranAyah(surah: 2, ayah: 255))
//     DeepLinkRouter.shared.open(path: "groups/usa")      // a push's path
//     DeepLinkRouter.shared.open(url: url)                // darulirfan://...
//
// RootView moves the tab bar for every request, once. The screen a request
// addresses takes it on appear and on each new request:
//
//     .onAppear { follow() }
//     .onChange(of: DeepLinkRouter.shared.requestCount) { follow() }
//     func follow() { if let id = DeepLinkRouter.shared.take(\.groupID) { ... } }

/// A place in the app.
enum AppRoute: Equatable, Sendable {
    /// Today, with the prayer times.
    case today
    /// The Qur'an reader; at a surah, and an ayah in it, when given.
    case quran(surah: Int?, ayah: Int?)
    case hadith
    /// The Zikr tab. `session` names an online zikr to show ("tahajjud").
    case zikr(session: String?)
    /// The official Daily Zikr broadcast, on the Zikr tab.
    case live
    case personalZikr
    /// The Halqah tab.
    case groups
    /// One Halqah.
    case group(id: String)
    /// Discover's official updates; one of them when given.
    case updates(itemID: String?)
    /// Discover's events; one of them when given.
    case events(eventID: String?)
    case media
    case library
    case topics

    static func quranAyah(surah: Int, ayah: Int?) -> AppRoute { .quran(surah: surah, ayah: ayah) }

    /// Reads "darulirfan://groups/usa", "groups/usa", "live/official-live",
    /// "zikr/tahajjud", "quran/2/255" or "quran". Exact names, never a
    /// substring: a Halqah called Liverpool is a group, not the live zikr.
    init?(path raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = text.range(of: "://") {
            guard text[..<separator.lowerBound].lowercased() == "darulirfan" else { return nil }
            text = String(text[separator.upperBound...])
        }
        let path = text.split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        let parts = path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        guard let head = parts.first?.lowercased() else { return nil }
        let second = parts.count > 1 ? parts[1] : nil
        let third = parts.count > 2 ? parts[2] : nil
        switch head {
        case "today", "prayer", "prayers":
            self = .today
        case "quran", "surah":
            let surah = second.flatMap { Int($0) }.flatMap { (1...114).contains($0) ? $0 : nil }
            let ayah = surah == nil ? nil : third.flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
            self = .quran(surah: surah, ayah: ayah)
        case "hadith":
            self = .hadith
        case "zikr":
            self = .zikr(session: second?.lowercased())
        case "personal-zikr":
            self = .personalZikr
        case "live":
            self = .live
        case "groups", "group", "halqah":
            if let id = second?.lowercased(), Self.isGroupID(id) {
                self = .group(id: id)
            } else {
                self = .groups
            }
        case "feed", "updates":
            self = .updates(itemID: second)
        case "events", "event":
            self = .events(eventID: second)
        case "media", "lectures":
            self = .media
        case "library":
            self = .library
        case "topics":
            self = .topics
        default:
            return nil
        }
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == "darulirfan" else { return nil }
        self.init(path: url.absoluteString)
    }

    /// The server names a Halqah by a slug of its name.
    private static func isGroupID(_ value: String) -> Bool {
        (1...40).contains(value.count)
            && value.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    // Typed views of a route, for `take`.

    var groupID: String? {
        if case .group(let id) = self { return id }
        return nil
    }

    /// The event an events route names, if it names one.
    var eventID: String? {
        if case .events(let id) = self { return id }
        return nil
    }

    /// The update an updates route names, if it names one.
    var updateID: String? {
        if case .updates(let id) = self { return id }
        return nil
    }

    /// Read-tab routes: the Qur'an or Hadith reader, or the books.
    var isRead: Bool {
        switch self {
        case .quran, .hadith, .library: return true
        default: return false
        }
    }
}

@MainActor
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    /// Counts every request, so asking for the same place twice still moves.
    private(set) var requestCount = 0
    /// The newest request, until the screen it addresses takes it.
    private(set) var pending: AppRoute?
    /// The newest request, until the tab bar has moved to it.
    @ObservationIgnored private var tabRequest: AppRoute?
    @ObservationIgnored private var lastURL: URL?
    @ObservationIgnored private var lastURLAt: Date = .distantPast

    /// Asks for `route`: the tab bar moves to it, and the screen it names
    /// takes it when it appears (or at once, if it is showing).
    func open(_ route: AppRoute) {
        pending = route
        tabRequest = route
        requestCount &+= 1
    }

    /// A push's `path`, or a path one of the app's screens names.
    @discardableResult
    func open(path: String) -> Bool {
        guard let route = AppRoute(path: path) else { return false }
        open(route)
        return true
    }

    /// A darulirfan:// link. The same link arriving twice at once (the scene
    /// root and the tab shell may both hear it) is one request.
    @discardableResult
    func open(url: URL) -> Bool {
        if url == lastURL, Date().timeIntervalSince(lastURLAt) < 1 { return true }
        guard let route = AppRoute(url: url) else { return false }
        lastURL = url
        lastURLAt = Date()
        open(route)
        return true
    }

    /// For the tab bar: where the newest request goes, once.
    func takeTabRequest() -> AppRoute? {
        defer { tabRequest = nil }
        return tabRequest
    }

    /// For a screen: the pending request's value when it is one this screen
    /// shows (`take(\.groupID)`), which then counts as delivered.
    func take<Value>(_ match: (AppRoute) -> Value?) -> Value? {
        guard let pending, let value = match(pending) else { return nil }
        self.pending = nil
        return value
    }

    /// Delivers the pending request if it is exactly `route`.
    func clear(_ route: AppRoute) {
        if pending == route { pending = nil }
    }
}
