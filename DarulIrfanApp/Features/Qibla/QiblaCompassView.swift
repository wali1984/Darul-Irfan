import SwiftUI

/// Qibla compass screen (pushed from the More tab). Shows a live compass
/// pointing to the Kaaba for the active place, a calibration banner when the
/// magnetometer needs settling, and an always-visible absolute bearing for
/// use without the device compass.
@MainActor
struct QiblaCompassView: View {
    private let appState: AppState
    @State private var viewModel: QiblaViewModel

    init(dependencies: AppDependencies, appState: AppState) {
        self.appState = appState
        _viewModel = State(initialValue: QiblaViewModel(
            qiblaService: dependencies.qibla,
            headingProvider: CompassHeadingProvider()
        ))
    }

    var body: some View {
        Group {
            if let place = appState.activePlace {
                compassContent(for: place)
            } else {
                DIEmptyState(
                    systemImage: "location.slash",
                    titleKey: "Set your location to find the Qibla",
                    messageKey: "Allow location access or choose your city in Settings, and the compass will point toward the Kaaba."
                )
                .frame(maxHeight: .infinity)
            }
        }
        .diScreenBackground()
        .navigationTitle("Qibla")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let place = appState.activePlace {
                viewModel.start(place: place)
            }
        }
        .onDisappear {
            viewModel.stop()
        }
        .onChange(of: appState.activePlace) { _, newPlace in
            if let newPlace {
                viewModel.start(place: newPlace)
            }
        }
    }

    // MARK: - Content

    private func compassContent(for place: PlaceCoordinate) -> some View {
        ScrollView {
            VStack(spacing: DISpacing.lg) {
                placeRow(for: place)

                if viewModel.needsCalibration && viewModel.isHeadingAvailable {
                    calibrationBanner
                }

                QiblaDialView(
                    dialRotation: viewModel.dialRotationDegrees,
                    kaabaRotation: viewModel.kaabaRotationDegrees,
                    showsNeedle: viewModel.isHeadingAvailable && viewModel.hasHeading,
                    isAligned: viewModel.isAligned
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Qibla compass"))
                .accessibilityValue(directionText)

                directionReadout

                manualBearingCard

                Text("Compass accuracy can vary near metal objects, magnets, or cases.")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DISpacing.lg)
            }
            .padding(DISpacing.md)
            .padding(.bottom, DISpacing.xl)
            .frame(maxWidth: .infinity)
        }
    }

    private func placeRow(for place: PlaceCoordinate) -> some View {
        HStack(spacing: DISpacing.xs) {
            Image(systemName: "mappin.and.ellipse")
                .font(.footnote)
                .foregroundStyle(DIColor.accent)
                .accessibilityHidden(true)
            Text(verbatim: place.name)
                .font(.subheadline)
                .foregroundStyle(DIColor.textMuted)
        }
    }

    private var calibrationBanner: some View {
        DICard {
            HStack(alignment: .top, spacing: DISpacing.sm) {
                Image(systemName: "gyroscope")
                    .foregroundStyle(DIColor.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text("Compass calibration needed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.textPrimary)
                    Text("Move your iPhone in a figure-eight motion until the reading settles.")
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
        }
    }

    // MARK: - Direction readout

    @ViewBuilder
    private var directionReadout: some View {
        if !viewModel.isHeadingAvailable {
            DICard {
                HStack(alignment: .top, spacing: DISpacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(DIColor.accent)
                        .accessibilityHidden(true)
                    Text("This device doesn't provide live compass headings. Use the bearing below with any physical compass.")
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textPrimary)
                }
            }
        } else if viewModel.isAligned {
            Label("You are facing the Qibla", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(DIColor.primary)
        } else if let offset = viewModel.relativeOffsetDegrees {
            let degrees = Int(abs(offset).rounded())
            Group {
                if offset > 0 {
                    Text("Qibla is \(degrees)° to your right")
                } else {
                    Text("Qibla is \(degrees)° to your left")
                }
            }
            .font(.headline)
            .foregroundStyle(DIColor.textPrimary)
            .monospacedDigit()
        } else {
            HStack(spacing: DISpacing.sm) {
                ProgressView()
                Text("Finding north…")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
    }

    /// Spoken/accessibility equivalent of the readout, applied to the dial.
    private var directionText: Text {
        if !viewModel.isHeadingAvailable {
            return Text("Live compass unavailable")
        }
        if viewModel.isAligned {
            return Text("You are facing the Qibla")
        }
        if let offset = viewModel.relativeOffsetDegrees {
            let degrees = Int(abs(offset).rounded())
            if offset > 0 {
                return Text("Qibla is \(degrees)° to your right")
            } else {
                return Text("Qibla is \(degrees)° to your left")
            }
        }
        return Text("Finding north")
    }

    // MARK: - Manual fallback

    private var manualBearingCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Without the compass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DIColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let bearing = viewModel.qiblaBearingRounded {
                    Text("Qibla: \(bearing)° from North")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DIColor.primary)
                        .monospacedDigit()
                }
                Text("Face north using any compass, then turn clockwise by this bearing to face the Kaaba in Makkah.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
    }
}
