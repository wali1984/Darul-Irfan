import MapKit
import SwiftUI

/// The Dar-ul-Irfan headquarters card: address, a small map with directions,
/// and contact actions (call, email, website).
@MainActor
struct DarulIrfanCardView: View {
    let place: DarulIrfanPlace

    var body: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                VStack(alignment: .leading, spacing: DISpacing.xs) {
                    Text(verbatim: place.name)
                        .font(DIFont.subheading)
                        .foregroundStyle(DIColor.textPrimary)
                    ForEach(place.addressLines.indices, id: \.self) { index in
                        Text(verbatim: place.addressLines[index])
                            .font(.subheadline)
                            .foregroundStyle(DIColor.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
                    ))) {
                        Marker("Dar-ul-Irfan", coordinate: coordinate)
                            .tint(DIColor.primary)
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
                    .allowsHitTesting(false)
                    .accessibilityLabel("Map showing the location of Dar-ul-Irfan")

                    if let directionsUrl {
                        Link(destination: directionsUrl) {
                            Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle")
                        }
                        .buttonStyle(DIPrimaryButtonStyle())
                    }
                }

                HStack(spacing: DISpacing.sm) {
                    if let phoneUrl {
                        Link(destination: phoneUrl) {
                            Label("Call", systemImage: "phone")
                        }
                        .buttonStyle(DISecondaryButtonStyle())
                    }
                    if let emailUrl {
                        Link(destination: emailUrl) {
                            Label("Email", systemImage: "envelope")
                        }
                        .buttonStyle(DISecondaryButtonStyle())
                    }
                    if let websiteUrl {
                        Link(destination: websiteUrl) {
                            Label("Website", systemImage: "safari")
                        }
                        .buttonStyle(DISecondaryButtonStyle())
                    }
                }

                if let phone = place.phone {
                    Text(verbatim: phone)
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                if let email = place.email {
                    Text(verbatim: email)
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
            }
        }
    }

    // MARK: - Derived values

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = place.latitude, let longitude = place.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var directionsUrl: URL? {
        guard let latitude = place.latitude, let longitude = place.longitude else { return nil }
        return URL(string: "https://maps.apple.com/?daddr=\(latitude),\(longitude)")
    }

    private var phoneUrl: URL? {
        guard let phone = place.phone else { return nil }
        let allowed = Set("+0123456789")
        let digits = String(phone.filter { allowed.contains($0) })
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    private var emailUrl: URL? {
        guard let email = place.email else { return nil }
        return URL(string: "mailto:\(email)")
    }

    private var websiteUrl: URL? {
        URL(string: place.websiteUrl)
    }
}
