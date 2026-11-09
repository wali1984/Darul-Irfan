import SwiftUI

/// "Approve a computer", for every signed-in member: the code the Darul
/// Irfan desktop app shows is typed here (or its QR, scanned with the phone's
/// camera, opens this screen with the code filled in), the computer asking is
/// shown for the member to confirm, and the computers signed in to the account
/// are listed, each with Sign out.
@MainActor
struct ApproveComputerView: View {
    let service: MemberGroupService
    /// A code from the QR's link, checked as soon as the screen opens.
    var initialCode: String?

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var code = ""
    @State private var working = false
    @State private var approved = false
    @State private var error: String?
    @State private var asking: ComputerLinkPreview?
    @State private var computers: [SignedInComputer]?
    @State private var listFailed = false
    @State private var signingOut: SignedInComputer?
    @State private var confirmingSignOutAll = false
    @State private var usedInitialCode = false
    @FocusState private var codeFocused: Bool

    private var computerService: ComputerSignInService { ComputerSignInService(groups: service) }
    private var letters: String { ComputerLinkCode.letters(of: code) }

    var body: some View {
        Form {
            Section {
                Text("Open Darul Irfan on your computer. It shows a code and a QR code: scan the QR code with this phone's camera, or type the code here.")
                    .diInterfaceFont(.subheadline)
                    .foregroundStyle(DIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Code, for example K7Q2-9MXD", text: $code)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($codeFocused)
                    .submitLabel(.continue)
                    .onSubmit { Task { await check() } }
                    // The code reads left to right in Urdu too, as the computer shows it.
                    .environment(\.layoutDirection, .leftToRight)
                    .onChange(of: code) { _, value in
                        let shown = ComputerLinkCode.shown(value)
                        if shown != value { code = shown }
                        if !shown.isEmpty { approved = false }
                    }
                    .accessibilityLabel(Text("Code from the computer"))
                Button {
                    Task { await check() }
                } label: {
                    if working && asking == nil { ProgressView() } else { Text("Continue") }
                }
                .buttonStyle(DIPrimaryButtonStyle())
                .disabled(working || letters.count != 8)
                if approved {
                    Label("The computer is signed in.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DIColor.actionForeground)
                        .transition(reduceMotion ? .identity : .opacity)
                }
                if let error {
                    Text(verbatim: error)
                        .foregroundStyle(DIColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } footer: {
                Text("A computer stays signed in for 30 days after it was last used. You can sign it out here at any time.")
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
                        row(computer)
                    }
                    if computers.count > 1 {
                        Button("Sign out all computers", role: .destructive) { confirmingSignOutAll = true }
                            .buttonStyle(DISecondaryButtonStyle(destructive: true))
                            .disabled(working)
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
        .navigationTitle("Approve a computer")
        .navigationBarTitleDisplayMode(.inline)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: approved)
        .task { await loadComputers() }
        .refreshable { await Task { await loadComputers() }.value }
        .onAppear(perform: useInitialCode)
        .sheet(item: $asking) { computer in
            ApproveComputerConfirmSheet(computer: computer, working: working) {
                Task { await approve() }
            } onCancel: {
                asking = nil
            }
            .presentationDetents([.medium, .large])
            .interactiveDismissDisabled(working)
        }
        .alert("Sign this computer out?", isPresented: Binding(
            get: { signingOut != nil }, set: { if !$0 { signingOut = nil } }
        ), presenting: signingOut) { computer in
            Button("Sign out", role: .destructive) { Task { await signOut(computer) } }
            Button("Cancel", role: .cancel) { signingOut = nil }
        } message: { _ in
            Text("Darul Irfan signs out on that computer straight away.")
        }
        .confirmationDialog("Sign out every computer?", isPresented: $confirmingSignOutAll, titleVisibility: .visible) {
            Button("Sign out all computers", role: .destructive) { Task { await signOutAll() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every computer signed in to your account is signed out straight away. This phone stays signed in.")
        }
    }

    private func row(_ computer: SignedInComputer) -> some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: ComputerPlatform.symbol(computer.platform))
                .foregroundStyle(DIColor.actionForeground)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: computer.name?.isEmpty == false ? (computer.name ?? "") : String(localized: "A computer"))
                    .diInterfaceFont(.subheadline, weight: .semibold)
                Text(verbatim: line(computer))
                    .diInterfaceFont(.caption)
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DISpacing.sm)
            Button("Sign out") { signingOut = computer }
                .buttonStyle(DICompactButtonStyle(destructive: true))
                .disabled(working)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Windows · Signed in 9 Nov 2026, 6:20 PM · Last used 6:40 PM", in Western digits.
    private func line(_ computer: SignedInComputer) -> String {
        var parts = [ComputerPlatform.name(computer.platform)]
        if let created = computer.createdAt {
            parts.append(String(localized: "Signed in \(GroupInvitationDate.text(created, locale: locale, includesTime: true))"))
        }
        if let used = computer.lastSeenAt, computer.createdAt.map({ used.timeIntervalSince($0) > 60 }) ?? true {
            parts.append(String(localized: "Last used \(GroupInvitationDate.text(used, locale: locale, includesTime: true))"))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " \u{00b7} ")
    }

    private func useInitialCode() {
        guard !usedInitialCode else { return }
        usedInitialCode = true
        if let initialCode, let found = ComputerLinkCode.code(in: initialCode) {
            code = found
            Task { await check() }
        } else {
            codeFocused = true
        }
    }

    /// Asks which computer shows the code, and shows it for the member to confirm.
    private func check() async {
        let value = letters
        guard !working, value.count == 8 else { return }
        working = true
        defer { working = false }
        do {
            let computer = try await computerService.preview(code: ComputerLinkCode.shown(value))
            error = nil
            codeFocused = false
            asking = computer
        } catch is CancellationError {
            return
        } catch {
            approved = false
            self.error = ComputerSignInService.failureText(for: error)
        }
    }

    private func approve() async {
        let value = letters
        guard !working, value.count == 8 else { return }
        working = true
        defer { working = false }
        do {
            try await computerService.approve(code: ComputerLinkCode.shown(value))
            asking = nil
            code = ""
            error = nil
            approved = true
            DIHaptics.success()
            await loadComputers()
        } catch is CancellationError {
            return
        } catch {
            asking = nil
            approved = false
            self.error = ComputerSignInService.failureText(for: error)
        }
    }

    private func loadComputers() async {
        do {
            computers = try await computerService.computers()
            listFailed = false
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { listFailed = true }
        }
    }

    private func signOut(_ computer: SignedInComputer) async {
        signingOut = nil
        guard !working else { return }
        working = true
        defer { working = false }
        do {
            try await computerService.signOut(computer.id)
            computers?.removeAll { $0.id == computer.id }
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = MemberGroupError.actionDescription(for: error)
        }
        await loadComputers()
    }

    private func signOutAll() async {
        guard !working else { return }
        working = true
        defer { working = false }
        do {
            try await computerService.signOutAll()
            computers = []
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = MemberGroupError.actionDescription(for: error)
        }
        await loadComputers()
    }
}

/// The computer asking, named before the member lets it in, with a warning
/// against approving a code someone else sent.
@MainActor
struct ApproveComputerConfirmSheet: View {
    let computer: ComputerLinkPreview
    let working: Bool
    let onApprove: () -> Void
    let onCancel: () -> Void
    @ScaledMetric(relativeTo: .title) private var tile: CGFloat = 64

    var body: some View {
        ScrollView {
            VStack(spacing: DISpacing.md) {
                Image(systemName: ComputerPlatform.symbol(computer.platform))
                    .font(.system(size: tile * 0.45, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x064B34))
                    .frame(width: tile, height: tile)
                    .background(Circle().fill(HalqahInk.tileGold))
                    .accessibilityHidden(true)
                Text("Approve this computer?")
                    .diInterfaceFont(.title3, weight: .bold)
                    .foregroundStyle(DIColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 4) {
                    Text(verbatim: computer.deviceName.isEmpty ? String(localized: "A computer") : computer.deviceName)
                        .diInterfaceFont(.headline, weight: .semibold)
                        .foregroundStyle(DIColor.textPrimary)
                    Text(verbatim: ComputerPlatform.name(computer.platform))
                        .diInterfaceFont(.subheadline, weight: .medium)
                        .foregroundStyle(HalqahInk.goldText)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(DISpacing.md)
                .diGlassPanel(cornerRadius: 20)
                .accessibilityElement(children: .combine)
                Text("Only approve a computer you are using yourself. It will be signed in as you, with everything your account can do. Never approve a code someone else sent you.")
                    .diInterfaceFont(.footnote)
                    .foregroundStyle(DIColor.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onApprove) {
                    if working { ProgressView().frame(maxWidth: .infinity) } else { Text("Approve").frame(maxWidth: .infinity) }
                }
                .buttonStyle(DIPrimaryButtonStyle())
                .disabled(working)
                Button("Cancel", action: onCancel)
                    .buttonStyle(DISecondaryButtonStyle())
                    .disabled(working)
            }
            .padding(DISpacing.lg)
            .diResponsiveWidth()
        }
        .diScreenBackground()
    }
}

/// The screen a computer's QR opens (darulirfan://approve-computer?code=...),
/// over the Halqah tab.
@MainActor
struct ApproveComputerLinkView: View {
    let code: String?

    @Environment(\.dismiss) private var dismiss
    @State private var service = MemberGroupService()

    var body: some View {
        Group {
            if MemberGroupService.hasSavedSession {
                ApproveComputerView(service: service, initialCode: code)
            } else {
                DIEmptyState(systemImage: "person.crop.circle.badge.questionmark",
                             titleKey: "Sign in on this phone first, then approve the computer from here.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .diScreenBackground()
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
                    .buttonStyle(DICompactButtonStyle())
            }
        }
    }
}
