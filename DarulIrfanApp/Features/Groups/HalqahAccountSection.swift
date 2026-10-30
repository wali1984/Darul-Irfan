import SwiftUI

/// The account at the end of the Halqah tab, moved from the end of the
/// groups list: the member's name, signing out, and deleting the account.
/// Shown while signed in.
@MainActor
struct HalqahAccountSection: View {
    @Bindable var model: GroupsModel
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            HalqahSectionLabel(titleKey: "Account")
            HalqahGlassList {
                if model.phase == .ready {
                    NavigationLink {
                        HalqahNameEditor(model: model)
                    } label: {
                        HalqahListRowLabel(
                            titleKey: "Your name",
                            systemImage: "person.fill",
                            value: model.displayName.map { Text(verbatim: $0) }
                        )
                    }
                    .buttonStyle(.plain)
                    HalqahRowDivider()
                }
                Button {
                    Task { await model.signOut() }
                } label: {
                    HalqahListRowLabel(
                        titleKey: "Sign out",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        mirrorsSymbol: true,
                        showsChevron: false
                    )
                }
                .buttonStyle(.plain)
                HalqahRowDivider()
                // Apple requires an account made in the app to be deletable
                // inside it, and a member should not have to hunt for it.
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    if model.isDeleting {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 52)
                    } else {
                        HalqahListRowLabel(
                            titleKey: "Delete my account",
                            systemImage: "trash",
                            tint: .danger,
                            showsChevron: false
                        )
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.isDeleting)
            }
            Text("Deleting removes your sign-in and your place in every group. Nothing the silsila published is affected.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DISpacing.xs)
        }
        .confirmationDialog("Delete your account?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await model.deleteAccount() } }
            Button("Keep my account", role: .cancel) {}
        } message: {
            Text("Your sign-in and your group memberships are removed. An administrator would have to add you again.")
        }
    }
}

/// The member's name, as their Halqah's admins and the meeting room show it.
@MainActor
struct HalqahNameEditor: View {
    @Bindable var model: GroupsModel
    @State private var draft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) {
                    TextField("Your name", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.name)
                        .submitLabel(.done)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .buttonStyle(.bordered)
                        .tint(DIColor.primary)
                        .disabled(model.isSavingName || trimmedDraft.isEmpty || trimmedDraft == (model.displayName ?? ""))
                }
                Text("Your name is shown to your Halqah's admins and in the meeting room.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let nameError = model.nameError {
                    Text(verbatim: nameError)
                        .font(.footnote)
                        .foregroundStyle(DIColor.danger)
                }
            }
            .padding(DISpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .diGlassPanel(cornerRadius: 24)
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .navigationTitle("Your name")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if draft.isEmpty { draft = model.displayName ?? "" } }
        .onChange(of: model.displayName) { _, name in draft = name ?? "" }
    }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        let name = trimmedDraft
        guard !name.isEmpty, name != model.displayName else { return }
        Task { await model.rename(name) }
    }
}
