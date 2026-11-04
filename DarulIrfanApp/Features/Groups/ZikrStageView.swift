import Observation
import SwiftUI

extension Notification.Name {
    /// A push for Our Sheikh arrived while the app was open: the stage polls now.
    static let halqahStageNudge = Notification.Name("halqahStageNudge")
}

/// Everything the live Zikr stage shows, kept current by one small request
/// every few seconds (and at once when a stage notification arrives).
@Observable
@MainActor
final class ZikrStageModel {
    let groupID: String
    let service: MemberGroupService
    private(set) var live: HalqaStageUpdate.Live?
    private(set) var pictureURLs: [URL] = []
    private(set) var canLead = false
    private(set) var cues: [HalqaZikrCue] = []
    private(set) var messages: [HalqaStageMessage] = []
    private(set) var catalogue: HalqaZikrStages?
    private(set) var loaded = false
    private(set) var failed = false
    private(set) var busy = false
    var actionError: String?
    private(set) var voice: ZikrVoiceListener.State = .off
    /// What the voice heard last, shown to the admin with Undo.
    private(set) var heard: HalqaZikrCue?
    private var cueCursor: Int64?
    private var chatCursor: Int64?
    private var listener: ZikrVoiceListener?

    init(groupID: String, service: MemberGroupService) {
        self.groupID = groupID
        self.service = service
    }

    var current: HalqaZikrCue? { cues.last }
    var presets: [HalqaStagePreset] { catalogue?.presets ?? [] }
    var recitations: [HalqaRecitation] { catalogue?.recitations ?? [] }
    var stages: [HalqaZikrStage] { catalogue?.stages ?? [] }

    func poll() async {
        do {
            let update = try await service.stage(in: groupID, cuesAfter: cueCursor, chatAfter: chatCursor)
            if catalogue == nil || canLead != update.canLead { catalogue = try await service.zikrStages(in: groupID) }
            live = update.live
            pictureURLs = [update.pictureHDURL, update.pictureURL].compactMap { $0 }
            canLead = update.canLead
            merge(cues: update.cues)
            let hidden = Set(update.hidden)
            let known = Set(messages.map(\.id))
            messages = (messages + update.messages.filter { !known.contains($0.id) })
                .filter { !hidden.contains($0.id) }.suffix(150).map { $0 }
            cueCursor = max(cueCursor ?? 0, update.nextCue)
            chatCursor = max(chatCursor ?? 0, update.nextChat)
            loaded = true
            failed = false
        } catch is CancellationError {
            return
        } catch {
            // The stage keeps what it shows; the next poll tries again.
            failed = !loaded
        }
    }

    private func merge(cues new: [HalqaZikrCue]) {
        let known = Set(cues.map(\.id))
        cues = (cues + new.filter { !known.contains($0.id) }).sorted { $0.sequence < $1.sequence }.suffix(60).map { $0 }
    }

    /// Announces a stage or recitation; retried with the same event id.
    func announce(_ stageID: String, fromVoice: Bool = false) async {
        guard canLead, current?.stageID != stageID else { return }
        busy = true
        defer { busy = false }
        let eventID = UUID()
        for attempt in 0..<3 {
            do {
                let cue = try await service.broadcastZikrStage(in: groupID, stageID: stageID, eventID: eventID)
                merge(cues: [cue])
                cueCursor = max(cueCursor ?? 0, cue.sequence)
                heard = fromVoice ? cue : nil
                actionError = nil
                return
            } catch is CancellationError {
                return
            } catch {
                if attempt == 2 { actionError = error.localizedDescription }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Puts back the stage that was showing before the last one.
    func undo() async {
        guard let last = current, let previous = cues.dropLast().last(where: { $0.stageID != last.stageID }) else { return }
        heard = nil
        await announce(previous.stageID)
    }

    func send(presetID: String? = nil, text: String? = nil) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            let message = try await service.sendStageMessage(in: groupID, messageID: UUID(), presetID: presetID, text: text)
            if !messages.contains(where: { $0.id == message.id }) { messages.append(message) }
            actionError = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    func remove(_ message: HalqaStageMessage) async {
        do {
            try await service.removeStageMessage(message.id, in: groupID)
            messages.removeAll { $0.id == message.id }
        } catch is CancellationError {
        } catch { actionError = error.localizedDescription }
    }

    func toggleVoice() async {
        if let listener, voice == .listening || voice == .asking {
            listener.stop()
            self.listener = nil
            return
        }
        let listener = ZikrVoiceListener()
        listener.onState = { [weak self] in self?.voice = $0 }
        listener.onHeard = { [weak self] stage in Task { await self?.announce(stage, fromVoice: true) } }
        self.listener = listener
        await listener.start()
    }

    func stopVoice() {
        listener?.stop()
        listener = nil
        voice = .off
    }
}

/// The live Zikr stage for Our Sheikh: Hazrat ji's picture, the stage or
/// recitation now (in Arabic while he recites), the Latifa on the diagram,
/// and the chat. Built to be streamed: always the dark emerald and gold look,
/// and "Presentation" hides the controls from the picture.
struct ZikrStageView: View {
    @State private var model: ZikrStageModel
    @State private var presenting = false
    @State private var draft = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(groupID: String, service: MemberGroupService) {
        _model = State(initialValue: ZikrStageModel(groupID: groupID, service: service))
    }

    private var urdu: Bool { locale.language.languageCode?.identifier == "ur" }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height && geometry.size.width > 640
            ZStack {
                backdrop
                if wide {
                    HStack(alignment: .top, spacing: DISpacing.lg) {
                        stagePanel.frame(maxWidth: .infinity)
                        chatPanel.frame(width: min(420, geometry.size.width * 0.36))
                    }
                    .padding(DISpacing.lg)
                } else {
                    ScrollView {
                        VStack(spacing: DISpacing.lg) {
                            stagePanel
                            chatPanel.frame(minHeight: 360)
                        }
                        .padding(DISpacing.md)
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .topTrailing) {
            if !presenting {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(Text("Close"))
                .padding(DISpacing.md)
            }
        }
        .onTapGesture(count: 2) { if presenting { presenting = false } }
        .statusBarHidden(presenting)
        .persistentSystemOverlays(presenting ? .hidden : .automatic)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await model.poll()
                try? await Task.sleep(for: .seconds(4))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .halqahStageNudge)) { _ in
            Task { await model.poll() }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model.stopVoice()
        }
        .alert("Could not complete action", isPresented: Binding(
            get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } }
        )) {
            Button("OK", role: .cancel) { model.actionError = nil }
        } message: { Text(verbatim: model.actionError ?? "") }
    }

    // MARK: Backdrop

    private var backdrop: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x03271B), Color(hex: 0x064B34), Color(hex: 0x021A12)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image("islamic-pattern").resizable(resizingMode: .tile).opacity(0.06)
            RadialGradient(colors: [DIColor.goldGlow.opacity(0.18), .clear], center: .top, startRadius: 10, endRadius: 520)
        }
        .ignoresSafeArea()
    }

    // MARK: Stage

    private var stagePanel: some View {
        VStack(spacing: DISpacing.lg) {
            header
            portrait
            nowShowing
            if model.canLead && !presenting { leadControls }
        }
    }

    private var header: some View {
        HStack(spacing: DISpacing.md) {
            Image("BrandEmblem").resizable().scaledToFit().frame(width: 54, height: 54)
                .diGoldGlow(radius: 10, opacity: 0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: model.live?.title ?? String(localized: "Online Zikr"))
                    .diInterfaceFont(.headline, weight: .semibold).foregroundStyle(DIColor.onPrimary)
                    .lineLimit(2)
                Text("Naqshbandia Owaisiah · Darul Irfan").diInterfaceFont(.caption)
                    .foregroundStyle(DIColor.accent)
            }
            Spacer(minLength: 0)
            if model.live != nil {
                Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                    .diInterfaceFont(.caption, weight: .bold).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(DIColor.crimson, in: Capsule())
            }
        }
        .padding(.trailing, presenting ? 0 : 48)
    }

    private var portrait: some View {
        StagePortrait(urls: model.pictureURLs)
            .frame(maxWidth: 640)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(DIColor.accent.opacity(0.7), lineWidth: 1.5))
            .diGoldGlow(radius: 18, opacity: 0.35)
    }

    @ViewBuilder
    private var nowShowing: some View {
        VStack(spacing: DISpacing.md) {
            if let cue = model.current {
                Text(verbatim: urdu ? cue.titleUr ?? cue.title : cue.title)
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .foregroundStyle(DIColor.accent).multilineTextAlignment(.center)
                    .diGoldGlow(radius: 12, opacity: 0.45)
                if !urdu, let titleUr = cue.titleUr {
                    Text(verbatim: titleUr).font(DIFont.urduBody(scale: 1.4)).foregroundStyle(DIColor.onPrimary.opacity(0.9))
                }
                if let arabic = cue.arabic {
                    Text(verbatim: arabic)
                        .font(DIFont.quranArabic(scale: 1.5)).foregroundStyle(DIColor.onPrimary)
                        .multilineTextAlignment(.center).environment(\.layoutDirection, .rightToLeft)
                        .lineSpacing(10).diGoldGlow(radius: 16, opacity: 0.5)
                        .accessibilityIdentifier("stage-arabic")
                } else if let latifa = Self.latifa(cue.stageID) {
                    MethodLatifaDiagram(highlighted: latifa, size: 200)
                        .padding(DISpacing.sm)
                        .background(DIColor.onPrimary.opacity(0.92), in: RoundedRectangle(cornerRadius: 20))
                        .environment(\.colorScheme, .light)
                }
            } else if !model.loaded && !model.failed {
                ProgressView().tint(DIColor.accent)
            } else {
                Text(model.live == nil ? LocalizedStringKey("The Zikr is not live now.") : LocalizedStringKey("The Zikr begins soon."))
                    .font(.system(size: 26, weight: .semibold, design: .serif)).foregroundStyle(DIColor.accent)
                Text(verbatim: DIBrand.anchorVerseArabic).font(DIFont.quranArabic(scale: 1.2))
                    .foregroundStyle(DIColor.onPrimary).diGoldGlow()
            }
            if model.failed {
                Text("Connecting to the live Zikr…").diInterfaceFont(.footnote).foregroundStyle(DIColor.onPrimary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DISpacing.lg)
        .diGlassPanel(cornerRadius: 26)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85), value: model.current?.id)
        .id(model.current?.id)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    static func latifa(_ stageID: String) -> Int? {
        guard stageID.hasPrefix("latifa-"), let number = Int(stageID.dropFirst(7)), (1...7).contains(number) else { return nil }
        return number
    }

    // MARK: Leading (admins)

    private var leadControls: some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            HStack {
                Button { Task { await model.toggleVoice() } } label: {
                    Label(model.voice == .listening ? LocalizedStringKey("Listening to Hazrat ji") : LocalizedStringKey("Listen to Hazrat ji"),
                          systemImage: model.voice == .listening ? "waveform" : "mic.fill")
                }
                .buttonStyle(DIPrimaryButtonStyle())
                .symbolEffect(.variableColor.iterative, isActive: model.voice == .listening && !reduceMotion)
                Button { presenting = true } label: { Label("Presentation", systemImage: "rectangle.on.rectangle") }
                    .buttonStyle(DISecondaryButtonStyle())
            }
            if case .unavailable(let reason) = model.voice {
                Text(verbatim: reason).diInterfaceFont(.footnote).foregroundStyle(DIColor.danger)
            }
            if let heard = model.heard, heard.id == model.current?.id {
                HStack {
                    Text("Heard: \(urdu ? heard.titleUr ?? heard.title : heard.title)").diInterfaceFont(.subheadline)
                    Spacer()
                    Button("Undo") { Task { await model.undo() } }.buttonStyle(DICompactButtonStyle()).disabled(model.busy)
                }
            }
            Text("Opening recitations").diInterfaceFont(.caption, weight: .semibold).foregroundStyle(DIColor.accent)
            chips(model.recitations.map { StageChip(id: $0.id, title: urdu ? $0.titleUr : $0.title) })
            Text("Stages").diInterfaceFont(.caption, weight: .semibold).foregroundStyle(DIColor.accent)
            chips(model.stages.map { StageChip(id: $0.id, title: urdu ? $0.titleUr ?? $0.title : $0.title) })
            Text("Tap to show it on the stage. Pressing \"Presentation\" hides these controls; double-tap the stage to bring them back.")
                .diInterfaceFont(.caption).foregroundStyle(DIColor.onPrimary.opacity(0.7))
        }
        .padding(DISpacing.md)
        .diGlassPanel(cornerRadius: 22)
    }

    private struct StageChip: Identifiable { let id: String; let title: String }

    private func chips(_ items: [StageChip]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: DISpacing.sm)], spacing: DISpacing.sm) {
            ForEach(items) { item in
                let showing = model.current?.stageID == item.id
                Button { Task { await model.announce(item.id) } } label: {
                    Text(verbatim: item.title).diInterfaceFont(.subheadline, weight: showing ? .bold : .regular)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(showing ? DIColor.primaryDeep : DIColor.onPrimary)
                        .background(showing ? DIColor.accent : DIColor.onPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DIColor.accent.opacity(0.5)))
                }
                .buttonStyle(DIPressableStyle())
                .disabled(model.busy)
            }
        }
    }

    // MARK: Chat

    private var chatPanel: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                .diInterfaceFont(.headline).foregroundStyle(DIColor.accent)
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DISpacing.sm) {
                        if model.messages.isEmpty {
                            Text("Messages from those joining appear here.")
                                .diInterfaceFont(.footnote).foregroundStyle(DIColor.onPrimary.opacity(0.6))
                        }
                        ForEach(model.messages) { message in
                            bubble(message).id(message.id)
                        }
                    }
                }
                .onChange(of: model.messages.last?.id) { _, last in
                    guard let last else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { reader.scrollTo(last, anchor: .bottom) }
                }
            }
            if model.live != nil && !presenting { composer }
        }
        .padding(DISpacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
        .diGlassPanel(cornerRadius: 22)
    }

    private func bubble(_ message: HalqaStageMessage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(verbatim: message.authorName).diInterfaceFont(.caption, weight: .semibold).foregroundStyle(DIColor.accent)
                if let city = message.city {
                    Text(verbatim: "· " + city).diInterfaceFont(.caption).foregroundStyle(DIColor.onPrimary.opacity(0.6))
                }
            }
            Text(verbatim: urdu ? message.textUr ?? message.text : message.text)
                .diInterfaceFont(.body).foregroundStyle(DIColor.onPrimary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(DIColor.onPrimary.opacity(message.presetID == nil ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 14))
        .contextMenu {
            if model.canLead {
                Button("Remove", role: .destructive) { Task { await model.remove(message) } }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DISpacing.sm) {
                    ForEach(model.presets) { preset in
                        Button { Task { _ = await model.send(presetID: preset.id) } } label: {
                            Text(verbatim: urdu ? preset.titleUr : preset.title).diInterfaceFont(.subheadline)
                                .padding(.horizontal, 12).frame(minHeight: 36)
                                .foregroundStyle(DIColor.onPrimary)
                                .background(DIColor.primary.opacity(0.55), in: Capsule())
                                .overlay(Capsule().strokeBorder(DIColor.accent.opacity(0.6)))
                        }
                        .buttonStyle(DIPressableStyle())
                        .disabled(model.busy)
                        .accessibilityIdentifier("stage-preset-" + preset.id)
                    }
                }
            }
            // Members send the ready-made messages only (owner, 2026-11-03).
            if model.canLead {
                HStack {
                    TextField("Write to everyone", text: $draft)
                        .textFieldStyle(.plain).padding(10)
                        .background(DIColor.onPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .submitLabel(.send).onSubmit(sendDraft)
                    Button(action: sendDraft) { Image(systemName: "paperplane.fill").padding(10) }
                        .disabled(model.busy || draft.trimmingCharacters(in: .whitespaces).isEmpty || draft.count > 200)
                        .accessibilityLabel(Text("Send"))
                }
            }
        }
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 200 else { return }
        Task { if await model.send(text: text) { draft = "" } }
    }
}

/// Hazrat ji's picture: YouTube's full-size frame, else its standard one.
/// Loaded by hand: YouTube answers a missing full-size frame with a grey
/// placeholder image and status 404, which AsyncImage would show.
private struct StagePortrait: View {
    let urls: [URL]
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            DIColor.primaryDeep
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image("BrandEmblem").resizable().scaledToFit().padding(40).opacity(0.8)
            }
        }
        .task(id: urls) {
            for url in urls {
                guard let (data, response) = try? await URLSession.shared.data(from: url),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let loaded = UIImage(data: data), loaded.size.width > 200 else { continue }
                image = loaded
                return
            }
        }
        .accessibilityHidden(true)
    }
}

/// On Our Sheikh's page while the Zikr is live: the way into the stage, in
/// place of the stage controls that used to sit on the page.
struct StageEntryCard: View {
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: DISpacing.md) {
                Image(systemName: "sparkles.tv.fill").font(.title).foregroundStyle(DIColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open the live Zikr stage").diInterfaceFont(.headline).foregroundStyle(DIColor.onPrimary)
                    Text("The current stage, the recitation in Arabic, and the chat.")
                        .diInterfaceFont(.subheadline).foregroundStyle(DIColor.onPrimary.opacity(0.8))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward").foregroundStyle(DIColor.accent)
            }
            .padding(DISpacing.md)
            .background(LinearGradient(colors: [DIColor.primaryDeep, DIColor.primary], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(DIColor.accent.opacity(0.6)))
        }
        .buttonStyle(DIPressableStyle())
        .diBreathingGlow(maxRadius: 10)
        .accessibilityIdentifier("open-zikr-stage")
    }
}
