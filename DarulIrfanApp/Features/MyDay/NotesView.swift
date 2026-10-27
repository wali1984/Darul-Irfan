import SwiftUI

/// Private notes, newest first. A note written from the Quran reader keeps
/// the ayah it was written about; notes are kept only on this device.
@MainActor
struct NotesView: View {
    @State private var store = MyDayStore.shared
    @State private var editing: DayNote?
    @State private var isAdding = false

    var body: some View {
        List {
            if store.document.notes.isEmpty {
                Text("No notes yet. Write one here, or from any ayah in the Quran reader.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
                    .listRowBackground(DIColor.surface)
            }
            ForEach(store.document.notes) { note in
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
                            .foregroundStyle(DIColor.primary)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .listRowBackground(DIColor.surface)
                .swipeActions {
                    Button(role: .destructive) {
                        store.delete(noteID: note.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Private notes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "square.and.pencil")
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
    @State private var text: String
    @State private var store = MyDayStore.shared

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
                    .foregroundStyle(DIColor.primary)
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
        .navigationTitle(note == nil ? "New note" : "Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.loadIfNeeded()
                    var saved = note ?? DayNote(text: "", reference: reference)
                    saved.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    saved.reference = reference
                    store.upsert(saved)
                    dismiss()
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
