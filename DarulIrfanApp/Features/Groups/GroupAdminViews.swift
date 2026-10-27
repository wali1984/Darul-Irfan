import SwiftUI
import UIKit

// What a group admin does from the phone: post, start a community zikr or a
// meeting, schedule a meeting, and keep the group's zikr times.

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

    private enum Kind: String, CaseIterable, Identifiable {
        case zikr = "Community Zikr"
        case meeting = "Meeting"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .zikr
    @State private var title = String(localized: "Community Zikr")
    @State private var videoLink = ""
    @State private var joinTogether = true
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Picker("What is starting", selection: $kind) {
                    ForEach(Kind.allCases) { kind in Text(LocalizedStringKey(kind.rawValue)).tag(kind) }
                }
                .pickerStyle(.segmented)
                .onChange(of: kind) { _, value in
                    title = value == .zikr ? String(localized: "Community Zikr") : String(localized: "Group meeting")
                }
                TextField("Title", text: $title)
            }
            if kind == .zikr {
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
                        Text("Joining together: integration in progress. Share a live video link meanwhile.")
                    }
                }
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
                    Label("Start now and notify the group", systemImage: "dot.radiowaves.left.and.right")
                }
                .disabled(working || !canStart)
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Go live")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }

    private var canStart: Bool {
        if kind == .meeting { return meetingsReady }
        let video = VideoLink.id(from: videoLink)
        let room = joinTogether && meetingsReady
        return (room || video != nil) && (videoLink.isEmpty || video != nil)
    }

    private func start() async {
        working = true
        defer { working = false }
        do {
            try await service.startLive(
                in: groupID,
                kind: kind == .zikr ? "zikr" : "meeting",
                title: title.trimmingCharacters(in: .whitespaces),
                videoID: kind == .zikr ? VideoLink.id(from: videoLink) : nil,
                room: kind == .meeting || (joinTogether && meetingsReady)
            )
            dismiss()
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
    @State private var title = String(localized: "Community Zikr")
    @State private var timing: Timing = .clock
    @State private var time = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var weekdays: Set<Int> = Set(1...7)
    @State private var duration = 30
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
            try await service.saveZikrSession(session, in: groupID)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
