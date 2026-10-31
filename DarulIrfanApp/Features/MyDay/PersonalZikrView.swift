import SwiftUI

@MainActor
struct PersonalZikrView: View {
    @State private var store = PersonalZikrStore.shared
    @State private var shajra = false
    @State private var adding = false
    @State private var customName = ""
    @State private var choosing: PersonalZikrStep?
    @State private var ended = false
    @State private var denied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    timer(at: context.date)
                        .onChange(of: store.run?.endsAt.map { $0 <= context.date } ?? false) { _, done in
                            if done { if scenePhase == .active { store.playChime() }; store.settle(at: context.date); ended = true; DIHaptics.success() }
                        }
                }
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { shajra.toggle() } } label: {
                    Label(shajra ? "Close Shajra" : "Read Shajra", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.bordered)
                if shajra { ShajraInlineContent().transition(.opacity) }
                PersonalZikrHistoryCard(entries: store.history)
                sequence
                reminders
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .navigationTitle("Your Daily Personal Zikr")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.screenActive = scenePhase == .active; store.settle(); store.refreshAlerts() }
        .onDisappear { store.screenActive = false }
        .onChange(of: scenePhase) { _, phase in
            store.screenActive = phase == .active
            if phase == .active { store.settle(); store.refreshAlerts() }
        }
        .sheet(item: $choosing) { step in durationSheet(step) }
        .sheet(isPresented: $adding) {
            NavigationStack {
                Form {
                    TextField("Muraqaba name", text: $customName)
                        .onChange(of: customName) { _, value in customName = String(value.prefix(80)) }
                    Button("Add") { store.addCustom(customName); customName = ""; adding = false }
                        .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .navigationTitle("Add a Muraqaba")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } } }
            }
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
                Text("A moment of connection").font(.footnote).foregroundStyle(Color(hex: 0xE9CE86))
                Spacer()
                DILivingSealMark(diameter: 38).accessibilityHidden(true)
            }
            Text(verbatim: position?.step.localizedTitle ?? String(localized: "Choose your stages"))
                .font(.title2.weight(.semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
            if let position { Text("Stage \(position.index + 1) of \(plan.count)").font(.caption).foregroundStyle(.white.opacity(0.7)) }
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
                    Text(run?.startedAt != nil ? "In progress" : run != nil ? "Paused" : "Ready when you are")
                        .font(.caption2).foregroundStyle(Color(hex: 0xE9CE86))
                }
            }
            .frame(width: 184, height: 184)
            Text("Total remaining: \(PersonalZikrMath.text(remaining))").font(.footnote).foregroundStyle(.white.opacity(0.8))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { controls }
                VStack(spacing: 12) { controls }
            }
            if run != nil { Button("Discard session") { store.discard(); ended = false }.buttonStyle(.bordered) }
            if ended { Text("Your personal Zikr session is complete.").font(.footnote).foregroundStyle(Color(hex: 0xF4D889)) }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Color(hex: 0x0B7250), Color(hex: 0x043221)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
        .onChange(of: position?.index) { old, next in
            if old != nil, next != nil, run?.startedAt != nil, scenePhase == .active { store.playChime(); DIHaptics.soft() }
        }
        .diAppear()
    }

    @ViewBuilder private var controls: some View {
        if store.run?.startedAt != nil {
            Button("Pause") { store.pause() }.buttonStyle(.bordered)
        } else {
            Button(store.run == nil ? "Start" : "Resume") {
                store.start(); ended = false; DIHaptics.light()
                Task { denied = !(await store.requestAlerts()) }
            }
            .buttonStyle(.borderedProminent).disabled(store.plan.isEmpty)
        }
        if store.run != nil {
            Button("Finish & save") { store.finish(); ended = true; DIHaptics.success() }.buttonStyle(.bordered)
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
                .font(.footnote).foregroundStyle(DIColor.textMuted)
            DICard {
                VStack(spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        stageRow(step, index: index)
                        if index < steps.count - 1 { Divider() }
                    }
                }
            }
            if store.run == nil {
                Button("Add a Muraqaba") { adding = true }.buttonStyle(.bordered).disabled(store.customs.count >= 24)
            }
        }
    }
    private func stageRow(_ step: PersonalZikrStep, index: Int) -> some View {
        let selected = store.plan.contains { $0.id == step.id }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(verbatim: "\(index + 1)").font(.caption).foregroundStyle(DIColor.primary)
                    .frame(width: 30, height: 30).background(DIColor.accent.opacity(0.12), in: Circle())
                Text(verbatim: step.localizedTitle).font(.subheadline.weight(.medium)).foregroundStyle(DIColor.textPrimary)
                Spacer(minLength: 0)
                Toggle(step.localizedTitle, isOn: Binding(get: { selected }, set: { store.configure(step, enabled: $0) }))
                    .labelsHidden().disabled(store.run != nil)
            }
            HStack(spacing: 8) {
                Button { choosing = step } label: { Text("\(step.minutes) min") }
                    .buttonStyle(.bordered).disabled(store.run != nil || !selected)
                if step.customID != nil && store.run == nil {
                    Button("Remove") { store.removeCustom(step.id) }.buttonStyle(.bordered)
                }
            }
            .padding(.leading, 40)
        }
    }
    private func durationSheet(_ step: PersonalZikrStep) -> some View {
        NavigationStack {
            List(1...60, id: \.self) { minutes in
                Button {
                    var next = step; next.minutes = minutes; store.configure(next, enabled: true); choosing = nil
                } label: {
                    HStack { Text("\(minutes) min"); Spacer(); if step.minutes == minutes { Image(systemName: "checkmark") } }
                }
            }
            .navigationTitle(step.localizedTitle)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { choosing = nil } } }
        }
        .presentationDetents([.medium, .large])
    }
    private var reminders: some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            DISectionHeader(titleKey: "Daily reminders")
            Text("Choose two gentle reminders in your local time.").font(.footnote).foregroundStyle(DIColor.textMuted)
            ForEach(0..<2, id: \.self) { index in
                DICard {
                    VStack(spacing: 8) {
                        Toggle(index == 0 ? "First reminder" : "Second reminder", isOn: Binding(get: { store.reminders[index].enabled }, set: { enabled in
                            Task {
                                let allowed: Bool
                                if enabled { allowed = await store.requestAlerts() } else { allowed = true }
                                denied = !allowed
                                var reminder = store.reminders[index]; reminder.enabled = enabled && allowed; store.setReminder(index, reminder)
                            }
                        }))
                        DatePicker("Time", selection: Binding(get: {
                            Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(store.reminders[index].minuteOfDay * 60))
                        }, set: { date in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                            var reminder = store.reminders[index]; reminder.minuteOfDay = (c.hour ?? 0) * 60 + (c.minute ?? 0); store.setReminder(index, reminder)
                        }), displayedComponents: .hourAndMinute)
                    }
                    .foregroundStyle(DIColor.textPrimary)
                }
            }
            if denied { Text("Enable notifications in Settings to receive Zikr alerts.").font(.footnote).foregroundStyle(DIColor.textMuted) }
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
                    Text("Your Daily Personal Zikr").font(.headline).foregroundStyle(Color(hex: 0xFFE3A0))
                    Text("Your sequence · Your time · Your progress").font(.caption).foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward").foregroundStyle(Color(hex: 0xFFE3A0))
            }
            .padding(18).frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [Color(hex: 0x0B7250), Color(hex: 0x064B34)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(DIPressableStyle())
    }
}

@MainActor
private struct PersonalZikrHistoryCard: View {
    let entries: [PersonalZikrEntry]
    @State private var all = false
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
                DISectionHeader(titleKey: "Your last 3 months")
                HStack {
                    if entries.count == 1 { Text("1 session") } else { Text("\(entries.count) sessions") }
                    Spacer()
                    Text("\(totalMinutes) min")
                }.font(.headline).foregroundStyle(DIColor.primary)
                let completed = Set(entries.map { Calendar.current.startOfDay(for: $0.endedAt) })
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 14), spacing: 4) {
                    ForEach(days, id: \.self) { day in
                        RoundedRectangle(cornerRadius: 3).fill(completed.contains(day) ? DIColor.primary : DIColor.accent.opacity(0.13))
                            .aspectRatio(1, contentMode: .fit).accessibilityLabel(Text(day, style: .date))
                            .accessibilityValue(completed.contains(day) ? Text("Completed") : Text("No session"))
                    }
                }
                Text("Every filled day is time you made for Zikr.").font(.caption).foregroundStyle(DIColor.textMuted)
                if entries.isEmpty { Text("Your completed sessions will appear here with their time and duration.").font(.footnote).foregroundStyle(DIColor.textMuted) }
                ForEach(all ? entries : Array(entries.prefix(7))) { entry in
                    HStack {
                        Text(entry.endedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                        Spacer()
                        Text("\(minutes(entry)) min").foregroundStyle(DIColor.textMuted)
                    }.font(.footnote)
                }
                if entries.count > 7 { Button(all ? "Show less" : "Show all sessions") { all.toggle() }.font(.footnote) }
            }
        }
    }
}
