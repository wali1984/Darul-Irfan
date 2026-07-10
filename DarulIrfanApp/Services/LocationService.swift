import Foundation
import CoreLocation

/// Live CoreLocation implementation of `LocationServicing`.
///
/// Concurrency approach: `CLLocationManager` must be created and used on a
/// single thread with a run loop, so the whole class is isolated to the main
/// actor — the manager is created there (in `init`, called from the main-actor
/// `AppDependencies.live()`) and every touch of it happens there. Delegate
/// callbacks are declared `nonisolated` (the Objective-C protocol requirements
/// are not actor-isolated); each one extracts only Sendable values from its
/// parameters and hops back onto the main actor to mutate state and resume
/// continuations. The explicit `@unchecked Sendable` conformance satisfies the
/// `LocationServicing: Sendable` contract and is safe because all mutable
/// state is main-actor-confined.
///
/// One-shot fixes use `requestLocation()` bridged to async/await with a
/// `CheckedContinuation`. Double-resume is impossible by construction: the
/// stored continuation is taken (set to nil) on the main actor before either
/// `didUpdateLocations` or `didFailWithError` resumes it, and a second
/// `currentPlace()` call while a fix is already in flight throws
/// `LocationServiceError.unavailable` instead of queueing.
@MainActor
final class LocationService: NSObject, LocationServicing, CLLocationManagerDelegate, @unchecked Sendable {

    private let manager: CLLocationManager

    /// Pending one-shot location request. At most one at a time.
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    /// Callers awaiting the outcome of `requestWhenInUseAuthorization()`.
    /// An array so concurrent `requestPermission()` calls all resolve.
    private var permissionContinuations: [CheckedContinuation<LocationAuthorizationStatus, Never>] = []

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        // City-level accuracy is plenty for prayer times and resolves faster.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - LocationServicing

    var authorizationStatus: LocationAuthorizationStatus {
        get async {
            mapped(manager.authorizationStatus)
        }
    }

    func requestPermission() async -> LocationAuthorizationStatus {
        let current = mapped(manager.authorizationStatus)
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            permissionContinuations.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentPlace() async throws -> PlaceCoordinate {
        var status = mapped(manager.authorizationStatus)
        if status == .notDetermined {
            status = await requestPermission()
        }
        guard status == .authorized else {
            throw LocationServiceError.permissionDenied
        }
        // A fix is already in flight; we deliberately do not queue.
        guard locationContinuation == nil else {
            throw LocationServiceError.unavailable
        }

        let location: CLLocation = try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
        return await place(for: location)
    }

    func searchPlaces(matching query: String) async throws -> [PlaceCoordinate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(trimmed)
            return placemarks.compactMap { placemark -> PlaceCoordinate? in
                guard let location = placemark.location else { return nil }
                let coordinate = location.coordinate
                let timeZone: TimeZone = placemark.timeZone ?? TimeZone.current
                return PlaceCoordinate(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    name: displayName(for: placemark, coordinate: coordinate),
                    timeZoneIdentifier: timeZone.identifier
                )
            }
        } catch {
            // "No result" is an ordinary empty outcome, not a failure.
            if let clError = error as? CLError, clError.code == .geocodeFoundNoResult {
                return []
            }
            throw LocationServiceError.unavailable
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.handleAuthorizationChange(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last
        Task { @MainActor in
            guard let continuation = self.locationContinuation else { return }
            self.locationContinuation = nil
            if let location = latest {
                continuation.resume(returning: location)
            } else {
                continuation.resume(throwing: LocationServiceError.unavailable)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let serviceError: LocationServiceError
        if let clError = error as? CLError, clError.code == .denied {
            serviceError = .permissionDenied
        } else {
            serviceError = .unavailable
        }
        Task { @MainActor in
            guard let continuation = self.locationContinuation else { return }
            self.locationContinuation = nil
            continuation.resume(throwing: serviceError)
        }
    }

    // MARK: - Private helpers

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        // The delegate fires once right after the manager is created, and again
        // while the permission dialog is still up; only a determined status
        // answers the callers waiting in requestPermission().
        guard status != .notDetermined else { return }
        let result = mapped(status)
        let waiters = permissionContinuations
        permissionContinuations.removeAll()
        for continuation in waiters {
            continuation.resume(returning: result)
        }
    }

    /// Reverse-geocodes a fix into a named place; falls back to a plain
    /// coordinates label when the geocoder is unavailable (e.g. offline).
    private func place(for location: CLLocation) async -> PlaceCoordinate {
        let coordinate = location.coordinate
        var name = coordinatesText(for: coordinate)
        var timeZoneIdentifier = TimeZone.current.identifier

        let geocoder = CLGeocoder()
        if let placemarks = try? await geocoder.reverseGeocodeLocation(location),
           let placemark = placemarks.first {
            name = displayName(for: placemark, coordinate: coordinate)
            if let placemarkTimeZone = placemark.timeZone {
                timeZoneIdentifier = placemarkTimeZone.identifier
            }
        }

        return PlaceCoordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            name: name,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    private func displayName(for placemark: CLPlacemark, coordinate: CLLocationCoordinate2D) -> String {
        if let locality = placemark.locality, !locality.isEmpty {
            return locality
        }
        if let placeName = placemark.name, !placeName.isEmpty {
            return placeName
        }
        return coordinatesText(for: coordinate)
    }

    private func coordinatesText(for coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.2f, %.2f", coordinate.latitude, coordinate.longitude)
    }

    private func mapped(_ status: CLAuthorizationStatus) -> LocationAuthorizationStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorizedWhenInUse, .authorizedAlways:
            return .authorized
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }
}
