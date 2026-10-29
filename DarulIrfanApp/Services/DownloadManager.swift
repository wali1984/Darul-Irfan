import CryptoKit
import Foundation
import Observation

// MARK: - Errors

/// Failures surfaced by `DownloadManager` beyond plain `URLError`s.
enum DownloadManagerError: LocalizedError {
    /// The server answered, but not with a success status code.
    case serverError(statusCode: Int)
    /// A PDF address answered "success" with something that is not a PDF,
    /// typically a Wi-Fi sign-in page. Never kept as the book.
    case notAPDF

    var errorDescription: String? {
        switch self {
        case .serverError(let statusCode):
            return String(localized: "The download could not be completed right now (server status \(statusCode)). Please try again later.")
        case .notAPDF:
            return String(localized: "What arrived was not the PDF, perhaps a Wi-Fi sign-in page. Please try again on another connection.")
        }
    }
}

// MARK: - DownloadManager

/// Live implementation of `DownloadManaging`.
///
/// Files are stored under
/// `Application Support/DarulIrfan/Downloads/<sha256-of-remote-url>.<ext>`
/// and recorded as `DownloadedAsset` rows via `DownloadsRepositoryProtocol`
/// (asset `id` == the SHA-256 hex of the remote URL string, so the same URL
/// always maps to the same file and row).
///
/// Progress: `activeDownloads` holds the fraction received so far (0...1),
/// updated in steps of at least one percent, so a 165 MB tafsir volume shows
/// how far it has come; the entry disappears on completion.
@Observable
@MainActor
final class DownloadManager: DownloadManaging {

    /// Active + queued downloads keyed by remote URL string, with the
    /// fraction received so far.
    private(set) var activeDownloads: [String: Double] = [:]

    private let downloadsRepository: any DownloadsRepositoryProtocol

    /// In-flight transfer tasks keyed by remote URL string, kept so that
    /// `cancelDownload(url:)` can stop them and duplicate requests can join
    /// the existing transfer instead of starting a second one.
    @ObservationIgnored
    private var inFlightTasks: [String: Task<DownloadedAsset, Error>] = [:]

    init(downloadsRepository: any DownloadsRepositoryProtocol) {
        self.downloadsRepository = downloadsRepository
    }

    // MARK: - DownloadManaging

    func download(
        url: URL,
        forContentItem contentItemID: String?,
        mediaItemID: String?
    ) async throws -> DownloadedAsset {
        let key = url.absoluteString

        // Already downloaded and still on disk: reuse it.
        if let existing = try await downloadsRepository.asset(remoteUrl: key),
           localURL(for: existing) != nil {
            return existing
        }

        // A transfer for this URL is already running: join it.
        if let inFlight = inFlightTasks[key] {
            return try await inFlight.value
        }

        let repository = downloadsRepository
        let transfer = Task { () throws -> DownloadedAsset in
            let (temporaryURL, response) = try await DownloadManager.fetch(url) { [weak self] fraction in
                Task { @MainActor in self?.reportProgress(fraction, for: key) }
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw DownloadManagerError.serverError(statusCode: httpResponse.statusCode)
            }

            // A captive portal answers any address with its own page and a
            // success status; kept, that page would open as the book.
            if DownloadManager.fileExtension(for: url) == "pdf", !DownloadManager.looksLikePDF(at: temporaryURL) {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw DownloadManagerError.notAPDF
            }

            do {
                try Task.checkCancellation()
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw error
            }

            let assetID = DownloadManager.sha256Hex(of: key)
            let fileName = "\(assetID).\(DownloadManager.fileExtension(for: url))"
            let destinationURL = try DownloadManager.downloadsDirectory()
                .appendingPathComponent(fileName, isDirectory: false)
            try DownloadManager.installFile(from: temporaryURL, to: destinationURL)

            let asset = DownloadedAsset(
                id: assetID,
                remoteUrl: key,
                relativeFilePath: fileName,
                byteSize: DownloadManager.fileSize(at: destinationURL),
                contentItemID: contentItemID,
                mediaItemID: mediaItemID,
                downloadedAt: Date()
            )
            try await repository.saveAsset(asset)
            return asset
        }

        inFlightTasks[key] = transfer
        activeDownloads[key] = 0

        do {
            let asset = try await transfer.value
            inFlightTasks[key] = nil
            activeDownloads[key] = nil
            return asset
        } catch {
            inFlightTasks[key] = nil
            activeDownloads[key] = nil
            throw error
        }
    }

    /// Progress from the transfer, dropped once it has finished or been
    /// cancelled.
    private func reportProgress(_ fraction: Double, for key: String) {
        guard inFlightTasks[key] != nil else { return }
        activeDownloads[key] = min(max(fraction, 0), 1)
    }

    func cancelDownload(url: URL) {
        let key = url.absoluteString
        inFlightTasks[key]?.cancel()
        inFlightTasks[key] = nil
        activeDownloads[key] = nil
    }

    func deleteAsset(_ asset: DownloadedAsset) async throws {
        // Remove the file first (tolerating an already-missing file), then
        // the database row so orphaned rows never outlive their files.
        if let fileURL = localURL(for: asset) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        try await downloadsRepository.deleteAsset(id: asset.id)
    }

    func localURL(for asset: DownloadedAsset) -> URL? {
        guard let directory = try? DownloadManager.downloadsDirectory() else { return nil }
        let fileURL = directory.appendingPathComponent(asset.relativeFilePath, isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }

    func totalBytesUsed() async -> Int64 {
        // File-system walk happens off the main actor.
        let task = Task.detached(priority: .utility) { () -> Int64 in
            guard let directory = try? DownloadManager.downloadsDirectory() else { return 0 }
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return 0 }

            var total: Int64 = 0
            for fileURL in contents {
                total += DownloadManager.fileSize(at: fileURL)
            }
            return total
        }
        return await task.value
    }

    // MARK: - Transfer

    /// Downloads `url` to a temporary file the caller then owns, reporting
    /// the fraction received in steps of at least one percent. Cancelling the
    /// calling task cancels the transfer.
    private nonisolated static func fetch(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (URL, URLResponse) {
        let handle = TransferHandle()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, URLResponse), Error>) in
                let task = URLSession.shared.downloadTask(with: url) { temporaryURL, response, error in
                    handle.finish()
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let temporaryURL, let response else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    // The system deletes its file as soon as this returns.
                    let kept = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: false)
                    do {
                        try FileManager.default.moveItem(at: temporaryURL, to: kept)
                        continuation.resume(returning: (kept, response))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                handle.start(task, progress: progress)
            }
        } onCancel: {
            handle.cancel()
        }
    }

    /// A PDF begins with "%PDF-"; readers accept it anywhere in the first
    /// kilobyte, so that is where it is looked for.
    private nonisolated static func looksLikePDF(at url: URL) -> Bool {
        guard let file = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? file.close() }
        guard let head = try? file.read(upToCount: 1_024) else { return false }
        return head.range(of: Data("%PDF-".utf8)) != nil
    }

    // MARK: - File helpers (nonisolated; safe from any executor)

    /// `Application Support/DarulIrfan/Downloads/`, created on first use.
    nonisolated static func downloadsDirectory() throws -> URL {
        let fileManager = FileManager.default
        let supportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = supportURL
            .appendingPathComponent("DarulIrfan", isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Moves the temporary download into place, replacing any previous copy,
    /// and leaves the file included in iCloud/iTunes backups (downloads are
    /// user-requested content the user would expect restored).
    private nonisolated static func installFile(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: sourceURL)
        } else {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = false
        var markedURL = destinationURL
        try? markedURL.setResourceValues(resourceValues)
    }

    private nonisolated static func fileSize(at url: URL) -> Int64 {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            return Int64(size)
        }
        return 0
    }

    /// Lowercased path extension of the remote URL, or "bin" when the URL has
    /// none (or an implausible one), so every stored file has an extension.
    private nonisolated static func fileExtension(for url: URL) -> String {
        let raw = url.pathExtension.lowercased()
        let isPlausible = !raw.isEmpty
            && raw.count <= 8
            && raw.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
        return isPlausible ? raw : "bin"
    }

    /// Lowercase hex SHA-256 of a string; used as both asset ID and filename.
    nonisolated static func sha256Hex(of string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Transfer handle

/// The URLSession task behind one download, so that cancelling the Swift
/// task cancels it, with its progress passed on in steps.
private final class TransferHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?
    private var isCancelled = false
    private var lastReported = 0.0

    func start(_ task: URLSessionDownloadTask, progress: @escaping @Sendable (Double) -> Void) {
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] value, _ in
            self?.report(value.fractionCompleted, to: progress)
        }
        lock.lock()
        self.task = task
        self.observation = observation
        let cancelledAlready = isCancelled
        lock.unlock()
        // Resumed either way, so its completion handler (which resumes the
        // waiting continuation) is certain to run.
        task.resume()
        if cancelledAlready {
            task.cancel()
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func finish() {
        lock.lock()
        let observation = self.observation
        self.observation = nil
        lock.unlock()
        observation?.invalidate()
    }

    private func report(_ fraction: Double, to progress: @Sendable (Double) -> Void) {
        lock.lock()
        let isStep = fraction - lastReported >= 0.01 || (fraction >= 1 && lastReported < 1)
        if isStep { lastReported = fraction }
        lock.unlock()
        if isStep { progress(fraction) }
    }
}
