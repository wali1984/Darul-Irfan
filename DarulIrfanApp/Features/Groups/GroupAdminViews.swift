import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// What a group admin does from the phone: post, start a community zikr (led
// live, or a past zikr or recording played to the group) or a meeting,
// schedule a meeting, and keep the group's zikr times.

/// Reads a video's id from whatever an admin pastes: a share link, a watch
/// link, a live link, or the bare id.
enum VideoLink {
    static func id(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil { return trimmed }
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else { return nil }
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        let shortLink = host == "youtu.be" || host.hasSuffix(".youtu.be")
        let videoHost = host == "youtube.com" || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com")
        guard shortLink || videoHost else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        var candidate: String?
        if shortLink {
            candidate = parts.first
        } else if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value {
            candidate = v
        } else if let index = parts.firstIndex(where: { ["live", "shorts", "embed"].contains($0) }), index + 1 < parts.count {
            candidate = parts[index + 1]
        }
        guard let candidate, candidate.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else { return nil }
        return candidate
    }

    /// The time a pasted link starts at, as YouTube's "Share at" writes it:
    /// `?t=221`, `&t=3m41s`, `?start=221`, `youtu.be/ID?t=90` (or `#t=90`).
    /// Nil when the link has none.
    static func startSeconds(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed) else { return nil }
        var values = (components.queryItems ?? [])
            .filter { $0.name == "t" || $0.name == "start" }
            .compactMap(\.value)
        if let fragment = components.fragment, fragment.hasPrefix("t=") {
            values.append(String(fragment.dropFirst(2)))
        }
        for value in values {
            if let seconds = timeParameter(value), seconds > 0 { return seconds }
        }
        return nil
    }

    /// "221", "221s", "3m41s", "1h2m3s" or "3:41".
    static func timeParameter(_ value: String) -> Int? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if text.contains(":") { return ClipTime.seconds(from: text) }
        var total = 0
        var digits = ""
        for character in text {
            if character.isASCII && character.isNumber {
                digits.append(character)
                continue
            }
            guard !digits.isEmpty, digits.count <= 6, let number = Int(digits) else { return nil }
            switch character {
            case "h": total += number * 3_600
            case "m": total += number * 60
            case "s": total += number
            default: return nil
            }
            digits = ""
        }
        if !digits.isEmpty {
            guard digits.count <= 6, let number = Int(digits) else { return nil }
            total += number
        }
        return total
    }
}

/// "Start at" and "End at" under a pasted YouTube link, in a Halqah with
/// video clips: only that part of the video plays, e.g. 3:41 to 44:02.
/// Both are optional.
struct VideoClipSection: View {
    @Binding var start: String
    @Binding var end: String

    var body: some View {
        Section {
            field("Start at", text: $start)
                .accessibilityIdentifier("clip-start")
            field("End at", text: $end)
                .accessibilityIdentifier("clip-end")
        } footer: {
            if let problem = VideoClipTimes.problem(start: start, end: end) {
                let message: LocalizedStringKey = problem == .endNotAfterStart
                    ? "End must be after the start."
                    : "Enter a time such as 3:41 or 1:02:03."
                Text(message).foregroundStyle(DIColor.danger)
                    .accessibilityIdentifier("clip-error")
            } else {
                Text("Optional: play only part of the video, for example from 3:41 to 44:02.")
            }
        }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        LabeledContent {
            TextField("0:00", text: text)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
        } label: {
            Text(title)
        }
    }
}

// MARK: - Post

@MainActor
struct GroupPostComposer: View {
    let groupID: String
    let service: MemberGroupService

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var message = ""
    @State private var videoLink = ""
    @State private var attachments: [PostDraftAttachment] = []
    @State private var postRequestID = UUID()
    @State private var uploadedMedia: [UUID: String] = [:]
    @State private var picks: [PhotosPickerItem] = []
    @State private var progress: String?
    @State private var working = false
    @State private var preparingMedia = false
    @State private var error: String?

    private static let maxAttachments = 10

    var body: some View {
        Form {
            Group {
            Section {
                // The quickest route from a WhatsApp group: copy the message
                // (or a picture) there, then paste it here.
                Button {
                    paste()
                } label: {
                    Label("Paste a copied message or picture", systemImage: "doc.on.clipboard")
                }
            } footer: {
                Text("Copy a message or a picture in WhatsApp or anywhere else, then paste it here. The first line becomes the title.")
            }
            Section {
                PhotosPicker(
                    selection: $picks,
                    maxSelectionCount: max(1, Self.maxAttachments - attachments.count),
                    matching: .any(of: [.images, .videos])
                ) {
                    Label("Add photos or videos", systemImage: "photo.on.rectangle.angled")
                }
                .disabled(attachments.count >= Self.maxAttachments)
                if !attachments.isEmpty {
                    PostAttachmentStrip(attachments: $attachments)
                }
            } footer: {
                Text("Up to 10 pictures and videos; each video up to 95 MB. They are seen by this Halqah only.")
            }
            Section {
                TextField(attachments.isEmpty ? "Title" : "Title (optional)", text: $title, axis: .vertical)
                TextField("Message", text: $message, axis: .vertical)
                    .lineLimit(3...12)
                TextField("Video link (optional)", text: $videoLink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } footer: {
                if !videoLink.isEmpty && VideoLink.id(from: videoLink) == nil {
                    Text("That video link was not recognised.")
                }
            }
            if let error {
                Section { Text(verbatim: error).foregroundStyle(DIColor.danger) }
            }
            if let progress {
                Section {
                    HStack(spacing: DISpacing.sm) {
                        ProgressView()
                        Text(verbatim: progress)
                    }
                }
            }
            if preparingMedia {
                Section { ProgressView("Loading") }
            }
            Section {
                Button {
                    Task { await save(publish: true) }
                } label: {
                    Label("Publish to the group", systemImage: "paperplane.fill")
                }
                .disabled(!canSave)
                Button("Save as draft") { Task { await save(publish: false) } }
                    .disabled(!canSave)
            } footer: {
                Text("Publishing notifies the group's members who have notifications on.")
            }
            }
            .listRowBackground(DIColor.surface)
        }
        .disabled(working || preparingMedia)
        .interactiveDismissDisabled(working || preparingMedia)
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .toggleStyle(SwitchToggleStyle(tint: DIColor.primary))
        .navigationTitle("New post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }.buttonStyle(DIToolbarButtonStyle()).disabled(working || preparingMedia)
        } }
        .onChange(of: picks) { _, chosen in
            guard !chosen.isEmpty, !working, !preparingMedia else { return }
            preparingMedia = true
            error = nil
            Task {
                defer { preparingMedia = false; picks = [] }
                for item in chosen where attachments.count < Self.maxAttachments {
                    if let attachment = await PostMediaPreparation.load(item) {
                        attachments.append(attachment)
                    } else {
                        error = String(localized: "Some photos or videos could not be opened. Download them to your phone and choose them again.")
                    }
                }
            }
        }
    }

    /// A title, or at least a picture or video, which can stand on its own.
    private var canSave: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasVideo = VideoLink.id(from: videoLink) != nil
        return !working && !preparingMedia && (hasTitle || !attachments.isEmpty || hasVideo)
            && (videoLink.isEmpty || hasVideo)
    }

    private func paste() {
        guard !working, !preparingMedia else { return }
        // Pictures copied from WhatsApp, Photos or a browser.
        for image in UIPasteboard.general.images ?? [] where attachments.count < Self.maxAttachments {
            if let prepared = PostMediaPreparation.picture(from: image) {
                attachments.append(PostDraftAttachment(content: .picture(prepared.0), preview: prepared.1))
            }
        }
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        var lines = text.components(separatedBy: .newlines)
        let first = lines.removeFirst().trimmingCharacters(in: .whitespaces)
        if title.isEmpty { title = String(first.prefix(120)) }
        let rest = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        message = first.count > 120 ? text : rest
        if videoLink.isEmpty, let link = text.components(separatedBy: .whitespacesAndNewlines).first(where: { VideoLink.id(from: $0) != nil && $0.contains("/") }) {
            videoLink = link
        }
    }

    private func save(publish: Bool) async {
        guard canSave else { return }
        working = true
        error = nil
        progress = String(localized: "Saving…")
        defer { working = false; progress = nil }
        do {
            // Each file goes up first; the post then names them, in order.
            var keys: [String] = []
            for (index, attachment) in attachments.enumerated() {
                progress = String(localized: "Sending \(index + 1) of \(attachments.count)...")
                if let key = uploadedMedia[attachment.id] {
                    keys.append(key)
                    continue
                }
                switch attachment.content {
                case .picture(let data):
                    keys.append(try await service.uploadPostMedia(picture: data, contentType: "image/jpeg", in: groupID))
                case .video(let url):
                    keys.append(try await service.uploadPostMedia(video: url, contentType: PostMediaPreparation.videoType(url), in: groupID))
                }
                uploadedMedia[attachment.id] = keys.last
            }
            progress = String(localized: "Saving…")
            try await service.createPost(
                in: groupID,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: message.trimmingCharacters(in: .whitespacesAndNewlines),
                videoID: VideoLink.id(from: videoLink),
                media: keys,
                publish: publish,
                requestID: postRequestID
            )
            dismiss()
        } catch {
            if let groupError = error as? MemberGroupError, case .requestFailed = groupError {
                self.error = String(localized: "The action could not be completed. Check your connection and try again.")
            } else if error is MemberGroupError {
                // Preserve sign-in, validation and rate-limit guidance from the service.
                self.error = error.localizedDescription
            } else {
                self.error = String(localized: "The action could not be completed. Check your connection and try again.")
            }
        }
    }
}

// MARK: - Live now

/// A YouTube link with its Start at and End at, as the fields show them.
struct VideoLinkDraft: Equatable {
    var link: String
    var start: String
    var end: String

    init(link: String, start: String, end: String) {
        self.link = link
        self.start = start
        self.end = end
    }

    init(videoID: String, startSeconds: Double?, endSeconds: Double?) {
        link = "https://youtu.be/" + videoID
        start = startSeconds.map { ClipTime.text($0) } ?? ""
        end = endSeconds.map { ClipTime.text($0) } ?? ""
    }
}

/// The start sheet's form. A simple Halqah page (owner 2026-11-19, addendum
/// 2: "no meeting option, no lead live, no record zikr option") starts a
/// Halqah Zikr from YouTube or a recording only, under the server's own
/// heading, and names the session after it.
struct HalqahStartForm: Equatable {
    let isSimple: Bool
    /// The server's start title, e.g. "Start Daily North America Nightly Zikr".
    let startTitle: String?

    /// The link and the Start at / End at the simple sheet opens with: the
    /// Halqah's saved zikr time's video (owner 2026-11-19, addendum 5). The
    /// admin may change them for this start; the zikr time stays as it is.
    let prefill: VideoLinkDraft?

    init(simple: Bool = false, startTitle: String? = nil, zikrSessions: [ZikrSession] = []) {
        isSimple = simple
        let trimmed = startTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.startTitle = simple && trimmed?.isEmpty == false ? trimmed : nil
        prefill = simple ? Self.savedVideo(in: zikrSessions) : nil
    }

    /// The first zikr time, by its start, that plays a video by itself.
    static func savedVideo(in sessions: [ZikrSession]) -> VideoLinkDraft? {
        let ordered = sessions.enumerated().sorted { first, second in
            let a = first.element.startHour * 60 + first.element.startMinute
            let b = second.element.startHour * 60 + second.element.startMinute
            return a != b ? a < b : first.offset < second.offset
        }
        for (_, session) in ordered {
            guard let item = session.autoplay?.first, item.isVideo, !item.id.isEmpty else { continue }
            return VideoLinkDraft(videoID: item.id, startSeconds: item.startSeconds, endSeconds: item.endSeconds)
        }
        return nil
    }

    /// The sheet's heading and the start tile's label; nil: "Go live".
    var heading: String? { startTitle }
    /// "Halqah Zikr" or "Meeting": a simple form is always a Halqah Zikr.
    var showsKindChoice: Bool { !isSimple }
    /// Leading live in a room, with its join, record and live link options.
    var offersLeadLive: Bool { !isSimple }
    /// The title field, unless the server's start title names the session.
    var showsTitleField: Bool { sessionTitle == nil }
    /// The session's title: the start title without a leading "Start ".
    var sessionTitle: String? {
        guard let startTitle else { return nil }
        let title = startTitle.hasPrefix("Start ") ? String(startTitle.dropFirst("Start ".count)) : startTitle
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
struct GroupLiveStarter: View {
    @Environment(\.locale) private var locale
    let groupID: String
    let service: MemberGroupService
    /// False while video meetings await their integration: no room can open.
    var meetingsReady = true
    /// Adds recordings and past zikr to the session already live.
    var addingToSession = false
    var sessionID: String? = nil
    /// A Halqah with video clips: a pasted YouTube link may play from a
    /// start time to an end time.
    var videoClips = false
    /// The full sheet, or a simple Halqah page's.
    var form = HalqahStartForm()

    private enum Kind: String, CaseIterable, Identifiable {
        case zikr = "Halqah Zikr"
        case meeting = "Meeting"
        var id: String { rawValue }
    }

    /// How the zikr reaches the group.
    private enum Source: String, CaseIterable, Identifiable {
        case room = "Lead live"
        case youtube = "YouTube"
        case recording = "Recording"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .zikr
    @State private var source: Source = .room
    @State private var title = String(localized: "Halqah Zikr")
    @State private var videoLink = ""
    /// "Start at" and "End at" for the pasted YouTube link (video clips only).
    @State private var clipStart = ""
    @State private var clipEnd = ""
    /// The saved zikr time's video has been filled in once (simple page).
    @State private var prefilled = false
    @State private var joinTogether = true
    /// Records the room into the group's recordings.
    @State private var recordRoom = true
    /// An admin's test: nobody is notified and only the Halqah's admins see it.
    @State private var testOnly = false
    @State private var library: GroupRecordingLibrary?
    @State private var libraryFailed = false
    @State private var libraryLoadGeneration = 0
    @State private var showAllPastVideos = false
    /// What plays, in order: recordings and past zikr, picked from either list.
    @State private var picked: [GroupQueueEntry] = []
    @State private var choosingFile = false
    @State private var uploading = false
    @State private var working = false
    @State private var error: String?

    @State private var deletingRecording: GroupRecording?

    private var sources: [Source] { addingToSession || !form.offersLeadLive ? [.youtube, .recording] : Source.allCases }

    /// The source in use: a simple form never leads live, also before the
    /// sheet's first task has moved it to YouTube.
    private var activeSource: Source { !form.offersLeadLive && source == .room ? .youtube : source }

    /// "Add to the session", a simple page's own heading, or "Go live".
    private var heading: Text {
        if addingToSession { return Text("Add to the session") }
        if let heading = form.heading { return Text(verbatim: heading) }
        return Text("Go live")
    }

    var body: some View {
        Form {
            Group {
                if !addingToSession && (form.showsKindChoice || form.showsTitleField) {
                    Section {
                        if form.showsKindChoice {
                            DISegmentedControl(items: Kind.allCases, title: { LocalizedStringKey($0.rawValue) }, selection: $kind)
                                .accessibilityLabel(Text("What is starting"))
                            .onChange(of: kind) { _, value in
                                title = value == .zikr ? String(localized: "Halqah Zikr") : String(localized: "Group meeting")
                            }
                        }
                        if form.showsTitleField {
                            TextField("Title", text: $title)
                        }
                    }
                }
                if kind == .zikr || addingToSession {
                    Section {
                        DISegmentedControl(items: sources, title: { LocalizedStringKey($0.rawValue) }, selection: $source)
                            .accessibilityLabel(Text("How the group joins"))
                    }
                    switch activeSource {
                    case .room: roomSection
                    case .youtube: youtubeSections
                    case .recording: recordingSections
                    }
                    if !picked.isEmpty && activeSource != .room { orderSection }
                } else {
                    Section {
                        if meetingsReady {
                            Text("Members join with audio and video from the group page.")
                                .foregroundStyle(DIColor.textMuted)
                            Toggle("Record the meeting", isOn: $recordRoom)
                        } else {
                            Text("Video meetings: integration in progress. They open here once it is complete.")
                                .foregroundStyle(DIColor.textMuted)
                        }
                    }
                }
                if libraryFailed {
                    Section {
                        Button("Try again") { Task { await loadLibrary() } }
                            .buttonStyle(DICompactButtonStyle())
                            .accessibilityIdentifier("recording-library-retry")
                    }
                }
                if !addingToSession {
                    Section {
                        Toggle("Test only", isOn: $testOnly)
                            .accessibilityIdentifier("session-test-only")
                    } footer: {
                        Text("Try the session, the stage and the room first: nobody is notified and only this Halqah's admins see it. End it as usual when you are done.")
                    }
                }
                Section {
                    Button {
                        Task { await start() }
                    } label: {
                        HStack(spacing: DISpacing.sm) {
                            if working { ProgressView().tint(.white) }
                            if addingToSession {
                                Label("Add to the session", systemImage: "text.badge.plus")
                            } else if testOnly {
                                Label("Start test without notifying anyone", systemImage: "testtube.2")
                            } else {
                                Label("Start now and notify the group", systemImage: "dot.radiowaves.left.and.right")
                            }
                        }
                    }
                    .buttonStyle(DIPrimaryButtonStyle())
                    .accessibilityIdentifier("session-start-action")
                    .disabled(working || uploading || !canStart)
                }
            }
            .disabled(working || uploading)
            .listRowBackground(DIColor.surface)
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .toggleStyle(SwitchToggleStyle(tint: DIColor.primary))
        .navigationTitle(heading)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(working || uploading)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if !working && !uploading { dismiss() } }.buttonStyle(DIToolbarButtonStyle()).disabled(working || uploading) } }
        .alert("Delete this recording?", isPresented: Binding(
            get: { deletingRecording != nil },
            set: { if !$0 { deletingRecording = nil } }
        ), presenting: deletingRecording) { recording in
            Button("Delete", role: .destructive) { Task { await delete(recording) } }
            Button("Cancel", role: .cancel) { deletingRecording = nil }
        } message: { recording in
            Text(verbatim: recording.title + "\n\n" + String(localized: "This removes the recording from the group's library. This cannot be undone."))
        }
        .alert(addingToSession ? "Add to the session" : "Go live", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(verbatim: error ?? "")
                .accessibilityIdentifier("recording-library-action-error")
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.audio, .movie]) { result in
            if case .success(let file) = result { Task { await upload(file) } }
        }
        .task {
            // Until the room service is connected, start where a zikr can play.
            // A simple page's sheet starts on YouTube too.
            if addingToSession || !meetingsReady || !form.offersLeadLive { source = .youtube }
            // A simple page's sheet opens with its saved zikr time's video and
            // times; a change here is for this start only.
            if !addingToSession, !prefilled, videoLink.isEmpty, let prefill = form.prefill {
                prefilled = true
                videoLink = prefill.link
                clipStart = prefill.start
                clipEnd = prefill.end
            }
            await loadLibrary()
        }
    }

    // MARK: Sources

    private var roomSection: some View {
        Section {
            Toggle("Members join the zikr together", isOn: $joinTogether)
                .disabled(!meetingsReady)
            if meetingsReady && joinTogether {
                Toggle("Record the zikr", isOn: $recordRoom)
            }
            TextField("Live video link (optional)", text: $videoLink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        } footer: {
            if meetingsReady {
                Text("Joining together opens a room where members listen as you lead the zikr. A live video link lets them watch it as well. Use either, or both.")
            } else {
                Text("Leading live in a room: integration in progress. Meanwhile share a live YouTube link here, or play a past zikr or a recording.")
            }
        }
    }

    @ViewBuilder
    private var youtubeSections: some View {
        Section {
            TextField("YouTube link, live or recorded", text: $videoLink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        } footer: {
            Text("A live link is watched live. A past zikr plays to everyone together, from one place you control: pause, move back or forward, or go to the next for the whole group.")
        }
        if videoClips {
            VideoClipSection(start: $clipStart, end: $clipEnd)
                .onChange(of: videoLink) { _, link in
                    // A link shared from a moment in the video starts there.
                    if let seconds = VideoLink.startSeconds(from: link) { clipStart = ClipTime.text(seconds) }
                }
        }
        Section {
            if let videos = library?.pastVideos {
                if videos.isEmpty {
                    Text("No past zikr videos yet.").foregroundStyle(DIColor.textMuted)
                }
                if videos.count > 5 {
                    Button { showAllPastVideos.toggle() } label: {
                        if showAllPastVideos { Text("Show less") }
                        else { Text("Show all \(videos.count)") }
                    }
                    .buttonStyle(DICompactButtonStyle())
                }
                ForEach(videos.prefix(showAllPastVideos ? videos.count : 5)) { video in
                    choiceRow(
                        entry: .video(video.videoID),
                        title: video.title,
                        detail: [GroupInvitationDate.text(video.publishedAt, locale: locale), length(video.durationSeconds)]
                    )
                }

            } else {
                libraryStatus
            }
        } header: {
            Text("Past zikr from the channel")
        } footer: {
            Text("Tap to add in the order they should play.")
        }
    }

    @ViewBuilder
    private var recordingSections: some View {
        Section {
            if let recordings = library?.recordings {
                if recordings.isEmpty {
                    Text("No recordings yet. Upload one from your phone.").foregroundStyle(DIColor.textMuted)
                }
                ForEach(recordings) { recording in
                    VStack(alignment: .leading, spacing: DISpacing.sm) {
                        choiceRow(
                            entry: .recording(recording.id),
                            title: recording.title,
                            detail: [length(recording.durationSeconds), ByteCountFormatter.string(fromByteCount: Int64(recording.byteSize), countStyle: .file)]
                        )
                        .accessibilityIdentifier("recording-choice-" + recording.id)
                        Button("Delete recording") { deletingRecording = recording }
                            .buttonStyle(DICompactButtonStyle(destructive: true))
                            .disabled(working || uploading)
                            .accessibilityIdentifier("recording-delete-" + recording.id)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { deletingRecording = recording }
                            .disabled(working || uploading)
                    }
                }
            } else {
                libraryStatus
            }
            Button {
                choosingFile = true
            } label: {
                if uploading {
                    HStack(spacing: DISpacing.sm) {
                        ProgressView()
                        Text("Uploading...")
                    }
                } else {
                    Label("Upload a recording", systemImage: "square.and.arrow.up")
                }
            }
            .disabled(uploading || working || library == nil)
        } header: {
            Text("The group's recordings")
        } footer: {
            Text("MP3, M4A, AAC, WAV, MP4 or MOV, up to 95 MB. Members listen together, from one place you control. The session stays open until you end it.")
        }
    }

    private var orderSection: some View {
        Section("Plays in this order") {
            ForEach(Array(picked.enumerated()), id: \.element) { index, entry in
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    Text(verbatim: "\(index + 1). \(titleOf(entry))")
                        .foregroundStyle(DIColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack { orderActions(entry, index: index) }
                        VStack(alignment: .leading) { orderActions(entry, index: index) }
                    }
                }
            }
            .onMove { from, to in picked.move(fromOffsets: from, toOffset: to) }
        }
    }

    @ViewBuilder
    private func orderActions(_ entry: GroupQueueEntry, index: Int) -> some View {
        Button("Move up") {
            guard let at = picked.firstIndex(of: entry), at > 0 else { return }
            picked.swapAt(at, at - 1)
        }
        .buttonStyle(DICompactButtonStyle())
        .disabled(index == 0)
        Button("Move down") {
            guard let at = picked.firstIndex(of: entry), at < picked.count - 1 else { return }
            picked.swapAt(at, at + 1)
        }
        .buttonStyle(DICompactButtonStyle())
        .disabled(index == picked.count - 1)
        Button("Remove") { picked.removeAll { $0 == entry } }
            .buttonStyle(DICompactButtonStyle(destructive: true))
    }

    @ViewBuilder
    private var libraryStatus: some View {
        if !libraryFailed { ProgressView() }
    }

    private func choiceRow(entry: GroupQueueEntry, title: String, detail: [String?]) -> some View {
        let position = picked.firstIndex(of: entry)
        return Button {
            if let position { picked.remove(at: position) } else { picked.append(entry) }
        } label: {
            HStack(spacing: DISpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).foregroundStyle(DIColor.textPrimary).lineLimit(2)
                    Text(verbatim: detail.compactMap { $0 }.joined(separator: " · "))
                        .diInterfaceFont(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                Spacer(minLength: 0)
                if let position {
                    Text(verbatim: "\(position + 1)")
                        .diInterfaceFont(.caption, weight: .bold)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(DIColor.primary))
                        .foregroundStyle(DIColor.onPrimary)
                }
            }
        }
        .accessibilityAddTraits(position != nil ? .isSelected : [])
    }

    private func titleOf(_ entry: GroupQueueEntry) -> String {
        switch entry {
        case .recording(let id): library?.recordings.first { $0.id == id }?.title ?? id
        case .video(let id): library?.pastVideos.first { $0.videoID == id }.map { "\($0.title) · \(GroupInvitationDate.text($0.publishedAt, locale: locale))" } ?? id
        case .clip(let id, let start, let end): GroupQueueEntry.clipTitle(id, start: start, end: end)
        }
    }

    private func length(_ seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3_600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(seconds))
    }

    // MARK: Starting

    /// What plays of the pasted YouTube link: all of it, unless this Halqah
    /// has video clips and the admin gave a start or an end.
    private var clipTimes: VideoClipTimes {
        guard showsClipFields, case .success(let times) = VideoClipTimes.read(start: clipStart, end: clipEnd) else {
            return VideoClipTimes()
        }
        return times
    }

    /// Start at and End at are on the sheet: a YouTube zikr in a Halqah with
    /// video clips.
    private var showsClipFields: Bool {
        videoClips && activeSource == .youtube && (kind == .zikr || addingToSession)
    }

    private var canStart: Bool {
        let video = VideoLink.id(from: videoLink)
        if !videoLink.isEmpty && video == nil && activeSource != .recording { return false }
        // End must be after the start.
        if showsClipFields && VideoClipTimes.problem(start: clipStart, end: clipEnd) != nil { return false }
        if addingToSession { return !picked.isEmpty || (activeSource == .youtube && video != nil) }
        if kind == .meeting { return meetingsReady }
        switch activeSource {
        case .room:
            return (joinTogether && meetingsReady) || video != nil
        case .youtube, .recording:
            return !picked.isEmpty || (activeSource == .youtube && video != nil)
        }
    }

    private func start() async {
        guard !working && !uploading && canStart else { return }
        working = true
        error = nil
        defer { working = false }
        // A simple page names the session after its start title.
        let title = form.sessionTitle ?? title.trimmingCharacters(in: .whitespaces)
        let video = VideoLink.id(from: videoLink)
        do {
            if addingToSession {
                // A pasted link here is a past video; a live one is refused.
                var entries = picked
                if activeSource == .youtube, let video { entries.insert(.youTube(video, times: clipTimes), at: 0) }
                try await service.addToSession(entries, in: groupID, sessionID: sessionID)
            } else if kind == .meeting {
                try await service.startLive(in: groupID, kind: "meeting", title: title, videoID: nil, room: true, record: recordRoom,
                                            test: testOnly)
            } else if activeSource == .room {
                try await service.startLive(in: groupID, kind: "zikr", title: title, videoID: video,
                                            room: joinTogether && meetingsReady, record: recordRoom, test: testOnly)
            } else {
                // The server asks YouTube whether a pasted link is live or past:
                // live is watched live, past joins the queue at the front.
                let clip = activeSource == .youtube && video != nil && !clipTimes.isEmpty ? clipTimes : nil
                try await service.startLive(in: groupID, kind: "zikr", title: title,
                                            videoID: activeSource == .youtube ? video : nil, room: false, queue: picked, test: testOnly,
                                            clip: clip)
            }
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            self.error = actionErrorMessage(error)
        }
    }

    // MARK: Recordings

    private func loadLibrary() async {
        libraryLoadGeneration += 1
        let generation = libraryLoadGeneration
        libraryFailed = false
        do {
            let loaded = try await service.recordings(in: groupID)
            guard !Task.isCancelled, generation == libraryLoadGeneration else { return }
            library = loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == libraryLoadGeneration else { return }
            libraryFailed = true
        }
    }

    private func upload(_ file: URL) async {
        guard !uploading && !working else { return }
        error = nil
        let types = ["mp3": "audio/mpeg", "m4a": "audio/mp4", "aac": "audio/aac", "wav": "audio/wav",
                     "mp4": "video/mp4", "m4v": "video/mp4", "mov": "video/quicktime"]
        guard let contentType = types[file.pathExtension.lowercased()] else {
            error = String(localized: "Choose an MP3, M4A, AAC, WAV, MP4 or MOV file.")
            return
        }
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > library?.maxUploadBytes ?? Int.max {
            error = String(localized: "The file is larger than 95 MB. Choose a shorter recording, or one saved at a lower quality.")
            return
        }
        uploading = true
        defer { uploading = false }
        do {
            let duration = try? await AVURLAsset(url: file).load(.duration).seconds
            let name = file.deletingPathExtension().lastPathComponent
            let uploadedID = try await service.uploadRecording(
                from: file, contentType: contentType, title: name,
                durationSeconds: duration.flatMap { $0.isFinite && $0 > 0 ? Int($0.rounded()) : nil }, in: groupID
            )
            // The response identifies this upload even if another admin uploads concurrently.
            picked.append(.recording(uploadedID))
            await loadLibrary()
        } catch is CancellationError {
            return
        } catch {
            self.error = actionErrorMessage(error)
        }
    }

    private func delete(_ recording: GroupRecording) async {
        guard !working && !uploading else { return }
        working = true
        error = nil
        defer { working = false }
        do {
            try await service.deleteRecording(recording.id, in: groupID)
            picked.removeAll { $0 == .recording(recording.id) }
            library?.recordings.removeAll { $0.id == recording.id }
            await loadLibrary()
        } catch is CancellationError {
            return
        } catch {
            self.error = actionErrorMessage(error)
        }
    }

    private func actionErrorMessage(_ failure: Error) -> String {
        if let groupError = failure as? MemberGroupError, case .requestFailed = groupError {
            return String(localized: "The action could not be completed. Check your connection and try again.")
        }
        if failure is MemberGroupError { return failure.localizedDescription }
        return String(localized: "The action could not be completed. Check your connection and try again.")
    }

}

// MARK: - Schedule a meeting

@MainActor
struct GroupMeetingScheduler: View {
    let groupID: String
    let service: MemberGroupService

    @Environment(\.dismiss) private var dismiss
    @State private var requestID = UUID()
    @State private var title = ""
    @State private var startsAt = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var duration = 60
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Form {
            Group {
                Section {
                    TextField("Title", text: $title)
                    DatePicker("Starts", selection: $startsAt, in: Date()..., displayedComponents: .date)
                    DatePicker("Time", selection: $startsAt, in: Date()..., displayedComponents: .hourAndMinute)
                    Stepper(value: $duration, in: 15...240, step: 15) {
                        Text("\(duration) minutes")
                    }
                } footer: {
                    Text("Members see the time in their own time zone, are told when it is scheduled, and can join from ten minutes before.").foregroundStyle(DIColor.textMuted)
                }
                if let error {
                    Section { Text(verbatim: error).foregroundStyle(DIColor.danger) }
                }
                Section {
                    Button { Task { await save() } } label: {
                        HStack(spacing: DISpacing.sm) {
                            if working { ProgressView().tint(DIColor.onPrimary) }
                            Text("Schedule the meeting")
                        }
                    }
                    .buttonStyle(DIPrimaryButtonStyle())
                    .disabled(working || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .disabled(working)
            .listRowBackground(DIColor.surface)
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .toggleStyle(SwitchToggleStyle(tint: DIColor.primary))
        .navigationTitle("Schedule a meeting")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(working)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { if !working { dismiss() } }.buttonStyle(DIToolbarButtonStyle()).disabled(working)
            }
        }
    }

    private func save() async {
        guard !working, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        working = true
        error = nil
        defer { working = false }
        do {
            try await service.scheduleMeeting(in: groupID, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                              startsAt: startsAt, durationMinutes: duration, requestID: requestID)
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Zikr time

@MainActor
struct GroupZikrEditor: View {
    let groupID: String
    let service: MemberGroupService
    /// A Halqah with video clips: the time may play a pasted YouTube link,
    /// from a start time to an end time.
    var videoClips = false

    /// A new zikr time; or, in a Halqah with video clips, an existing one
    /// filled in and saved under its own id, so the admin changes what it
    /// plays in one step (owner 2026-11-19).
    init(groupID: String, service: MemberGroupService, videoClips: Bool = false, editing existing: ZikrSession? = nil) {
        self.groupID = groupID
        self.service = service
        self.videoClips = videoClips
        guard let existing else { return }
        let draft = ZikrTimeDraft(existing, videoClips: videoClips)
        _title = State(initialValue: draft.title)
        switch draft.anchor {
        case .afterIsha?: _timing = State(initialValue: .afterIsha)
        case .beforeFajr?, .tahajjud?: _timing = State(initialValue: .beforeFajr)
        case nil: _timing = State(initialValue: .clock)
        }
        _time = State(initialValue: draft.time)
        _weekdays = State(initialValue: draft.weekdays)
        _duration = State(initialValue: draft.durationMinutes)
        _autoplay = State(initialValue: draft.autoplay)
        _videoLink = State(initialValue: draft.videoLink)
        _clipStart = State(initialValue: draft.clipStart)
        _clipEnd = State(initialValue: draft.clipEnd)
        _sessionID = State(initialValue: existing.id)
    }

    private enum Timing: String, CaseIterable, Identifiable {
        case clock = "At a time"
        case afterIsha = "After Isha at Dar-ul-Irfan"
        case beforeFajr = "Before Fajr at Dar-ul-Irfan"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var title = String(localized: "Halqah Zikr")
    @State private var timing: Timing = .clock
    @State private var time = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var weekdays: Set<Int> = Set(1...7)
    @State private var duration = 30
    /// A recording or past zikr this time plays by itself.
    @State private var autoplay: GroupQueueEntry?
    /// A pasted YouTube link it plays instead, with its Start at and End at
    /// (video clips only). A link wins over a choice from the library.
    @State private var videoLink = ""
    @State private var clipStart = ""
    @State private var clipEnd = ""
    @State private var library: GroupRecordingLibrary?
    @State private var libraryFailed = false
    @State private var loadingLibrary = false
    @State private var sessionID = "zikr-\(UUID().uuidString.prefix(8).lowercased())"
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Form {
            Group {
                Section {
                    TextField("Title", text: $title)
                    Picker("When", selection: $timing) {
                        ForEach(Timing.allCases) { timing in Text(LocalizedStringKey(timing.rawValue)).tag(timing) }
                    }
                    if timing == .clock {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    }
                    Stepper(value: $duration, in: 10...120, step: 5) {
                        Text("\(duration) minutes")
                    }
                } footer: {
                    Text(timing == .clock
                         ? "The time is in your own time zone; members see it in theirs."
                         : "Follows the prayer time at Dar-ul-Irfan each day.")
                        .foregroundStyle(DIColor.textMuted)
                }
                if timing == .clock && (loadingLibrary || libraryFailed) {
                    Section {
                        if loadingLibrary { ProgressView("Loading the library…") }
                        if libraryFailed {
                            Text("Could not load playback choices.").foregroundStyle(DIColor.danger)
                            Button("Try again") { Task { await loadLibrary() } }
                                .buttonStyle(DICompactButtonStyle())
                        }
                    }
                }
                if timing == .clock, let library, !(library.recordings.isEmpty && library.pastVideos.isEmpty) {
                    Section {
                        NavigationLink {
                            GroupAutoplayChoices(library: library, selection: $autoplay)
                        } label: {
                            VStack(alignment: .leading, spacing: DISpacing.xs) {
                                Text("Plays by itself").foregroundStyle(DIColor.textPrimary)
                                Text(verbatim: autoplayTitle).diInterfaceFont(.subheadline)
                                    .foregroundStyle(DIColor.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityIdentifier("autoplay-choices")
                    } footer: {
                        Text("At this time, if no admin has started a session, it starts by itself, plays this to the group and notifies everyone. An admin ends it.").foregroundStyle(DIColor.textMuted)
                    }
                }
                if timing == .clock && videoClips {
                    Section {
                        TextField("YouTube link", text: $videoLink)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .accessibilityIdentifier("autoplay-video-link")
                    } footer: {
                        if !videoLink.isEmpty && VideoLink.id(from: videoLink) == nil {
                            Text("That video link was not recognised.").foregroundStyle(DIColor.danger)
                        } else {
                            Text("A link pasted here plays instead of a choice from the library.").foregroundStyle(DIColor.textMuted)
                        }
                    }
                    VideoClipSection(start: $clipStart, end: $clipEnd)
                        .onChange(of: videoLink) { _, link in
                            // A link shared from a moment in the video starts there.
                            if let seconds = VideoLink.startSeconds(from: link) { clipStart = ClipTime.text(seconds) }
                        }
                }
                Section("Days") {
                    let symbols = weekdayNames
                    ForEach(1...7, id: \.self) { day in
                        Toggle(isOn: Binding(
                            get: { weekdays.contains(day) },
                            set: { on in if on { weekdays.insert(day) } else if weekdays.count > 1 { weekdays.remove(day) } }
                        )) {
                            Text(verbatim: symbols[day - 1])
                        }
                    }
                }
                if let error {
                    Section { Text(verbatim: error).foregroundStyle(DIColor.danger) }
                }
                Section {
                    Button { Task { await save() } } label: {
                        HStack(spacing: DISpacing.sm) {
                            if working { ProgressView().tint(DIColor.onPrimary) }
                            Text("Save zikr time")
                        }
                    }
                        .buttonStyle(DIPrimaryButtonStyle())
                        .disabled(working || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !videoReady)
                }
            }
            .disabled(working)
            .listRowBackground(DIColor.surface)
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .toggleStyle(SwitchToggleStyle(tint: DIColor.primary))
        .navigationTitle("Zikr time")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(working)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if !working { dismiss() } }.buttonStyle(DIToolbarButtonStyle()).disabled(working) } }
        .task { await loadLibrary() }
    }

    private func loadLibrary() async {
        guard !loadingLibrary else { return }
        loadingLibrary = true
        libraryFailed = false
        defer { loadingLibrary = false }
        do {
            library = try await service.recordings(in: groupID)
        } catch is CancellationError {
            return
        } catch {
            libraryFailed = true
        }
    }

    private var autoplayTitle: String {
        switch autoplay {
        case .recording(let id): return library?.recordings.first { $0.id == id }?.title ?? id
        case .video(let id): return library?.pastVideos.first { $0.videoID == id }.map {
            "\($0.title) · \(GroupInvitationDate.text($0.publishedAt, locale: locale))"
        } ?? id
        case .clip(let id, let start, let end): return GroupQueueEntry.clipTitle(id, start: start, end: end)
        case nil: return String(localized: "Nothing: an admin starts it")
        }
    }

    /// A pasted link (video clips only) is a video the server can find, and
    /// its End at is after its Start at; with no link there is nothing to check.
    private var videoReady: Bool {
        guard videoClips, timing == .clock else { return true }
        let link = videoLink.trimmingCharacters(in: .whitespacesAndNewlines)
        if !link.isEmpty && VideoLink.id(from: link) == nil { return false }
        return VideoClipTimes.problem(start: clipStart, end: clipEnd) == nil
    }

    /// What the time plays by itself: a pasted link, from its Start at to its
    /// End at, before a choice from the library.
    private var autoplayEntries: [GroupQueueEntry] {
        guard timing == .clock else { return [] }
        if videoClips, let video = VideoLink.id(from: videoLink),
           case .success(let times) = VideoClipTimes.read(start: clipStart, end: clipEnd) {
            return [.youTube(video, times: times)]
        }
        return [autoplay].compactMap { $0 }
    }

    private var weekdayNames: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar.weekdaySymbols
    }

    private func save() async {
        guard !working, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, videoReady else { return }
        working = true
        error = nil
        defer { working = false }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let session = ZikrSession(
            id: sessionID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            weekdays: weekdays.sorted(),
            startHour: timing == .clock ? (parts.hour ?? 20) : (timing == .afterIsha ? 21 : 4),
            startMinute: timing == .clock ? (parts.minute ?? 0) : (timing == .afterIsha ? 15 : 0),
            durationMinutes: duration,
            timeZoneIdentifier: timing == .clock ? TimeZone.current.identifier : "Asia/Karachi",
            joinUrl: nil,
            instructions: nil,
            availabilityNote: nil,
            sourceUrl: nil,
            anchor: timing == .clock ? nil : (timing == .afterIsha ? "afterIsha" : "beforeFajr")
        )
        do {
            try await service.saveZikrSession(session, autoplay: autoplayEntries, in: groupID)
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// What the zikr time editor shows for an existing time: its title, when it
/// is, its days and length, and what it plays by itself - in a Halqah with
/// video clips a YouTube video as its link with its Start at and End at.
struct ZikrTimeDraft {
    var title: String
    /// Nil for a clock time.
    var anchor: ZikrAnchor?
    /// Its start today, in its own time zone; the picker shows it in the phone's.
    var time: Date
    var weekdays: Set<Int>
    var durationMinutes: Int
    var autoplay: GroupQueueEntry?
    var videoLink: String
    var clipStart: String
    var clipEnd: String

    init(_ session: ZikrSession, videoClips: Bool, today: Date = Date()) {
        title = session.title
        anchor = session.zikrAnchor
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: session.timeZoneIdentifier) ?? .current
        time = calendar.date(bySettingHour: min(max(session.startHour, 0), 23), minute: min(max(session.startMinute, 0), 59),
                             second: 0, of: today) ?? today
        let days = Set(session.weekdays.filter { (1...7).contains($0) })
        weekdays = days.isEmpty ? Set(1...7) : days
        // The editor's own range.
        durationMinutes = min(max(session.durationMinutes, 10), 120)
        autoplay = nil
        videoLink = ""
        clipStart = ""
        clipEnd = ""
        guard let item = session.autoplay?.first else { return }
        if item.isVideo {
            if videoClips {
                videoLink = "https://youtu.be/" + item.id
                clipStart = item.startSeconds.map { ClipTime.text($0) } ?? ""
                clipEnd = item.endSeconds.map { ClipTime.text($0) } ?? ""
            } else {
                autoplay = .video(item.id)
            }
        } else if item.kind == "recording" {
            autoplay = .recording(item.id)
        }
    }
}

/// Full titles stay readable at large text sizes while preserving the selected item.
private struct GroupAutoplayChoices: View {
    @Environment(\.locale) private var locale
    let library: GroupRecordingLibrary
    @Binding var selection: GroupQueueEntry?
    @Environment(\.dismiss) private var dismiss
    @State private var showAllPastVideos = false

    var body: some View {
        List {
            Group {
                choice(nil, title: String(localized: "Nothing: an admin starts it"))
                ForEach(library.recordings) { recording in
                    choice(.recording(recording.id), title: recording.title)
                }
                if library.pastVideos.count > 20 {
                    Button { showAllPastVideos.toggle() } label: {
                        if showAllPastVideos { Text("Show less") }
                        else { Text("Show all \(library.pastVideos.count)") }
                    }
                    .buttonStyle(DICompactButtonStyle())
                    .accessibilityIdentifier("autoplay-expand-videos")
                }
                ForEach(library.pastVideos.prefix(showAllPastVideos ? library.pastVideos.count : 20)) { video in
                    choice(.video(video.videoID), title: "\(video.title) · \(GroupInvitationDate.text(video.publishedAt, locale: locale))")
                }
            }
            .listRowBackground(DIColor.surface)
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Plays by itself")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if case .video(let id) = selection,
               let index = library.pastVideos.firstIndex(where: { $0.videoID == id }), index >= 20 {
                showAllPastVideos = true
            }
        }
    }

    private func choice(_ entry: GroupQueueEntry?, title: String) -> some View {
        Button {
            selection = entry
            dismiss()
        } label: {
            HStack {
                Text(verbatim: title).foregroundStyle(DIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DISpacing.sm)
                if entry == selection {
                    Image(systemName: "checkmark").foregroundStyle(DIColor.actionForeground)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DIPressableStyle())
        .accessibilityAddTraits(entry == selection ? .isSelected : [])
        .accessibilityIdentifier("autoplay-choice-" + (entry?.itemID ?? "none"))
    }
}
