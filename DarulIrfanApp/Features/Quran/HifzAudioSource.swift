import CryptoKit
import Foundation

/// Compositions need random access to the complete source recording. A reader
/// can stream an MP3, but practice must not assemble repeated remote ranges
/// while an unrelated background download is still in progress.
@MainActor
enum HifzAudioSource {
    enum Failure: Error { case invalidResponse, emptyAudio }

    static func localURL(
        for remote: URL,
        directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hifz-audio", isDirectory: true),
        download: (URL) async throws -> (URL, URLResponse) = { try await URLSession.shared.download(from: $0) }
    ) async throws -> URL {
        try Task.checkCancellation()
        if remote.isFileURL {
            try HifzComposition.requireReadableLocalAudio(remote)
            return remote
        }
        guard remote.scheme == "https" else { throw Failure.invalidResponse }
        let digest = SHA256.hash(data: Data(remote.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let local = directory.appendingPathComponent(digest).appendingPathExtension("mp3")
        if let size = try? local.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
           size.isRegularFile == true, (size.fileSize ?? 0) > 0 { return local }
        if FileManager.default.fileExists(atPath: local.path) {
            try HifzComposition.requireReadableLocalAudio(local)
            try FileManager.default.removeItem(at: local)
        }
        let (temporary, response) = try await download(remote)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.mimeType?.hasPrefix("audio/") == true || response.mimeType == "application/octet-stream" else {
            throw Failure.invalidResponse
        }
        let values = try temporary.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { throw Failure.emptyAudio }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Another preparation may have completed while this request awaited.
        // Never replace a file an active composition may already be reading.
        if !FileManager.default.fileExists(atPath: local.path) {
            try FileManager.default.moveItem(at: temporary, to: local)
        }
        return local
    }
}
