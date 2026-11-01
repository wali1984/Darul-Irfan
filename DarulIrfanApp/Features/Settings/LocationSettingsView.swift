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
    @State private var deviceUpdateFailed = false
    @AppStorage("today.weather.enabled") private var weatherEnabled = true
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

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
            Section {
                Toggle("Weather on Today", isOn: $weatherEnabled)
                    .frame(minHeight: 48)
                    .listRowBackground(DIColor.surface)
            } footer: {
                Text("Apple Weather uses your selected city's approximate location. Precise device coordinates are not sent.")
                    .foregroundStyle(DIColor.textMuted)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .toggleStyle(SwitchToggleStyle(tint: DIColor.primary))
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.refreshAuthorizationStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.refreshAuthorizationStatus() }
            }
        }
        .onChange(of: appState.settings.locationMode) { _, mode in
            deviceUpdateFailed = false
            // A fresh fix rather than the last place this phone was found
            // at, which would otherwise drive the times until the app next
            // comes to the foreground.
            if mode == .device {
                updateDevicePlace()
            }
        }
    }

    // MARK: - Mode

    private var modeSection: some View {
        Section {
            DISegmentedControl(items: [LocationMode.device, .manual], title: { $0 == .device ? "Device" : "Manual" }, selection: modeBinding)
                .accessibilityLabel(Text("Location Mode"))
            .listRowBackground(DIColor.surface)
        } header: {
            SettingsSectionHeader(titleKey: "Location Mode", systemImage: "location.viewfinder")
        } footer: {
            Text("Device mode uses your location only on this phone to calculate prayer times. Manual mode uses a city you choose.")
                .foregroundStyle(DIColor.textMuted)
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
                        .foregroundStyle(DIColor.textMuted)
                } else {
                    Text("Not determined yet").foregroundStyle(DIColor.textMuted)
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
                .buttonStyle(DISecondaryButtonStyle())
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
                .buttonStyle(DISecondaryButtonStyle())
                .listRowBackground(DIColor.surface)
            }
            if deviceUpdateFailed && viewModel.authorization != .denied {
                Text("We couldn't determine your location right now. Please try again in a moment, or choose your city manually below.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(DIColor.surface)
            }
        } header: {
            SettingsSectionHeader(titleKey: "Current Location", systemImage: "location.fill")
        } footer: {
            if viewModel.authorization == .denied {
                Text("Location access is currently off for Darul Irfan. You can allow it in the Settings app, or choose a city manually below.")
                    .foregroundStyle(DIColor.textMuted)
            } else {
                Text("Your precise location is never stored — only the resolved city name and approximate, city-level coordinates are kept so prayer times work offline.")
                    .foregroundStyle(DIColor.textMuted)
            }
        }
    }

    private func updateDevicePlace() {
        guard !isRefreshingDevicePlace else { return }
        isRefreshingDevicePlace = true
        deviceUpdateFailed = false
        Task {
            if viewModel.authorization == .notDetermined {
                await viewModel.requestPermission()
            }
            let succeeded = await appState.refreshDevicePlace()
            deviceUpdateFailed = !succeeded && appState.settings.locationMode == .device
            await viewModel.refreshAuthorizationStatus()
            isRefreshingDevicePlace = false
        }
    }

    // MARK: - Manual mode

    private var manualSection: some View {
        Section {
            if appState.settings.locationMode == .manual, let manual = appState.settings.manualPlace {
                LabeledContent("Selected City") {
                    Text(manual.name).foregroundStyle(DIColor.textMuted)
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

            Button {
                DIHaptics.soft()
                Task { await viewModel.search() }
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .buttonStyle(DISecondaryButtonStyle())
            .disabled(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSearching)
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
                    .diOctagramWatermark(size: 180, opacity: 0.05)
                    .listRowBackground(Color.clear)
                }
            }
        } header: {
            SettingsSectionHeader(titleKey: "Manual City", systemImage: "map.fill")
        } footer: {
            Text("Choosing a city switches to manual mode, which keeps prayer times accurate while travelling or offline.")
                .foregroundStyle(DIColor.textMuted)
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
                        .foregroundStyle(DIColor.actionForeground)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(minHeight: 48)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .listRowBackground(DIColor.surface)
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class LocationSettingsViewModel {
    private let location: any LocationServicing

    private var searchRevision = 0
    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            searchRevision += 1
            results = []
            isSearching = false
            searchFailed = false
            hasSearched = false
        }
    }
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
        searchRevision += 1
        let request = searchRevision
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = []
        hasSearched = false
        searchFailed = false
        guard !trimmed.isEmpty else {
            isSearching = false
            return
        }
        isSearching = true
        do {
            let found = try await location.searchPlaces(matching: trimmed)
            guard request == searchRevision else { return }
            results = found
        } catch is CancellationError {
            guard request == searchRevision else { return }
            isSearching = false
            return
        } catch {
            guard request == searchRevision else { return }
            searchFailed = true
        }
        hasSearched = true
        isSearching = false
    }
}
