import SwiftUI
import UserNotifications

@MainActor
struct PersonalZikrView: View {
    @State private var store = PersonalZikrStore.shared
    @State private var shajra = false
    @State private var adding = false
    @State private var customName = ""
    @State private var choosing: PersonalZikrStep?
    @State private var ended = false
    @State private var confirmingDiscard = false
    @State private var denied = false
    @State private var requestingReminder = false
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    timer(at: context.date)
                        .onChange(of: store.run?.endsAt.map { $0 <= context.date } ?? false) { _, done in
                            if done && isVisible && scenePhase == .active {
                                store.playChime()
                                store.settle(at: context.date)
                                ended = store.run == nil
                                if ended { DIHaptics.success() }
                            }
                        }
                }
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { shajra.toggle() } } label: {
                    Label(shajra ? "Close Shajra" : "Read Shajra", systemImage: "point.3.connected.trianglepath.dotted")
                        .diInterfaceFont(.headline, weight: .bold)
                        .foregroundStyle(Color(hex: 0x163D2D))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(LinearGradient(colors: [Color(hex: 0xFFE3A0), Color(hex: 0xDDB65F)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: DIColor.goldGlow.opacity(0.22), radius: 10, y: 4)
                }
                .buttonStyle(DIPressableStyle())
                .accessibilityIdentifier("personal-zikr-shajra")
                if shajra { ShajraInlineContent().transition(.opacity) }
                MethodOfZikrLink()
                if store.historyReadFailed {
                    DICard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Your personal records could not be read. Please try again.").foregroundStyle(DIColor.textPrimary)
                            Button("Retry") { store.retryHistory() }.buttonStyle(DISecondaryButtonStyle())
                        }
                    }
                } else {
                    PersonalZikrHistoryCard(entries: store.history)
                }
                sequence
                reminders
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .toggleStyle(SwitchToggleStyle(tint: DIColor.primary))
        .navigationTitle("Your Daily Personal Zikr")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isVisible = true; store.screenActive = scenePhase == .active; store.settle(); store.refreshAlerts() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refreshAlertAccess()
        }
        .onDisappear { isVisible = false; store.screenActive = false }
        .onChange(of: scenePhase) { _, phase in
            // Navigation keeps this view alive behind Method of Zikr. A scene
            // resume alone must not silence alerts for that hidden timer.
            store.screenActive = isVisible && phase == .active
            if isVisible && phase == .active { store.settle(); store.refreshAlerts() }
        }
        .confirmationDialog("Discard this session?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard session", role: .destructive) { store.discard(); ended = false }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(item: $choosing) { step in durationSheet(step) }
        .sheet(isPresented: $adding) {
            NavigationStack {
                Form {
                    TextField("Muraqaba name", text: $customName)
                        .onChange(of: customName) { _, value in customName = String(value.prefix(80)) }
                    Button("Add") { store.addCustom(customName); customName = ""; adding = false }
                        .buttonStyle(DIPrimaryButtonStyle())
                        .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .navigationTitle("Add a Muraqaba")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } } }
            }
            .tint(DIColor.actionForeground)
            .presentationDetents([.medium])
        }
    }

    private func timer(at now: Date) -> some View {
        let run = store.run
        let plan = run?.plan ?? store.plan
        let position = PersonalZikrMath.position(plan, elapsed: run?.elapsed(at: now) ?? 0)
        let remaining = PersonalZikrMath.total(plan) - (run?.elapsed(at: now) ?? 0)
        let progress = position.map { 1 - $0.remaining / Double($0.step.minutes * 60) } ?? 0
        return VStack(spacing: 14) {
            HStack {
                Text("A moment of connection").diInterfaceFont(.footnote).foregroundStyle(Color(hex: 0xE9CE86))
                Spacer()
                DILivingSealMark(diameter: 38).accessibilityHidden(true)
            }
            Text(verbatim: run != nil && remaining <= 0 ? String(localized: "Completed") : position?.step.localizedTitle ?? String(localized: "Choose your stages"))
                .diInterfaceFont(.title2, weight: .semibold).foregroundStyle(.white).multilineTextAlignment(.center)
            if let position { Text("Stage \(position.index + 1) of \(plan.count)").diInterfaceFont(.caption).foregroundStyle(.white.opacity(0.7)) }
            ZStack {
                Circle().stroke(Color(hex: 0xE9CE86).opacity(0.12), lineWidth: 1)
                Circle().stroke(.white.opacity(0.12), lineWidth: 4).padding(8)
                Circle().trim(from: 0, to: min(1, max(0, progress)))
                    .stroke(Color(hex: 0xF4D889), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(8)
                    .animation(reduceMotion ? nil : .linear(duration: 0.85), value: progress)
                VStack(spacing: 4) {
                    Text(verbatim: PersonalZikrMath.text(position?.remaining ?? 0))
                        .font(.system(size: 42, weight: .light).monospacedDigit()).foregroundStyle(.white)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(run != nil && remaining <= 0 ? "Completed" : run?.startedAt != nil ? "In progress" : run != nil ? "Paused" : "Ready when you are")
                        .diInterfaceFont(.caption2).foregroundStyle(Color(hex: 0xE9CE86))
                }
            }
            .frame(width: 184, height: 184)
            Text("Total remaining: \(PersonalZikrMath.text(remaining))").diInterfaceFont(.footnote).foregroundStyle(.white.opacity(0.8))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { controls }
                VStack(spacing: 12) { controls }
            }
            if run != nil { Button("Discard session") { confirmingDiscard = true }.buttonStyle(ZikrTimerButtonStyle()) }
            if ended { Text("Your personal Zikr session is complete.").diInterfaceFont(.footnote).foregroundStyle(Color(hex: 0xF4D889)) }
        }
        .tint(Color(hex: 0xE9CE86))
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Color(hex: 0x0B7250), Color(hex: 0x043221)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
        .onChange(of: position?.index) { old, next in
            if old != nil, next != nil, run?.startedAt != nil, isVisible, scenePhase == .active { store.playChime(); DIHaptics.soft() }
        }
        .diAppear()
    }

    @ViewBuilder private var controls: some View {
        if store.run?.startedAt != nil {
            Button("Pause") { store.pause() }.buttonStyle(ZikrTimerButtonStyle())
        } else {
            Button(store.run == nil ? "Start" : "Resume") {
                store.start(); ended = false; DIHaptics.light()
                Task { denied = !(await store.requestAlerts()) }
            }
            .buttonStyle(ZikrTimerButtonStyle(prominent: true)).disabled(store.plan.isEmpty || store.historyReadFailed)
        }
        if store.run != nil {
            Button("Finish & save") { ended = store.finish(); if ended { DIHaptics.success() } }
                .buttonStyle(ZikrTimerButtonStyle()).disabled(store.historyReadFailed)
        }
    }

    private var steps: [PersonalZikrStep] {
        let plan = store.run?.plan ?? store.plan
        return PersonalZikrStage.allCases.map { stage in plan.first { $0.customID == nil && $0.stage == stage } ?? PersonalZikrStep(stage: stage, minutes: store.storedMinutes(stage)) } + store.customs
    }
    private var sequence: some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            DISectionHeader(titleKey: store.run == nil ? "Your Zikr sequence" : "Current sequence")
            Text("Choose your stages. Set 1–60 minutes each; a soft chime marks every change.")
                .diInterfaceFont(.footnote).foregroundStyle(DIColor.textMuted)
            DICard {
                VStack(spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        stageRow(step, index: index)
                        if index < steps.count - 1 { Divider() }
                    }
                }
            }
            if store.run == nil {
                Button("Add a Muraqaba") { adding = true }.buttonStyle(DISecondaryButtonStyle()).disabled(store.customs.count >= 24)
            }
        }
    }
    private func stageRow(_ step: PersonalZikrStep, index: Int) -> some View {
        let selected = store.plan.contains { $0.id == step.id }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(verbatim: "\(index + 1)").diInterfaceFont(.caption).foregroundStyle(DIColor.actionForeground)
                    .frame(width: 30, height: 30).background(DIColor.accent.opacity(0.12), in: Circle())
                Text(verbatim: step.localizedTitle).diInterfaceFont(.subheadline, weight: .medium).foregroundStyle(DIColor.textPrimary)
                Spacer(minLength: 0)
                Toggle(step.localizedTitle, isOn: Binding(get: { selected }, set: { store.configure(step, enabled: $0) }))
                    .labelsHidden().disabled(store.run != nil)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { stageActions(step, selected: selected) }
                VStack(alignment: .leading, spacing: 8) { stageActions(step, selected: selected) }
            }
            .padding(.leading, 40)
        }
    }
    @ViewBuilder private func stageActions(_ step: PersonalZikrStep, selected: Bool) -> some View {
        Button { choosing = step } label: { Text("\(step.minutes) min") }
            .buttonStyle(DICompactButtonStyle(minimumHeight: 48)).disabled(store.run != nil || !selected)
        if step.customID != nil && store.run == nil {
            Button("Remove") { store.removeCustom(step.id) }.buttonStyle(DICompactButtonStyle(destructive: true, minimumHeight: 48))
        }
    }
    private func durationSheet(_ step: PersonalZikrStep) -> some View {
        NavigationStack {
            List(1...60, id: \.self) { minutes in
                Button {
                    var next = step; next.minutes = minutes; store.configure(next, enabled: true); choosing = nil
                } label: {
                    HStack { Text("\(minutes) min"); Spacer(); if step.minutes == minutes { Image(systemName: "checkmark").accessibilityHidden(true) } }
                }
                .buttonStyle(DISecondaryButtonStyle())
                .accessibilityAddTraits(step.minutes == minutes ? .isSelected : [])
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .diScreenBackground()
            .navigationTitle(step.localizedTitle)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { choosing = nil } } }
        }
        .tint(DIColor.actionForeground)
        .presentationDetents([.medium, .large])
    }
    private func refreshAlertAccess() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard !Task.isCancelled else { return }
        denied = settings.authorizationStatus == .denied
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            DISectionHeader(titleKey: "Daily reminders")
            Text("Choose two gentle reminders in your local time.").diInterfaceFont(.footnote).foregroundStyle(DIColor.textMuted)
            ForEach(0..<2, id: \.self) { index in
                DICard {
                    VStack(spacing: 8) {
                        Toggle(index == 0 ? "First reminder" : "Second reminder", isOn: Binding(get: { store.reminders[index].enabled }, set: { enabled in
                            guard !requestingReminder else { return }
                            requestingReminder = true
                            Task {
                                defer { requestingReminder = false }
                                let allowed: Bool
                                if enabled { allowed = await store.requestAlerts() } else { allowed = true }
                                await refreshAlertAccess()
                                var reminder = store.reminders[index]; reminder.enabled = enabled && allowed; store.setReminder(index, reminder)
                            }
                        }))
                        .disabled(requestingReminder)
                        DatePicker("Time", selection: Binding(get: {
                            store.reminders[index].date(on: .now)
                        }, set: { date in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                            var reminder = store.reminders[index]; reminder.minuteOfDay = (c.hour ?? 0) * 60 + (c.minute ?? 0); store.setReminder(index, reminder)
                        }), displayedComponents: .hourAndMinute)
                    }
                    .foregroundStyle(DIColor.textPrimary)
                }
            }
            if denied {
                Text("Enable notifications in Settings to receive Zikr alerts.").diInterfaceFont(.footnote).foregroundStyle(DIColor.textMuted)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }.buttonStyle(DISecondaryButtonStyle())
            }
        }
    }
}

@MainActor
struct PersonalZikrLink: View {
    var body: some View {
        NavigationLink { PersonalZikrView() } label: {
            HStack(spacing: 14) {
                DILivingSealMark(diameter: 42).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Daily Personal Zikr").diInterfaceFont(.headline).foregroundStyle(Color(hex: 0xFFE3A0))
                    Text("Your sequence · Your time · Your progress").diInterfaceFont(.caption).foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward").foregroundStyle(Color(hex: 0xFFE3A0))
            }
            .padding(18).frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [Color(hex: 0x0B7250), Color(hex: 0x064B34)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(DIPressableStyle())
        .accessibilityIdentifier("personal-zikr-entry")
    }
}

#if DEBUG
/// Populated history coverage without starting timers or writing personal records.
struct PersonalZikrHistoryAuditFixture: View {
    private let entries: [PersonalZikrEntry] = (1...9).map { index in
        let end = Calendar.current.date(byAdding: .day, value: -index, to: .now)!
        let duration = Double(index * 60)
        return PersonalZikrEntry(id: "audit-\(index)", startedAt: end.addingTimeInterval(-duration),
                                 endedAt: end, duration: duration)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                PersonalZikrHistoryCard(entries: entries)
                    .padding(DISpacing.md).diResponsiveWidth()
            }
            .diScreenBackground()
            .tint(DIColor.actionForeground)
            .navigationTitle("Your Daily Personal Zikr")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif

private struct ZikrTimerButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        let colors: [Color] = !enabled
            ? [Color(hex: 0xD9D6C9), Color(hex: 0xC4C4B8)]
            : prominent ? [Color(hex: 0xFFE3A0), Color(hex: 0xDDB65F)]
            : [Color(hex: 0xFCF9F0), Color(hex: 0xEDE5D4)]
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        configuration.label
            .diInterfaceFont(.headline).multilineTextAlignment(.center)
            .foregroundStyle(Color(hex: 0x163D2D))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(minWidth: 48, minHeight: 48)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color(hex: 0xE9CE86).opacity(enabled ? 0.7 : 0.25), lineWidth: 1))
            .shadow(color: .black.opacity(enabled && !configuration.isPressed ? 0.14 : 0), radius: 4, y: 2)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

@MainActor
private struct PersonalZikrHistoryCard: View {
    let entries: [PersonalZikrEntry]
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var all = false
    @State private var expanded = false
    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .month, value: -3, to: today) ?? today
        return (0..<95).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.filter { $0 <= today }
    }
    private var totalMinutes: Int { Int(entries.reduce(0) { $0 + $1.duration }) / 60 }
    private func minutes(_ entry: PersonalZikrEntry) -> Int { Int(ceil(entry.duration / 60)) }
    var body: some View {
        DICard {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { summary; Spacer(minLength: 0) }
                    VStack(alignment: .leading, spacing: 4) { summary }
                }.diInterfaceFont(.headline).foregroundStyle(DIColor.actionForeground)
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { expanded.toggle() }
                } label: {
                    Label("Your last 3 months", systemImage: expanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(DISecondaryButtonStyle())
                .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
                if expanded {
                VStack(alignment: .leading, spacing: 14) {
                let completed = Set(entries.map { Calendar.current.startOfDay(for: $0.endedAt) })
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 14), spacing: 4) {
                    ForEach(days, id: \.self) { day in
                        RoundedRectangle(cornerRadius: 3).fill(completed.contains(day) ? DIColor.primary : DIColor.accent.opacity(0.13))
                            .aspectRatio(1, contentMode: .fit).accessibilityLabel(Text(day, style: .date))
                            .accessibilityValue(completed.contains(day) ? Text("Completed") : Text("No session"))
                    }
                }
                Text("Every filled day is time you made for Zikr.").diInterfaceFont(.caption).foregroundStyle(DIColor.textMuted)
                if entries.isEmpty { Text("Your completed sessions will appear here with their time and duration.").diInterfaceFont(.footnote).foregroundStyle(DIColor.textMuted) }
                ForEach(all ? entries : Array(entries.prefix(7))) { entry in
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { sessionDetails(entry); Spacer(minLength: 0) }
                        VStack(alignment: .leading, spacing: 4) { sessionDetails(entry) }
                    }.diInterfaceFont(.footnote)
                }
                if entries.count > 7 {
                    Button(all ? "Show recent sessions" : "Show all sessions") { all.toggle() }
                        .buttonStyle(DISecondaryButtonStyle())
                }
                }
                .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
    @ViewBuilder private var summary: some View {
        if entries.count == 1 { Text("1 session") } else { Text("\(entries.count) sessions") }
        Text("\(totalMinutes) min")
    }
    @ViewBuilder private func sessionDetails(_ entry: PersonalZikrEntry) -> some View {
        // Keep localized dates and clocks separate so RTL month names cannot
        // reorder the Western time and its day-period marker.
        Text(entry.endedAt, format: .dateTime.day().month(.abbreviated).locale(locale))
        Text(entry.endedAt, format: .dateTime.hour().minute().locale(locale))
            .environment(\.layoutDirection, .leftToRight)
        Text("\(minutes(entry)) min").foregroundStyle(DIColor.textMuted)
    }
}
