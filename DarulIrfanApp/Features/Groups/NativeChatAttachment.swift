import Foundation

/// An app-owned copy outlives the file picker's temporary access grant.
struct NativeChatAttachment: Sendable {
    let url: URL
    let name: String
    let bytes: Int
    var isImage: Bool { ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) }
    static let maximumBytes = 20 * 1024 * 1024
    enum Failure: Error { case unavailable, tooLarge }

    static func prepare(_ source: URL) throws -> NativeChatAttachment {
        let granted = source.startAccessingSecurityScopedResource()
        defer { if granted { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(12)
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("halqa-\(UUID().uuidString).\(ext)")
        guard FileManager.default.createFile(atPath: target.path, contents: nil) else { throw Failure.unavailable }
        do {
            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            let output = try FileHandle(forWritingTo: target)
            defer { try? output.close() }
            var count = 0
            while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                count += chunk.count
                guard count <= maximumBytes else { throw Failure.tooLarge }
                try output.write(contentsOf: chunk)
            }
            guard count > 0 else { throw Failure.unavailable }
            return NativeChatAttachment(url: target, name: source.lastPathComponent, bytes: count)
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }

    func discard() { try? FileManager.default.removeItem(at: url) }
}
