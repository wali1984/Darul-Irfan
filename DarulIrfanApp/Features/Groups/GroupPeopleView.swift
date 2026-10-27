import SwiftUI
import UIKit

// A group's people, run by its admins from the phone: who is in the group,
// adding someone by email or by a code sent to their phone, making and
// unmaking the group's admins, removing people, and withdrawing invitations
// nobody has used yet.

@MainActor
struct GroupPeopleView: View {
    let groupID: String
    let groupName: String
    let service: MemberGroupService

    @Environment(\.dismiss) private var dismiss
    @State private var people: GroupPeople?
    @State private var error: String?
    @State private var adding = false
    @State private var working = false
    @State private var removing: GroupPerson?

    var body: some View {
        List {
            Section {
                Button {
                    adding = true
                } label: {
                    Label("Add people", systemImage: "person.badge.plus")
                }
            } footer: {
                Text("Add someone by email, or send an invitation code to their phone, as a member or as an admin of this group.")
            }
            if let error {
                Section { Text(verbatim: error).foregroundStyle(DIColor.danger) }
            }
            if let people {
                let admins = people.members.filter { $0.role != .member }
                let members = people.members.filter { $0.role == .member }
                if !admins.isEmpty {
                    Section("Admins") { ForEach(admins) { personRow($0) } }
                }
                Section("Members") {
                    if members.isEmpty {
                        Text("No members yet.").foregroundStyle(DIColor.textMuted)
                    }
                    ForEach(members) { personRow($0) }
                }
                if !people.invitations.isEmpty {
                    Section {
                        ForEach(people.invitations) { invitationRow($0) }
                    } header: {
                        Text("Invitations not used yet")
                    } footer: {
                        Text("Withdraw one to stop it admitting anyone.")
                    }
                }
            } else if error == nil {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await load() }
        .refreshable { await load() }
        .disabled(working)
        .sheet(isPresented: $adding, onDismiss: { Task { await load() } }) {
            NavigationStack { AddGroupPersonView(groupID: groupID, groupName: groupName, service: service) }
        }
        .confirmationDialog(
            "Remove from the group?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { person in
            Button("Remove \(person.displayName)", role: .destructive) {
                Task { await act { try await service.remove(person.id, from: groupID) } }
            }
        } message: { _ in
            Text("They keep their account and any other groups, and can be added again later.")
        }
    }

    private func personRow(_ person: GroupPerson) -> some View {
        HStack(spacing: DISpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DISpacing.xs) {
                    Text(verbatim: person.displayName)
                    if person.isYou {
                        Text("(you)").foregroundStyle(DIColor.textMuted)
                    }
                }
                if let email = person.email, email != person.displayName {
                    Text(verbatim: email).font(.caption).foregroundStyle(DIColor.textMuted)
                }
            }
            Spacer(minLength: DISpacing.sm)
            if person.role == .superadmin {
                roleBadge("Super admin")
            } else if person.role == .admin {
                roleBadge("Admin")
            }
            if person.isChangeable {
                Menu {
                    if person.role == .admin {
                        Button {
                            Task { await act { try await service.setRole(.member, of: person.id, in: groupID) } }
                        } label: {
                            Label("Make a member", systemImage: "person")
                        }
                    } else {
                        Button {
                            Task { await act { try await service.setRole(.admin, of: person.id, in: groupID) } }
                        } label: {
                            Label("Make an admin of this group", systemImage: "person.badge.key")
                        }
                    }
                    Button(role: .destructive) {
                        removing = person
                    } label: {
                        Label("Remove from the group", systemImage: "person.badge.minus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                        .accessibilityLabel(Text("Change \(person.displayName)"))
                }
            }
        }
    }

    private func roleBadge(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(DIColor.primary)
            .padding(.horizontal, DISpacing.sm)
            .padding(.vertical, 2)
            .background(DIColor.primary.opacity(0.12), in: Capsule())
    }

    private func invitationRow(_ invitation: GroupInvitation) -> some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: invitation.kind == "email" ? "envelope" : "number")
                .foregroundStyle(DIColor.textMuted)
            VStack(alignment: .leading, spacing: 2) {
                if let label = invitation.label {
                    Text(verbatim: label)
                } else {
                    Text("Code without a note")
                }
                Group {
                    if invitation.kind == "email" {
                        Text("Added when they sign in with Apple")
                    } else if let expires = invitation.expiresAt {
                        Text("Code, until \(expires.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                .font(.caption)
                .foregroundStyle(DIColor.textMuted)
            }
            Spacer(minLength: DISpacing.sm)
            if invitation.role == .admin { roleBadge("Admin") }
            Button(role: .destructive) {
                Task { await act { try await service.revokeInvitation(invitation.id, in: groupID) } }
            } label: {
                Text("Withdraw")
            }
            .buttonStyle(.borderless)
        }
    }

    private func load() async {
        do {
            people = try await service.people(in: groupID)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func act(_ change: () async throws -> Void) async {
        working = true
        defer { working = false }
        do {
            try await change()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        await load()
    }
}

// MARK: - Adding someone

@MainActor
struct AddGroupPersonView: View {
    let groupID: String
    let groupName: String
    let service: MemberGroupService

    private enum Method: String, CaseIterable, Identifiable {
        case email = "Email"
        case phone = "Phone"
        case code = "Code only"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var method: Method = .email
    @State private var email = ""
    @State private var phone = ""
    @State private var role: GroupRole = .member
    @State private var days = 14
    @State private var working = false
    @State private var error: String?
    @State private var result: AddPersonResult?
    @State private var copied = false

    var body: some View {
        Form {
            if let result {
                resultSections(result)
            } else {
                entrySections
            }
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .navigationTitle("Add people")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: result == nil ? .cancellationAction : .confirmationAction) {
                Button(result == nil ? "Cancel" : "Done") { dismiss() }
            }
        }
    }

    // MARK: Entry

    @ViewBuilder
    private var entrySections: some View {
        Section {
            Picker("Add by", selection: $method) {
                ForEach(Method.allCases) { method in Text(LocalizedStringKey(method.rawValue)).tag(method) }
            }
            .pickerStyle(.segmented)
            switch method {
            case .email:
                TextField("Email address", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case .phone:
                TextField("Phone number, with country code", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            case .code:
                EmptyView()
            }
        } footer: {
            switch method {
            case .email:
                Text("They are added as soon as they sign in with Apple using this email, or at once if they already have. If they hide their email from apps, send a code instead.")
            case .phone:
                Text("A single-use code is made for them, and you send it from your phone by text message or another app.")
            case .code:
                Text("A single-use code to hand over however you like.")
            }
        }
        Section {
            Picker("Role", selection: $role) {
                Text("Member").tag(GroupRole.member)
                Text("Admin of this group").tag(GroupRole.admin)
            }
        } footer: {
            Text("Admins post, approve drafts, run zikr and meetings, and add or remove people, in this group only.")
        }
        if method != .email {
            Section {
                Stepper(value: $days, in: 1...90) {
                    Text("The code lasts \(days) days")
                }
            }
        }
        if let error {
            Section { Text(verbatim: error).foregroundStyle(DIColor.danger) }
        }
        Section {
            Button {
                Task { await save() }
            } label: {
                if working {
                    ProgressView()
                } else {
                    Label(method == .email ? "Add to the group" : "Make the code",
                          systemImage: method == .email ? "person.badge.plus" : "key")
                }
            }
            .disabled(working || !canSave)
        }
    }

    private var canSave: Bool {
        switch method {
        case .email: return email.contains("@") && email.contains(".")
        case .phone: return phone.filter(\.isNumber).count >= 7
        case .code: return true
        }
    }

    private func save() async {
        working = true
        defer { working = false }
        do {
            result = try await service.addPerson(
                to: groupID,
                email: method == .email ? email.trimmingCharacters(in: .whitespaces) : nil,
                phone: method == .phone ? phone : nil,
                role: role,
                codeDays: days
            )
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Result

    @ViewBuilder
    private func resultSections(_ result: AddPersonResult) -> some View {
        switch result.result {
        case "added":
            Section {
                Label {
                    Text("\(result.name ?? email) is now in \(groupName).")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DIColor.primary)
                }
            }
        case "pending":
            Section {
                Label {
                    Text("\(email) will be added to \(groupName) when they sign in with Apple using this email.")
                } icon: {
                    Image(systemName: "clock.badge.checkmark").foregroundStyle(DIColor.primary)
                }
            } footer: {
                Text("Nothing to send: they open Halqah in the app and sign in. If they hide their email from apps, send them a code instead.")
            }
        default:
            if let code = result.code {
                codeSections(code: code, result: result)
            }
        }
        Section {
            Button {
                self.result = nil
                email = ""
                phone = ""
                copied = false
            } label: {
                Label("Add someone else", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private func codeSections(code: String, result: AddPersonResult) -> some View {
        let message = invitationMessage(code: code, expires: result.expiresAt)
        Section {
            Text(verbatim: code)
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)
                .environment(\.layoutDirection, .leftToRight)
            if let expires = result.expiresAt {
                Text("Works once, until \(expires.formatted(date: .abbreviated, time: .shortened)).")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
            }
        } footer: {
            Text("This is the only time the code is shown. Send it now; it is listed under the group's invitations until it is used.")
        }
        Section {
            if let phone = result.phone {
                Button {
                    if let url = smsURL(phone: phone, message: message) { openURL(url) }
                } label: {
                    Label("Send by text message", systemImage: "message")
                }
                Button {
                    if let url = whatsappURL(phone: phone, message: message) { openURL(url) }
                } label: {
                    Label("Send on WhatsApp", systemImage: "phone.bubble")
                }
            }
            ShareLink(item: message) {
                Label("Send another way", systemImage: "square.and.arrow.up")
            }
            Button {
                UIPasteboard.general.string = code
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy the code", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
        }
    }

    private func invitationMessage(code: String, expires: Date?) -> String {
        let until = expires?.formatted(date: .abbreviated, time: .omitted) ?? ""
        return String(localized: "Assalamu alaikum. You are invited to the \(groupName) group in the Darul Irfan app. Open the app, go to Halqah, and enter this code: \(code). It works once, until \(until).")
    }

    private func smsURL(phone: String, message: String) -> URL? {
        let body = message.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return URL(string: "sms:+\(phone)&body=\(body)")
    }

    private func whatsappURL(phone: String, message: String) -> URL? {
        var components = URLComponents(string: "https://wa.me/\(phone)")
        components?.queryItems = [URLQueryItem(name: "text", value: message)]
        return components?.url
    }
}
