import PhotosUI
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

// The Super admin's pictures for the Today page: drafts forwarded on WhatsApp
// to approve, pictures added from the phone, and what is published for which
// day. Nothing reaches readers until it is published for a day.

@MainActor
struct DailyMediaManagerView: View {
    let service: MemberGroupService

    @State private var items: [DailyMediaItem]?
    @State private var failed = false
    @State private var editing: DailyMediaItem?
    @State private var adding = false

    var body: some View {
        List {
            Section {
                Button { adding = true } label: { Label("Add a picture", systemImage: "photo.badge.plus") }
            } footer: {
                Text("Or forward a picture to the WhatsApp Business number with #ayah, #hadith, #aqwal, #quote or #announcement at the start of its caption, and a date such as 2026-11-02 if you like. It arrives here as a draft.")
            }
            if failed && items != nil {
                Button("Try again") { Task { await load() } }
            }
            if let items {
                let drafts = items.filter { $0.status == "draft" }
                let rest = items.filter { $0.status != "draft" }
                if !drafts.isEmpty {
                    Section("Waiting for you") { ForEach(drafts) { row($0) } }
                }
                Section("Published and hidden") {
                    if rest.isEmpty { Text("Nothing yet.").foregroundStyle(DIColor.textMuted) }
                    ForEach(rest) { row($0) }
                }
            } else if failed {
                Button("Try again") { Task { await load() } }
            } else {
                ProgressView()
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Today's pictures")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { item in
            NavigationStack { DailyMediaEditor(service: service, item: item) }
        }
        .sheet(isPresented: $adding, onDismiss: { Task { await load() } }) {
            NavigationStack { DailyMediaEditor(service: service, item: nil) }
        }
    }

    private func row(_ item: DailyMediaItem) -> some View {
        Button { editing = item } label: {
            HStack(spacing: DISpacing.sm) {
                AsyncImage(url: item.imageURL) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() } else { DIColor.sandstone }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.slot?.title ?? "Picture").foregroundStyle(DIColor.textPrimary)
                    Text(verbatim: [item.day.map { day in item.endDay.map { "\(day) – \($0)" } ?? day }, item.caption]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(DIColor.textMuted)
                        .lineLimit(2)
                    if item.status == "hidden" {
                        Text("Hidden").font(.caption2.weight(.bold)).foregroundStyle(DIColor.textMuted)
                    } else if item.source == "whatsapp" && item.status == "draft" {
                        Text("From WhatsApp").font(.caption2.weight(.bold)).foregroundStyle(DIColor.primary)
                    }
                }
            }
        }
    }

    private func load() async {
        failed = false
        do { items = try await service.manageDailyMedia() } catch { failed = true }
    }
}

/// Adds a picture, or changes one: where it shows, its day, caption and
/// pop-up, and whether it is published.
@MainActor
struct DailyMediaEditor: View {
    let service: MemberGroupService
    /// nil adds a new picture.
    let item: DailyMediaItem?

    @Environment(\.dismiss) private var dismiss
    @State private var slot: DailyMediaItem.Slot = .quote
    @State private var day = Date()
    @State private var hasEnd = false
    @State private var endDay = Date()
    @State private var caption = ""
    @State private var popup = true
    @State private var pick: PhotosPickerItem?
    @State private var picture: Data?
    @State private var preview: UIImage?
    @State private var working = false
    @State private var loadingPicture = false
    @State private var choosingFile = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                if let preview {
                    Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 260)
                } else if let url = item?.imageURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFit() } else { ProgressView() }
                    }
                    .frame(maxHeight: 260)
                }
                if item == nil {
                    PhotosPicker(selection: $pick, matching: .images, preferredItemEncoding: .compatible) {
                        Label(preview == nil ? "Choose a picture" : "Choose another", systemImage: "photo.on.rectangle")
                    }
                    .disabled(working || loadingPicture)
                    Button { choosingFile = true } label: {
                        Label("Choose from Files", systemImage: "folder")
                    }
                    .disabled(working || loadingPicture)
                }
                if loadingPicture { ProgressView("Loading picture…") }
            }
            Section {
                Picker("Shows on", selection: $slot) {
                    ForEach(DailyMediaItem.Slot.allCases) { slot in Text(slot.title).tag(slot) }
                }
                DatePicker("Day", selection: $day, displayedComponents: .date)
                    .onChange(of: day) { _, value in if endDay < value { endDay = value } }
                if slot == .announcement {
                    Toggle("Runs several days", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Last day", selection: $endDay, in: day..., displayedComponents: .date)
                    }
                }
                if slot != .quote {
                    Toggle("Also open it over the Today page", isOn: $popup)
                }
                TextField("Caption (optional)", text: $caption, axis: .vertical)
                    .lineLimit(1...4)
            } footer: {
                Text(slot == .quote
                     ? "The day's quote opens over the Today page once, the first time it is opened that day."
                     : "On that day it takes its card's place on the Today page, in each reader's own time zone. Without a picture, the card shows the app's own ayah, hadith or saying for the day.")
            }
            if let error {
                Section { Text(verbatim: error).foregroundStyle(DIColor.danger) }
            }
            Section {
                if working { ProgressView() }
                Button(item?.status == "published" ? "Save" : "Publish") { Task { await save(publish: true) } }
                    .disabled(working || loadingPicture || (item == nil && picture == nil))
                if item == nil {
                    Button("Save as a draft") { Task { await save(publish: false) } }
                        .disabled(working || loadingPicture || picture == nil)
                }
                if let item {
                    if item.status == "published" {
                        Button("Hide it") { Task { await setStatus("hidden") } }.disabled(working)
                    }
                    Button("Delete", role: .destructive) { Task { await delete(item) } }.disabled(working)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle(item == nil ? "Add a picture" : "Picture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(working) } }
        .onAppear(perform: fill)
        .task(id: pick) { await read(pick) }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                Task { await readFile(url) }
            } else if case .failure = result {
                error = String(localized: "The picture could not be opened. Download it to your phone and choose it again.")
            }
        }
        .interactiveDismissDisabled(working)
    }

    private static func dayKey(_ date: Date) -> String { DayKey.make(from: date, timeZone: .autoupdatingCurrent) }

    private static func date(_ key: String?) -> Date? {
        guard let key else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    private func fill() {
        guard let item else { return }
        slot = item.slot ?? .quote
        day = Self.date(item.day) ?? Date()
        if let end = Self.date(item.endDay) { hasEnd = true; endDay = end }
        caption = item.caption ?? ""
        popup = item.popup
    }

    /// The chosen picture, made a JPEG no larger than 2048 pixels across.
    private func read(_ chosen: PhotosPickerItem?) async {
        guard let chosen else { return }
        loadingPicture = true
        error = nil
        picture = nil
        preview = nil
        defer { loadingPicture = false; pick = nil }
        do {
            guard let data = try await chosen.loadTransferable(type: Data.self) else {
                error = String(localized: "The picture could not be opened. Download it to your phone and choose it again.")
                return
            }
            try Task.checkCancellation()
            prepare(data)
        } catch is CancellationError {
            return
        } catch {
            self.error = String(localized: "The picture could not be opened. Download it to your phone and choose it again.")
        }
    }

    private func readFile(_ url: URL) async {
        loadingPicture = true
        error = nil
        picture = nil
        preview = nil
        defer { loadingPicture = false }
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                return try Data(contentsOf: url, options: .mappedIfSafe)
            }.value
            prepare(data)
        } catch {
            self.error = String(localized: "The picture could not be opened. Download it to your phone and choose it again.")
        }
    }

    private func prepare(_ data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else {
            error = String(localized: "The picture could not be opened. Download it to your phone and choose it again.")
            return
        }
        let image = UIImage(cgImage: thumbnail)
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            error = String(localized: "The picture could not be opened. Download it to your phone and choose it again.")
            return
        }
        preview = image
        picture = jpeg
    }

    private func save(publish: Bool) async {
        working = true
        error = nil
        defer { working = false }
        let end = slot == .announcement && hasEnd ? Self.dayKey(endDay) : nil
        let showsOver = slot == .quote || popup
        do {
            if let item {
                var fields: [String: Any] = [
                    "slot": slot.rawValue, "day": Self.dayKey(day), "caption": caption, "popup": showsOver,
                    "endDay": end ?? NSNull(),
                ]
                if publish { fields["status"] = "published" }
                try await service.updateDailyMedia(item.id, fields)
            } else if let picture {
                try await service.uploadDailyMedia(
                    picture, contentType: "image/jpeg", slot: slot, day: Self.dayKey(day), endDay: end,
                    caption: caption.trimmingCharacters(in: .whitespacesAndNewlines), popup: showsOver, publish: publish
                )
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func setStatus(_ status: String) async {
        guard let item else { return }
        working = true
        defer { working = false }
        do {
            try await service.updateDailyMedia(item.id, ["status": status])
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ item: DailyMediaItem) async {
        working = true
        defer { working = false }
        do {
            try await service.deleteDailyMedia(item.id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
