import SwiftUI

@MainActor
struct TodayWeatherView: View {
    let latitude: Double
    let longitude: Double
    let city: String
    let timeZone: TimeZone
    @AppStorage("today.weather.enabled") private var enabled = true
    @AppStorage("today.weather.unit") private var unit = "C"
    @State private var snapshot: CityWeatherSnapshot?
    @State private var snapshotGrid: String?
    @State private var showing = false
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    private var grid: WeatherCityGrid? { WeatherCityGrid(latitude: latitude, longitude: longitude) }
    private var reloadKey: String { "\(grid?.key ?? "")|\(enabled)|\(scenePhase == .active)" }
    private static let legal = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if enabled, let snapshot, snapshot.usable(at: Date()), snapshotGrid == grid?.key {
                Button { showing = true } label: {
                    Label(CityWeatherSnapshot.temperature(snapshot.temperatureCelsius, unit: unit, locale: locale), systemImage: "thermometer.medium")
                        .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Color(hex: 0xFFE3A0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Local weather"))
                .accessibilityValue(Text(verbatim: CityWeatherSnapshot.temperature(snapshot.temperatureCelsius, unit: unit, locale: locale)))
                Link(destination: Self.legal) {
                    Image("AppleWeatherMark").renderingMode(.original).resizable().scaledToFit().frame(width: 77, height: 14)
                }
                .accessibilityLabel(Text("Apple Weather data sources"))
            }
        }
        .task(id: reloadKey) {
            guard enabled, scenePhase == .active, let grid else { snapshot = nil; return }
            while !Task.isCancelled {
                let value = await CityWeatherService.shared.current(for: grid)
                guard !Task.isCancelled else { return }
                snapshot = value; snapshotGrid = grid.key
                do { try await Task.sleep(for: .seconds(600)) } catch { return }
            }
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
                        Section("Temperature unit") {
                            Picker("Temperature unit", selection: $unit) {
                                Text("Celsius (°C)").tag("C")
                                Text("Fahrenheit (°F)").tag("F")
                            }.pickerStyle(.segmented)
                        }
                        Section {
                            Link("Apple Weather data sources", destination: Self.legal)
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
