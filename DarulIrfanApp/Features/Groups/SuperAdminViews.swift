import SwiftUI

// What only the Super admin does from the phone: make, rename and retire
// Halqahs, and see everyone who has signed in, to place them in any Halqah,
// change their role there, or take them out of it.

/// Makes a Halqah, or renames one and changes its description.
@MainActor
struct HalqahEditor: View {
    let service: MemberGroupService
    /// The Halqah being edited; nil makes a new one.
    var halqah: MemberGroup? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Name, for example New York", text: $name)
                TextField("Description (optional)", text: $description, axis: .vertical)
                    .lineLimit(1...4)
            } footer: {
                Text(halqah == nil
                     ? "A new Halqah starts empty. Add its first Administrator from its Members screen, or from Everyone who has signed in."
                     : "Members see the new name straight away.")
            }
            if let error {
                Section { Text(verbatim: error).foregroundStyle(DIColor.danger) }
            }
            Section {
                Button(halqah == nil ? "Make the Halqah" : "Save") { Task { await save() } }
                    .disabled(working || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .toggleStyle(SwitchToggleStyle(tint: DIColor.primary))
        .navigationTitle(halqah == nil ? "New Halqah" : "Edit Halqah")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear {
            name = halqah?.name ?? ""
            description = halqah?.description ?? ""
        }
    }

    private func save() async {
        working = true
        defer { working = false }
        let name = name.trimmingCharacters(in: .whitespaces)
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let halqah {
                try await service.updateHalqah(halqah.id, name: name, description: description)
            } else {
                try await service.createHalqah(name: name, description: description)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Everyone who has signed in, with their Halqahs.
@MainActor
struct MemberDirectoryView: View {
    let service: MemberGroupService
    let halqahs: [MemberGroup]

    @State private var people: [DirectoryPerson]?
    @State private var failed = false
    @State private var search = ""

    private var shown: [DirectoryPerson] {
        guard let people else { return [] }
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return people }
        return people.filter { person in
            person.displayName.lowercased().contains(query) || (person.email?.lowercased().contains(query) ?? false)
                || person.halqahs.contains { $0.groupName.lowercased().contains(query) }
        }
    }

    var body: some View {
        List {
            if people != nil {
                if shown.isEmpty {
                    Text("No one matches.").foregroundStyle(DIColor.textMuted)
                }
                ForEach(shown) { person in
                    NavigationLink {
                        DirectoryPersonView(person: person, service: service, halqahs: halqahs, onChange: { await load() })
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: DISpacing.xs) {
                                Text(verbatim: person.displayName)
                                if person.isSuperAdmin {
                                    Text("Super admin").font(.caption2.weight(.bold)).foregroundStyle(DIColor.primary)
                                }
                            }
                            Text(verbatim: person.halqahs.isEmpty
                                 ? String(localized: "Not in a Halqah yet")
                                 : person.halqahs.map(\.groupName).joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(DIColor.textMuted)
                        }
                    }
                }
            } else if failed {
                Button("Try again") { Task { await load() } }
            } else {
                ProgressView()
            }
        }
        .searchable(text: $search, prompt: Text("Name, email or Halqah"))
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .toggleStyle(SwitchToggleStyle(tint: DIColor.primary))
        .navigationTitle("Everyone who has signed in")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        failed = false
        do { people = try await service.directory() } catch { failed = true }
    }
}

/// One person's Halqahs: place them in another, change their role, or take
/// them out.
@MainActor
struct DirectoryPersonView: View {
    let person: DirectoryPerson
    let service: MemberGroupService
    let halqahs: [MemberGroup]
    let onChange: () async -> Void

    @State private var places: [DirectoryPerson.Place] = []
    @State private var newHalqah = ""
    @State private var newRole: GroupRole = .member
    @State private var working = false
    @State private var error: String?

    private var changeable: Bool { !person.isYou && !person.isSuperAdmin }
    private var open: [MemberGroup] { halqahs.filter { halqah in !places.contains { $0.groupID == halqah.id } } }

    var body: some View {
        Form {
            Section {
                if let email = person.email { LabeledContent("Email", value: email) }
                if let seen = person.lastSeenAt {
                    LabeledContent("Last seen", value: seen.formatted(date: .abbreviated, time: .shortened))
                }
                if person.isSuperAdmin {
                    Text("Super admin: everything, in every Halqah.").foregroundStyle(DIColor.textMuted)
                }
            }
            Section("Halqahs") {
                if places.isEmpty {
                    Text("Not in a Halqah yet").foregroundStyle(DIColor.textMuted)
                }
                ForEach(places, id: \.groupID) { place in
                    HStack {
                        Text(verbatim: place.groupName)
                        Spacer(minLength: 0)
                        if changeable {
                            Menu {
                                ForEach([GroupRole.administrator, .admin, .member], id: \.self) { role in
                                    if role != place.role {
                                        Button { Task { await setRole(role, in: place) } } label: { Text(role.title) }
                                    }
                                }
                                Button(role: .destructive) { Task { await remove(from: place) } } label: {
                                    Label("Remove from the Halqah", systemImage: "person.badge.minus")
                                }
                            } label: {
                                Text(place.role.title).font(.subheadline.weight(.semibold))
                            }
                        } else {
                            Text(place.role.title).foregroundStyle(DIColor.textMuted)
                        }
                    }
                }
            }
            if changeable && !open.isEmpty {
                Section("Add to a Halqah") {
                    Picker("Halqah", selection: $newHalqah) {
                        Text("Choose").tag("")
                        ForEach(open) { halqah in Text(verbatim: halqah.name).tag(halqah.id) }
                    }
                    Picker("Role", selection: $newRole) {
                        ForEach([GroupRole.member, .admin, .administrator], id: \.self) { role in Text(role.title).tag(role) }
                    }
                    Button("Add") { Task { await add() } }
                        .disabled(working || newHalqah.isEmpty)
                }
            }
            if let error {
                Section { Text(verbatim: error).foregroundStyle(DIColor.danger) }
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .toggleStyle(SwitchToggleStyle(tint: DIColor.primary))
        .navigationTitle(Text(verbatim: person.displayName))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(working)
        .onAppear { places = person.halqahs }
    }

    private func act(_ change: () async throws -> Void, then update: () -> Void) async {
        working = true
        defer { working = false }
        do {
            try await change()
            update()
            error = nil
            await onChange()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func setRole(_ role: GroupRole, in place: DirectoryPerson.Place) async {
        await act({ try await service.setRole(role, of: person.id, in: place.groupID) }) {
            if let index = places.firstIndex(of: place) { places[index].role = role }
        }
    }

    private func remove(from place: DirectoryPerson.Place) async {
        await act({ try await service.remove(person.id, from: place.groupID) }) {
            places.removeAll { $0.groupID == place.groupID }
        }
    }

    private func add() async {
        guard let halqah = halqahs.first(where: { $0.id == newHalqah }) else { return }
        let role = newRole
        await act({ try await service.place(person.id, in: halqah.id, role: role) }) {
            places.append(.init(groupID: halqah.id, groupName: halqah.name, role: role))
            newHalqah = ""
            newRole = .member
        }
    }
}
