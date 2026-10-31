import SwiftUI

@MainActor
struct TodayWeatherView: View {
    let snapshot: CityWeatherSnapshot?
    let city: String
    let timeZone: TimeZone
    @Environment(\.scenePhase) private var scenePhase
    @State private var unit = CityWeatherSnapshot.deviceUnit()
    @State private var showing = false
    @Environment(\.locale) private var locale
    private static let legal = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    var body: some View {
        HStack(spacing: 8) {
            if let snapshot {
                Button { showing = true } label: {
                    HStack(spacing: 6) {
                        Text("Local weather").foregroundStyle(.white.opacity(0.75))
                        Text(verbatim: "·").foregroundStyle(.white.opacity(0.5))
                        Text(verbatim: CityWeatherSnapshot.temperature(snapshot.temperatureCelsius, unit: unit, locale: locale)).fontWeight(.semibold).foregroundStyle(Color(hex: 0xFFE3A0))
                    }.font(.caption).monospacedDigit().frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Local weather"))
                .accessibilityValue(Text(verbatim: CityWeatherSnapshot.temperature(snapshot.temperatureCelsius, unit: unit, locale: locale)))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { unit = CityWeatherSnapshot.deviceUnit() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
            unit = CityWeatherSnapshot.deviceUnit()
        }
        .sheet(isPresented: $showing) {
            if let snapshot {
                NavigationStack {
                    Form {
                        Section {
                            VStack(spacing: 10) {
                                Text(verbatim: city).font(.headline)
                                Text(verbatim: CityWeatherSnapshot.temperature(snapshot.temperatureCelsius, unit: unit, locale: locale))
                                    .font(.system(size: 44, weight: .light).monospacedDigit()).foregroundStyle(DIColor.primary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 12)
                            LabeledContent("Feels like") { Text(verbatim: CityWeatherSnapshot.temperature(snapshot.feelsLikeCelsius, unit: unit, locale: locale)) }
                            LabeledContent("Humidity") { Text(verbatim: "\(Int((snapshot.humidity * 100).rounded()))%") }
                            LabeledContent("Updated") { Text(snapshot.observedAt, format: Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)) }
                        }
                        LabeledContent("Temperature unit") { Text("Follows phone settings") }
                        Section {
                            Link(destination: Self.legal) {
                                HStack(spacing: 16) {
                                    Image("AppleWeatherMark").renderingMode(.original).resizable().scaledToFit().frame(width: 77, height: 14)
                                    Text("Apple Weather data sources").font(.caption).foregroundStyle(.white)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                    .background(Color(hex: 0x086B50), in: RoundedRectangle(cornerRadius: 12))
                            }.accessibilityLabel(Text("Apple Weather data sources"))
                        } footer: {
                            Text("Apple Weather uses your selected city's approximate location. Precise device coordinates are not sent.")
                        }
                    }
                    .navigationTitle("Local weather")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showing = false } } }
                }.presentationDetents([.medium, .large])
            }
        }
    }
}
