import SwiftUI

/// Zikr section entry point, linked from the More tab: the verified Method of
/// Zikr summary, the online zikr schedule with reminders, and the personal
/// tasbih counters.
@MainActor
struct ZikrHomeView: View {
    @State private var viewModel: ZikrHomeViewModel
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: ZikrHomeViewModel(notifications: dependencies.notifications))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                DISectionHeader(titleKey: "Method of Zikr", systemImage: "heart")
                MethodOfZikrCard()

                DISectionHeader(titleKey: "Online Zikr", systemImage: "clock")
                if viewModel.isLoaded && viewModel.sessions.isEmpty {
                    DIEmptyState(
                        systemImage: "clock",
                        titleKey: "Schedule not available",
                        messageKey: "The online zikr schedule could not be loaded. Current timings are always announced on naqshbandiaowaisiah.org."
                    )
                } else {
                    ForEach(viewModel.sessions) { session in
                        ZikrSessionCard(session: session, viewModel: viewModel)
                    }
                }

                DISectionHeader(titleKey: "Tasbih", systemImage: "hand.tap")
                NavigationLink {
                    TasbihListView(trackerRepository: dependencies.trackerRepository)
                } label: {
                    DICard {
                        HStack(spacing: DISpacing.md) {
                            Image(systemName: "hand.tap")
                                .font(.title3)
                                .foregroundStyle(DIColor.primary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: DISpacing.xs) {
                                Text("Tasbih Counters")
                                    .font(DIFont.subheading)
                                    .foregroundStyle(DIColor.textPrimary)
                                Text("Count your personal zikr and build a gentle daily habit.")
                                    .font(.subheadline)
                                    .foregroundStyle(DIColor.textMuted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.forward")
                                .font(.footnote)
                                .foregroundStyle(DIColor.textMuted)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(DISpacing.md)
        }
        .navigationTitle("Zikr")
        .diScreenBackground()
        .task { await viewModel.load() }
        .alert("Notifications are off", isPresented: $viewModel.showPermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To receive zikr reminders, please allow notifications for Darul Irfan in iOS Settings.")
        }
    }
}

// MARK: - Method of Zikr

/// Verified description only — see Docs/RESEARCH_NOTES.md. The full
/// illustrated instructions are deliberately not reproduced here; they are
/// taught on the official website.
private struct MethodOfZikrCard: View {
    private let methodOfZikrURL = URL(string: "https://www.naqshbandiaowaisiah.org/method-of-zikr.html")

    var body: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Zikr-e Khafi Qalbi")
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                Text("The method of zikr in the Naqshbandia Owaisiah order is Zikr-e Khafi Qalbi, practised with Pas Anfas — \"guarding every breath\".")
                    .font(.body)
                    .foregroundStyle(DIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A distinguishing feature of this order is spiritual bai'at directly at the hands of the holy Prophet ﷺ — the Owaisiah transmission.")
                    .font(.body)
                    .foregroundStyle(DIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The complete illustrated method of zikr is taught on the official website.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = methodOfZikrURL {
                    Link(destination: url) {
                        Label("Read the Method of Zikr", systemImage: "safari")
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(DIColor.primary)
                }
            }
        }
    }
}

// MARK: - Online zikr session card

@MainActor
private struct ZikrSessionCard: View {
    let session: ZikrSession
    let viewModel: ZikrHomeViewModel

    var body: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text(verbatim: session.title)
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)

                HStack(spacing: DISpacing.sm) {
                    if ZikrScheduleMath.isDaily(session.weekdays) {
                        DIPillBadge(text: String(localized: "Daily"))
                    } else {
                        DIPillBadge(text: ZikrScheduleMath.shortWeekdaySymbols(for: session.weekdays).joined(separator: " · "))
                    }
                    if session.durationMinutes > 0 {
                        Text("About \(session.durationMinutes) minutes")
                            .font(.caption)
                            .foregroundStyle(DIColor.textMuted)
                    }
                }

                if let next = viewModel.nextOccurrence(forSessionID: session.id) {
                    Text("Next session: \(next.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.primary)
                }
                Text("Announced time: \(ZikrScheduleMath.announcedTimeText(for: session))")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)

                if let note = session.availabilityNote {
                    Text(verbatim: note)
                        .font(.footnote)
                        .italic()
                        .foregroundStyle(DIColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let instructions = session.instructions {
                    Text("How to join")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DIColor.textPrimary)
                        .padding(.top, DISpacing.xs)
                    Text(verbatim: instructions)
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let joinUrlString = session.joinUrl, let joinUrl = URL(string: joinUrlString) {
                    Link(destination: joinUrl) {
                        Label("Join Online Zikr", systemImage: "link")
                    }
                    .buttonStyle(DIPrimaryButtonStyle())
                    .padding(.top, DISpacing.xs)
                }

                Toggle(isOn: Binding(
                    get: { viewModel.isReminderEnabled(session.id) },
                    set: { newValue in
                        Task { await viewModel.setReminder(newValue, for: session) }
                    }
                )) {
                    Label("Remind me before each session", systemImage: "bell")
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textPrimary)
                }
                .tint(DIColor.primary)
                .padding(.top, DISpacing.xs)

                if let sourceString = session.sourceUrl, let sourceUrl = URL(string: sourceString) {
                    Link("Schedule source: naqshbandiaowaisiah.org", destination: sourceUrl)
                        .font(.footnote)
                        .tint(DIColor.textMuted)
                }
            }
        }
    }
}
