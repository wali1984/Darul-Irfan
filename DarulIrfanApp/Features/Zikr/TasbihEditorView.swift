import SwiftUI

/// Create/edit sheet for a tasbih counter: title plus an optional per-session
/// target. Counts and lifetime totals are preserved when editing.
struct TasbihEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var targetText: String

    private let original: TasbihCounter?
    private let onSave: (TasbihCounter) -> Void

    init(counter: TasbihCounter?, onSave: @escaping (TasbihCounter) -> Void) {
        self.original = counter
        self.onSave = onSave
        _title = State(initialValue: counter?.title ?? "")
        _targetText = State(initialValue: counter?.target.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                } header: {
                    Text("Name")
                } footer: {
                    Text("For example: SubhanAllah, Alhamdulillah, Allahu Akbar, or Durood Sharif.")
                }
                Section {
                    TextField("Target (optional)", text: $targetText)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Target")
                } footer: {
                    Text("A per-session goal such as 100. Leave empty for open-ended counting.")
                }
            }
            .navigationTitle(original == nil ? "New Counter" : "Edit Counter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let name = trimmedTitle
        guard !name.isEmpty else { return }

        let parsedTarget = Int(targetText.trimmingCharacters(in: .whitespaces))
        let target: Int?
        if let parsedTarget, parsedTarget > 0 {
            target = parsedTarget
        } else {
            target = nil
        }

        var counter = original ?? TasbihCounter(
            id: UUID(),
            title: name,
            target: nil,
            count: 0,
            lifetimeCount: 0,
            updatedAt: Date()
        )
        counter.title = name
        counter.target = target
        counter.updatedAt = Date()
        onSave(counter)
        dismiss()
    }
}
