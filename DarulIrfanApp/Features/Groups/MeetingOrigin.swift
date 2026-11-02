import Foundation

/// Credentials and media permissions stay on the configured HTTPS origin.
enum MeetingOrigin {
    static func allows(_ address: URL?, trusted: URL) -> Bool {
        guard let address,
              let actual = URLComponents(url: address, resolvingAgainstBaseURL: false),
              let expected = URLComponents(url: trusted, resolvingAgainstBaseURL: false),
              actual.scheme?.lowercased() == "https", expected.scheme?.lowercased() == "https",
              actual.user == nil, actual.password == nil,
              expected.user == nil, expected.password == nil,
              let host = actual.host, host.lowercased() == expected.host?.lowercased() else { return false }
        return (actual.port ?? 443) == (expected.port ?? 443)
    }

    static func allows(scheme: String, host: String, port: Int, trusted: URL) -> Bool {
        var origin = URLComponents()
        origin.scheme = scheme
        origin.host = host
        // WKSecurityOrigin uses zero for an unspecified port.
        origin.port = port == 0 ? nil : port
        return allows(origin.url, trusted: trusted)
    }
}
