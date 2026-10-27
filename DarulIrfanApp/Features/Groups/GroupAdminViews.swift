import AVFoundation
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
        let parts = url.pathComponents.filter { $0 != "/" }
        var candidate: String?
        if host.hasSuffix("youtu.be") {
            candidate = parts.first
        } else if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value {
            candidate = v
        } else if let index = parts.firstIndex(where: { ["live", "shorts", "embed"].contains($0) }), index + 1 < parts.count {
            candidate = parts[index + 1]
        }
        guard let candidate, candidate.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else { return nil }
        return candidate
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
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                // The quickest route from a WhatsApp group: copy the message
                // there, then paste it here.
                Button {
                    paste()
                } label: {
                    Label("Paste a copied message", systemImage: "doc.on.clipboard")
                }
            } footer: {
                Text("Copy a message in WhatsApp or anywhere else, then paste it here. The first line becomes the title.")
            }
            Section {
                TextField("Title", text: $title, axis: .vertical)
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
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("New post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }

    private var canSave: Bool {
        !working && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (videoLink.isEmpty || VideoLink.id(from: videoLink) != nil)
    }

    private func paste() {
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
        working = true
        defer { working = false }
        do {
            try await service.createPost(
                in: groupID,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: message.trimmingCharacters(in: .whitespacesAndNewlines),
                videoID: VideoLink.id(from: videoLink),
                publish: publish
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Live now

@MainActor
struct GroupLiveStarter: View {
    let groupID: String
    let service: MemberGroupService
    /// False while video meetings await their integration: no room can open.
    var meetingsReady = true
    /// Adds recordings and past zikr to the session already live.
    var addingToSession = false

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
    @State private var joinTogether = true
    @State private var library: GroupRecordingLibrary?
    @State private var libraryFailed = false
    /// What plays, in order: recordings and past zikr, picked from either list.
    @State private var picked: [GroupQueueEntry] = []
    @State private var choosingFile = false
    @State private var uploading = false
    @State private var working = false
    @State private var error: String?

    private var sources: [Source] { addingToSession ? [.youtube, .recording] : Source.allCases }

    var body: some View {
        Form {
            if !addingToSession {
                Section {
                    Picker("What is starting", selection: $kind) {
                        ForEach(Kind.allCases) { kind in Text(LocalizedStringKey(kind.rawValue)).tag(kind) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _, value in
                        title = value == .zikr ? String(localized: "Halqah Zikr") : String(localized: "Group meeting")
                    }
                    TextField("Title", text: $title)
                }
            }
            if kind == .zikr || addingToSession {
                Section {
                    Picker("How the group joins", selection: $source) {
                        ForEach(sources) { source in Text(LocalizedStringKey(source.rawValue)).tag(source) }
                    }
                    .pickerStyle(.segmented)
                }
                switch source {
                case .room: roomSection
                case .youtube: youtubeSections
                case .recording: recordingSections
                }
                if !picked.isEmpty && source != .room { orderSection }
            } else {
                Section {
                    if meetingsReady {
                        Text("Members join with audio and video from the group page.")
                            .foregroundStyle(DIColor.textMuted)
                    } else {
                        Text("Video meetings: integration in progress. They open here once it is complete.")
                            .foregroundStyle(DIColor.textMuted)
                    }
                }
            }
            if let error {
                Section { Text(verbatim: error).foregroundStyle(DIColor.danger) }
            }
            Section {
                Button {
                    Task { await start() }
                } label: {
                    if addingToSession {
                        Label("Add to the session", systemImage: "text.badge.plus")
                    } else {
                        Label("Start now and notify the group", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
                .disabled(working || uploading || !canStart)
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle(addingToSession ? "Add to the session" : "Go live")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.audio, .movie]) { result in
            if case .success(let file) = result { Task { await upload(file) } }
        }
        .task {
            // Until the room service is connected, start where a zikr can play.
            if addingToSession || !meetingsReady { source = .youtube }
            await loadLibrary()
        }
    }

    // MARK: Sources

    private var roomSection: some View {
        Section {
            Toggle("Members join the zikr together", isOn: $joinTogether)
                .disabled(!meetingsReady)
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
        Section {
            if let videos = library?.pastVideos {
                if videos.isEmpty {
                    Text("No past zikr videos yet.").foregroundStyle(DIColor.textMuted)
                }
                ForEach(videos.prefix(40)) { video in
                    choiceRow(
                        entry: .video(video.videoID),
                        title: video.title,
                        detail: [video.publishedAt.formatted(date: .abbreviated, time: .omitted), length(video.durationSeconds)]
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
                    choiceRow(
                        entry: .recording(recording.id),
                        title: recording.title,
                        detail: [length(recording.durationSeconds), ByteCountFormatter.string(fromByteCount: Int64(recording.byteSize), countStyle: .file)]
                    )
                    .swipeActions {
                        Button("Delete", role: .destructive) { Task { await delete(recording) } }
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
            .disabled(uploading || library == nil)
        } header: {
            Text("The group's recordings")
        } footer: {
            Text("MP3, M4A, AAC, WAV, MP4 or MOV, up to 95 MB. Members listen together, from one place you control. The session stays open until you end it.")
        }
    }

    private var orderSection: some View {
        Section("Plays in this order") {
            ForEach(Array(picked.enumerated()), id: \.element) { index, entry in
                HStack {
                    Text(verbatim: "\(index + 1). \(titleOf(entry))").lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        picked.removeAll { $0 == entry }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(DIColor.danger)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove"))
                }
            }
            .onMove { from, to in picked.move(fromOffsets: from, toOffset: to) }
        }
    }

    @ViewBuilder
    private var libraryStatus: some View {
        if libraryFailed {
            Button("Try again") { Task { await loadLibrary() } }
        } else {
            ProgressView()
        }
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
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                Spacer(minLength: 0)
                if let position {
                    Text(verbatim: "\(position + 1)")
                        .font(.caption.weight(.bold))
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
        case .video(let id): library?.pastVideos.first { $0.videoID == id }?.title ?? id
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

    private var canStart: Bool {
        let video = VideoLink.id(from: videoLink)
        if !videoLink.isEmpty && video == nil && source != .recording { return false }
        if addingToSession { return !picked.isEmpty || (source == .youtube && video != nil) }
        if kind == .meeting { return meetingsReady }
        switch source {
        case .room:
            return (joinTogether && meetingsReady) || video != nil
        case .youtube, .recording:
            return !picked.isEmpty || (source == .youtube && video != nil)
        }
    }

    private func start() async {
        working = true
        defer { working = false }
        let title = title.trimmingCharacters(in: .whitespaces)
        let video = VideoLink.id(from: videoLink)
        do {
            if addingToSession {
                // A pasted link here is a past video; a live one is refused.
                var entries = picked
                if source == .youtube, let video { entries.insert(.video(video), at: 0) }
                try await service.addToSession(entries, in: groupID)
            } else if kind == .meeting {
                try await service.startLive(in: groupID, kind: "meeting", title: title, videoID: nil, room: true)
            } else if source == .room {
                try await service.startLive(in: groupID, kind: "zikr", title: title, videoID: video, room: joinTogether && meetingsReady)
            } else {
                // The server asks YouTube whether a pasted link is live or past:
                // live is watched live, past joins the queue at the front.
                try await service.startLive(in: groupID, kind: "zikr", title: title,
                                            videoID: source == .youtube ? video : nil, room: false, queue: picked)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Recordings

    private func loadLibrary() async {
        libraryFailed = false
        do {
            library = try await service.recordings(in: groupID)
        } catch {
            libraryFailed = true
        }
    }

    private func upload(_ file: URL) async {
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
            try await service.uploadRecording(
                from: file, contentType: contentType, title: name,
                durationSeconds: duration.flatMap { $0.isFinite && $0 > 0 ? Int($0.rounded()) : nil }, in: groupID
            )
            let before = Set(library?.recordings.map(\.id) ?? [])
            await loadLibrary()
            // What was just uploaded joins the order.
            if let added = library?.recordings.first(where: { !before.contains($0.id) }) {
                picked.append(.recording(added.id))
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ recording: GroupRecording) async {
        do {
            try await service.deleteRecording(recording.id, in: groupID)
            picked.removeAll { $0 == .recording(recording.id) }
            await loadLibrary()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Schedule a meeting

@MainActor
struct GroupMeetingScheduler: View {
    let groupID: String
    let service: MemberGroupService

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var startsAt = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var duration = 60
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                DatePicker("Starts", selection: $startsAt, in: Date()...)
                Stepper(value: $duration, in: 15...240, step: 15) {
                    Text("\(duration) minutes")
                }
            } footer: {
                Text("Members see the time in their own time zone, are told when it is scheduled, and can join from ten minutes before.")
            }
            if let error {
                Section { Text(verbatim: error).foregroundStyle(DIColor.danger) }
            }
            Section {
                Button("Schedule the meeting") { Task { await save() } }
                    .disabled(working || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Schedule a meeting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }

    private func save() async {
        working = true
        defer { working = false }
        do {
            try await service.scheduleMeeting(in: groupID, title: title.trimmingCharacters(in: .whitespaces),
                                              startsAt: startsAt, durationMinutes: duration)
            dismiss()
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

    private enum Timing: String, CaseIterable, Identifiable {
        case clock = "At a time"
        case afterIsha = "After Isha at Dar-ul-Irfan"
        case beforeFajr = "Before Fajr at Dar-ul-Irfan"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var title = String(localized: "Halqah Zikr")
    @State private var timing: Timing = .clock
    @State private var time = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var weekdays: Set<Int> = Set(1...7)
    @State private var duration = 30
    /// A recording or past zikr this time plays by itself.
    @State private var autoplay: GroupQueueEntry?
    @State private var library: GroupRecordingLibrary?
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Form {
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
            }
            if timing == .clock, let library, !(library.recordings.isEmpty && library.pastVideos.isEmpty) {
                Section {
                    Picker("Plays by itself", selection: $autoplay) {
                        Text("Nothing: an admin starts it").tag(GroupQueueEntry?.none)
                        ForEach(library.recordings) { recording in
                            Text(verbatim: recording.title).tag(GroupQueueEntry?.some(.recording(recording.id)))
                        }
                        ForEach(library.pastVideos.prefix(20)) { video in
                            Text(verbatim: "\(video.title) · \(video.publishedAt.formatted(date: .abbreviated, time: .omitted))")
                                .tag(GroupQueueEntry?.some(.video(video.videoID)))
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text("At this time, if no admin has started a session, it starts by itself, plays this to the group and notifies everyone. An admin ends it.")
                }
            }
            Section("Days") {
                let symbols = Calendar.current.weekdaySymbols
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
                Button("Save zikr time") { Task { await save() } }
                    .disabled(working || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Zikr time")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .task { library = try? await service.recordings(in: groupID) }
    }

    private func save() async {
        working = true
        defer { working = false }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let session = ZikrSession(
            id: "zikr-\(UUID().uuidString.prefix(8).lowercased())",
            title: title.trimmingCharacters(in: .whitespaces),
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
            try await service.saveZikrSession(session, autoplay: timing == .clock ? [autoplay].compactMap { $0 } : [], in: groupID)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
