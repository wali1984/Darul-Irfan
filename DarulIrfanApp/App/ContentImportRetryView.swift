import SwiftUI

/// What a content page shows when the part of the app's content it reads is
/// empty. That content is imported before any screen opens, so an empty page
/// means the import failed: Try Again runs it again, and the page then reads
/// its content once more.
@MainActor
struct ContentImportRetryView: View {
    let systemImage: String
    /// Says the content could not be loaded.
    let titleKey: LocalizedStringKey
    /// Shown while the import runs again.
    let openingTitleKey: LocalizedStringKey
    let contentSync: any ContentSyncServicing
    let reload: @MainActor () async -> Void

    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: DISpacing.md) {
            if isRetrying {
                DIEmptyState(
                    systemImage: systemImage,
                    titleKey: openingTitleKey,
                    messageKey: "This takes a moment after installing or updating the app."
                )
                ProgressView()
                    .tint(DIColor.primary)
            } else {
                DIEmptyState(
                    systemImage: systemImage,
                    titleKey: titleKey,
                    messageKey: "Please try again in a moment."
                )
                Button("Try Again") {
                    Task { await retry() }
                }
                .buttonStyle(DICompactButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func retry() async {
        guard !isRetrying else { return }
        isRetrying = true
        defer { isRetrying = false }
        await ContentImportRetry.run(contentSync)
        await reload()
    }
}

/// One import at a time, whichever page asked: a page that asks while one
/// runs waits for that one.
@MainActor
private enum ContentImportRetry {
    private static var running: Task<Void, Never>?

    static func run(_ contentSync: any ContentSyncServicing) async {
        if let running {
            await running.value
            return
        }
        let task = Task {
            do {
                _ = try await contentSync.importSeedDataIfNeeded()
            } catch {
                AppLog.content("Seed import retry failed: \(error)")
            }
        }
        running = task
        await task.value
        running = nil
    }
}
