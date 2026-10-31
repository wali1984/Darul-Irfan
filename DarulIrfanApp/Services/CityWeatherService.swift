import Foundation

struct WeatherCityGrid: Equatable, Sendable {
    let latitude: String
    let longitude: String
    var key: String { "\(latitude),\(longitude)" }
    init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        func coarse(_ value: Double) -> String {
            let rounded = floor(value * 10 + 0.5) / 10
            return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded == 0 ? 0 : rounded)
        }
        self.latitude = coarse(latitude); self.longitude = coarse(longitude)
    }
}

struct CityWeatherSnapshot: Codable, Sendable {
    static func deviceUnit(locale: Locale = .autoupdatingCurrent) -> String {
        UnitTemperature(forLocale: locale) == .fahrenheit ? "F" : "C"
    }
    let temperatureCelsius: Double
    let feelsLikeCelsius: Double
    let humidity: Double
    let isDaylight: Bool
    let observedAt: Date
    let expiresAt: Date
    func usable(at now: Date) -> Bool {
        temperatureCelsius.isFinite && (-100...70).contains(temperatureCelsius) && feelsLikeCelsius.isFinite
            && humidity.isFinite && (0...1).contains(humidity)
            && now.timeIntervalSince(observedAt) <= 3600 && observedAt.timeIntervalSince(now) <= 300
    }
    static func temperature(_ celsius: Double, unit: String, locale: Locale = .current) -> String {
        let value = unit == "F" ? celsius * 9 / 5 + 32 : celsius
        let format = NumberFormatter(); format.locale = locale; format.maximumFractionDigits = 0
        return "\(format.string(from: NSNumber(value: value)) ?? "")°\(unit == "F" ? "F" : "C")"
    }
}

/// The app never holds Apple's signing key or developer token. Only the
/// selected city's 0.1-degree grid is sent to the shared WeatherKit service.
actor CityWeatherService {
    static let shared = CityWeatherService()
    private struct Cached: Codable { let grid: String; let value: CityWeatherSnapshot }
    private let defaults = UserDefaults.standard
    private let cacheKey = "today.weather.cache"

    func current(for grid: WeatherCityGrid) async -> CityWeatherSnapshot? {
        let now = Date()
        let saved = defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(Cached.self, from: $0) }
        let cached = saved?.grid == grid.key && saved?.value.usable(at: now) == true ? saved?.value : nil
        if let cached, cached.expiresAt > now { return cached }
        var url = URLComponents(url: OfficialPlatformConfiguration.baseURL.appendingPathComponent("v1/weather/current"), resolvingAgainstBaseURL: false)
        url?.queryItems = [URLQueryItem(name: "lat", value: grid.latitude), URLQueryItem(name: "lon", value: grid.longitude)]
        guard let url = url?.url else { return cached }
        do {
            var request = URLRequest(url: url); request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return cached }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let value = try decoder.decode(CityWeatherSnapshot.self, from: data)
            guard value.usable(at: Date()) else { return cached }
            defaults.set(try? JSONEncoder().encode(Cached(grid: grid.key, value: value)), forKey: cacheKey)
            return value
        } catch { return cached }
    }
}
