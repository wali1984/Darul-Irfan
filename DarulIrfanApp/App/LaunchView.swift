import SwiftUI

/// Brand splash shown while the dependency graph is built and settings load.
/// Deliberately quiet: deep emerald field, the app's name in Urdu and
/// English, the tagline, and a subtle progress indicator.
struct LaunchView: View {
    var body: some View {
        ZStack {
            DIColor.primaryDeep.ignoresSafeArea()

            VStack(spacing: DISpacing.md) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(DIColor.accent)
                    .accessibilityHidden(true)

                VStack(spacing: DISpacing.sm) {
                    Text(verbatim: "دارالعرفان")
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .foregroundStyle(DIColor.onPrimary)

                    Text("Darul Irfan")
                        .font(DIFont.heading)
                        .foregroundStyle(DIColor.onPrimary.opacity(0.92))

                    Text("Light of Sacred Knowledge")
                        .font(.subheadline)
                        .foregroundStyle(DIColor.onPrimary.opacity(0.75))
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)

                ProgressView()
                    .tint(DIColor.accent)
                    .padding(.top, DISpacing.lg)
                    .accessibilityLabel("Loading")
            }
            .padding(DISpacing.lg)
        }
    }
}
