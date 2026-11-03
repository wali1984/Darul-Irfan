import Observation
import SwiftUI

/// Content & storage settings: space used by downloads, and a confirmed
/// "clear all downloads" action.
@MainActor
struct ContentStorageSettingsView: View {
    private let appState: AppState
    @State private var viewModel: StorageSettingsViewModel
    @State private var isConfirmingClear = false

    init(dependencies: AppDependencies, appState: AppState) {
        self.appState = appState
        _viewModel = State(initialValue: StorageSettingsViewModel(
            downloadManager: dependencies.downloadManager,
            downloadsRepository: dependencies.downloadsRepository
        ))
    }

    var body: some View {
        List {
            storageSection
        }
        .diInterfaceFont(.body)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .toggleStyle(SwitchToggleStyle(tint: DIColor.primary))
        .navigationTitle("Content & Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .confirmationDialog(
            "Remove all downloaded content?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Remove All Downloads", role: .destructive) {
                Task { await viewModel.clearAllDownloads() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Downloaded audio and documents will be removed from this device. Your bookmarks and reading progress are kept.")
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        Section {
            LabeledContent("Storage Used") {
                if viewModel.loadFailed {
                    Text(verbatim: "--").foregroundStyle(DIColor.textMuted)
                } else if viewModel.hasLoaded {
                    Text(viewModel.bytesUsed, format: .byteCount(style: .file))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(DIColor.textMuted)
                } else {
                    ProgressView()
                }
            }
            .listRowBackground(DIColor.surface)

            LabeledContent("Downloaded Items") {
                if viewModel.loadFailed {
                    Text(verbatim: "--").foregroundStyle(DIColor.textMuted)
                } else if viewModel.hasLoaded {
                    Text(viewModel.assetCount, format: .number)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(DIColor.textMuted)
                } else {
                    ProgressView()
                }
            }
            .listRowBackground(DIColor.surface)

            Button(role: .destructive) {
                isConfirmingClear = true
            } label: {
                HStack {
                    Text("Clear Downloaded Content")
                    Spacer()
                    if viewModel.isClearing {
                        ProgressView()
                    }
                }
            }
            .buttonStyle(DISecondaryButtonStyle(destructive: true))
            .disabled((viewModel.assetCount == 0 && viewModel.bytesUsed == 0) || viewModel.loadFailed || viewModel.isClearing || viewModel.isLoading || !viewModel.hasLoaded)
            .listRowBackground(DIColor.surface)
            if viewModel.loadFailed {
                Button("Retry") { Task { await viewModel.load() } }
                    .buttonStyle(DISecondaryButtonStyle())
                    .disabled(viewModel.isClearing || viewModel.isLoading)
                    .listRowBackground(DIColor.surface)
            }
        } header: {
            SettingsSectionHeader(titleKey: "Storage", systemImage: "internaldrive.fill")
        } footer: {
            storageFooter
                .diInterfaceFont(.footnote)
                .foregroundStyle(DIColor.textMuted)
        }
    }

    @ViewBuilder
    private var storageFooter: some View {
        if viewModel.failedDeletions > 0 {
            Text("Some files could not be removed. Please try again.")
        } else if viewModel.loadFailed {
            Text("Storage details could not be loaded right now.")
        } else if viewModel.hasLoaded && viewModel.assetCount == 0 && viewModel.bytesUsed == 0 {
            Text("You have no downloaded content yet. Lectures and publications you download for offline use will appear here.")
        } else {
            Text("Removing downloads frees space on this device; everything remains available to stream or download again.")
        }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class StorageSettingsViewModel {
    private let downloadManager: any DownloadManaging
    private let downloadsRepository: any DownloadsRepositoryProtocol

    private(set) var bytesUsed: Int64 = 0
    private(set) var assetCount = 0
    private(set) var hasLoaded = false
    private(set) var isClearing = false
    private(set) var isLoading = false
    private(set) var failedDeletions = 0
    private(set) var loadFailed = false

    init(
        downloadManager: any DownloadManaging,
        downloadsRepository: any DownloadsRepositoryProtocol
    ) {
        self.downloadManager = downloadManager
        self.downloadsRepository = downloadsRepository
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let bytes = await downloadManager.totalBytesUsed()
        do {
            let count = try await downloadsRepository.allAssets().count
            try Task.checkCancellation()
            let practice = HifzAudioSource.cacheSummary()
            bytesUsed = bytes + practice.bytes
            assetCount = count + practice.files
            loadFailed = false
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            loadFailed = true
            hasLoaded = true
        }
    }

    /// Deletes every downloaded asset, continuing past individual failures so
    /// one bad file does not block the rest.
    func clearAllDownloads() async {
        guard !isClearing, !isLoading else { return }
        isClearing = true
        defer { isClearing = false }
        failedDeletions = 0
        // Practice may be reading the file it kept; it cannot outlive that file.
        HifzPlayer.active?.stop()
        failedDeletions += HifzAudioSource.clearCache()
        do {
            let assets = try await downloadsRepository.allAssets()
            for asset in assets {
                do {
                    try await downloadManager.deleteAsset(asset)
                } catch {
                    failedDeletions += 1
                }
            }
            failedDeletions += try await downloadManager.clearOrphanedFiles()
        } catch {
            failedDeletions += 1
        }
        await load()
    }
}
