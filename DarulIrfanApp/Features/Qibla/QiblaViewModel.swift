import Foundation
import Observation
import UIKit

/// Drives the Qibla compass: a fixed great-circle bearing to the Kaaba for
/// the active place plus a live device heading from the compass provider.
/// All angles are degrees from true north.
@Observable
@MainActor
final class QiblaViewModel {
    private let qiblaService: any QiblaServicing
    private let headingProvider: any HeadingProviding

    /// Bearing to the Kaaba from the current place; nil until `start` runs.
    private(set) var qiblaBearing: Double?
    /// Continuous heading used for rotations. It accumulates shortest-path
    /// deltas so animated rotations never spin the long way around when the
    /// raw heading wraps past north (359° → 0°).
    private(set) var displayHeading: Double = 0
    private(set) var hasHeading = false
    private(set) var needsCalibration = false
    private(set) var isHeadingAvailable = true

    private var lastRawHeading: Double?
    private var wasAligned = false
    private var isRunning = false

    /// Degrees either side of the exact bearing that count as "facing it".
    private let alignmentTolerance: Double = 5

    init(qiblaService: any QiblaServicing, headingProvider: any HeadingProviding) {
        self.qiblaService = qiblaService
        self.headingProvider = headingProvider
    }

    // MARK: - Lifecycle

    /// Computes the bearing for `place` and begins heading updates. Safe to
    /// call again with a new place while running: the bearing refreshes and
    /// updates continue uninterrupted.
    func start(place: PlaceCoordinate) {
        qiblaBearing = qiblaService.qiblaDirection(from: place)
        isHeadingAvailable = headingProvider.isHeadingAvailable
        refreshAlignment()
        guard isHeadingAvailable, !isRunning else { return }
        isRunning = true
        headingProvider.startUpdates { [weak self] in
            self?.headingDidChange()
        }
        headingDidChange()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        headingProvider.stopUpdates()
    }

    // MARK: - Derived state

    /// Signed offset from the current heading to the Qibla in (-180, 180].
    /// Positive means the Qibla is to the user's right.
    var relativeOffsetDegrees: Double? {
        guard let qibla = qiblaBearing, hasHeading, let heading = lastRawHeading else { return nil }
        return Self.signedOffset(qibla - heading)
    }

    var isAligned: Bool {
        guard let offset = relativeOffsetDegrees else { return false }
        return abs(offset) <= alignmentTolerance
    }

    /// Rotation applied to the compass card so its north tracks true north
    /// while the top of the screen represents the direction the user faces.
    var dialRotationDegrees: Double {
        hasHeading ? -displayHeading : 0
    }

    /// Rotation applied to the Kaaba marker arm: `qibla - heading`, i.e.
    /// where the Kaaba lies relative to the direction the device is facing.
    /// With no live heading the dial stays north-up and the marker sits at
    /// the absolute bearing.
    var kaabaRotationDegrees: Double {
        guard let qibla = qiblaBearing else { return 0 }
        return hasHeading ? qibla - displayHeading : qibla
    }

    /// Whole-degree bearing from north (0–359) for the manual fallback text.
    var qiblaBearingRounded: Int? {
        guard let qibla = qiblaBearing else { return nil }
        let value = Int(qibla.rounded()) % 360
        return value < 0 ? value + 360 : value
    }

    // MARK: - Heading updates

    private func headingDidChange() {
        needsCalibration = headingProvider.needsCalibration
        guard let raw = headingProvider.currentHeading else { return }
        if let last = lastRawHeading {
            displayHeading += Self.signedOffset(raw - last)
        } else {
            displayHeading = raw
        }
        lastRawHeading = raw
        hasHeading = true
        refreshAlignment()
    }

    /// Fires a success haptic the moment the user comes within tolerance.
    private func refreshAlignment() {
        let aligned = isAligned
        if aligned && !wasAligned {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        wasAligned = aligned
    }

    /// Normalizes any angle difference into (-180, 180].
    private static func signedOffset(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value <= -180 { value += 360 }
        return value
    }
}
