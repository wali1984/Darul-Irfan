import Foundation

struct NearbyMasjid: Decodable, Identifiable, Sendable {
    struct Attribution: Decodable, Sendable {
        let provider: String
        let uri: String?
    }
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let attributions: [Attribution]

    var isValid: Bool {
        !id.isEmpty && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
    }
}

enum NearbyMasjidError: Error { case invalidLocation, unavailable, limitReached, invalidResponse }

/// Results exist only in the requesting screen's memory. Calling this service
/// is an explicit search action, never a background refresh or prefetch.
enum NearbyMasjidService {
    private struct Payload: Decodable { let items: [NearbyMasjid]; let attribution: String }
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    static func search(latitude: Double, longitude: Double, language: String) async throws -> [NearbyMasjid] {
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180 else {
            throw NearbyMasjidError.invalidLocation
        }
        var url = URLComponents(url: OfficialPlatformConfiguration.baseURL.appendingPathComponent("v1/masjids/nearby"), resolvingAgainstBaseURL: false)!
        let locale = Locale(identifier: "en_US_POSIX")
        url.queryItems = [URLQueryItem(name: "lat", value: String(format: "%.8f", locale: locale, latitude)),
                          URLQueryItem(name: "lon", value: String(format: "%.8f", locale: locale, longitude)),
                          URLQueryItem(name: "lang", value: language == "ur" ? "ur" : "en")]
        var request = URLRequest(url: url.url!)
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw NearbyMasjidError.invalidResponse }
        if response.statusCode == 429 { throw NearbyMasjidError.limitReached }
        guard response.statusCode == 200 else { throw NearbyMasjidError.unavailable }
        guard data.count <= 512_000 else { throw NearbyMasjidError.invalidResponse }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.attribution == "Google Maps", payload.items.count <= 20,
              payload.items.allSatisfy(\.isValid), Set(payload.items.map(\.id)).count == payload.items.count else {
            throw NearbyMasjidError.invalidResponse
        }
        return payload.items
    }
}
