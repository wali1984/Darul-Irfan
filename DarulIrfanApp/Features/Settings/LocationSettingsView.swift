import Observation
import SwiftUI
import UIKit

/// Location settings: device vs. manual mode, the current detected city with
/// an on-demand refresh, and a city search for manual mode.
@MainActor
struct LocationSettingsView: View {
    private let appState: AppState
    @State private var viewModel: LocationSettingsViewModel
    @State private var isRefreshingDevicePlace = false
    @Environment(\.openURL) private var openURL

    init(dependencies: AppDependencies, appState: AppState) {
        self.appState = appState
        _viewModel = State(initialValue: LocationSettingsViewModel(location: dependencies.location))
    }

    var body: some View {
        List {
            modeSection
            if appState.settings.locationMode == .device {
                deviceSection
            }
            manualSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.refreshAuthorizationStatus()
        }
    }

    // MARK: - Mode

    private var modeSection: some View {
        Section {
            Picker("Location Mode", selection: modeBinding) {
                Text("Device").tag(LocationMode.device)
                Text("Manual").tag(LocationMode.manual)
            }
            .pickerStyle(.segmented)
            .listRowBackground(DIColor.surface)
        } footer: {
            Text("Device mode uses your location only on this phone to calculate prayer times. Manual mode uses a city you choose.")
        }
    }

    private var modeBinding: Binding<LocationMode> {
        SettingsBinding.value(
            in: appState,
            get: { $0.locationMode },
            set: { settings, mode in settings.locationMode = mode }
        )
    }

    // MARK: - Device mode

    private var deviceSection: some View {
        Section {
            LabeledContent("Detected City") {
                if let place = appState.settings.lastKnownPlace {
                    Text(place.name)
                } else {
                    Text("Not determined yet")
                }
            }
            .listRowBackground(DIColor.surface)

            if viewModel.authorization == .denied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("Open Settings to Allow Location", systemImage: "gear")
                }
                .foregroundStyle(DIColor.primary)
                .listRowBackground(DIColor.surface)
            } else {
                Button {
                    updateDevicePlace()
                } label: {
                    HStack {
                        Label("Update Now", systemImage: "arrow.clockwise")
                        Spacer()
                        if isRefreshingDevicePlace {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRefreshingDevicePlace)
                .foregroundStyle(DIColor.primary)
                .listRowBackground(DIColor.surface)
            }
        } header: {
            Text("Current Location")
        } footer: {
            if viewModel.authorization == .denied {
                Text("Location access is currently off for Darul Irfan. You can allow it in the Settings app, or choose a city manually below.")
            } else {
                Text("Your precise location is never stored — only the resolved city name and approximate, city-level coordinates are kept so prayer times work offline.")
            }
        }
    }

    private func updateDevicePlace() {
        guard !isRefreshingDevicePlace else { return }
        isRefreshingDevicePlace = true
        Task {
            if viewModel.authorization == .notDetermined {
                await viewModel.requestPermission()
            }
            await appState.refreshDevicePlaceIfNeeded()
            await viewModel.refreshAuthorizationStatus()
            isRefreshingDevicePlace = false
        }
    }

    // MARK: - Manual mode

    private var manualSection: some View {
        Section {
            if appState.settings.locationMode == .manual, let manual = appState.settings.manualPlace {
                LabeledContent("Selected City") {
                    Text(manual.name)
                }
                .listRowBackground(DIColor.surface)
            }

            HStack(spacing: DISpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
                TextField("Search for a city", text: $viewModel.query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.search() }
                    }
                if viewModel.isSearching {
                    ProgressView()
                }
            }
            .listRowBackground(DIColor.surface)

            ForEach(viewModel.results, id: \.self) { place in
                placeRow(place)
            }

            if viewModel.hasSearched && viewModel.results.isEmpty && !viewModel.isSearching {
                if viewModel.searchFailed {
                    Text("The search could not be completed. Please check your connection and try again.")
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                        .listRowBackground(DIColor.surface)
                } else {
                    DIEmptyState(
                        systemImage: "mappin.slash",
                        titleKey: "No matching places",
                        messageKey: "Try searching with the city name in English, for example \"Chakwal\"."
                    )
                    .listRowBackground(Color.clear)
                }
            }
        } header: {
            Text("Manual City")
        } footer: {
            Text("Choosing a city switches to manual mode, which keeps prayer times accurate while travelling or offline.")
        }
    }

    private func placeRow(_ place: PlaceCoordinate) -> some View {
        let isSelected = appState.settings.manualPlace == place
        return Button {
            Task {
                await appState.updateSettings { settings in
                    settings.manualPlace = place
                    settings.locationMode = .manual
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .foregroundStyle(DIColor.textPrimary)
                    Text(place.timeZoneIdentifier)
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                Spacer(minLength: DISpacing.sm)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DIColor.primary)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .listRowBackground(DIColor.surface)
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class LocationSettingsViewModel {
    private let location: any LocationServicing

    var query: String = ""
    private(set) var results: [PlaceCoordinate] = []
    private(set) var isSearching = false
    private(set) var searchFailed = false
    private(set) var hasSearched = false
    private(set) var authorization: LocationAuthorizationStatus = .notDetermined

    init(location: any LocationServicing) {
        self.location = location
    }

    func refreshAuthorizationStatus() async {
        authorization = await location.authorizationStatus
    }

    func requestPermission() async {
        authorization = await location.requestPermission()
    }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            hasSearched = false
            return
        }
        isSearching = true
        searchFailed = false
        do {
            results = try await location.searchPlaces(matching: trimmed)
        } catch {
            results = []
            searchFailed = true
        }
        hasSearched = true
        isSearching = false
    }
}
