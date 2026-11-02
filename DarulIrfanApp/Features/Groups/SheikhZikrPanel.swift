import SwiftUI

private struct PendingSheikhStageAction: Codable {
    let kind: String
    let id: UUID
    var stageID = ""
    var title = ""
    var titleUr = ""
}

@MainActor
struct SheikhZikrPanel: View {
    let groupID: String
    let service: MemberGroupService
    @AppStorage private var pendingJSON: String

    init(groupID: String, service: MemberGroupService, pendingStore: UserDefaults = .standard) {
        self.groupID = groupID
        self.service = service
        _pendingJSON = AppStorage(wrappedValue: "", "halqa.\(groupID).\(service.memberID ?? "signed-out").pending-stage-action", store: pendingStore)
    }
    @State private var catalogue: HalqaZikrStages?
    @State private var cues: [HalqaZikrCue] = []
    @State private var error: String?
    @State private var busy = false
    @State private var generation = 0
    @State private var controls = false
    @State private var history = false
    @State private var adding = false
    @State private var title = ""
    @State private var titleUr = ""
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var urdu: Bool { locale.language.languageCode?.identifier == "ur" }
    private var pending: PendingSheikhStageAction? {
        try? JSONDecoder().decode(PendingSheikhStageAction.self, from: Data(pendingJSON.utf8))
    }
    private func stageTitle(_ stage: HalqaZikrStage) -> String { urdu ? stage.titleUr ?? stage.title : stage.title }
    private func cueTitle(_ cue: HalqaZikrCue) -> String { urdu ? cue.titleUr ?? cue.title : cue.title }

    var body: some View {
        DICard(borderColor: DIColor.accent, borderWidth: 1.5) {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                Label("Guided Zikr", systemImage: "waveform.circle.fill")
                    .diInterfaceFont(.headline).foregroundStyle(DIColor.textPrimary)
                if let current = cues.last {
                    Text(verbatim: cueTitle(current)).diInterfaceFont(.title3).bold().foregroundStyle(DIColor.scripture)
                    Text(verbatim: current.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .diInterfaceFont(.caption).foregroundStyle(DIColor.textMuted)
                } else {
                    Text("Awaiting the next Zikr stage").diInterfaceFont(.title3).bold().foregroundStyle(DIColor.scripture)
                }
                Text("Follow the stage announced by your Sheikh.").diInterfaceFont(.subheadline).foregroundStyle(DIColor.textMuted)
                if let error {
                    Text(verbatim: error).diInterfaceFont(.subheadline).foregroundStyle(DIColor.danger)
                    Button("Try again") { Task { await load() } }.buttonStyle(DICompactButtonStyle()).disabled(busy)
                } else if catalogue == nil { ProgressView() }
                if catalogue?.canBroadcast == true {
                    if let pending {
                        Text("An announcement is awaiting confirmation. Check the chat or retry.")
                            .diInterfaceFont(.caption).foregroundStyle(DIColor.textMuted)
                        Button("Retry pending action") { Task { await send(pending) } }.buttonStyle(DIPrimaryButtonStyle()).disabled(busy)
                        Button("Discard pending action") { pendingJSON = "" }.buttonStyle(DICompactButtonStyle()).disabled(busy)
                    }
                    Button(LocalizedStringKey(controls ? "Hide stage controls" : "Lead Zikr")) { controls.toggle() }
                        .buttonStyle(DISecondaryButtonStyle())
                    if controls { stageControls }
                }
                Button(LocalizedStringKey(history ? "Hide stage announcements" : "Recent stage announcements")) { history.toggle() }
                    .buttonStyle(DICompactButtonStyle())
                if history {
                    if cues.isEmpty { Text("No stage announcements yet.").foregroundStyle(DIColor.textMuted) }
                    ForEach(cues.reversed()) { cue in
                        VStack(alignment: .leading, spacing: DISpacing.xs) {
                            Text(verbatim: cueTitle(cue)).diInterfaceFont(.headline)
                            Text(verbatim: cue.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .diInterfaceFont(.caption).foregroundStyle(DIColor.textMuted)
                        }
                    }
                }
                if busy { ProgressView() }
            }
            .foregroundStyle(DIColor.textPrimary)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: controls)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: history)
        }
        .diAppear()
        .diBreathingGlow(maxRadius: 8)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await load()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }

    private var stageControls: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            Text("Tap a stage to announce it to this Halqa.").diInterfaceFont(.caption).foregroundStyle(DIColor.textMuted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DISpacing.sm), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: DISpacing.sm) {
                ForEach(catalogue?.stages ?? []) { stage in
                    Button { Task { await send(PendingSheikhStageAction(kind: "cue", id: UUID(), stageID: stage.id)) } } label: {
                        Text(verbatim: stageTitle(stage)).frame(maxWidth: .infinity)
                    }.buttonStyle(DICompactButtonStyle()).disabled(busy || pending != nil)
                }
            }
            Button("Add Muraqaba") { adding.toggle() }.buttonStyle(DISecondaryButtonStyle()).disabled(busy || pending != nil)
            if adding {
                Text("Muraqaba name").diInterfaceFont(.caption)
                TextField("Muraqaba name", text: $title).padding(DISpacing.sm).background(DIColor.background, in: RoundedRectangle(cornerRadius: 10)).disabled(busy)
                Text("Urdu name (optional)").diInterfaceFont(.caption)
                TextField("Urdu name (optional)", text: $titleUr).padding(DISpacing.sm).background(DIColor.background, in: RoundedRectangle(cornerRadius: 10)).disabled(busy)
                Button("Save") {
                    Task { await send(PendingSheikhStageAction(kind: "custom", id: UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines), titleUr: titleUr.trimmingCharacters(in: .whitespacesAndNewlines))) }
                }.buttonStyle(DIPrimaryButtonStyle())
                    .disabled(busy || pending != nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 100 || titleUr.count > 100)
            }
        }
    }

    private func load() async {
        generation += 1
        let ticket = generation
        do {
            let stages = try await service.zikrStages(in: groupID)
            let events = try await service.zikrCues(in: groupID)
            guard ticket == generation, !Task.isCancelled else { return }
            catalogue = stages; cues = events.cues; error = nil
            if let pending {
                let id = pending.id.uuidString.lowercased()
                if (pending.kind == "cue" && cues.contains(where: { $0.id == id })) ||
                    (pending.kind == "custom" && stages.stages.contains(where: { $0.id == "custom-" + id })) { pendingJSON = "" }
            }
        } catch is CancellationError { return }
        catch { if ticket == generation { self.error = error.localizedDescription } }
    }

    private func send(_ action: PendingSheikhStageAction) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            pendingJSON = String(decoding: try JSONEncoder().encode(action), as: UTF8.self)
            if action.kind == "cue" {
                let cue = try await service.broadcastZikrStage(in: groupID, stageID: action.stageID, eventID: action.id)
                generation += 1
                cues = (cues.filter { $0.id != cue.id } + [cue]).sorted { $0.sequence < $1.sequence }
            } else {
                _ = try await service.addZikrStage(in: groupID, requestID: action.id, title: action.title, titleUr: action.titleUr.isEmpty ? nil : action.titleUr)
                adding = false; title = ""; titleUr = ""
            }
            pendingJSON = ""; error = nil
            await load()
        } catch is CancellationError { return }
        catch { self.error = error.localizedDescription }
    }
}
