import Foundation
import CoreLocation
import UIKit

/// Live compass feed for the Qibla screen.
///
/// Owns its own `CLLocationManager` (created and used exclusively on the main
/// actor, matching the `@MainActor` `HeadingProviding` contract). Heading
/// updates and location updates are started together: `trueHeading` is only
/// valid while location updates are also running, so we prefer it when it is
/// valid (`>= 0`) and fall back to `magneticHeading` otherwise, saying so
/// through `isMagneticHeading`. A negative `headingAccuracy` from CoreLocation
/// means the compass needs a figure-eight calibration, surfaced via
/// `needsCalibration`.
///
/// Delegate callbacks are `nonisolated` (the Objective-C requirements carry no
/// actor isolation); they copy the plain `Double` values out of `CLHeading`
/// and hop onto the main actor before touching state or notifying the UI.
@MainActor
final class CompassHeadingProvider: NSObject, HeadingProviding, CLLocationManagerDelegate {

    private let manager: CLLocationManager
    private var onChange: (@MainActor () -> Void)?
    private var isRunning = false

    /// Degrees from north; prefers true heading, falls back to magnetic.
    /// Nil until the first valid reading arrives.
    private(set) var currentHeading: Double?

    /// True while the reading is magnetic (no true heading available).
    private(set) var isMagneticHeading = false

    /// True when CoreLocation reports a negative heading accuracy.
    private(set) var needsCalibration: Bool = false

    var isHeadingAvailable: Bool {
        CLLocationManager.headingAvailable()
    }

    var canUseTrueNorth: Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        // Coarse accuracy is enough for true-north declination correction.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Report changes of one degree or more; keeps the needle smooth
        // without flooding the main actor.
        manager.headingFilter = 1
    }

    // MARK: - HeadingProviding

    func startUpdates(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        isRunning = true

        guard CLLocationManager.headingAvailable() else { return }

        updateHeadingOrientation()
        // Magnetic heading works without any location permission.
        manager.startUpdatingHeading()

        // trueHeading is only valid while location updates run, and those
        // need authorization. If undetermined, ask; the authorization
        // delegate callback starts location updates once granted.
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func stopUpdates() {
        isRunning = false
        manager.stopUpdatingHeading()
        manager.stopUpdatingLocation()
        onChange = nil
    }

    /// Headings are measured from the top of the screen as the interface is
    /// shown. CoreLocation measures from the top of the device held upright:
    /// the same on iPhone, where the app is portrait only, but a quarter or
    /// half turn off on an iPad turned sideways or upside down.
    private func updateHeadingOrientation() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let interface = scene?.effectiveGeometry.interfaceOrientation else { return }
        let device: CLDeviceOrientation
        switch interface {
        case .portrait: device = .portrait
        case .portraitUpsideDown: device = .portraitUpsideDown
        // The interface turns against the device: with the interface in
        // landscape-left the device itself is turned to the right.
        case .landscapeLeft: device = .landscapeRight
        case .landscapeRight: device = .landscapeLeft
        default: return
        }
        if manager.headingOrientation != device {
            manager.headingOrientation = device
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let trueHeading = newHeading.trueHeading
        let magneticHeading = newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy

        Task { @MainActor in
            guard self.isRunning else { return }
            // Follows the iPad as it rotates; the next reading uses it.
            self.updateHeadingOrientation()
            self.needsCalibration = accuracy < 0
            let usesTrueNorth = trueHeading >= 0
            let resolved = usesTrueNorth ? trueHeading : magneticHeading
            // Both headings negative means no usable reading at all.
            self.currentHeading = resolved >= 0 ? resolved : nil
            self.isMagneticHeading = !usesTrueNorth
            self.onChange?()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.isRunning else { return }
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.startUpdatingLocation()
            }
            self.onChange?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Continuous updates: a transient location failure is not fatal —
        // the compass keeps working from the magnetic heading.
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        // Let iOS show its figure-eight calibration overlay when needed.
        true
    }
}
