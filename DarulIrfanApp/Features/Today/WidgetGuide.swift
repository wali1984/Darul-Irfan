import SwiftUI

/// Whether Today offers the widget guide. iPhone lets only the person place
/// a widget: no app can put one on the Lock Screen or Home Screen itself. So
/// Today offers the steps once, after a place is set (the widgets have
/// nothing to show before), until the person opens the guide or closes the
/// offer. Settings › Widgets keeps the guide afterwards.
enum WidgetGuideOffer {
    static let handledKey = "widgetGuide.offerHandled"

    static func shouldOffer(handled: Bool, hasPlace: Bool) -> Bool {
        hasPlace && !handled
    }
}

/// The one-time offer on Today.
struct TodayWidgetOffer: View {
    let hasPlace: Bool
    @AppStorage(WidgetGuideOffer.handledKey) private var handled = false
    @State private var showingGuide = false

    var body: some View {
        Group {
            if WidgetGuideOffer.shouldOffer(handled: handled, hasPlace: hasPlace) {
                DICard(borderColor: DIColor.accent.opacity(0.6)) {
                    VStack(alignment: .leading, spacing: DISpacing.sm) {
                        HStack(alignment: .top, spacing: DISpacing.sm) {
                            DISealEmblem(diameter: 36, glow: false)
                            VStack(alignment: .leading, spacing: DISpacing.xs) {
                                Text("Add Darul Irfan to your Lock Screen")
                                    .diInterfaceFont(.headline)
                                    .foregroundStyle(DIColor.textPrimary)
                                Text("See the next prayer and its countdown without opening the app.")
                                    .diInterfaceFont(.subheadline)
                                    .foregroundStyle(DIColor.textMuted)
                            }
                            Spacer(minLength: 0)
                            Button {
                                handled = true
                            } label: {
                                Image(systemName: "xmark")
                                    .diInterfaceFont(.footnote, weight: .semibold)
                                    .foregroundStyle(DIColor.textMuted)
                                    .padding(DISpacing.xs)
                            }
                            .accessibilityLabel(Text("Close"))
                        }
                        Button("Show me how") {
                            showingGuide = true
                            handled = true
                        }
                        .buttonStyle(DIPrimaryButtonStyle())
                    }
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingGuide) {
            NavigationStack {
                WidgetGuideView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingGuide = false }
                        }
                    }
            }
        }
    }
}

/// Settings › Widgets: how to place each widget, on iPhone and Apple Watch.
struct WidgetGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                SettingsBrandBanner(
                    titleKey: "Widgets",
                    subtitleKey: "Prayer times at a glance"
                )
                .diAppear()

                Text("iPhone lets only you place widgets: no app can add one for you. These steps take a moment.")
                    .diInterfaceFont(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
                    .padding(.horizontal, DISpacing.xs)

                WidgetGuideCard(
                    systemImage: "lock.fill",
                    titleKey: "Lock Screen",
                    steps: [
                        "Touch and hold the Lock Screen, then tap Customize and choose the Lock Screen.",
                        "Tap the space under the clock, or the line above it.",
                        "Choose Darul Irfan: Next Prayer shows the countdown, Silsila Seal shows the seal."
                    ]
                )
                .diAppear(delay: 0.04)

                WidgetGuideCard(
                    systemImage: "apps.iphone",
                    titleKey: "Home Screen",
                    steps: [
                        "Touch and hold an empty part of the Home Screen, then tap Edit and Add Widget.",
                        "Search for Darul Irfan.",
                        "Choose Prayer Overview (small, medium or large), Ayah of the Day, Next Prayer or Today's Prayer Times."
                    ]
                )
                .diAppear(delay: 0.08)

                WidgetGuideCard(
                    systemImage: "iphone.landscape",
                    titleKey: "StandBy",
                    steps: [
                        "Charge your iPhone on its side while it is locked.",
                        "Swipe to the widgets, touch and hold, then add Prayer Overview."
                    ]
                )
                .diAppear(delay: 0.12)

                WidgetGuideCard(
                    systemImage: "applewatch",
                    titleKey: "Apple Watch",
                    steps: [
                        "Touch and hold the watch face, tap Edit, then choose a complication.",
                        "Choose Next Prayer, Prayer Countdown, Silsila Seal or Next Zikr.",
                        "Open Darul Irfan on the watch to see the seal come to life."
                    ]
                )
                .diAppear(delay: 0.16)

                Text("Apple Watch has no lock screen that apps can change. The seal animates in the app itself and rests, dimmed, when your wrist is down.")
                    .diInterfaceFont(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .padding(.horizontal, DISpacing.xs)
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WidgetGuideCard: View {
    let systemImage: String
    let titleKey: LocalizedStringKey
    let steps: [LocalizedStringKey]

    var body: some View {
        DIElevatedCard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) {
                    ZStack {
                        Circle().fill(DIColor.accent.opacity(0.14))
                        Image(systemName: systemImage)
                            .diInterfaceFont(.subheadline, weight: .semibold)
                            .foregroundStyle(DIColor.accent)
                    }
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                    Text(titleKey)
                        .diInterfaceFont(.headline, design: .serif)
                        .foregroundStyle(DIColor.textPrimary)
                }
                .accessibilityAddTraits(.isHeader)

                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: DISpacing.sm) {
                        Text(verbatim: "\(index + 1)")
                            .diInterfaceFont(.subheadline, weight: .bold)
                            .foregroundStyle(DIColor.accent)
                            .frame(minWidth: 16)
                        Text(step)
                            .diInterfaceFont(.subheadline)
                            .foregroundStyle(DIColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
