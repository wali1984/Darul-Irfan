import CryptoKit
import Foundation

/// Compositions need random access to the complete source recording. A reader
/// can stream an MP3, but practice must not assemble repeated remote ranges
/// while an unrelated background download is still in progress.
@MainActor
enum HifzAudioSource {
    enum Failure: Error { case invalidResponse, emptyAudio }

    nonisolated static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hifz-audio", isDirectory: true)
    }

    /// `onProgress` reports 0...1 during the app's own transfer, when the
    /// server gives the file's size. An injected `download` reports nothing.
    static func localURL(
        for remote: URL,
        directory: URL = HifzAudioSource.cacheDirectory,
        download: ((URL) async throws -> (URL, URLResponse))? = nil,
        onProgress: @escaping @MainActor (Double) -> Void = { _ in }
    ) async throws -> URL {
        try Task.checkCancellation()
        if remote.isFileURL {
            try HifzComposition.requireReadableLocalAudio(remote)
            return remote
        }
        guard let local = cachedFile(for: remote, directory: directory) else { throw Failure.invalidResponse }
        if let size = try? local.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
           size.isRegularFile == true, (size.fileSize ?? 0) > 0 { return local }
        if FileManager.default.fileExists(atPath: local.path) {
            try HifzComposition.requireReadableLocalAudio(local)
            try FileManager.default.removeItem(at: local)
        }
        let transfer: (URL, URLResponse)
        if let download {
            transfer = try await download(remote)
        } else {
            transfer = try await tracked(remote, onProgress: onProgress)
        }
        let (temporary, response) = transfer
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

    /// Forgets the kept copy of a recording that would not load, so Retry can
    /// repair it. Audio already on the phone by its own address is never touched.
    static func discardCachedCopy(for remote: URL, directory: URL = HifzAudioSource.cacheDirectory) {
        guard let local = cachedFile(for: remote, directory: directory) else { return }
        try? FileManager.default.removeItem(at: local)
    }

    /// What Settings > Content & Storage counts for practice recordings.
    static func cacheSummary(directory: URL = HifzAudioSource.cacheDirectory) -> (bytes: Int64, files: Int) {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        var bytes: Int64 = 0
        var count = 0
        for file in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            bytes += Int64(values.fileSize ?? 0)
            count += 1
        }
        return (bytes, count)
    }

    /// Removes every kept recording; returns how many would not go.
    static func clearCache(directory: URL = HifzAudioSource.cacheDirectory) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var failed = 0
        for file in files {
            do { try FileManager.default.removeItem(at: file) } catch { failed += 1 }
        }
        return failed
    }

    private static func cachedFile(for remote: URL, directory: URL) -> URL? {
        guard remote.scheme == "https" else { return nil }
        let digest = SHA256.hash(data: Data(remote.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension("mp3")
    }

    private static func tracked(_ remote: URL, onProgress: @escaping @MainActor (Double) -> Void) async throws -> (URL, URLResponse) {
        let transfer = HifzAudioTransfer()
        let monitor = Task { @MainActor in
            while !Task.isCancelled {
                if let fraction = transfer.fractionCompleted { onProgress(fraction) }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        defer { monitor.cancel() }
        return try await transfer.run(remote)
    }
}

/// One whole-file transfer that can be polled for progress and cancelled.
private final class HifzAudioTransfer: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var cancelled = false

    var fractionCompleted: Double? {
        lock.lock()
        let current = task
        lock.unlock()
        guard let current, current.countOfBytesExpectedToReceive > 0 else { return nil }
        return min(1, Double(current.countOfBytesReceived) / Double(current.countOfBytesExpectedToReceive))
    }

    func run(_ remote: URL) async throws -> (URL, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, URLResponse), Error>) in
                let download = URLSession.shared.downloadTask(with: remote) { location, response, error in
                    guard let location, let response else {
                        if (error as? URLError)?.code == .cancelled { continuation.resume(throwing: CancellationError()) }
                        else { continuation.resume(throwing: error ?? URLError(.badServerResponse)) }
                        return
                    }
                    // The system deletes `location` when this handler returns.
                    let kept = FileManager.default.temporaryDirectory
                        .appendingPathComponent("hifz-\(UUID().uuidString).download")
                    do {
                        try FileManager.default.moveItem(at: location, to: kept)
                        continuation.resume(returning: (kept, response))
                    } catch { continuation.resume(throwing: error) }
                }
                attach(download)
                download.resume()
            }
        } onCancel: {
            cancel()
        }
    }

    private func attach(_ download: URLSessionDownloadTask) {
        lock.lock()
        task = download
        let alreadyCancelled = cancelled
        lock.unlock()
        if alreadyCancelled { download.cancel() }
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let current = task
        lock.unlock()
        current?.cancel()
    }
}
