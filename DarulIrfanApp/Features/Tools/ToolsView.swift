import SwiftUI

/// Every everyday tool in one place: opened from Today's "All tools" and
/// from Community, so nothing useful is buried three screens deep.
@MainActor
struct ToolsView: View {
    let dependencies: AppDependencies
    let appState: AppState

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: DISpacing.sm)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                group("Prayer", systemImage: "sun.max") {
                    tool("Qibla", "location.north.line") { QiblaCompassView(dependencies: dependencies, appState: appState) }
                    tool("Monthly timetable", "calendar") { MonthlyTimetableView(dependencies: dependencies, appState: appState) }
                    tool("Fasting record", "moon.haze") { FastingView(dependencies: dependencies, appState: appState) }
                    tool("Islamic days", "star.circle") { IslamicDaysView(hijri: dependencies.hijri, appState: appState) }
                }
                group("Remembrance", systemImage: "moon.stars") {
                    tool("Tasbih", "hand.tap") {
                        TasbihListView(trackerRepository: dependencies.trackerRepository, devotionalMetrics: dependencies.devotionalMetrics)
                    }
                    tool("Duas", "hands.and.sparkles") { DuasView() }
                    tool("99 Names", "sparkles") { NamesOfAllahView() }
                    tool("Topics", "square.grid.2x2") { TopicsBrowseView(dependencies: dependencies, appState: appState) }
                }
                group("My Day", systemImage: "checklist") {
                    tool("My Day", "checklist") { MyDayView(dependencies: dependencies, appState: appState) }
                    tool("Your Daily Personal Zikr", "timer") { FocusTimerView(dependencies: dependencies, appState: appState) }
                    tool("Private notes", "note.text") { NotesView() }
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .diPageHeading("Tools")
    }

    private func group<Content: View>(
        _ title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: title, systemImage: systemImage)
            LazyVGrid(columns: columns, spacing: DISpacing.sm) {
                content()
            }
        }
    }

    private func tool<Destination: View>(
        _ title: LocalizedStringKey,
        _ systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            ToolTile(title: title, systemImage: systemImage)
        }
        .buttonStyle(DIPressableStyle())
        .accessibilityIdentifier("tool-" + systemImage)
    }
}

/// A square tool button: medallion icon above a short name.
struct ToolTile: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(spacing: DISpacing.xs) {
            ZStack {
                Circle().fill(DIGradient.emerald)
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DIColor.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .padding(.vertical, DISpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                .fill(DIColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                .stroke(DIColor.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
