import SwiftUI
import UserNotifications

// The Today screen's everyday sections, in the order a day is lived:
// tools to hand, the day's own tasks, where reading and listening left off,
// one thing to understand today, and what is coming up.

// MARK: - Quick tools

/// Quran, Duas, Qibla, Tasbih, My Day and Focus, one tap each, then every
/// other tool behind "All tools".
@MainActor
struct TodayQuickTools: View {
    let dependencies: AppDependencies
    let appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DISpacing.sm) {
                Button {
                    DIHaptics.soft()
                    // The Quran lives in the Read tab; the shell switches to it.
                    NotificationCenter.default.post(name: .didReceiveAppDeepLink, object: "quran")
                } label: {
                    QuickToolChip(title: "Quran", systemImage: "book.closed")
                }
                .buttonStyle(DIPressableStyle())
                chip("Duas", "hands.and.sparkles") { DuasView() }
                chip("Qibla", "location.north.line") { QiblaCompassView(dependencies: dependencies, appState: appState) }
                chip("Tasbih", "hand.tap") {
                    TasbihListView(trackerRepository: dependencies.trackerRepository, devotionalMetrics: dependencies.devotionalMetrics)
                }
                chip("My Day", "checklist") { MyDayView(dependencies: dependencies, appState: appState) }
                chip("Focus", "timer") { FocusTimerView(dependencies: dependencies, appState: appState) }
                chip("All tools", "square.grid.2x2") { ToolsView(dependencies: dependencies, appState: appState) }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip<Destination: View>(
        _ title: LocalizedStringKey,
        _ systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            QuickToolChip(title: title, systemImage: systemImage)
        }
        .buttonStyle(DIPressableStyle())
        .simultaneousGesture(TapGesture().onEnded { DIHaptics.soft() })
    }
}

struct QuickToolChip: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(DIGradient.emerald)
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DIColor.textPrimary)
                .lineLimit(1)
        }
        .frame(width: 70)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - My Day

/// The next three things still to do today, with Add and View all.
@MainActor
struct TodayMyDayCard: View {
    let dependencies: AppDependencies
    let appState: AppState
    @State private var store = MyDayStore.shared
    @State private var isAdding = false

    var body: some View {
        let today = Date()
        let schedule = MyDayPrayerTimes.schedule(on: today, dependencies: dependencies, appState: appState)
        let open = MyDayPlanner.ordered(store.tasks(on: today), on: today, schedule: schedule)
            .filter { !$0.task.isDone(on: today) }
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack {
                    DISectionHeader(titleKey: "My Day", systemImage: "checklist")
                    Spacer()
                    Button {
                        isAdding = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                if open.isEmpty {
                    Text("Nothing left for today. Add a task, or plan one for after a prayer.")
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textMuted)
                }
                ForEach(Array(open.prefix(3))) { entry in
                    DayTaskRow(task: entry.task, time: entry.time, day: today) {
                        store.toggleDone(taskID: entry.task.id, on: today)
                        DIHaptics.light()
                        Task { await appState.refreshScheduledNotificationsAndWidgets() }
                    } onOpen: {}
                }
                NavigationLink {
                    MyDayView(dependencies: dependencies, appState: appState)
                } label: {
                    Text(open.count > 3 ? "View all \(open.count)" : "View all")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack {
                DayTaskEditorView(task: nil) { task in
                    store.upsert(task)
                    Task { await appState.refreshScheduledNotificationsAndWidgets() }
                }
            }
        }
        .onAppear { store.loadIfNeeded() }
    }
}

// MARK: - Continue

/// Where the Quran reading and the last lecture left off.
@MainActor
struct TodayContinueCard: View {
    let dependencies: AppDependencies

    @State private var reading: (surah: QuranSurah, ayah: Int)?
    @State private var listening: (item: MediaItem, progress: PlaybackProgress)?

    var body: some View {
        Group {
            if reading != nil || listening != nil {
                DICard {
                    VStack(alignment: .leading, spacing: DISpacing.sm) {
                        DISectionHeader(titleKey: "Continue", systemImage: "arrow.uturn.forward")
                        if let reading {
                            Button {
                                DIHaptics.soft()
                                NotificationCenter.default.post(name: .didReceiveAppDeepLink, object: "quran")
                                NotificationCenter.default.post(
                                    name: .openQuranAyah,
                                    object: QuranAyahLink(surah: reading.surah.id, ayah: reading.ayah)
                                )
                            } label: {
                                row(
                                    icon: "book.closed",
                                    title: Text(verbatim: reading.surah.nameTransliterated),
                                    detail: Text("Ayah \(reading.ayah)")
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        if let listening, let url = listening.item.streamUrl.flatMap({ URL(string: $0) }) {
                            Button {
                                DIHaptics.soft()
                                // The player restores the saved position itself.
                                let item = AudioPlayableItem(
                                    id: listening.item.id,
                                    title: listening.item.title,
                                    subtitle: listening.item.speaker,
                                    url: url,
                                    mediaItemID: listening.item.id
                                )
                                dependencies.audioPlayer.play(item, queue: [])
                            } label: {
                                row(
                                    icon: "play.circle",
                                    title: Text(verbatim: listening.item.title),
                                    detail: Text("Resume listening")
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func row(icon: String, title: Text, detail: Text) -> some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(DIColor.primary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                title.font(.subheadline.weight(.semibold)).foregroundStyle(DIColor.textPrimary).lineLimit(2)
                detail.font(.caption).foregroundStyle(DIColor.textMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.footnote).foregroundStyle(DIColor.textMuted)
        }
        .contentShape(Rectangle())
    }

    private func load() async {
        if let progress = try? await dependencies.quranRepository.lastReadPosition(),
           let surahs = try? await dependencies.quranRepository.allSurahs(),
           let surah = surahs.first(where: { $0.id == progress.surahNumber }) {
            reading = (surah, progress.ayahNumber)
        }
        if let recent = try? await dependencies.mediaRepository.recentlyPlayed(limit: 1).first {
            listening = recent
        }
    }
}

// MARK: - Understand something today

/// One theme a day, from the app's own reviewed topics: its verses with the
/// Silsila's translation, and related books and bayans. Nothing generated.
@MainActor
struct TodayUnderstandCard: View {
    let dependencies: AppDependencies
    let appState: AppState
    @State private var topic: Topic?

    var body: some View {
        Group {
            if let topic {
                NavigationLink {
                    TopicDetailView(topic: topic, dependencies: dependencies, appState: appState)
                } label: {
                    DICard {
                        VStack(alignment: .leading, spacing: DISpacing.sm) {
                            DISectionHeader(titleKey: "Understand something today", systemImage: "lightbulb")
                            HStack(spacing: DISpacing.sm) {
                                Image(systemName: topic.systemIcon)
                                    .font(.title2)
                                    .foregroundStyle(DIColor.accent)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: topic.name(for: appState.settings.language))
                                        .font(DIFont.subheading)
                                        .foregroundStyle(DIColor.textPrimary)
                                    Text("Verses, tafsir, books and bayans on this theme")
                                        .font(.caption)
                                        .foregroundStyle(DIColor.textMuted)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.forward").font(.footnote).foregroundStyle(DIColor.textMuted)
                            }
                        }
                    }
                }
                .buttonStyle(DIPressableStyle())
            }
        }
        .task {
            let topics = await Task.detached(priority: .utility) { SeedBundle.topics() }.value
            guard !topics.isEmpty else { return }
            // The same theme all day, a different one each day.
            let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
            topic = topics[day % topics.count]
        }
    }
}

// MARK: - Upcoming

/// The next online zikr session and the next Dar-ul-Irfan program.
@MainActor
struct TodayUpcomingCard: View {
    let dependencies: AppDependencies
    let appState: AppState
    @State private var zikr: (title: String, start: Date)?
    @State private var event: CommunityEvent?

    var body: some View {
        Group {
            if zikr != nil || event != nil {
                DICard {
                    VStack(alignment: .leading, spacing: DISpacing.sm) {
                        DISectionHeader(titleKey: "Upcoming", systemImage: "calendar.badge.clock")
                        if let zikr {
                            Button {
                                NotificationCenter.default.post(name: .didReceiveAppDeepLink, object: "zikr")
                            } label: {
                                line(icon: "sparkles", title: zikr.title, when: Text("Your time: \(ZikrScheduleMath.localTimeText(zikr.start))"))
                            }
                            .buttonStyle(.plain)
                        }
                        if let event, let start = event.startDate {
                            NavigationLink {
                                EventDetailView(event: event, notifications: dependencies.notifications)
                            } label: {
                                line(
                                    icon: "building.columns",
                                    title: event.title,
                                    when: Text(start, format: .dateTime.weekday(.abbreviated).day().month())
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func line(icon: String, title: String, when: Text) -> some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: icon).foregroundStyle(DIColor.primary).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.subheadline.weight(.semibold)).foregroundStyle(DIColor.textPrimary)
                when.font(.caption).foregroundStyle(DIColor.textMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.footnote).foregroundStyle(DIColor.textMuted)
        }
        .contentShape(Rectangle())
    }

    private func load() async {
        let now = Date()
        let sessions = SeedBundle.zikrSessions()
            .map { ZikrAnchorResolver.resolved($0, at: now, calculator: dependencies.prayerCalculation) }
        zikr = sessions
            .compactMap { session in
                ZikrScheduleMath.currentOrNextOccurrence(of: session, at: now).map { (session.title, $0) }
            }
            .min { $0.1 < $1.1 }
            .map { (title: $0.0, start: $0.1) }
        let events = (try? await dependencies.eventsRepository.events()) ?? []
        event = events
            .filter { ($0.startDate ?? .distantPast) >= Calendar.current.startOfDay(for: now) }
            .min { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }
}

// MARK: - Reminder status

/// Whether prayer alerts will actually arrive: permission, and how many
/// prayers have an alert on. Opens the notification settings, where a test
/// reminder can be sent.
@MainActor
struct TodayReminderStatus: View {
    let dependencies: AppDependencies
    let appState: AppState
    @State private var allowed: Bool?

    var body: some View {
        NavigationLink {
            NotificationSettingsView(dependencies: dependencies, appState: appState)
        } label: {
            HStack(spacing: DISpacing.sm) {
                Image(systemName: allowed == false ? "bell.slash.fill" : "bell.badge.fill")
                    .foregroundStyle(allowed == false ? DIColor.danger : DIColor.primary)
                Group {
                    if allowed == false {
                        Text("Notifications are off - prayer alerts will not arrive")
                    } else {
                        Text("Alerts on for \(enabledCount) of 5 prayers")
                    }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(DIColor.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward").font(.caption).foregroundStyle(DIColor.textMuted)
            }
            .padding(.horizontal, DISpacing.sm)
            .padding(.vertical, DISpacing.xs)
        }
        .buttonStyle(.plain)
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            allowed = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral
        }
    }

    private var enabledCount: Int {
        Prayer.obligatory.filter { appState.settings.prayerNotifications.style(for: $0) != .off }.count
    }
}

// MARK: - Calculation method

/// Which convention today's times follow, and where - stated plainly under
/// the times so nobody has to guess why they differ from a mosque's sheet.
@MainActor
struct TodayMethodLine: View {
    let appState: AppState

    var body: some View {
        let calculation = appState.settings.calculation
        let method = String(localized: String.LocalizationValue(calculation.method.englishName))
        let asr = calculation.asrMethod == .hanafi ? String(localized: "Hanafi Asr") : String(localized: "Shafi Asr")
        let place = appState.activePlace?.name ?? ""
        Text(verbatim: [method, asr, place].filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(DIColor.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DISpacing.sm)
    }
}

/// Offered once, when the method in use is not the one used where the
/// person is and they have never chosen one themselves.
@MainActor
struct TodayMethodSuggestion: View {
    let appState: AppState

    var body: some View {
        let calculation = appState.settings.calculation
        if calculation.methodConfirmed != true,
           let place = appState.activePlace,
           let recommended = CalculationMethodChoice.recommended(forCountryCode: place.countryCode),
           recommended != calculation.method {
            let current = String(localized: String.LocalizationValue(calculation.method.englishName))
            let suggested = String(localized: String.LocalizationValue(recommended.englishName))
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    Label("Check your calculation method", systemImage: "exclamationmark.circle")
                        .font(.headline)
                    Text("Times are calculated with \(current). Around \(place.name), \(suggested) is in common use, and Fajr and Isha can differ between them by 15 to 30 minutes.")
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textMuted)
                    HStack(spacing: DISpacing.sm) {
                        Button("Use \(suggested)") {
                            Task {
                                await appState.updateSettings {
                                    $0.calculation.method = recommended
                                    $0.calculation.methodConfirmed = true
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Keep \(current)") {
                            Task { await appState.updateSettings { $0.calculation.methodConfirmed = true } }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}
