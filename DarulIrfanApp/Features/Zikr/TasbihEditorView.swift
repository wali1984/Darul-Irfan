import SwiftUI

/// Create/edit sheet for a tasbih counter: title plus an optional per-session
/// target. Counts and lifetime totals are preserved when editing.
struct TasbihEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var targetText: String
    @State private var isSaving = false
    @State private var saveFailed = false
    @State private var draftID = UUID()

    private let original: TasbihCounter?
    private let onSave: (TasbihCounter) async throws -> Void

    init(counter: TasbihCounter?, onSave: @escaping (TasbihCounter) async throws -> Void) {
        self.original = counter
        self.onSave = onSave
        _title = State(initialValue: counter?.title ?? "")
        _targetText = State(initialValue: counter?.target.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, prompt: Text("Title").foregroundColor(DIColor.textMuted))
                        .listRowBackground(DIColor.surface)
                } header: {
                    Text("Name")
                } footer: {
                    Text("For example: SubhanAllah, Alhamdulillah, Allahu Akbar, or Durood Sharif.")
                }
                Section {
                    TextField("Target (optional)", text: $targetText, prompt: Text("Target (optional)").foregroundColor(DIColor.textMuted))
                        .keyboardType(.numberPad)
                        .listRowBackground(DIColor.surface)
                } header: {
                    Text("Target")
                } footer: {
                    Text("A per-session goal such as 100. Leave empty for open-ended counting.")
                }
            }
            .disabled(isSaving)
            .scrollContentBackground(.hidden)
            .diScreenBackground()
            .navigationTitle(original == nil ? "New Counter" : "Edit Counter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("tasbih-editor-cancel")
                    .buttonStyle(DICompactButtonStyle())
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        save()
                    }
                    .buttonStyle(DICompactButtonStyle())
                    .disabled(trimmedTitle.isEmpty || isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .alert("Unable to save counter", isPresented: $saveFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your changes are still here. Please try saving again.")
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let name = trimmedTitle
        guard !name.isEmpty, !isSaving else { return }

        let target = TasbihCounter.parseTarget(targetText)

        var counter = original ?? TasbihCounter(
            id: draftID,
            title: name,
            target: nil,
            count: 0,
            lifetimeCount: 0,
            updatedAt: Date()
        )
        counter.title = name
        counter.target = target
        counter.updatedAt = Date()
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await onSave(counter)
                dismiss()
            } catch {
                saveFailed = true
            }
        }
    }
}
