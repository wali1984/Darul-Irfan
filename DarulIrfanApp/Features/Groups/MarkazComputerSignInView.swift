import SwiftUI

/// Signs a computer in to the reporting website with the code it shows, and
/// lists the computers signed in, each with Sign out.
@MainActor
struct MarkazComputerSignInView: View {
    let service: MemberGroupService

    @Environment(\.locale) private var locale
    @State private var code = ""
    @State private var working = false
    @State private var approved = false
    @State private var error: String?
    @State private var computers: [MarkazReportingSession]?
    @State private var listFailed = false
    @State private var signingOut: MarkazReportingSession?
    @FocusState private var codeFocused: Bool

    /// The code's eight letters and digits, without the dash.
    private var letters: String { Self.letters(of: code) }

    var body: some View {
        Form {
            Section {
                Text("Open reporting.wajidali.us (this will be transferred to the Silsila's official domain) on the computer and type the code shown there.")
                    .diInterfaceFont(.subheadline)
                    .foregroundStyle(DIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Code, for example K7Q2-9MXD", text: $code)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($codeFocused)
                    .submitLabel(.done)
                    .onSubmit { Task { await approve() } }
                    .environment(\.layoutDirection, .leftToRight)
                    .onChange(of: code) { _, value in
                        let shown = Self.shown(value)
                        if shown != value { code = shown }
                        if !shown.isEmpty { approved = false }
                    }
                    .accessibilityLabel(Text("Code from the computer"))
                Button {
                    Task { await approve() }
                } label: {
                    if working { ProgressView() } else { Text("Approve") }
                }
                .buttonStyle(DISecondaryButtonStyle())
                .disabled(working || letters.count != 8)
                if approved {
                    Label("The computer is signed in.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DIColor.primary)
                }
                if let error {
                    Text(verbatim: error).foregroundStyle(DIColor.danger)
                }
            } footer: {
                Text("The computer stays signed in for 12 hours, and sees the reports only.")
            }
            .listRowBackground(DIColor.surface)
            Section("Signed-in computers") {
                if listFailed {
                    Text("The list could not be loaded. Please try again.")
                        .foregroundStyle(DIColor.textMuted)
                }
                if let computers {
                    if computers.isEmpty {
                        Text("No computer is signed in.").foregroundStyle(DIColor.textMuted)
                    }
                    ForEach(computers) { computer in
                        HStack(spacing: DISpacing.sm) {
                            Image(systemName: "desktopcomputer")
                                .foregroundStyle(DIColor.primary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: computer.name?.isEmpty == false ? (computer.name ?? "") : String(localized: "A computer"))
                                    .diInterfaceFont(.subheadline, weight: .semibold)
                                Text(verbatim: line(computer))
                                    .diInterfaceFont(.caption)
                                    .foregroundStyle(DIColor.textMuted)
                            }
                            Spacer(minLength: DISpacing.sm)
                            Button("Sign out") { signingOut = computer }
                                .buttonStyle(DICompactButtonStyle(destructive: true))
                                .disabled(working)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } else if !listFailed {
                    ProgressView()
                }
            }
            .listRowBackground(DIColor.surface)
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .navigationTitle("Sign in on a computer")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadComputers() }
        .refreshable { await Task { await loadComputers() }.value }
        .onAppear { codeFocused = true }
        .alert("Sign this computer out?", isPresented: Binding(
            get: { signingOut != nil }, set: { if !$0 { signingOut = nil } }
        ), presenting: signingOut) { computer in
            Button("Sign out", role: .destructive) { Task { await signOut(computer) } }
            Button("Cancel", role: .cancel) { signingOut = nil }
        } message: { _ in
            Text("The reports close on that computer straight away.")
        }
    }

    private func line(_ computer: MarkazReportingSession) -> String {
        var parts: [String] = []
        if let created = computer.createdAt {
            parts.append(String(localized: "Signed in \(GroupInvitationDate.text(created, locale: locale, includesTime: true))"))
        }
        if let expires = computer.expiresAt {
            parts.append(String(localized: "Until \(GroupInvitationDate.clock(expires, locale: locale))"))
        }
        return parts.joined(separator: " \u{00b7} ")
    }

    /// Letters and digits only, in capitals, eight at most.
    static func letters(of text: String) -> String {
        String(text.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(8))
    }

    /// The code as the computer shows it: "K7Q2-9MXD", the dash put in.
    static func shown(_ text: String) -> String {
        let value = letters(of: text)
        guard value.count > 4 else { return value }
        return String(value.prefix(4)) + "-" + String(value.dropFirst(4))
    }

    private func approve() async {
        let value = letters
        guard !working, value.count == 8 else { return }
        working = true
        defer { working = false }
        do {
            try await MarkazService(groups: service).approveReportingLink(code: Self.shown(value))
            code = ""
            error = nil
            approved = true
            DIHaptics.light()
            await loadComputers()
        } catch is CancellationError {
            return
        } catch {
            approved = false
            if let groupError = error as? MemberGroupError, case .notSignedIn = groupError {
                self.error = groupError.localizedDescription
            } else {
                self.error = String(localized: "That code was not accepted. It may have expired: get a new code on the computer and try again.")
            }
        }
    }

    private func loadComputers() async {
        do {
            computers = try await MarkazService(groups: service).reportingSessions()
            listFailed = false
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { listFailed = true }
        }
    }

    private func signOut(_ computer: MarkazReportingSession) async {
        signingOut = nil
        guard !working else { return }
        working = true
        defer { working = false }
        do {
            try await MarkazService(groups: service).signOutComputer(computer.id)
            computers?.removeAll { $0.id == computer.id }
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = MemberGroupError.actionDescription(for: error)
        }
        await loadComputers()
    }
}
