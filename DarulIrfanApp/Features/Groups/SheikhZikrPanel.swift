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
    let isLiveZikr: Bool
    @AppStorage private var pendingJSON: String

    init(groupID: String, service: MemberGroupService, isLiveZikr: Bool, pendingStore: UserDefaults = .standard) {
        self.groupID = groupID
        self.service = service
        self.isLiveZikr = isLiveZikr
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
    /// The stage announcement an admin asked to remove, awaiting confirmation.
    @State private var cueToRemove: HalqaZikrCue?
    @State private var title = ""
    @State private var titleUr = ""
    private enum EditorField: Hashable { case name, urduName }
    @FocusState private var editorField: EditorField?
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
                    Text(verbatim: GroupInvitationDate.text(current.createdAt, locale: locale, includesTime: true))
                        .diInterfaceFont(.caption).foregroundStyle(DIColor.textMuted)
                } else {
                    Text("Awaiting the next Zikr stage").diInterfaceFont(.title3).bold().foregroundStyle(DIColor.scripture)
                }
                Text(HalqahStage.isOurSheikh(groupID)
                     ? LocalizedStringKey("Follow the stage announced by your Sheikh.")
                     : LocalizedStringKey("Follow the stage announced by the one leading the Zikr."))
                    .diInterfaceFont(.subheadline).foregroundStyle(DIColor.textMuted)
                if let error {
                    Text(verbatim: error).diInterfaceFont(.subheadline).foregroundStyle(DIColor.danger)
                    Button("Try again") { Task { await load() } }.buttonStyle(DICompactButtonStyle()).disabled(busy)
                } else if catalogue == nil { ProgressView() }
                if isLiveZikr && catalogue?.canBroadcast == true {
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
                        HStack(spacing: DISpacing.sm) {
                            VStack(alignment: .leading, spacing: DISpacing.xs) {
                                Text(verbatim: cueTitle(cue)).diInterfaceFont(.headline)
                                Text(verbatim: GroupInvitationDate.text(cue.createdAt, locale: locale, includesTime: true))
                                    .diInterfaceFont(.caption).foregroundStyle(DIColor.textMuted)
                            }
                            Spacer(minLength: 0)
                            // Admins take a stage announcement off the stage for everyone.
                            if catalogue?.canBroadcast == true {
                                Button { cueToRemove = cue } label: { Image(systemName: "trash") }
                                    .buttonStyle(DICompactButtonStyle(destructive: true))
                                    .disabled(busy)
                                    .accessibilityLabel(Text(verbatim: String(localized: "Remove") + ": " + cueTitle(cue)))
                                    .accessibilityIdentifier("sheikh-cue-remove-" + cue.id)
                            }
                        }
                    }
                }
                if busy { ProgressView() }
            }
            .foregroundStyle(DIColor.textPrimary)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: controls)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: history)
        }
        .sheet(isPresented: $adding) { stageEditor }
        .alert("Remove this stage announcement?", isPresented: Binding(
            get: { cueToRemove != nil }, set: { if !$0 { cueToRemove = nil } }
        ), presenting: cueToRemove) { cue in
            Button("Remove", role: .destructive) {
                cueToRemove = nil
                Task { await remove(cue) }
            }
            Button("Cancel", role: .cancel) { cueToRemove = nil }
        } message: { cue in
            Text(verbatim: cueTitle(cue) + "\n\n" + String(localized: "It is taken off the stage for everyone."))
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

        }
    }

    private var canSaveStage: Bool {
        !busy && pending == nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 100 && titleUr.count <= 100
    }

    private var stageEditor: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DISpacing.md) {
                    DICard {
                        VStack(alignment: .leading, spacing: DISpacing.sm) {
                            Text("Muraqaba name").diInterfaceFont(.caption)
                            TextField("Muraqaba name", text: $title)
                                .diInterfaceFont(.body)
                                .focused($editorField, equals: .name).submitLabel(.next)
                                .onSubmit { editorField = .urduName }
                                .autocorrectionDisabled()
                                .padding(DISpacing.sm).background(DIColor.background, in: RoundedRectangle(cornerRadius: 10))
                            Text("Urdu name (optional)").diInterfaceFont(.caption)
                            TextField("Urdu name (optional)", text: $titleUr)
                                .diInterfaceFont(.body)
                                .focused($editorField, equals: .urduName).submitLabel(.done)
                                .onSubmit { editorField = nil }
                                .autocorrectionDisabled()
                                .padding(DISpacing.sm).background(DIColor.background, in: RoundedRectangle(cornerRadius: 10))
                        }.disabled(busy || pending != nil)
                    }
                    if let error { Text(verbatim: error).diInterfaceFont(.subheadline).foregroundStyle(DIColor.danger) }
                    if let pending, pending.kind == "custom" {
                        Button("Retry pending action") { Task { await send(pending) } }
                            .buttonStyle(DIPrimaryButtonStyle()).disabled(busy)
                            .accessibilityIdentifier("sheikh-stage-editor-retry")
                    }
                    if busy { ProgressView() }
                }.padding(DISpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .diScreenBackground()
            .navigationTitle("Add Muraqaba")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editorField = nil; adding = false }.disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        editorField = nil
                        Task { await send(PendingSheikhStageAction(kind: "custom", id: UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines), titleUr: titleUr.trimmingCharacters(in: .whitespacesAndNewlines))) }
                    }.disabled(!canSaveStage)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(busy)
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
                    (pending.kind == "custom" && stages.stages.contains(where: { $0.id == "custom-" + id })) {
                    pendingJSON = ""
                    if pending.kind == "custom" {
                        editorField = nil
                        adding = false; title = ""; titleUr = ""
                    }
                }
            }
        } catch is CancellationError { return }
        catch { if ticket == generation { self.error = error.localizedDescription } }
    }

    private func remove(_ cue: HalqaZikrCue) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await service.removeZikrCue(cue.id, in: groupID)
            // A load that started before the removal must not bring it back.
            generation += 1
            cues.removeAll { $0.id == cue.id }
            error = nil
        } catch is CancellationError { return }
        catch { self.error = error.localizedDescription }
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
