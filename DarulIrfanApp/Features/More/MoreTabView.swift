import SwiftUI

/// Root of the "More" tab: hosts Zikr, Events & Dar-ul-Irfan, Qibla, the
/// daily Companion, Settings, and About, plus the global search sheet.
/// Owns its own NavigationStack per the app navigation contract.
@MainActor
struct MoreTabView: View {
    private let dependencies: AppDependencies
    private let appState: AppState

    @State private var isSearchPresented = false

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
    }

    var body: some View {
        NavigationStack {
            List {
                communitySection
                appSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .diScreenBackground()
            .navigationTitle("More")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSearchPresented = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search")
                }
            }
            .sheet(isPresented: $isSearchPresented) {
                GlobalSearchView(dependencies: dependencies)
            }
        }
    }

    // MARK: - Sections

    private var communitySection: some View {
        Section {
            NavigationLink {
                ZikrHomeView(dependencies: dependencies, appState: appState)
            } label: {
                MoreLinkRow(
                    titleKey: "Zikr",
                    subtitleKey: "Method of Zikr and online sessions",
                    systemImage: "sparkles",
                    iconColor: DIColor.primary
                )
            }
            .listRowBackground(DIColor.surface)

            NavigationLink {
                EventsHomeView(dependencies: dependencies, appState: appState)
            } label: {
                MoreLinkRow(
                    titleKey: "Events & Dar-ul-Irfan",
                    subtitleKey: "Ijtema dates, announcements and directions",
                    systemImage: "calendar",
                    iconColor: DIColor.primary
                )
            }
            .listRowBackground(DIColor.surface)

            NavigationLink {
                QiblaCompassView(dependencies: dependencies, appState: appState)
            } label: {
                MoreLinkRow(
                    titleKey: "Qibla Compass",
                    subtitleKey: "Direction to the Kaaba",
                    systemImage: "location.north.circle.fill",
                    iconColor: DIColor.accent
                )
            }
            .listRowBackground(DIColor.surface)

            NavigationLink {
                CompanionHomeView(dependencies: dependencies, appState: appState)
            } label: {
                MoreLinkRow(
                    titleKey: "Daily Companion",
                    subtitleKey: "99 Names, duas, Islamic days and tasbih",
                    systemImage: "heart.text.square.fill",
                    iconColor: DIColor.primary
                )
            }
            .listRowBackground(DIColor.surface)
        } header: {
            Text("Community")
        }
    }

    private var appSection: some View {
        Section {
            NavigationLink {
                SettingsHomeView(dependencies: dependencies, appState: appState)
            } label: {
                MoreLinkRow(
                    titleKey: "Settings",
                    subtitleKey: "Prayer setup, appearance and storage",
                    systemImage: "gearshape.fill",
                    iconColor: DIColor.primaryDeep
                )
            }
            .listRowBackground(DIColor.surface)

            NavigationLink {
                AboutView()
            } label: {
                MoreLinkRow(
                    titleKey: "About",
                    subtitleKey: "Darul Irfan and Silsila Naqshbandia Owaisiah",
                    systemImage: "info.circle.fill",
                    iconColor: DIColor.primaryDeep
                )
            }
            .listRowBackground(DIColor.surface)
        } header: {
            Text("App")
        }
    }
}

// MARK: - Row

private struct MoreLinkRow: View {
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey
    let systemImage: String
    var iconColor: Color = DIColor.primary

    var body: some View {
        HStack(spacing: DISpacing.md) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(DIColor.onPrimary)
                .frame(width: 32, height: 32)
                .background(iconColor)
                .clipShape(RoundedRectangle(cornerRadius: DIRadius.sm, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.body.weight(.medium))
                    .foregroundStyle(DIColor.textPrimary)
                Text(subtitleKey)
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
        .padding(.vertical, DISpacing.xs)
    }
}
