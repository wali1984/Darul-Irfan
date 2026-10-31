import SwiftUI

@MainActor
struct TodayWeatherView: View {
    let snapshot: CityWeatherSnapshot?
    let city: String
    let timeZone: TimeZone
    @AppStorage("today.weather.unit") private var unit = "C"
    @State private var showing = false
    @Environment(\.locale) private var locale
    private static let legal = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    var body: some View {
        HStack(spacing: 8) {
            if let snapshot {
                Button { showing = true } label: {
                    HStack(spacing: 6) {
                        Label("Local weather", systemImage: "thermometer.medium").foregroundStyle(.white.opacity(0.75))
                        Text(verbatim: CityWeatherSnapshot.temperature(snapshot.temperatureCelsius, unit: unit, locale: locale)).fontWeight(.semibold).foregroundStyle(Color(hex: 0xFFE3A0))
                    }.font(.caption).monospacedDigit().frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Local weather"))
                .accessibilityValue(Text(verbatim: CityWeatherSnapshot.temperature(snapshot.temperatureCelsius, unit: unit, locale: locale)))
                Spacer(minLength: 8)
                Link(destination: Self.legal) {
                    Image("AppleWeatherMark").renderingMode(.original).resizable().scaledToFit().frame(width: 77, height: 14)
                        .frame(height: 32)
                }
                .accessibilityLabel(Text("Apple Weather data sources"))
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
