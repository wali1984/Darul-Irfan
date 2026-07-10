import Foundation
import Observation

// MARK: - Steps

/// Ordered pages of the first-run flow.
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case language
    case location
    case calculation
    case notifications
    case finish

    /// Every step can be skipped except the welcome/finish bookends and the
    /// location choice, which prayer times depend on.
    var isSkippable: Bool {
        switch self {
        case .language, .calculation, .notifications: return true
        case .welcome, .location, .finish: return false
        }
    }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
}

// MARK: - ViewModel

/// Drives the first-run flow: language choice, location setup (device or
/// manual city), calculation preferences, and notification permission.
/// All persistence goes through `AppState.updateSettings`.
@Observable
@MainActor
final class OnboardingViewModel {
    enum LocationSetupPhase: Equatable {
        case idle
        case requestingPermission
        case locating
        case resolved(PlaceCoordinate)
        case denied
        case failed
    }

    enum NotificationSetupPhase: Equatable {
        case idle
        case requesting
        case granted
        case denied
    }

    private let location: any LocationServicing
    private let notifications: any NotificationScheduling
    private let appState: AppState

    // Navigation
    private(set) var step: OnboardingStep = .welcome

    // Language
    private(set) var selectedLanguage: AppLanguage

    // Location
    private(set) var locationPhase: LocationSetupPhase = .idle
    var citySearchQuery: String = ""
    private(set) var citySearchResults: [PlaceCoordinate] = []
    private(set) var isSearchingCities = false
    private(set) var citySearchFailed = false
    private(set) var hasSearchedCities = false

    // Calculation
    var selectedMethod: CalculationMethodChoice
    var selectedAsrMethod: AsrMethodChoice

    // Notifications
    private(set) var notificationPhase: NotificationSetupPhase = .idle

    // Finish
    private(set) var isFinishing = false

    init(
        location: any LocationServicing,
        notifications: any NotificationScheduling,
        appState: AppState
    ) {
        self.location = location
        self.notifications = notifications
        self.appState = appState
        self.selectedLanguage = appState.settings.language
        self.selectedMethod = appState.settings.calculation.method
        self.selectedAsrMethod = appState.settings.calculation.asrMethod
    }

    // MARK: - Navigation

    /// True once any place (device-resolved or manual) is available for
    /// calculations; gates the location step's Continue button.
    var hasSelectedPlace: Bool { appState.activePlace != nil }

    var activePlaceName: String? { appState.activePlace?.name }

    func advance() {
        if let next = step.next { step = next }
    }

    func goBack() {
        if let previous = step.previous { step = previous }
    }

    // MARK: - Language

    func selectLanguage(_ language: AppLanguage) async {
        selectedLanguage = language
        await appState.updateSettings { $0.language = language }
    }

    // MARK: - Location

    /// Requests when-in-use permission and resolves a one-shot device
    /// location. On denial or failure the view offers manual city search.
    func useDeviceLocation() async {
        guard locationPhase != .requestingPermission, locationPhase != .locating else { return }
        locationPhase = .requestingPermission
        let status = await location.requestPermission()
        guard status == .authorized else {
            locationPhase = .denied
            return
        }
        locationPhase = .locating
        do {
            let place = try await location.currentPlace()
            await appState.updateSettings {
                $0.lastKnownPlace = place
                $0.locationMode = .device
            }
            locationPhase = .resolved(place)
        } catch {
            locationPhase = .failed
        }
    }

    func searchCities() async {
        let query = citySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isSearchingCities else { return }
        isSearchingCities = true
        citySearchFailed = false
        do {
            citySearchResults = try await location.searchPlaces(matching: query)
        } catch {
            citySearchResults = []
            citySearchFailed = true
        }
        hasSearchedCities = true
        isSearchingCities = false
    }

    func chooseManualPlace(_ place: PlaceCoordinate) async {
        await appState.updateSettings {
            $0.manualPlace = place
            $0.locationMode = .manual
        }
        locationPhase = .resolved(place)
    }

    // MARK: - Calculation

    /// The method/Asr choices as currently persisted (used by the summary
    /// page, which must not show uncommitted picker state).
    var savedMethod: CalculationMethodChoice { appState.settings.calculation.method }
    var savedAsrMethod: AsrMethodChoice { appState.settings.calculation.asrMethod }

    func commitCalculationAndAdvance() async {
        await appState.updateSettings {
            $0.calculation.method = selectedMethod
            $0.calculation.asrMethod = selectedAsrMethod
        }
        advance()
    }

    // MARK: - Notifications

    func requestNotificationPermission() async {
        guard notificationPhase != .requesting else { return }
        notificationPhase = .requesting
        let granted = await notifications.requestPermission()
        notificationPhase = granted ? .granted : .denied
    }

    // MARK: - Finish

    /// Marks onboarding complete and primes notifications + widgets. The view
    /// calls `onComplete` after this returns.
    func completeOnboarding() async {
        guard !isFinishing else { return }
        isFinishing = true
        await appState.updateSettings { $0.hasCompletedOnboarding = true }
        await appState.refreshScheduledNotificationsAndWidgets()
        isFinishing = false
    }
}
