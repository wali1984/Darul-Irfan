import Foundation
import Observation
import SwiftUI

// MARK: - Years view model

/// Loads the distinct archive years for an optional category filter.
@Observable
@MainActor
final class ArchiveBrowserViewModel {
    let category: MediaCategory?

    private let mediaRepository: any MediaRepositoryProtocol

    private(set) var years: [Int] = []
    private(set) var isLoading = false
    private(set) var loadErrorMessage: String?
    private var hasLoadedOnce = false

    init(category: MediaCategory?, mediaRepository: any MediaRepositoryProtocol) {
        self.category = category
        self.mediaRepository = mediaRepository
    }

    func load() async {
        if !hasLoadedOnce {
            isLoading = true
        }
        loadErrorMessage = nil
        do {
            years = try await mediaRepository.availableYears(category: category)
            hasLoadedOnce = true
        } catch {
            loadErrorMessage = "The archive could not be loaded right now. Please try again in a moment."
        }
        isLoading = false
    }
}

// MARK: - Years view

/// First level of the archive: a list of years, newest first. Selecting a
/// year drills into its months.
struct ArchiveBrowserView: View {
    private let dependencies: AppDependencies
    @State private var viewModel: ArchiveBrowserViewModel

    init(dependencies: AppDependencies, category: MediaCategory? = nil) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: ArchiveBrowserViewModel(
            category: category,
            mediaRepository: dependencies.mediaRepository
        ))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.loadErrorMessage {
                DIEmptyState(
                    systemImage: "wifi.exclamationmark",
                    titleKey: "Something went wrong",
                    messageKey: LocalizedStringKey(message)
                )
            } else if viewModel.years.isEmpty {
                DIEmptyState(
                    systemImage: "calendar",
                    titleKey: "No archive yet",
                    messageKey: "Yearly lecture archives will appear here after the library syncs. Pull down to refresh."
                )
            } else {
                yearList
            }
        }
        .diScreenBackground()
        .navigationTitle("Browse by Year")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
    }

    private var yearList: some View {
        List {
            ForEach(viewModel.years, id: \.self) { year in
                NavigationLink {
                    ArchiveYearView(
                        dependencies: dependencies,
                        category: viewModel.category,
                        year: year
                    )
                } label: {
                    HStack(spacing: DISpacing.sm) {
                        Image(systemName: "calendar")
                            .foregroundStyle(DIColor.primary)
                            .accessibilityHidden(true)
                        Text(verbatim: String(year))
                            .font(.headline)
                            .foregroundStyle(DIColor.textPrimary)
                    }
                    .padding(.vertical, DISpacing.xs)
                }
                .listRowBackground(DIColor.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Months view model

/// One month bucket within an archive year.
struct MediaArchiveMonth: Identifiable, Equatable {
    let month: Int
    let count: Int

    var id: Int { month }
}

/// Loads the items of one year and groups them into month buckets.
@Observable
@MainActor
final class ArchiveYearViewModel {
    let category: MediaCategory?
    let year: Int

    private let mediaRepository: any MediaRepositoryProtocol

    private(set) var months: [MediaArchiveMonth] = []
    private(set) var totalCount = 0
    private(set) var isLoading = false
    private(set) var loadErrorMessage: String?
    private var hasLoadedOnce = false

    init(category: MediaCategory?, year: Int, mediaRepository: any MediaRepositoryProtocol) {
        self.category = category
        self.year = year
        self.mediaRepository = mediaRepository
    }

    func load() async {
        if !hasLoadedOnce {
            isLoading = true
        }
        loadErrorMessage = nil
        do {
            let items = try await mediaRepository.items(
                category: category, year: year, month: nil, limit: 2000
            )
            totalCount = items.count
            var counts: [Int: Int] = [:]
            for item in items {
                if let month = item.month {
                    counts[month, default: 0] += 1
                }
            }
            months = counts
                .map { MediaArchiveMonth(month: $0.key, count: $0.value) }
                .sorted { $0.month > $1.month }
            hasLoadedOnce = true
        } catch {
            loadErrorMessage = "This year could not be loaded right now. Please try again in a moment."
        }
        isLoading = false
    }
}

// MARK: - Months view

/// Second level of the archive: the months of one year, plus an "everything
/// from this year" row that also covers undated items.
struct ArchiveYearView: View {
    private let dependencies: AppDependencies
    @State private var viewModel: ArchiveYearViewModel

    init(dependencies: AppDependencies, category: MediaCategory?, year: Int) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: ArchiveYearViewModel(
            category: category,
            year: year,
            mediaRepository: dependencies.mediaRepository
        ))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.loadErrorMessage {
                DIEmptyState(
                    systemImage: "wifi.exclamationmark",
                    titleKey: "Something went wrong",
                    messageKey: LocalizedStringKey(message)
                )
            } else if viewModel.totalCount == 0 {
                DIEmptyState(
                    systemImage: "calendar",
                    titleKey: "Nothing here yet",
                    messageKey: "Items for this year will appear after the next library sync."
                )
            } else {
                monthList
            }
        }
        .diScreenBackground()
        .navigationTitle(Text(verbatim: String(viewModel.year)))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
    }

    private var monthList: some View {
        List {
            NavigationLink {
                MediaItemListView(
                    filter: .year(category: viewModel.category, year: viewModel.year),
                    dependencies: dependencies
                )
            } label: {
                HStack(spacing: DISpacing.sm) {
                    Image(systemName: "square.stack")
                        .foregroundStyle(DIColor.primary)
                        .accessibilityHidden(true)
                    Text("All of \(String(viewModel.year))")
                        .font(.headline)
                        .foregroundStyle(DIColor.textPrimary)
                    Spacer(minLength: 0)
                    Text("\(viewModel.totalCount) items")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                .padding(.vertical, DISpacing.xs)
            }
            .listRowBackground(DIColor.surface)

            ForEach(viewModel.months) { bucket in
                NavigationLink {
                    MediaItemListView(
                        filter: .month(
                            category: viewModel.category,
                            year: viewModel.year,
                            month: bucket.month
                        ),
                        dependencies: dependencies
                    )
                } label: {
                    HStack(spacing: DISpacing.sm) {
                        Image(systemName: "calendar")
                            .foregroundStyle(DIColor.primary)
                            .accessibilityHidden(true)
                        Text(verbatim: MediaTimeFormat.monthName(bucket.month))
                            .font(.headline)
                            .foregroundStyle(DIColor.textPrimary)
                        Spacer(minLength: 0)
                        Text("\(bucket.count) items")
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                    }
                    .padding(.vertical, DISpacing.xs)
                }
                .listRowBackground(DIColor.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}
