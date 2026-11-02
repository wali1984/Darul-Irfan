import Foundation

/// Private scratch files for one practice screen. The recorder must validate
/// that a clip decodes before accepting it; byte checks are not audio validation.
/// Call only from the owning recording controller, serially on the main actor.
@MainActor
final class RecitationPracticeFiles {
    enum Failure: Error { case closed, foreignFile, invalidSize, invalidDuration }
    static let maximumBytes: Int64 = 10 * 1024 * 1024
    static let maximumDuration: Double = 300
    private static var cleanedRoots: Set<URL> = []
    private let directory: URL
    private let manager: FileManager
    private var pending: URL?
    private var closed = false
    private(set) var current: URL?

    init(cacheDirectory: URL, manager: FileManager = .default) throws {
        self.manager = manager
        let root = cacheDirectory.appendingPathComponent("recitation-practice", isDirectory: true).standardizedFileURL
        try Self.cleanPreviousProcessFiles(root, manager: manager)
        directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
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

    /// Once per root/process, before any new screen owns a clip. Remove only
    /// this feature's UUID session/clip names, never links or unknown contents.
    private static func cleanPreviousProcessFiles(_ root: URL, manager: FileManager) throws {
        guard !cleanedRoots.contains(root) else { return }
        if manager.fileExists(atPath: root.path) {
            guard try manager.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType == .typeDirectory else {
                throw Failure.foreignFile
            }
            for folder in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                guard UUID(uuidString: folder.lastPathComponent) != nil,
                      try manager.attributesOfItem(atPath: folder.path)[.type] as? FileAttributeType == .typeDirectory else { continue }
                for clip in try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                    guard clip.pathExtension == "m4a", UUID(uuidString: clip.deletingPathExtension().lastPathComponent) != nil,
                          try manager.attributesOfItem(atPath: clip.path)[.type] as? FileAttributeType == .typeRegular else { continue }
                    try manager.removeItem(at: clip)
                }
                if try manager.contentsOfDirectory(atPath: folder.path).isEmpty { try manager.removeItem(at: folder) }
            }
        }
        cleanedRoots.insert(root)
    }
}
