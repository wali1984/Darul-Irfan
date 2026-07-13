import Observation
import SwiftUI

/// Content & storage settings: auto-download preference, space used by
/// downloads, and a confirmed "clear all downloads" action.
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
            downloadsSection
            storageSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .diScreenBackground()
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

    // MARK: - Auto-download

    private var downloadsSection: some View {
        Section {
            Toggle("Auto-download new content on Wi-Fi", isOn: autoDownloadBinding)
                .tint(DIColor.primary)
                .listRowBackground(DIColor.surface)
        } header: {
            SettingsSectionHeader(titleKey: "Downloads", systemImage: "arrow.down.circle.fill")
        } footer: {
            Text("When enabled, new content packs are fetched automatically while you are on Wi-Fi.")
        }
    }

    private var autoDownloadBinding: Binding<Bool> {
        SettingsBinding.value(
            in: appState,
            get: { $0.autoDownloadOnWifi },
            set: { settings, enabled in settings.autoDownloadOnWifi = enabled }
        )
    }

    // MARK: - Storage

    private var storageSection: some View {
        Section {
            LabeledContent("Storage Used") {
                if viewModel.hasLoaded {
                    Text(viewModel.bytesUsed, format: .byteCount(style: .file))
                        .monospacedDigit()
                } else {
                    ProgressView()
                }
            }
            .listRowBackground(DIColor.surface)

            LabeledContent("Downloaded Items") {
                if viewModel.hasLoaded {
                    Text(viewModel.assetCount, format: .number)
                        .monospacedDigit()
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
            .disabled(viewModel.assetCount == 0 || viewModel.isClearing || !viewModel.hasLoaded)
            .listRowBackground(DIColor.surface)
        } header: {
            SettingsSectionHeader(titleKey: "Storage", systemImage: "internaldrive.fill")
        } footer: {
            storageFooter
        }
    }

    @ViewBuilder
    private var storageFooter: some View {
        if viewModel.failedDeletions > 0 {
            Text("Some files could not be removed. Please try again.")
        } else if viewModel.loadFailed {
            Text("Storage details could not be loaded right now.")
        } else if viewModel.hasLoaded && viewModel.assetCount == 0 {
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
        loadFailed = false
        bytesUsed = await downloadManager.totalBytesUsed()
        do {
            assetCount = try await downloadsRepository.allAssets().count
        } catch {
            loadFailed = true
        }
        hasLoaded = true
    }

    /// Deletes every downloaded asset, continuing past individual failures so
    /// one bad file does not block the rest.
    func clearAllDownloads() async {
        guard !isClearing else { return }
        isClearing = true
        failedDeletions = 0
        do {
            let assets = try await downloadsRepository.allAssets()
            for asset in assets {
                do {
                    try await downloadManager.deleteAsset(asset)
                } catch {
                    failedDeletions += 1
                }
            }
        } catch {
            loadFailed = true
        }
        isClearing = false
        await load()
    }
}
