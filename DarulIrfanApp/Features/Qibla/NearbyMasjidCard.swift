import SwiftUI
import CoreLocation

@MainActor
struct NearbyMasjidCard: View {
    let latitude: Double
    let longitude: Double
    let locationName: String
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @State private var requestID: UUID?
    @State private var items: [NearbyMasjid] = []
    @State private var loading = false
    @State private var searched = false
    @State private var expanded = false
    @State private var errorKey: String?
    @State private var linkFailed = false

    var body: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                Label("Nearby masjids", systemImage: "mappin.and.ellipse").diInterfaceFont(.headline)
                Text(verbatim: locationName).diInterfaceFont(.subheadline)
                Text("Search within 10 km of your selected location.").diInterfaceFont(.footnote).foregroundStyle(DIColor.textMuted)
                Button("Search nearby") { loading = true; errorKey = nil; items = []; expanded = false; requestID = UUID() }
                    .buttonStyle(DISecondaryButtonStyle()).disabled(loading)
                if loading { ProgressView() }
                if let errorKey { Text(LocalizedStringKey(errorKey)).diInterfaceFont(.footnote).foregroundStyle(DIColor.textMuted) }
                if searched && !loading && errorKey == nil && items.isEmpty {
                    Text("No masjids found within 10 km.").diInterfaceFont(.footnote)
                }
                ForEach(expanded ? items : Array(items.prefix(3))) { item in
                    VStack(alignment: .leading, spacing: DISpacing.sm) {
                        Text(verbatim: item.name).diInterfaceFont(.headline)
                        if !item.address.isEmpty { Text(verbatim: item.address).diInterfaceFont(.footnote) }
                        let meters = CLLocation(latitude: latitude, longitude: longitude).distance(from: CLLocation(latitude: item.latitude, longitude: item.longitude))
                        Text(verbatim: String(format: "%.1f km", locale: Locale(identifier: "en_US_POSIX"), meters / 1000)).diInterfaceFont(.footnote)
                            .environment(\.layoutDirection, .leftToRight)
                        Text("Straight-line distance").diInterfaceFont(.caption).foregroundStyle(DIColor.textMuted)
                        Button("Directions") { directions(item) }.buttonStyle(DICompactButtonStyle())
                            .accessibilityLabel(Text("Directions to \(item.name)"))
                        ForEach(Array(item.attributions.enumerated()), id: \.offset) { _, attribution in
                            if let value = attribution.uri, let url = URL(string: value), url.scheme == "https" {
                                Button { open(url) } label: { Text(verbatim: attribution.provider) }.buttonStyle(DICompactButtonStyle())
                            } else { Text(verbatim: attribution.provider).diInterfaceFont(.caption) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                }
                if items.count > 3 {
                    Button { expanded.toggle() } label: {
                        if expanded { Text("Show less") } else { Text("Show all \(items.count)") }
                    }.buttonStyle(DISecondaryButtonStyle())
                    .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
                }
                if searched && errorKey == nil && !loading {
                    Text(verbatim: "Google Maps").font(.system(size: 14, weight: .medium)).foregroundStyle(DIColor.textPrimary)
                }
            }
        }
        .task(id: requestID) {
            guard requestID != nil else { return }
            do {
                let results = try await NearbyMasjidService.search(latitude: latitude, longitude: longitude, language: locale.language.languageCode?.identifier ?? "en")
                guard !Task.isCancelled else { return }
                items = results; searched = true; loading = false
            } catch {
                guard !Task.isCancelled else { return }
                errorKey = (error as? NearbyMasjidError) == .limitReached ? "Nearby search limit reached. Please try another day." : "Nearby search is unavailable. Please try again later."
                searched = true; loading = false
            }
        }
        .onDisappear { requestID = nil; loading = false }
        .alert("Could not open link", isPresented: $linkFailed) { Button("OK", role: .cancel) {} }
    }

    private func directions(_ item: NearbyMasjid) {
        var url = URLComponents(string: "https://www.google.com/maps/dir/")!
        url.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "destination", value: item.name), URLQueryItem(name: "destination_place_id", value: item.id)]
        if let url = url.url { open(url) }
    }
    private func open(_ url: URL) { openURL(url) { if !$0 { linkFailed = true } } }
}
