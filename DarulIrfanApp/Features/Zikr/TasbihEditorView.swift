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
                        .diInterfaceFont(.body)
                        .listRowBackground(DIColor.surface)
                } header: {
                    Text("Name")
                        .diInterfaceFont(.footnote)
                } footer: {
                    Text("For example: SubhanAllah, Alhamdulillah, Allahu Akbar, or Durood Sharif.")
                        .diInterfaceFont(.footnote)
                }
                Section {
                    TextField("Target (optional)", text: $targetText, prompt: Text("Target (optional)").foregroundColor(DIColor.textMuted))
                        .diInterfaceFont(.body)
                        .keyboardType(.numberPad)
                        .listRowBackground(DIColor.surface)
                } header: {
                    Text("Target")
                        .diInterfaceFont(.footnote)
                } footer: {
                    Text("A per-session goal such as 100. Leave empty for open-ended counting.")
                        .diInterfaceFont(.footnote)
                }
            }
            .disabled(isSaving)
            .scrollContentBackground(.hidden)
            .diScreenBackground()
            .navigationTitle(original == nil ? "New Counter" : "Edit Counter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: DISpacing.sm) {
                    Text(original == nil ? "New Counter" : "Edit Counter")
                        .diInterfaceFont(.headline)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    HStack(alignment: .center, spacing: DISpacing.md) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("tasbih-editor-cancel")
                    .buttonStyle(DISecondaryButtonStyle())
                    .disabled(isSaving)
                    Button(isSaving ? "Saving…" : "Save") {
                        save()
                    }
                    .buttonStyle(DISecondaryButtonStyle())
                    .disabled(trimmedTitle.isEmpty || isSaving)
                    }
                }
                .padding(DISpacing.md)
                .background(DIColor.background)
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
