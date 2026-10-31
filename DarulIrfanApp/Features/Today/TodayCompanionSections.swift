import SwiftUI
import UserNotifications

// The Today screen's everyday sections: tools to hand, where reading and
// listening left off, and the pieces of the Prayer times page that say how
// the times are calculated and whether alerts will arrive. My Day,
// Understand and Upcoming left Today in the October 2026 redesign (to the
// My Day orb, Discover's Theme of the day and the Zikr tab); their cards are
// kept here for the screens that take them up.

// MARK: - Quick tools

/// The tool orbs: Duas, Qibla, Tasbih and My Day, one tap each, then every
/// other tool (Focus, Notes, Fasting, the timetable) behind the gold "All
/// tools". The Quran is the Read tab's.
@MainActor
struct TodayQuickTools: View {
    let dependencies: AppDependencies
    let appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Large text: three to a row, so no name is cut short.
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: DISpacing.md
                ) {
                    orbs
                }
            } else {
                HStack(alignment: .top, spacing: 6) {
                    orbs
                }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var orbs: some View {
        orb("Duas", "hands.and.sparkles") { DuasView() }
        orb("Qibla", "location.north.line") { QiblaCompassView(dependencies: dependencies, appState: appState) }
        orb("Tasbih", "hand.tap") {
            TasbihListView(trackerRepository: dependencies.trackerRepository, devotionalMetrics: dependencies.devotionalMetrics)
        }
        orb("My Day", "checklist") { MyDayView(dependencies: dependencies, appState: appState) }
        orb("All tools", "square.grid.2x2", gold: true) { ToolsView(dependencies: dependencies, appState: appState) }
    }

    private func orb<Destination: View>(
        _ title: LocalizedStringKey,
        _ systemImage: String,
        gold: Bool = false,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            DIToolOrb(titleKey: title, systemImage: systemImage, gold: gold)
        }
        .buttonStyle(DIPressableStyle())
        .accessibilityIdentifier("quick-tool-" + systemImage)
        .simultaneousGesture(TapGesture().onEnded { DIHaptics.soft() })
    }
}

/// The tool chip Today used before the orbs; kept for any screen that
/// wants the smaller chip.
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
    @State private var editing: DayTask?

    var body: some View {
        let today = Date()
        let schedule = prayerSchedule(on: today)
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
                    } onOpen: {
                        editing = entry.task
                    }
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
                DayTaskEditorView(task: nil, prayerSchedule: { prayerSchedule(on: $0) }) { task in
                    store.upsert(task)
                    Task { await appState.refreshScheduledNotificationsAndWidgets() }
                }
            }
        }
        .sheet(item: $editing) { task in
            NavigationStack {
                DayTaskEditorView(task: task, prayerSchedule: { prayerSchedule(on: $0) }, onSave: { updated in
                    store.upsert(updated)
                    Task { await appState.refreshScheduledNotificationsAndWidgets() }
                }, onDelete: {
                    store.delete(taskID: task.id)
                    Task { await appState.refreshScheduledNotificationsAndWidgets() }
                })
            }
        }
        .onAppear { store.loadIfNeeded() }
    }

    private func prayerSchedule(on day: Date) -> PrayerDaySchedule? {
        MyDayPrayerTimes.schedule(on: day, dependencies: dependencies, appState: appState)
    }
}

// MARK: - Continue

/// Continue: where the Qur'an reading and the last bayan left off, as two
/// tiles side by side, each with how far it has gone.
@MainActor
struct TodayContinueCard: View {
    let dependencies: AppDependencies

    @State private var reading: (surah: QuranSurah, ayah: Int)?
    @State private var listening: (item: MediaItem, progress: PlaybackProgress)?
    /// The last lecture as the player takes it: the downloaded file when
    /// there is one, so it resumes offline too.
    @State private var listeningPlayable: AudioPlayableItem?

    var body: some View {
        Group {
            if reading != nil || listeningPlayable != nil {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    TodaySectionTitle(titleKey: "Continue", systemImage: "arrow.counterclockwise")
                    HStack(alignment: .top, spacing: 10) {
                        if let reading {
                            readingTile(surah: reading.surah, ayah: reading.ayah)
                        }
                        if let listening, let playable = listeningPlayable {
                            listeningTile(item: listening.item, progress: listening.progress, playable: playable)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task { await load() }
    }

    private func readingTile(surah: QuranSurah, ayah: Int) -> some View {
        Button {
            DIHaptics.soft()
            // Kept until the reader takes it, so it lands even the first
            // time the Read tab opens.
            DeepLinkRouter.shared.open(.quranAyah(surah: surah.id, ayah: ayah))
        } label: {
            tile(
                systemImage: "book.closed",
                gold: false,
                title: Text(verbatim: surah.nameTransliterated),
                titleIsUrdu: false,
                detail: Text("Qur'an · Ayah \(ayah)"),
                progress: Double(ayah) / Double(max(surah.ayahCount, 1))
            )
        }
        .buttonStyle(DIPressableStyle())
    }

    private func listeningTile(item: MediaItem, progress: PlaybackProgress, playable: AudioPlayableItem) -> some View {
        let secondsLeft = max(0, progress.durationSeconds - progress.positionSeconds)
        let minutesLeft = max(1, Int((secondsLeft / 60).rounded()))
        return Button {
            DIHaptics.soft()
            // The player restores the saved position itself.
            dependencies.audioPlayer.play(playable, queue: [])
        } label: {
            tile(
                systemImage: "play.fill",
                gold: true,
                title: Text(verbatim: item.title),
                titleIsUrdu: item.language == "ur",
                detail: progress.durationSeconds > 0 ? Text("Bayan · \(minutesLeft) min left") : Text("Resume listening"),
                progress: progress.fractionCompleted
            )
        }
        .buttonStyle(DIPressableStyle())
    }

    private func tile(
        systemImage: String,
        gold: Bool,
        title: Text,
        titleIsUrdu: Bool,
        detail: Text,
        progress: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TodayOrbIcon(systemImage: systemImage, gold: gold)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(titleIsUrdu ? DIFont.urduBody(scale: 0.85) : Font.subheadline.weight(.bold))
                    .foregroundStyle(DIColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                detail
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            progressBar(progress)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .todayGlass(cornerRadius: 22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func progressBar(_ progress: Double) -> some View {
        let value = min(max(progress.isFinite ? progress : 0, 0), 1)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(TodayPalette.track)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x13A06F), DIColor.goldGlow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(value))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private func load() async {
        if let progress = try? await dependencies.quranRepository.lastReadPosition(),
           let surahs = try? await dependencies.quranRepository.allSurahs(),
           let surah = surahs.first(where: { $0.id == progress.surahNumber }) {
            reading = (surah, progress.ayahNumber)
        }
        if let recent = try? await dependencies.mediaRepository.recentlyPlayed(limit: 1).first {
            listening = recent
            let assets = (try? await dependencies.downloadsRepository.allAssets()) ?? []
            listeningPlayable = MediaPlayback.playableItem(
                for: recent.item,
                asset: assets.first(where: { $0.mediaItemID == recent.item.id }),
                downloadManager: dependencies.downloadManager
            )
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
    var liveShown = false
    @Environment(\.scenePhase) private var scenePhase
    /// The official schedule, as the Zikr tab and the reminders follow it.
    @State private var sessions: [ZikrSession] = []
    @State private var events: [CommunityEvent] = []

    /// Event dates are calendar days, stored as midnight UTC. They are read
    /// and shown as that day, not moved into the phone's time zone, where
    /// they fell a day early across the Americas.
    private static let eventTimeZone = TimeZone(identifier: "UTC") ?? .current

    var body: some View {
        // Re-read every minute, so a session that has ended gives way to
        // the next one while Today stays open.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(at: context.date)
        }
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await load() }
            }
        }
    }

    @ViewBuilder
    private func content(at now: Date) -> some View {
        let zikr = nextZikr(at: now)
        let event = nextEvent(at: now)
        if let zikr {
            Button {
                DeepLinkRouter.shared.open(route(for: zikr))
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(DailyZikrBanner.phase(start: zikr.startsAt, end: zikr.endsAt, now: now) == .live ? "LIVE NOW" : "Upcoming")
                        .font(.caption.weight(.bold)).foregroundStyle(Color(hex: 0xFFE3A0))
                    Text(LocalizedStringKey(DailyZikrBanner.title))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text("Your time: \(ZikrScheduleMath.localTimeText(zikr.startsAt))")
                        .font(.footnote).foregroundStyle(Color(hex: 0xE9CE86))
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Color(hex: 0x0D7A55), Color(hex: 0x04321F)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
            }
            .buttonStyle(DIPressableStyle())
        }
        if let event, let start = event.startDate {
            DICard {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    DISectionHeader(titleKey: "Upcoming", systemImage: "calendar.badge.clock")
                        NavigationLink {
                            EventDetailView(event: event, notifications: dependencies.notifications)
                        } label: {
                            line(
                                icon: "building.columns",
                                title: event.title,
                                when: Text(start, format: Date.FormatStyle(timeZone: Self.eventTimeZone).weekday(.abbreviated).day().month())
                            )
                        }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    /// The Zikr tab at the card of the session shown: the Daily Zikr
    /// broadcast, or the Tahajjud zikr joined on Paltalk.
    private func route(for zikr: WidgetZikrSession) -> AppRoute {
        let sessionID = zikr.id.split(separator: "|").first.map(String.init) ?? ""
        if sessionID == "zikr-after-isha" { return .live }
        if sessionID.contains("tahajjud") { return .zikr(session: "tahajjud") }
        return .zikr(session: nil)
    }

    /// The session in progress, or else the next one.
    private func nextZikr(at now: Date) -> WidgetZikrSession? {
        ZikrOccurrences.widgetSessions(
            for: sessions.filter { $0.id == "zikr-after-isha" },
            reference: now,
            perSession: 2,
            calculator: dependencies.prayerCalculation
        ).first { !liveShown && DailyZikrBanner.phase(start: $0.startsAt, end: $0.endsAt, now: now) != nil }
    }

    /// The first program on or after the person's today.
    private func nextEvent(at now: Date) -> CommunityEvent? {
        let today = DayKey.make(from: now)
        return events
            .filter { event in
                guard let start = event.startDate else { return false }
                return DayKey.make(from: start, timeZone: Self.eventTimeZone) >= today
            }
            .min { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
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
        sessions = OfficialZikrSchedule.sessions()
        events = (try? await dependencies.eventsRepository.events()) ?? []
    }
}

// MARK: - Reminder status

/// Whether prayer alerts will actually arrive: permission, and how many
/// prayers have an alert on ("Alerts on for 5 of 5 prayers ›" under the
/// Prayer times page's times). Opens the notification settings, where a
/// test reminder can be sent.
@MainActor
struct TodayReminderStatus: View {
    let dependencies: AppDependencies
    let appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var allowed: Bool?

    var body: some View {
        NavigationLink {
            NotificationSettingsView(dependencies: dependencies, appState: appState)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: allowed == false ? "bell.slash.fill" : "bell.badge.fill")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                Group {
                    if allowed == false {
                        Text("Notifications are off - prayer alerts will not arrive")
                    } else {
                        Text("Alerts on for \(enabledCount) of 5 prayers")
                    }
                }
                .font(.subheadline.weight(.bold))
                .multilineTextAlignment(.leading)
                Image(systemName: "chevron.forward")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(allowed == false ? DIColor.danger : TodayPalette.emerald)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task { allowed = await dependencies.notifications.notificationsAllowed() }
        // Coming back from the Settings app with notifications allowed must
        // not leave "Notifications are off" on screen.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { allowed = await dependencies.notifications.notificationsAllowed() }
            }
        }
    }

    private var enabledCount: Int {
        Prayer.obligatory.filter { appState.settings.prayerNotifications.style(for: $0) != .off }.count
    }
}

// MARK: - Calculation method

/// Which convention today's times follow, and where - stated plainly under
/// the times so nobody has to guess why they differ from a mosque's sheet.
/// The Prayer times page names the place in its own header, so it leaves
/// the place out here.
@MainActor
struct TodayMethodLine: View {
    let appState: AppState
    var showsPlace = true

    var body: some View {
        let calculation = appState.settings.calculation
        let method = String(localized: String.LocalizationValue(calculation.method.englishName))
        let asr = calculation.asrMethod == .hanafi ? String(localized: "Hanafi Asr") : String(localized: "Shafi Asr")
        let place = showsPlace ? (appState.activePlace?.name ?? "") : ""
        Text(verbatim: [method, asr, place].filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.footnote.weight(.medium))
            .foregroundStyle(DIColor.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Offered once, when the method in use is not the one used where the
/// person is and they have never chosen one themselves. Sits in the footer
/// of the Prayer times page's times.
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
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Label("Check your calculation method", systemImage: "exclamationmark.circle")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TodayPalette.goldText)
                Text("Times are calculated with \(current). Around \(place.name), \(suggested) is in common use, and Fajr and Isha can differ between them by 15 to 30 minutes.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DISpacing.sm) {
                        useButton(recommended: recommended, suggested: suggested)
                        keepButton(current: current)
                    }
                    VStack(alignment: .leading, spacing: DISpacing.sm) {
                        useButton(recommended: recommended, suggested: suggested)
                        keepButton(current: current)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DIColor.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.vertical, DISpacing.xs)
        }
    }

    private func useButton(recommended: CalculationMethodChoice, suggested: String) -> some View {
        Button("Use \(suggested)") {
            Task {
                await appState.updateSettings {
                    $0.calculation.method = recommended
                    $0.calculation.methodConfirmed = true
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(DIColor.primary)
    }

    private func keepButton(current: String) -> some View {
        Button("Keep \(current)") {
            Task { await appState.updateSettings { $0.calculation.methodConfirmed = true } }
        }
        .buttonStyle(.bordered)
        .tint(DIColor.primary)
    }
}
