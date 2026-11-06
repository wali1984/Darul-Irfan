import Observation
import SwiftUI

extension Notification.Name {
    /// A push for a Halqah arrived while the app was open: that Halqah's
    /// stage polls now. The object is the Halqah's id, when the push named one.
    static let halqahStageNudge = Notification.Name("halqahStageNudge")
}

/// Every Halqah's live Zikr has its stage, led by its own admins (owner,
/// 2026-11-04). Only a few things stay Our Sheikh's own: Hazrat ji's
/// photograph on the stage and the words that name him.
enum HalqahStage {
    static let ourSheikhID = "our-sheikh"

    static func isOurSheikh(_ groupID: String) -> Bool { groupID == ourSheikhID }

    /// The stage's picture: Hazrat ji's photograph from the live video on Our
    /// Sheikh's stage only; every other Halqah shows the Silsila's logo there.
    static func portraitURLs(groupID: String, pictureURL: URL?, pictureHDURL: URL?) -> [URL] {
        guard isOurSheikh(groupID) else { return [] }
        return [pictureHDURL, pictureURL].compactMap { $0 }
    }

    /// The Halqah a push opens ("…/groups/<id>"), so only its stage polls.
    static func groupID(fromPath path: String?) -> String? {
        guard let path, let range = path.range(of: "groups/", options: .backwards) else { return nil }
        let rest = path[range.upperBound...].prefix { $0 != "?" && $0 != "#" }
        guard let id = rest.split(separator: "/").first.map(String.init), !id.isEmpty else { return nil }
        return id
    }

    /// The stage after Masjid-e-Nabawi and before the Dua: the Shajra Sharif.
    static let shajraID = "shajra"
    /// The dua that closes the Zikr.
    static let duaID = "dua"

    /// How the stage card shows a stage: the Shajra's own lines, the Dua's
    /// card, or the stage's name (with the Arabic while it is recited).
    enum Card: Equatable {
        case standard
        case shajra
        case dua
    }

    static func card(for stageID: String) -> Card {
        switch stageID.lowercased() {
        case shajraID: return .shajra
        case duaID: return .dua
        default: return .standard
        }
    }

    /// The names the app knows for the stages that close the Zikr, for a cue
    /// that arrives without its own (an older server, or one that sends only
    /// the id).
    private static let knownTitles: [String: (english: String, urdu: String)] = [
        shajraID: ("Shajra Sharif", "شجرہ شریف"),
        duaID: ("Dua", "دعا"),
    ]

    private static func named(_ text: String?, notID stageID: String) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
              trimmed.caseInsensitiveCompare(stageID) != .orderedSame else { return nil }
        return trimmed
    }

    /// A stage's name as the stage shows it, in the app's language: the
    /// server's own; for a stage that comes without a name, or with its id
    /// for a name, the app's; never a raw id such as "shajra".
    static func title(stageID: String, title: String, titleUr: String?, urdu: Bool) -> String {
        let known = knownTitles[stageID.lowercased()]
        if urdu, let shown = named(titleUr, notID: stageID) ?? known?.urdu { return shown }
        if let shown = named(title, notID: stageID) { return shown }
        if let known { return urdu ? known.urdu : known.english }
        return stageID.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    /// The Urdu name under the English one (English only); nil when there is none.
    static func secondaryTitle(stageID: String, titleUr: String?, urdu: Bool) -> String? {
        guard !urdu else { return nil }
        return named(titleUr, notID: stageID) ?? knownTitles[stageID.lowercased()]?.urdu
    }
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
    /// Admins and the Super admin may take announcements and messages off
    /// the stage, live or not.
    private(set) var canModerate = false
    private(set) var cues: [HalqaZikrCue] = []
    private(set) var messages: [HalqaStageMessage] = []
    private(set) var catalogue: HalqaZikrStages?
    private(set) var loaded = false
    private(set) var failed = false
    private(set) var busy = false
    /// A stage announcement is on its way to the server.
    private(set) var announcing = false
    var actionError: String?
    private(set) var voice: ZikrVoiceListener.State = .off
    /// What the voice heard last, shown to the admin with Undo.
    private(set) var heard: HalqaZikrCue?
    /// The last few words the microphone heard, for the live indicator.
    private(set) var voiceWords = ""
    /// A heard stage that could not be shown, in place of an alert (an
    /// alert would cover the streamed stage).
    private(set) var voiceNotice: String?
    /// Why adding a Muraqaba from the stage failed.
    private(set) var addError: String?
    private var cueCursor: Int64?
    private var chatCursor: Int64?
    private var listener: ZikrVoiceListener?
    /// Stages waiting to be announced, in the order asked for.
    private var stageQueue: [StageRequest] = []
    /// Kept while the same Muraqaba is retried, so a lost answer adds it once.
    private var addRequest: (id: UUID, key: String)?

    /// A stage to announce, and whether the voice (not a tap) asked for it.
    struct StageRequest: Equatable, Sendable {
        let stageID: String
        let fromVoice: Bool
    }

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
            pictureURLs = HalqahStage.portraitURLs(groupID: groupID, pictureURL: update.pictureURL, pictureHDURL: update.pictureHDURL)
            canLead = update.canLead
            canModerate = update.canModerate ?? update.canLead
            cues = Self.stageCues(cues, adding: update.cues, hidden: update.hiddenCues ?? [], isLive: update.live != nil)
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
        cues = Self.stageCues(cues, adding: new, hidden: [], isLive: true)
    }

    /// The stage's announcements after a poll: the new ones added in order,
    /// those an admin removed taken away, and none at all once the Zikr is no
    /// longer live (they belong to the session they were made in).
    nonisolated static func stageCues(_ cues: [HalqaZikrCue], adding new: [HalqaZikrCue], hidden: [String], isLive: Bool) -> [HalqaZikrCue] {
        guard isLive else { return [] }
        let known = Set(cues.map(\.id))
        let removed = Set(hidden.map { $0.lowercased() })
        return (cues + new.filter { !known.contains($0.id) })
            .filter { !removed.contains($0.id.lowercased()) }
            .sorted { $0.sequence < $1.sequence }.suffix(60).map { $0 }
    }

    /// The waiting stages once another is asked for. Nothing is dropped
    /// because an announcement is still on its way: taps keep their order,
    /// a newer voice detection replaces an older one still waiting (Hazrat ji
    /// has moved on), and the same stage twice in a row is asked once.
    nonisolated static func queue(_ queue: [StageRequest], adding request: StageRequest) -> [StageRequest] {
        var next = request.fromVoice ? queue.filter { !$0.fromVoice } : queue
        if next.last?.stageID == request.stageID { return next }
        next.append(request)
        return next
    }

    /// The stage list with a Muraqaba just added from the stage, at once.
    nonisolated static func catalogue(_ catalogue: HalqaZikrStages, adding stage: HalqaZikrStage) -> HalqaZikrStages {
        guard !catalogue.stages.contains(where: { $0.id == stage.id }) else { return catalogue }
        return HalqaZikrStages(canBroadcast: catalogue.canBroadcast, stages: catalogue.stages + [stage],
                               recitations: catalogue.recitations, presets: catalogue.presets)
    }

    /// Announces a stage or recitation. Requests made while one is on its
    /// way wait their turn rather than being lost; each is retried with the
    /// same event id.
    func announce(_ stageID: String, fromVoice: Bool = false) async {
        guard canLead else { return }
        stageQueue = Self.queue(stageQueue, adding: StageRequest(stageID: stageID, fromVoice: fromVoice))
        guard !announcing else { return }
        announcing = true
        defer { announcing = false }
        while !stageQueue.isEmpty {
            await broadcast(stageQueue.removeFirst())
        }
    }

    private func broadcast(_ request: StageRequest) async {
        guard current?.stageID != request.stageID else { return }
        let eventID = UUID()
        // The voice keeps trying for about half a minute: nobody may be at the phone.
        let attempts = request.fromVoice ? 7 : 3
        for attempt in 0..<attempts {
            // A newer stage heard since then is what Hazrat ji is on now.
            if request.fromVoice, attempt > 0, stageQueue.contains(where: \.fromVoice) { return }
            do {
                let cue = try await service.broadcastZikrStage(in: groupID, stageID: request.stageID, eventID: eventID)
                merge(cues: [cue])
                cueCursor = max(cueCursor ?? 0, cue.sequence)
                heard = request.fromVoice ? cue : nil
                actionError = nil
                voiceNotice = nil
                return
            } catch is CancellationError {
                return
            } catch {
                guard attempt < attempts - 1 else {
                    if request.fromVoice {
                        voiceNotice = String(localized: "Could not show the stage heard. Tap it to show it.")
                    } else {
                        actionError = error.localizedDescription
                    }
                    return
                }
                try? await Task.sleep(for: .seconds(request.fromVoice ? min(8, 1 << attempt) : 1))
            }
        }
    }

    /// Puts back the stage that was showing before the last one.
    func undo() async {
        guard let last = current, let previous = cues.dropLast().last(where: { $0.stageID != last.stageID }) else { return }
        heard = nil
        await announce(previous.stageID)
    }

    /// Adds a Muraqaba from the stage; it joins the stage buttons at once.
    func addMuraqaba(title: String, titleUr: String) async -> Bool {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let urduName = titleUr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canLead, !name.isEmpty, name.count <= 100, urduName.count <= 100, !busy else { return false }
        let key = name + "\n" + urduName
        let requestID = (addRequest?.key == key ? addRequest?.id : nil) ?? UUID()
        addRequest = (requestID, key)
        busy = true
        defer { busy = false }
        do {
            let stage = try await service.addZikrStage(in: groupID, requestID: requestID, title: name,
                                                       titleUr: urduName.isEmpty ? nil : urduName)
            if let catalogue { self.catalogue = Self.catalogue(catalogue, adding: stage) }
            addRequest = nil
            addError = nil
            // The server's own order, keeping the new one should it lag behind.
            if let fresh = try? await service.zikrStages(in: groupID) { catalogue = Self.catalogue(fresh, adding: stage) }
            return true
        } catch is CancellationError {
            return false
        } catch {
            addError = error.localizedDescription
            return false
        }
    }

    func clearAddError() { addError = nil }

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

    /// Takes a stage announcement off the stage for everyone (admins).
    func remove(_ cue: HalqaZikrCue) async {
        guard canModerate else { return }
        busy = true
        defer { busy = false }
        do {
            try await service.removeZikrCue(cue.id, in: groupID)
            cues.removeAll { $0.id == cue.id }
            if heard?.id == cue.id { heard = nil }
            actionError = nil
        } catch is CancellationError {
        } catch { actionError = error.localizedDescription }
    }

    /// "Go Live": one tap listens for the rest of the session.
    func toggleVoice() async {
        if let listener, voice == .listening || voice == .asking {
            listener.stop()
            self.listener = nil
            voiceWords = ""
            return
        }
        let listener = ZikrVoiceListener()
        listener.onState = { [weak self] in self?.voice = $0 }
        listener.onHeard = { [weak self] stage in Task { await self?.announce(stage, fromVoice: true) } }
        listener.onWords = { [weak self] in self?.voiceWords = $0 }
        self.listener = listener
        voiceNotice = nil
        await listener.start()
    }

    /// Back in the app: the microphone picks up again if it was taken.
    func resumeVoice() {
        listener?.resumeIfNeeded()
    }

    func stopVoice() {
        listener?.stop()
        listener = nil
        voice = .off
        voiceWords = ""
    }
}

/// The live Zikr stage of a Halqah (every Halqah, led by its own admins):
/// the Silsila's seal, the Halqah's name, on Our Sheikh's stage Hazrat ji's
/// picture (the live video's own frame, a photograph) and on every other
/// Halqah's the Silsila's logo in its place, the stage or
/// recitation now in a floating card (in Arabic while he recites), and the
/// chat. Built to be streamed: always the dark emerald and gold look, alive
/// with light, and "Presentation" hides the controls from the picture. No
/// illustrations on the stage (owner, 2026-11-04).
struct ZikrStageView: View {
    @State private var model: ZikrStageModel
    /// The Halqah's own name, shown on its stage.
    let groupName: String
    @State private var presenting = false
    @State private var draft = ""
    @State private var addingMuraqaba = false
    /// The stage announcement an admin asked to remove, awaiting confirmation.
    @State private var cueToRemove: HalqaZikrCue?
    @State private var liveAudio: LiveAudioMode?
    @State private var liveAudioToken = ""
    /// Our Sheikh's live sound, heard on the stage itself (the live
    /// service's listener page, out of sight).
    @State private var listening = false
    @State private var listenToken = ""
    /// What the live sound says of itself ("Live", "Waiting for Hazrat ji…").
    @State private var listenStatus = ""
    /// Opened by a Join: the live sound starts once the stage knows the Zikr
    /// is live.
    @State private var listenWanted: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(groupID: String, groupName: String, service: MemberGroupService, listenOnOpen: Bool = false) {
        self.groupName = groupName
        _model = State(initialValue: ZikrStageModel(groupID: groupID, service: service))
        _listenWanted = State(initialValue: listenOnOpen && HalqahStage.isOurSheikh(groupID))
    }

    private var ourSheikh: Bool { HalqahStage.isOurSheikh(model.groupID) }

    private var urdu: Bool { locale.language.languageCode?.identifier == "ur" }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height && geometry.size.width > 640
            ZStack {
                StageBackdrop()
                if wide {
                    HStack(alignment: .top, spacing: DISpacing.lg) {
                        ScrollView { stagePanel }.frame(maxWidth: .infinity)
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
            model.resumeVoice()
            while !Task.isCancelled {
                await model.poll()
                try? await Task.sleep(for: .seconds(4))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .halqahStageNudge)) { note in
            // Another Halqah's push leaves this stage alone.
            if let id = note.object as? String, id != model.groupID { return }
            Task { await model.poll() }
        }
        .background {
            if listening {
                LiveListenPlayer(token: listenToken, urdu: urdu) { listenStatus = $0 }
            }
        }
        // The live sound follows the Zikr: it starts for a Join once the Zikr
        // is live, and stops when the Zikr ends.
        .onChange(of: model.live != nil) { _, isLive in
            if isLive {
                if listenWanted {
                    listenWanted = false
                    startListening()
                }
            } else {
                stopListening()
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            model.stopVoice()
            stopListening()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sheet(isPresented: $addingMuraqaba) { StageMuraqabaEditor(model: model) }
        .fullScreenCover(item: $liveAudio, onDismiss: { liveAudioToken = "" }) { mode in
            LiveAudioView(mode: mode, token: liveAudioToken, urdu: urdu)
        }
        .alert("Could not complete action", isPresented: Binding(
            get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } }
        )) {
            Button("OK", role: .cancel) { model.actionError = nil }
        } message: { Text(verbatim: model.actionError ?? "") }
        .confirmationDialog("Remove this stage announcement?", isPresented: Binding(
            get: { cueToRemove != nil }, set: { if !$0 { cueToRemove = nil } }
        ), titleVisibility: .visible, presenting: cueToRemove) { cue in
            Button("Remove", role: .destructive) {
                cueToRemove = nil
                Task { await model.remove(cue) }
            }
            Button("Cancel", role: .cancel) { cueToRemove = nil }
        } message: { cue in
            Text(verbatim: cueTitle(cue) + "\n\n" + String(localized: "It is taken off the stage for everyone."))
        }
    }

    private func cueTitle(_ cue: HalqaZikrCue) -> String {
        HalqahStage.title(stageID: cue.stageID, title: cue.title, titleUr: cue.titleUr, urdu: urdu)
    }

    // MARK: Stage

    private var stagePanel: some View {
        VStack(spacing: DISpacing.lg) {
            header
            portrait
            nowShowing
            if ourSheikh && !presenting && (model.live != nil || model.canModerate) { liveAudioControls }
            if model.canLead && !presenting { leadControls }
            if model.canModerate && !presenting && !model.cues.isEmpty { announcementList }
        }
    }

    /// This session's stage announcements, newest first, for admins to take
    /// any of them off the stage.
    private var announcementList: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            Text("Stage announcements").diInterfaceFont(.caption, weight: .semibold).foregroundStyle(DIColor.accent)
            ForEach(model.cues.reversed()) { cue in
                HStack(spacing: DISpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: cueTitle(cue)).diInterfaceFont(.subheadline, weight: cue.id == model.current?.id ? .bold : .regular)
                            .foregroundStyle(DIColor.onPrimary)
                        Text(verbatim: GroupInvitationDate.text(cue.createdAt, locale: locale, includesTime: true))
                            .diInterfaceFont(.caption).foregroundStyle(DIColor.onPrimary.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                    Button { cueToRemove = cue } label: { Image(systemName: "trash").padding(8) }
                        .foregroundStyle(DIColor.danger)
                        .disabled(model.busy)
                        .accessibilityLabel(Text(verbatim: String(localized: "Remove") + ": " + cueTitle(cue)))
                        .accessibilityIdentifier("stage-cue-remove-" + cue.id)
                }
                .contextMenu {
                    Button("Remove", role: .destructive) { cueToRemove = cue }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DISpacing.md)
        .diGlassPanel(cornerRadius: 22)
    }

    private var header: some View {
        HStack(spacing: DISpacing.md) {
            StageEmblem(size: presenting ? 92 : 72)
            VStack(alignment: .leading, spacing: 2) {
                halqahName
                    .diInterfaceFont(.caption, weight: .semibold)
                    .foregroundStyle(DIColor.accent)
                    .lineLimit(1)
                    .accessibilityIdentifier("stage-halqah-name")
                Text(verbatim: model.live?.title ?? String(localized: "Online Zikr"))
                    .diInterfaceFont(.title3, weight: .semibold).foregroundStyle(DIColor.onPrimary)
                    .lineLimit(2)
                    .diGoldTextShimmer(delay: 2.4)
                Text("Naqshbandia Owaisiah · Darul Irfan").diInterfaceFont(.caption)
                    .foregroundStyle(DIColor.accent)
                    .diGoldTextShimmer(delay: 1.2)
            }
            Spacer(minLength: 0)
            if model.live?.isTest == true {
                HalqahTestBadge()
            }
            if model.live != nil {
                HStack(spacing: 6) {
                    DILivePulse(color: .white, size: 7)
                    Text("LIVE")
                }
                .diInterfaceFont(.caption, weight: .bold).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(DIColor.crimson, in: Capsule())
                .diBreathingGlow(color: DIColor.crimson, maxRadius: 10)
            }
        }
        .padding(.trailing, presenting ? 0 : 48)
    }

    /// The Halqah's name as its page shows it (Our Sheikh's in Urdu too).
    private var halqahName: Text {
        ourSheikh ? Text(LocalizedStringKey(groupName)) : Text(verbatim: groupName)
    }

    /// Hazrat ji's photograph from the live video on Our Sheikh's stage (kept:
    /// it is a photo, not an illustration); the logo on every other Halqah's.
    private var portrait: some View {
        StagePortrait(urls: model.pictureURLs)
            .frame(maxWidth: 640)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(DIColor.accent.opacity(0.7), lineWidth: 1.5))
            .diBreathingGlow(maxRadius: 22)
    }

    /// The running stage, floating; a new one arrives with a burst of light.
    private var nowShowing: some View {
        VStack(spacing: DISpacing.sm) {
            ZStack {
                if let cue = model.current {
                    StageFloatingCard {
                        cueContent(cue)
                    }
                    .id(cue.id)
                    .transition(reduceMotion ? AnyTransition.opacity : .stageArrival)
                } else if !model.loaded && !model.failed {
                    ProgressView().tint(DIColor.accent).padding(DISpacing.xl)
                } else {
                    StageFloatingCard(burst: false) {
                        idleContent
                    }
                    .transition(reduceMotion ? AnyTransition.opacity : .stageArrival)
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.75, dampingFraction: 0.7), value: model.current?.id)
            if model.failed {
                Text("Connecting to the live Zikr…").diInterfaceFont(.footnote).foregroundStyle(DIColor.onPrimary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DISpacing.sm)
        .contextMenu {
            if model.canModerate, let cue = model.current {
                Button("Remove from the stage", role: .destructive) { cueToRemove = cue }
            }
        }
    }

    @ViewBuilder
    private func cueContent(_ cue: HalqaZikrCue) -> some View {
        switch HalqahStage.card(for: cue.stageID) {
        case .shajra: shajraContent(cue)
        case .dua: duaContent(cue)
        case .standard: standardContent(cue)
        }
    }

    /// The Shajra Sharif: its name, then its lines rising slowly through the
    /// card from the first to the last, where they stop (still, with Reduce
    /// Motion). The words are ShajraText's, exactly as the Shajra page shows them.
    @ViewBuilder
    private func shajraContent(_ cue: HalqaZikrCue) -> some View {
        Text(verbatim: cueTitle(cue))
            .font(.system(size: 32, weight: .semibold, design: .serif))
            .foregroundStyle(DIColor.accent).multilineTextAlignment(.center)
            .diGoldTextShimmer()
            .diGoldGlow(radius: 12, opacity: 0.45)
            .accessibilityIdentifier("stage-title")
        if let secondary = HalqahStage.secondaryTitle(stageID: cue.stageID, titleUr: cue.titleUr, urdu: urdu) {
            Text(verbatim: secondary).font(DIFont.urduBody(scale: 1.3)).foregroundStyle(DIColor.onPrimary.opacity(0.92))
                .multilineTextAlignment(.center)
        }
        ShajraStageLines(announcedAt: cue.createdAt, urdu: urdu)
            .frame(height: presenting ? 440 : 330)
            .accessibilityIdentifier("stage-shajra")
    }

    /// The dua that closes the Zikr, on a card of its own.
    @ViewBuilder
    private func duaContent(_ cue: HalqaZikrCue) -> some View {
        Image(systemName: "hands.and.sparkles.fill")
            .font(.system(size: 52, weight: .regular))
            .foregroundStyle(DIColor.accent)
            .diGoldGlow(radius: 14, opacity: 0.55)
            .accessibilityHidden(true)
        Text(verbatim: cueTitle(cue))
            .font(.system(size: 40, weight: .semibold, design: .serif))
            .foregroundStyle(DIColor.accent).multilineTextAlignment(.center)
            .diGoldTextShimmer()
            .diGoldGlow(radius: 12, opacity: 0.45)
            .accessibilityIdentifier("stage-title")
        if let secondary = HalqahStage.secondaryTitle(stageID: cue.stageID, titleUr: cue.titleUr, urdu: urdu) {
            Text(verbatim: secondary).font(DIFont.urduBody(scale: 1.5)).foregroundStyle(DIColor.onPrimary.opacity(0.92))
                .multilineTextAlignment(.center)
        }
        Text("Join in the dua")
            .diInterfaceFont(.title3, weight: .medium)
            .foregroundStyle(DIColor.onPrimary.opacity(0.85))
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("stage-dua")
    }

    @ViewBuilder
    private func standardContent(_ cue: HalqaZikrCue) -> some View {
        if let latifa = Self.latifa(cue.stageID) {
            LatifaMedallion(number: latifa)
        }
        Text(verbatim: cueTitle(cue))
            .font(.system(size: 36, weight: .semibold, design: .serif))
            .foregroundStyle(DIColor.accent).multilineTextAlignment(.center)
            .diGoldTextShimmer()
            .diGoldGlow(radius: 12, opacity: 0.45)
            .accessibilityIdentifier("stage-title")
        if let titleUr = HalqahStage.secondaryTitle(stageID: cue.stageID, titleUr: cue.titleUr, urdu: urdu) {
            Text(verbatim: titleUr).font(DIFont.urduBody(scale: 1.4)).foregroundStyle(DIColor.onPrimary.opacity(0.92))
                .multilineTextAlignment(.center)
                .diGoldTextShimmer(delay: 2)
        }
        if let arabic = cue.arabic {
            Text(verbatim: arabic)
                .font(DIFont.quranArabic(scale: 1.5)).foregroundStyle(DIColor.onPrimary)
                .multilineTextAlignment(.center).environment(\.layoutDirection, .rightToLeft)
                .lineSpacing(10)
                .diGoldTextShimmer(delay: 1.4)
                .diGoldGlow(radius: 16, opacity: 0.5)
                .accessibilityIdentifier("stage-arabic")
        }
    }

    @ViewBuilder
    private var idleContent: some View {
        StageEmblem(size: 112)
        Text(model.live == nil ? LocalizedStringKey("The Zikr is not live now.") : LocalizedStringKey("The Zikr begins soon."))
            .font(.system(size: 26, weight: .semibold, design: .serif)).foregroundStyle(DIColor.accent)
            .multilineTextAlignment(.center)
            .diGoldTextShimmer()
        Text(verbatim: DIBrand.anchorVerseArabic).font(DIFont.quranArabic(scale: 1.2))
            .foregroundStyle(DIColor.onPrimary).multilineTextAlignment(.center)
            .diGoldTextShimmer(delay: 1.6)
            .diGoldGlow()
    }

    static func latifa(_ stageID: String) -> Int? {
        guard stageID.hasPrefix("latifa-"), let number = Int(stageID.dropFirst(7)), (1...7).contains(number) else { return nil }
        return number
    }

    // MARK: Leading (admins)

    private var leadControls: some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            ViewThatFits(in: .horizontal) {
                HStack { goLiveButton; presentationButton }
                VStack(alignment: .leading, spacing: DISpacing.sm) { goLiveButton; presentationButton }
            }
            if case .unavailable(let reason) = model.voice {
                Text(verbatim: reason).diInterfaceFont(.footnote).foregroundStyle(DIColor.danger)
            }
            if model.voice == .listening { liveIndicator }
            if let notice = model.voiceNotice {
                Text(verbatim: notice).diInterfaceFont(.footnote).foregroundStyle(DIColor.danger)
            }
            if let heard = model.heard, heard.id == model.current?.id {
                HStack {
                    Text("Heard: \(urdu ? heard.titleUr ?? heard.title : heard.title)").diInterfaceFont(.subheadline)
                    Spacer()
                    Button("Undo") { Task { await model.undo() } }.buttonStyle(DICompactButtonStyle()).disabled(model.announcing)
                        .accessibilityIdentifier("stage-voice-undo")
                }
            }
            Text("Opening recitations").diInterfaceFont(.caption, weight: .semibold).foregroundStyle(DIColor.accent)
            chips(model.recitations.map { StageChip(id: $0.id, title: urdu ? $0.titleUr : $0.title) })
            Text("Stages").diInterfaceFont(.caption, weight: .semibold).foregroundStyle(DIColor.accent)
            chips(model.stages.map { StageChip(id: $0.id, title: urdu ? $0.titleUr ?? $0.title : $0.title) })
            Button { addingMuraqaba = true } label: { Label("Add Muraqaba", systemImage: "plus.circle.fill") }
                .buttonStyle(DISecondaryButtonStyle())
                .disabled(model.busy)
                .accessibilityIdentifier("stage-add-muraqaba")
            Text("Tap to show it on the stage. Pressing \"Presentation\" hides these controls; double-tap the stage to bring them back.")
                .diInterfaceFont(.caption).foregroundStyle(DIColor.onPrimary.opacity(0.7))
            Text(ourSheikh
                 ? LocalizedStringKey("After \"Go Live\", each stage Hazrat ji names is shown by itself, until you stop it. \"Undo\" puts back a wrong one.")
                 : LocalizedStringKey("After \"Go Live\", each stage named in the Zikr is shown by itself, until you stop it. \"Undo\" puts back a wrong one."))
                .diInterfaceFont(.caption).foregroundStyle(DIColor.onPrimary.opacity(0.7))
        }
        .padding(DISpacing.md)
        .diGlassPanel(cornerRadius: 22)
    }

    private var goLiveButton: some View {
        let live = model.voice == .listening
        return Button { Task { await model.toggleVoice() } } label: {
            Label(live ? (ourSheikh ? LocalizedStringKey("Live: following Hazrat ji's voice")
                                    : LocalizedStringKey("Live: following the leader's voice"))
                       : LocalizedStringKey("Go Live"),
                  systemImage: live ? "waveform" : "dot.radiowaves.left.and.right")
        }
        .buttonStyle(DIPrimaryButtonStyle())
        .symbolEffect(.variableColor.iterative, isActive: live && !reduceMotion)
        .accessibilityIdentifier("stage-go-live")
    }

    /// Our Sheikh's live sound (Android LiveAudioButtons): everyone can hear
    /// the Zikr while it is live, here on the stage; admins can also send
    /// this phone's voice to the app, Paltalk and YouTube.
    private var liveAudioControls: some View {
        VStack(spacing: DISpacing.sm) {
            if model.live != nil {
                Button { listening ? stopListening() : startListening() } label: {
                    Label(listening ? LocalizedStringKey("Stop listening") : LocalizedStringKey("Listen live"),
                          systemImage: listening ? "stop.fill" : "headphones")
                }
                .buttonStyle(DIPrimaryButtonStyle())
                .accessibilityIdentifier("stage-listen-live")
                if listening {
                    HStack(spacing: DISpacing.sm) {
                        DILivePulse(size: 8)
                        Text(verbatim: listenStatus.isEmpty ? String(localized: "Live audio") : listenStatus)
                            .diInterfaceFont(.footnote)
                            .foregroundStyle(DIColor.onPrimary.opacity(0.85))
                            .lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("stage-listen-status")
                }
            }
            if model.canModerate {
                Button { openLiveAudio(.broadcast) } label: { Label("Broadcast", systemImage: "music.mic") }
                    .buttonStyle(DISecondaryButtonStyle())
                    .accessibilityIdentifier("stage-broadcast")
                Text("Your voice goes to the app, Paltalk and YouTube.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
        }
    }

    /// Hears the live sound on the stage, out of sight, while the stage shows.
    private func startListening() {
        guard ourSheikh, !listening else { return }
        Task {
            let token = await model.service.liveAudioToken ?? ""
            guard model.live != nil, !listening else { return }
            listenToken = token
            listenStatus = ""
            listening = true
        }
    }

    private func stopListening() {
        listening = false
        listenToken = ""
        listenStatus = ""
    }

    private func openLiveAudio(_ mode: LiveAudioMode) {
        // One microphone: following Hazrat ji's voice pauses while this
        // phone broadcasts, and the live sound stops (it would echo).
        if mode == .broadcast {
            model.stopVoice()
            stopListening()
        }
        Task {
            liveAudioToken = await model.service.liveAudioToken ?? ""
            liveAudio = mode
        }
    }

    private var presentationButton: some View {
        Button { presenting = true } label: { Label("Presentation", systemImage: "rectangle.on.rectangle") }
            .buttonStyle(DISecondaryButtonStyle())
    }

    /// A small sign that the microphone is on, with the last words it heard.
    private var liveIndicator: some View {
        HStack(spacing: DISpacing.sm) {
            DILivePulse(size: 8)
            Group {
                if model.voiceWords.isEmpty {
                    Text("Listening…")
                } else {
                    Text("Last heard: \(model.voiceWords)")
                }
            }
            .diInterfaceFont(.footnote)
            .foregroundStyle(DIColor.onPrimary.opacity(0.85))
            .lineLimit(1)
            .truncationMode(.head)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stage-voice-indicator")
    }

    private struct StageChip: Identifiable { let id: String; let title: String }

    /// Taps never wait for the one before: they are announced in turn.
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
                .accessibilityIdentifier("stage-chip-" + item.id)
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
            if model.canModerate {
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

// MARK: - Adding a Muraqaba from the stage

/// The same Muraqaba editor as the Guided Zikr panel's, opened from the stage.
private struct StageMuraqabaEditor: View {
    let model: ZikrStageModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var titleUr = ""
    @State private var saving = false
    private enum Field: Hashable { case name, urduName }
    @FocusState private var field: Field?

    private var canSave: Bool {
        !saving && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 100 && titleUr.count <= 100
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DISpacing.md) {
                    DICard {
                        VStack(alignment: .leading, spacing: DISpacing.sm) {
                            Text("Muraqaba name").diInterfaceFont(.caption)
                            TextField("Muraqaba name", text: $title)
                                .diInterfaceFont(.body)
                                .focused($field, equals: .name).submitLabel(.next)
                                .onSubmit { field = .urduName }
                                .autocorrectionDisabled()
                                .padding(DISpacing.sm).background(DIColor.background, in: RoundedRectangle(cornerRadius: 10))
                                .accessibilityIdentifier("stage-muraqaba-name")
                            Text("Urdu name (optional)").diInterfaceFont(.caption)
                            TextField("Urdu name (optional)", text: $titleUr)
                                .diInterfaceFont(.body)
                                .focused($field, equals: .urduName).submitLabel(.done)
                                .onSubmit { field = nil }
                                .autocorrectionDisabled()
                                .padding(DISpacing.sm).background(DIColor.background, in: RoundedRectangle(cornerRadius: 10))
                                .accessibilityIdentifier("stage-muraqaba-urdu-name")
                        }.disabled(saving)
                    }
                    if let error = model.addError {
                        Text(verbatim: error).diInterfaceFont(.subheadline).foregroundStyle(DIColor.danger)
                    }
                    if saving { ProgressView() }
                }
                .padding(DISpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .diScreenBackground()
            .navigationTitle("Add Muraqaba")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { field = nil; dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                        .accessibilityIdentifier("stage-muraqaba-save")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(saving)
        .onAppear { model.clearAddError(); field = .name }
    }

    private func save() {
        field = nil
        saving = true
        Task {
            let added = await model.addMuraqaba(title: title, titleUr: titleUr)
            saving = false
            if added { dismiss() }
        }
    }
}

// MARK: - Stage light (Reduce Motion stills all of it)

/// The stage's living background: deep emerald with drifting aurora, the
/// Islamic pattern turning slowly, a rosette of octagrams turning the other
/// way, the seal faintly behind it all, a breathing gold glow and rising
/// motes of light.
private struct StageBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false
    @State private var breathing = false

    var body: some View {
        GeometryReader { geometry in
            let side = max(geometry.size.width, geometry.size.height)
            ZStack {
                LinearGradient(colors: [Color(hex: 0x03271B), Color(hex: 0x064B34), Color(hex: 0x021A12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                DIAuroraLayer(intensity: 0.85)
                Image("islamic-pattern").resizable(resizingMode: .tile)
                    .frame(width: side * 1.5, height: side * 1.5)
                    .opacity(0.07)
                    .rotationEffect(.degrees(turning ? 360 : 0))
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                ZStack {
                    ForEach(0..<3, id: \.self) { ring in
                        DIOctagram(innerRatio: 0.74)
                            .stroke(DIColor.accent.opacity(0.10 - Double(ring) * 0.02), lineWidth: 1)
                            .frame(width: side * (0.45 + 0.25 * CGFloat(ring)), height: side * (0.45 + 0.25 * CGFloat(ring)))
                            .rotationEffect(.degrees(Double(ring) * 15))
                    }
                }
                .rotationEffect(.degrees(turning ? -360 : 0))
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.4)
                Image("BrandEmblem").resizable().scaledToFit()
                    .frame(width: side * 0.42)
                    .opacity(0.05)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.4)
                RadialGradient(colors: [DIColor.goldGlow.opacity(breathing ? 0.26 : 0.14), .clear],
                               center: .top, startRadius: 10, endRadius: side * 0.7)
                StageParticles()
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 240).repeatForever(autoreverses: false)) { turning = true }
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}

/// Motes of gold light rising slowly up the stage; still under Reduce Motion.
private struct StageParticles: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let count = 42

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.addFilter(.blur(radius: 1.2))
                for index in 0..<Self.count {
                    let seed = Double(index) + 1
                    let speed = 0.02 + Self.unit(seed * 78.233) * 0.04
                    let progress = (time * speed + Self.unit(seed * 3.17)).truncatingRemainder(dividingBy: 1)
                    let x = Self.unit(seed * 12.9898) * size.width + sin(time * 0.4 + seed) * 14
                    let y = size.height * (1.05 - progress * 1.1)
                    let radius = 1.2 + Self.unit(seed * 5.31) * 2.6
                    let alpha = sin(progress * .pi) * (0.3 + Self.unit(seed * 9.7) * 0.5)
                    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                 with: .color(DIColor.goldGlow.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A fixed pseudo-random number in 0..<1 for a seed.
    private static func unit(_ value: Double) -> Double {
        let scaled = sin(value) * 43758.5453
        return scaled - scaled.rounded(.down)
    }
}

/// The Silsila's seal on the stage: a gold ring and an octagram turning
/// slowly around it, with a breathing glow.
private struct StageEmblem: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [DIColor.goldGlow.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: size * 0.62))
                .frame(width: size * 1.25, height: size * 1.25)
            DIOctagram(innerRatio: 0.78)
                .stroke(DIColor.accent.opacity(0.55), lineWidth: 1)
                .frame(width: size * 1.08, height: size * 1.08)
                .rotationEffect(.degrees(turning ? 360 : 0))
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(AngularGradient(colors: [DIColor.accent.opacity(0), DIColor.accent, Color(hex: 0xFFF4CF)], center: .center),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: size * 0.98, height: size * 0.98)
                .rotationEffect(.degrees(turning ? -720 : 0))
            Image("BrandEmblem").resizable().scaledToFit()
                .frame(width: size * 0.82, height: size * 0.82)
        }
        .frame(width: size, height: size)
        .diBreathingGlow(maxRadius: 16)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) { turning = true }
        }
    }
}

/// The running stage's card: floating gently, its glow breathing, lights
/// travelling round its edge, and a burst of light as it arrives.
private struct StageFloatingCard<Content: View>: View {
    var burst = true
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bob = false
    @State private var glow = false
    private let radius: CGFloat = 30

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        VStack(spacing: DISpacing.md) { content() }
            .padding(.horizontal, DISpacing.xl)
            .padding(.vertical, DISpacing.lg + 4)
            .frame(maxWidth: 680)
            .background {
                shape.fill(LinearGradient(colors: [Color(hex: 0x0B7250).opacity(0.85), Color(hex: 0x064B34).opacity(0.9), Color(hex: 0x03261A).opacity(0.92)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(DIAuroraLayer(intensity: 0.55).clipShape(shape))
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [DIColor.accent, DIColor.accent.opacity(0.25), Color(hex: 0xFFF4CF)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
            .overlay { if !reduceMotion { StageOrbitLights(cornerRadius: radius) } }
            .overlay { if burst && !reduceMotion { StageBurst(cornerRadius: radius) } }
            .shadow(color: DIColor.goldGlow.opacity(glow ? 0.55 : 0.22), radius: glow ? 32 : 16)
            .offset(y: reduceMotion ? 0 : (bob ? -7 : 7))
            .accessibilityElement(children: .combine)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) { bob = true }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { glow = true }
            }
    }
}

/// Three points of light orbiting the card's edge.
private struct StageOrbitLights: View {
    let cornerRadius: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let head = (time / 9 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .trim(from: max(0, head - 0.05), to: head)
                        .stroke(Color(hex: 0xFFF4CF), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .blur(radius: 1.2)
                        .shadow(color: DIColor.goldGlow, radius: 6)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A ring of gold light that bursts outwards once, as a new stage arrives.
private struct StageBurst: View {
    let cornerRadius: CGFloat
    @State private var fired = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(RadialGradient(colors: [Color(hex: 0xFFF4CF).opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: 280))
                .opacity(fired ? 0 : 1)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(DIColor.goldGlow, lineWidth: fired ? 1 : 6)
                .scaleEffect(fired ? 1.25 : 0.96)
                .opacity(fired ? 0 : 0.9)
                .blur(radius: fired ? 8 : 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { withAnimation(.easeOut(duration: 1.2)) { fired = true } }
    }
}

/// The Latifa's number on a turning gold octagram (a numeral, not a picture).
private struct LatifaMedallion: View {
    let number: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        ZStack {
            DIOctagram(innerRatio: 0.72)
                .fill(LinearGradient(colors: [Color(hex: 0xFFE9A8), Color(hex: 0xE0B75F), Color(hex: 0xB48A2C)],
                                     startPoint: .top, endPoint: .bottom))
                .rotationEffect(.degrees(turning ? 360 : 0))
            Circle().fill(DIColor.primaryDeep).padding(14)
            Text(verbatim: String(number))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(DIColor.accent)
        }
        .frame(width: 74, height: 74)
        .diBreathingGlow(maxRadius: 18)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) { turning = true }
        }
    }
}

/// Blur, scale and fade together, for a stage's arrival and departure.
private struct StageArrivalEffect: ViewModifier {
    let blur: CGFloat
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.blur(radius: blur).scaleEffect(scale).opacity(opacity)
    }
}

private extension AnyTransition {
    /// A new stage comes in large and blurred and settles sharp; the old one
    /// sinks away.
    static var stageArrival: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: StageArrivalEffect(blur: 24, scale: 1.35, opacity: 0),
                                 identity: StageArrivalEffect(blur: 0, scale: 1, opacity: 1)),
            removal: .modifier(active: StageArrivalEffect(blur: 14, scale: 0.8, opacity: 0),
                               identity: StageArrivalEffect(blur: 0, scale: 1, opacity: 1))
        )
    }
}

/// Hazrat ji's picture: YouTube's full-size frame, else its standard one;
/// the Silsila's logo when there is none (every Halqah but Our Sheikh).
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
                    .diBreathingGlow(maxRadius: 18)
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

/// The Shajra on the live stage: each link of the chain in Urdu (with the
/// website's English line under it in English), then the closing dua in
/// Arabic, rising slowly from the first line to the last and stopping there
/// (ShajraStageScroll). A stage opened late joins it where it is. Reduce
/// Motion shows the lines still, to scroll by hand. Android ShajraStageLines.
struct ShajraStageLines: View {
    /// When the Shajra was announced on the stage.
    let announcedAt: Date
    let urdu: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentHeight: CGFloat = 0
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { box in
            if reduceMotion {
                ScrollView(showsIndicators: false) { lines.frame(width: box.size.width) }
            } else {
                lines
                    .frame(width: box.size.width)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { inner in
                        Color.clear.preference(key: ShajraHeightKey.self, value: inner.size.height)
                    })
                    .modifier(ShajraRise(progress: progress, distance: max(0, contentHeight - box.size.height)))
                    .frame(width: box.size.width, height: box.size.height, alignment: .top)
                    .clipped()
            }
        }
        .onPreferenceChange(ShajraHeightKey.self) { height in
            Task { @MainActor in contentHeight = height }
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                                     .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .task(id: announcedAt) { await rise() }
    }

    private var lines: some View {
        VStack(spacing: DISpacing.md) {
            ForEach(ShajraText.entries) { entry in
                VStack(spacing: 4) {
                    Text(verbatim: entry.urdu)
                        .font(DIFont.urduBody(scale: 1.25))
                        .foregroundStyle(entry.kind == .sheikh ? DIColor.onPrimary : DIColor.accent)
                        .multilineTextAlignment(.center)
                        .environment(\.layoutDirection, .rightToLeft)
                        .lineSpacing(6)
                    if !urdu {
                        Text(verbatim: entry.english)
                            .diInterfaceFont(.footnote)
                            .foregroundStyle(DIColor.onPrimary.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: ShajraText.closingArabic)
                .font(DIFont.quranArabic(scale: 1.15))
                .foregroundStyle(DIColor.accent)
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .rightToLeft)
                .lineSpacing(8)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DISpacing.lg)
    }

    /// Where the Shajra is now, then on to its last line at its pace.
    private func rise() async {
        guard !reduceMotion else { return }
        let elapsed = Date().timeIntervalSince(announcedAt)
        progress = CGFloat(ShajraStageScroll.progress(elapsed: elapsed))
        let remaining = ShajraStageScroll.remaining(elapsed: elapsed)
        guard remaining > 0 else { return }
        // Once the lines are laid out and measured.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        withAnimation(.linear(duration: max(remaining - 0.4, 0.1))) { progress = 1 }
    }
}

/// Moves the Shajra's lines up by `progress` of `distance`; the distance can
/// change (the lines measured late) while the rise goes on.
private struct ShajraRise: GeometryEffect {
    var progress: CGFloat
    var distance: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 0, y: -distance * progress))
    }
}

private struct ShajraHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// In every other Halqah while Our Sheikh's own Zikr is live (Daily Zikr, or
/// the Tahajjud zikr before dawn): joined on Our Sheikh's live stage with the
/// app's live sound, where the YouTube stream used to play (owner, 2026-11-06).
struct SheikhLiveJoinCard: View {
    var body: some View {
        Button {
            DIHaptics.light()
            DeepLinkRouter.shared.open(.sheikhStage)
        } label: {
            HStack(spacing: DISpacing.md) {
                DILivePulse(color: .white, size: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live now: \(String(localized: "Our Sheikh"))")
                        .diInterfaceFont(.headline).foregroundStyle(DIColor.onPrimary)
                    Text("Join Zikr").diInterfaceFont(.subheadline).foregroundStyle(DIColor.onPrimary.opacity(0.85))
                }
                Spacer(minLength: 0)
                Image(systemName: "headphones").font(.title3).foregroundStyle(DIColor.accent)
            }
            .padding(DISpacing.md)
            .background(LinearGradient(colors: [DIColor.primaryDeep, DIColor.primary], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(DIColor.accent.opacity(0.6)))
        }
        .buttonStyle(DIPressableStyle())
        .accessibilityIdentifier("sheikh-live-join")
    }
}

/// On a Halqah's page while its Zikr is live (in a room, a live video or a
/// recording played from the app): the way into the stage, in place of the
/// stage controls that used to sit on the page.
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
