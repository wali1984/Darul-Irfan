import MapKit
import SwiftUI

/// The Dar-ul-Irfan headquarters card: a gradient crest, address, an inset map
/// with directions, and contact actions (call, email, website).
@MainActor
struct DarulIrfanCardView: View {
    let place: DarulIrfanPlace

    var body: some View {
        DIElevatedCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                crest
                VStack(alignment: .leading, spacing: DISpacing.md) {
                    if let coordinate {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
                        ))) {
                            Marker("Dar-ul-Irfan", coordinate: coordinate)
                                .tint(DIColor.primary)
                        }
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                                .stroke(DIColor.border, lineWidth: 1)
                        )
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
                            contactChip(url: phoneUrl, title: "Call", systemImage: "phone.fill")
                        }
                        if let emailUrl {
                            contactChip(url: emailUrl, title: "Email", systemImage: "envelope.fill")
                        }
                        if let websiteUrl {
                            contactChip(url: websiteUrl, title: "Website", systemImage: "safari.fill")
                        }
                    }

                    if place.phone != nil || place.email != nil {
                        VStack(alignment: .leading, spacing: DISpacing.xs) {
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
                .padding(DISpacing.md)
            }
        }
    }

    // MARK: - Crest header

    private var crest: some View {
        ZStack(alignment: .bottomLeading) {
            DIGradient.hero()
                .overlay(alignment: .topTrailing) {
                    DIOctagram(innerRatio: 0.5)
                        .stroke(Color.white, lineWidth: 1.5)
                        .frame(width: 160, height: 160)
                        .opacity(0.08)
                        .offset(x: 50, y: -30)
                }

            HStack(alignment: .center, spacing: DISpacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "building.columns.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: place.name)
                        .font(DIFont.subheading)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(place.addressLines.indices, id: \.self) { index in
                        Text(verbatim: place.addressLines[index])
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DISpacing.md)
        }
    }

    private func contactChip(url: URL, title: LocalizedStringKey, systemImage: String) -> some View {
        Link(destination: url) {
            VStack(spacing: DISpacing.xs) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(DIColor.primary)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DIColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DISpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                    .fill(DIColor.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                    .stroke(DIColor.primary.opacity(0.25), lineWidth: 1)
            )
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
