import SwiftUI
import UIKit

/// Onboarding page 3: the one step that cannot be skipped. Offers a one-shot
/// device location (privacy-first, on-device only) with a manual city search
/// fallback that also carries users through permission denial.
struct OnboardingLocationStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: DISpacing.md) {
            OnboardingStepHeader(
                titleKey: "Your Location",
                subtitleKey: "Prayer times and the Qibla direction depend on where you are."
            )

            privacyNote

            if viewModel.hasSelectedPlace, let name = viewModel.activePlaceName {
                selectedPlaceCard(name: name)
            }

            deviceLocationButton

            if viewModel.locationPhase == .denied {
                deniedGuidance
            }
            if viewModel.locationPhase == .failed {
                failedGuidance
            }

            manualSearchSection

            if !viewModel.hasSelectedPlace {
                Text("Choose one of the options above to continue.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .padding(.top, DISpacing.xs)
            }
        }
    }

    // MARK: - Privacy

    private var privacyNote: some View {
        DICard {
            HStack(alignment: .top, spacing: DISpacing.sm) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(DIColor.primary)
                    .accessibilityHidden(true)
                Text("Your location stays on this device. It is used only to calculate prayer times and the Qibla direction, and is never sent to any server.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
    }

    // MARK: - Device location

    private var isResolvingDeviceLocation: Bool {
        viewModel.locationPhase == .requestingPermission || viewModel.locationPhase == .locating
    }

    private var deviceLocationButton: some View {
        Button {
            Task { await viewModel.useDeviceLocation() }
        } label: {
            if isResolvingDeviceLocation {
                HStack(spacing: DISpacing.sm) {
                    ProgressView()
                        .tint(DIColor.primary)
                    Text("Finding your location…")
                }
            } else {
                Label("Use My Location", systemImage: "location.fill")
            }
        }
        .buttonStyle(DISecondaryButtonStyle())
        .disabled(isResolvingDeviceLocation)
    }

    private var deniedGuidance: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) {
                    Image(systemName: "location.slash")
                        .foregroundStyle(DIColor.textMuted)
                        .accessibilityHidden(true)
                    Text("Location access is currently off for Darul Irfan.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.textPrimary)
                }
                Text("That's completely fine — you can choose your city below instead, or allow access in the iPhone Settings app.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                Button("Open iPhone Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DIColor.primary)
            }
        }
    }

    private var failedGuidance: some View {
        DICard {
            HStack(alignment: .top, spacing: DISpacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(DIColor.accent)
                    .accessibilityHidden(true)
                Text("We couldn't determine your location right now. Please try again in a moment, or choose your city manually below.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
    }

    // MARK: - Selected place

    private func selectedPlaceCard(name: String) -> some View {
        DICard {
            HStack(spacing: DISpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DIColor.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text("Prayer times will be calculated for")
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                    Text(verbatim: name)
                        .font(.headline)
                        .foregroundStyle(DIColor.textPrimary)
                }
            }
        }
    }

    // MARK: - Manual city search

    private var manualSearchSection: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Choose City Manually", systemImage: "magnifyingglass")

            HStack(spacing: DISpacing.sm) {
                TextField("Search for a city", text: $viewModel.citySearchQuery)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.searchCities() }
                    }
                    .padding(.horizontal, DISpacing.md)
                    .frame(minHeight: 44)
                    .background(DIColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous)
                            .stroke(DIColor.border, lineWidth: 1)
                    )

                Button {
                    Task { await viewModel.searchCities() }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DIColor.onPrimary)
                        .frame(width: 44, height: 44)
                        .background(DIColor.primary)
                        .clipShape(RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous))
                }
                .accessibilityLabel(Text("Search"))
                .disabled(viewModel.isSearchingCities)
            }

            if viewModel.isSearchingCities {
                HStack(spacing: DISpacing.sm) {
                    ProgressView()
                    Text("Searching…")
                        .font(.footnote)
                        .foregroundStyle(DIColor.textMuted)
                }
            } else if viewModel.citySearchFailed {
                Text("The search didn't go through. Please check your connection and try again.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.danger)
            } else if viewModel.hasSearchedCities && viewModel.citySearchResults.isEmpty {
                Text("No matching places found. Try a nearby larger city.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
            }

            ForEach(viewModel.citySearchResults, id: \.self) { place in
                resultRow(place)
            }
        }
        .padding(.top, DISpacing.sm)
    }

    private func resultRow(_ place: PlaceCoordinate) -> some View {
        Button {
            Task { await viewModel.chooseManualPlace(place) }
        } label: {
            HStack(spacing: DISpacing.sm) {
                Image(systemName: "mappin.circle")
                    .foregroundStyle(DIColor.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text(verbatim: place.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DIColor.textPrimary)
                    Text(verbatim: place.timeZoneIdentifier)
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(DISpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DIColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                    .stroke(DIColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
