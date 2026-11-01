import SwiftUI

/// Private notes, newest first. A note written from the Quran reader keeps
/// the ayah it was written about; notes are kept only on this device.
@MainActor
struct NotesView: View {
    @State private var store = MyDayStore.shared
    @State private var saveFailed = false
    @State private var editing: DayNote?
    @State private var isAdding = false
    private static let ayahCounts = Dictionary(SeedBundle.quranSurahs().map { ($0.id, $0.ayahCount) }, uniquingKeysWith: { first, _ in first })

    var body: some View {
        List {
            if store.document.notes.isEmpty {
                Text("No notes yet. Write one here, or from any ayah in the Quran reader.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
                    .listRowBackground(DIColor.surface)
            }
            ForEach(store.document.notes) { note in
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                Button {
                    editing = note
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let reference = note.reference {
                            Label {
                                Text(verbatim: reference.label)
                            } icon: {
                                Image(systemName: reference.kind == .ayah ? "book.closed" : "link")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DIColor.actionForeground)
                        }
                        Text(verbatim: note.text)
                            .font(.body)
                            .foregroundStyle(DIColor.textPrimary)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                        Text(note.updatedAt, format: .dateTime.day().month().year())
                            .font(.caption2)
                            .foregroundStyle(DIColor.textMuted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                }
                .buttonStyle(.plain)
                if let source = note.reference?.quranReference(ayahCounts: Self.ayahCounts) {
                    Button {
                        DeepLinkRouter.shared.open(.quranAyah(surah: source.surah, ayah: source.firstAyah))
                    } label: {
                        Label("Open in the Quran", systemImage: "book.closed")
                    }
                    .buttonStyle(DICompactButtonStyle(minimumHeight: 48))
                    .accessibilityIdentifier("note-quran-source")
                }
                }
                .listRowBackground(DIColor.surface)
                .swipeActions {
                    Button(role: .destructive) {
                        saveFailed = !store.delete(noteID: note.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .myDayReadState(store)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .alert("Could not save. Please try again.", isPresented: $saveFailed) {
            Button("OK", role: .cancel) { }
        }
        .tint(DIColor.actionForeground)
        .navigationTitle("Private notes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(DIColor.actionForeground)
                }
                .accessibilityLabel("New note")
            }
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack { NoteEditorView(note: nil, reference: nil) }
        }
        .sheet(item: $editing) { note in
            NavigationStack { NoteEditorView(note: note, reference: note.reference) }
        }
        .onAppear { store.loadIfNeeded() }
    }
}

/// Writes or edits one note. Opened with a reference from the reader, it
/// starts out tied to that ayah.
@MainActor
struct NoteEditorView: View {
    let note: DayNote?
    let reference: NoteReference?

    @Environment(\.dismiss) private var dismiss
    @State private var newNoteID = UUID()
    @State private var text: String
    @State private var store = MyDayStore.shared
    @State private var saveFailed = false

    init(note: DayNote?, reference: NoteReference?) {
        self.note = note
        self.reference = reference
        _text = State(initialValue: note?.text ?? "")
    }

    var body: some View {
        Form {
            if let reference {
                Section {
                    Label {
                        Text(verbatim: reference.label)
                    } icon: {
                        Image(systemName: "book.closed")
                    }
                    .foregroundStyle(DIColor.actionForeground)
                }
            }
            Section {
                TextField("Write your note", text: $text, axis: .vertical)
                    .lineLimit(6...20)
            } footer: {
                Text("Only you can see this note. It stays on this phone.")
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .alert("Could not save. Please try again.", isPresented: $saveFailed) {
            Button("OK", role: .cancel) { }
        }
        .tint(DIColor.actionForeground)
        .navigationTitle(note == nil ? "New note" : "Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.loadIfNeeded()
                    var saved = note ?? DayNote(id: newNoteID, text: "", reference: reference)
                    saved.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    saved.reference = reference
                    if store.upsert(saved) { dismiss() } else { saveFailed = true }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct MyDayReadStateModifier: ViewModifier {
    let store: MyDayStore
    func body(content: Content) -> some View {
        VStack(spacing: DISpacing.sm) {
            if !store.canRead || store.recoveredFile {
                DICard {
                    VStack(spacing: DISpacing.sm) {
                        Text(store.recoveredFile ?
                             "An unreadable personal-data file was kept safely aside. New records can be saved on this phone." :
                             store.loadFailed ? "Your personal records could not be read. Please try again." : "Loading...")
                            .font(.subheadline)
                            .foregroundStyle(DIColor.textMuted)
                        if store.loadFailed {
                            Button("Retry") { store.loadIfNeeded() }
                                .buttonStyle(DISecondaryButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, DISpacing.md)
            }
            if store.canRead { content } else { Spacer() }
        }
    }
}

extension View {
    func myDayReadState(_ store: MyDayStore) -> some View {
        modifier(MyDayReadStateModifier(store: store))
    }
}
