import Foundation

/// Private scratch files for one practice screen. The recorder must validate
/// that a clip decodes before accepting it; byte checks are not audio validation.
/// Call only from the owning recording controller, serially on the main actor.
@MainActor
final class RecitationPracticeFiles {
    enum Failure: Error { case closed, foreignFile, invalidSize, invalidDuration }
    static let maximumBytes: Int64 = 10 * 1024 * 1024
    static let maximumDuration: Double = 300
    private let directory: URL
    private let manager: FileManager
    private var pending: URL?
    private var closed = false
    private(set) var current: URL?

    init(cacheDirectory: URL, manager: FileManager = .default) throws {
        self.manager = manager
        directory = cacheDirectory.appendingPathComponent("recitation-practice", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
    }

    func begin() throws -> URL {
        guard !closed else { throw Failure.closed }
        if let pending { try removeIfPresent(pending) }
        let file = directory.appendingPathComponent(UUID().uuidString + ".m4a")
        try Data().write(to: file, options: .atomic)
        pending = file
        return file
    }

    /// Accept only the latest owned recording after the recorder has stopped and
    /// a decoder has supplied its duration. A failed replacement keeps current.
    func accept(_ file: URL, decodedDuration: Double) throws {
        guard !closed else { throw Failure.closed }
        guard file == pending else { throw Failure.foreignFile }
        guard decodedDuration.isFinite, decodedDuration > 0,
              decodedDuration <= Self.maximumDuration + 1 else { throw Failure.invalidDuration }
        let attributes = try manager.attributesOfItem(atPath: file.path)
        let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              bytes > 0, bytes <= Self.maximumBytes else { throw Failure.invalidSize }
        if let current { try removeIfPresent(current) }
        current = file
        pending = nil
    }

    func discardPending() throws {
        if let pending { try removeIfPresent(pending) }
        pending = nil
    }

    func deleteCurrent() throws {
        if let current { try removeIfPresent(current) }
        current = nil
    }

    /// Closing invalidates late callbacks even when cleanup itself fails. The
    /// caller can retry cleanup; errors must not be reported as successful erase.
    func close() throws {
        closed = true
        try removeIfPresent(directory)
        pending = nil
        current = nil
    }

    private func removeIfPresent(_ file: URL) throws {
        if manager.fileExists(atPath: file.path) { try manager.removeItem(at: file) }
    }
}
