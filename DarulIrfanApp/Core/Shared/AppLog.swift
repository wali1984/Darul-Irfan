import Foundation
import OSLog

/// Privacy-preserving unified logging. MetricKit remains separately opt-in;
/// these local logs are never uploaded as free-form text.
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "us.naqshbaniaowaisiah"
    private static let contentLogger = Logger(subsystem: subsystem, category: "content")
    private static let searchLogger = Logger(subsystem: subsystem, category: "search")
    private static let presentationLogger = Logger(subsystem: subsystem, category: "presentation")

    static func content(_ message: String) {
        contentLogger.error("\(message, privacy: .private(mask: .hash))")
    }

    static func search(_ message: String) {
        searchLogger.error("\(message, privacy: .private(mask: .hash))")
    }

    static func presentation(_ message: String) {
        presentationLogger.debug("\(message, privacy: .private(mask: .hash))")
    }
}
