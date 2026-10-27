import AuthenticationServices
import SwiftUI
import UIKit

/// Entry point for the silsila's private regional groups.
///
/// Signing in is not joining. The backend gives a new member no groups until an
/// admin places them, so a member who has just signed in correctly sees nothing
/// and is shown the identifier an admin needs in order to add them.
@MainActor
@Observable
final class GroupsModel {
    enum Phase: Equatable {
        case signedOut
        case loading
        case ready
        case failed(String)
    }

    let service = MemberGroupService()
    var phase: Phase = .loading
    var groups: [MemberGroup] = []
    var role: MemberRole = .member
    var memberID: String?
    var isDeleting = false
    var isRedeeming = false
    /// Shown under the code field only; a failed code is not a screen-level
    /// failure, and must not throw the member out of the sign-in card.
    var inviteError: String?

    func start() async {
        guard await service.isSignedIn else {
            phase = .signedOut
            return
        }
        await refresh()
    }

    func refresh() async {
        phase = .loading
        memberID = await service.memberID
        do {
            let list = try await service.groups()
            groups = list.groups
            role = list.role ?? .member
            phase = .ready
            // Group notices reach this phone once its notifications are
            // registered; linking is quiet and harmless before then.
            if let installation = SecureInstallationIdentity.load() {
                await service.linkNotifications(installationID: installation)
            }
        } catch MemberGroupError.notSignedIn {
            groups = []
            phase = .signedOut
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func completeSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure:
            // A cancelled sign-in is not an error worth shouting about.
            let stillSignedIn = await service.isSignedIn
            phase = stillSignedIn ? .ready : .signedOut
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let token = credential.identityToken else {
                phase = .failed(MemberGroupError.signInRejected.localizedDescription)
                return
            }
            // Apple discloses the name only on the first authorisation, so it is
            // sent when offered and never demanded afterwards.
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            phase = .loading
            do {
                memberID = try await service.signIn(identityToken: token, displayName: name.isEmpty ? nil : name)
                await refresh()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Redeems an administrator's invitation code. On success the member is
    /// already in their group, so the list is simply reloaded.
    func redeemInvite(_ rawCode: String) async {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        isRedeeming = true
        inviteError = nil
        defer { isRedeeming = false }
        do {
            memberID = try await service.redeemInvite(code: code, displayName: nil)
            await refresh()
        } catch {
            inviteError = error.localizedDescription
        }
    }

    func signOut() async {
        await service.signOut()
        groups = []
        memberID = nil
        phase = .signedOut
    }

    func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await service.deleteAccount()
            groups = []
            memberID = nil
            phase = .signedOut
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

@MainActor
struct GroupsHomeView: View {
    var dependencies: AppDependencies? = nil
    @State private var model = GroupsModel()
    @State private var isConfirmingDelete = false
    @State private var inviteCode = ""
    @State private var isShowingHowItWorks = true
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                switch model.phase {
                case .signedOut:
                    signInCard
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, DISpacing.lg)
                case .ready:
                    if model.role != .member { roleCard }
                    if model.groups.isEmpty { awaitingApprovalCard } else { groupList }
                    // Another code (a second group, or an admin role) adds to
                    // this same account.
                    addCodeCard
                    accountCard
                case .failed(let message):
                    failureCard(message)
                    accountCard
                }
                howItWorksCard
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .diPageHeading("Private groups")
        .task { await model.start() }
        .refreshable { await model.refresh() }
    }

    private var signInCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Members only")
                    .font(.headline)
                Text("These groups are for members of Silsila Naqshbandia Owaisiah. Enter the invitation code an administrator gave you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // The code is the primary way in: it needs nothing from Apple
                // or Google, so it works the same on every platform, and
                // admission stays an administrator's decision.
                HStack(spacing: DISpacing.sm) {
                    TextField("Invitation code", text: $inviteCode)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($isCodeFocused)
                        .submitLabel(.join)
                        .onSubmit { redeem() }
                        .accessibilityLabel("Invitation code")
                    Button(action: redeem) {
                        if model.isRedeeming { ProgressView() } else { Text("Join") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isRedeeming)
                }
                if let inviteError = model.inviteError {
                    Text(inviteError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if MemberGroupsFeature.appleSignInAvailable {
                    Text("Or sign in, then ask an administrator to add you.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    SignInWithAppleButton(.signIn) { request in
                        // Only the name is requested. A group needs to know who
                        // you are to an administrator, not how to contact you.
                        request.requestedScopes = [.fullName]
                    } onCompletion: { result in
                        Task { await model.completeSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 48)
                    .accessibilityLabel("Sign in with Apple to see your private group")
                }
            }
        }
    }

    /// How the groups work, in the order a member meets it. Open by default
    /// until the member is in a group, then folded away.
    private var howItWorksCard: some View {
        DICard {
            DisclosureGroup(isExpanded: $isShowingHowItWorks) {
                VStack(alignment: .leading, spacing: DISpacing.md) {
                    howStep(1, "Get your invitation code",
                            "Ask the administrator of your region's group - Darul Irfan, United States or Canada - for an invitation code. Each code admits one person to one group and expires after 30 days.")
                    howStep(2, "Join with the code",
                            "Type the code in the box above and tap Join. You are added to your group straight away; there is nothing else to wait for.")
                    howStep(3, "Read and watch",
                            "Open your group to read its announcements and to watch recorded zikr inside the app. Pull down to check for new posts.")
                    howStep(4, "Join a meeting",
                            "When a group has a meeting, its link appears at the top of the group. Tap it to join the meeting.")
                    howStep(5, "Private by design",
                            "Only members of a group can see it, and one region cannot see another's. Members read; administrators publish. Nothing you do here is shown to other members.")
                    howStep(6, "Leaving",
                            "Delete my account removes your sign-in and your place in every group. To come back, ask for a new code.")
                }
                .padding(.top, DISpacing.sm)
            } label: {
                Label("How private groups work", systemImage: "questionmark.circle")
                    .font(.headline)
                    .foregroundStyle(DIColor.textPrimary)
            }
            .tint(DIColor.primary)
        }
        .onChange(of: model.groups.isEmpty) { _, isEmpty in
            if !isEmpty { isShowingHowItWorks = false }
        }
    }

    private func howStep(_ number: Int, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: DISpacing.sm) {
            Text(verbatim: "\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(DIColor.onPrimary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(DIColor.primary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DIColor.textPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func redeem() {
        isCodeFocused = false
        DIHaptics.light()
        let code = inviteCode
        Task {
            await model.redeemInvite(code)
            if model.inviteError == nil { inviteCode = "" }
        }
    }

    private var awaitingApprovalCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Waiting to be added")
                    .font(.headline)
                Text("You are signed in, but you are not in a group yet. Send the identifier below to an administrator and they will add you to your region's group.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let memberID = model.memberID {
                    HStack {
                        Text(memberID)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = memberID
                            DIHaptics.light()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var groupList: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            ForEach(model.groups) { group in
                NavigationLink {
                    GroupDetailView(group: group, service: model.service, dependencies: dependencies)
                } label: {
                    DICard {
                        HStack(alignment: .top, spacing: DISpacing.sm) {
                            VStack(alignment: .leading, spacing: DISpacing.xs) {
                                Text(LocalizedStringKey(group.name))
                                    .font(.headline)
                                if let description = group.description {
                                    Text(verbatim: description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                if group.canManage == true {
                                    Label("You are an admin of this group", systemImage: "person.badge.key")
                                        .font(.caption)
                                        .foregroundStyle(DIColor.accent)
                                }
                            }
                            Spacer(minLength: 0)
                            if group.isLive == true {
                                Label(group.liveKind == "meeting" ? "Meeting live" : "Zikr live", systemImage: "dot.radiowaves.left.and.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(DIColor.primary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var roleCard: some View {
        DICard {
            Label(model.role == .superadmin
                  ? "Super admin: you can post, approve and run zikr and meetings in every group."
                  : "Group admin: you can post, approve and run zikr and meetings in your groups.",
                  systemImage: "person.badge.key.fill")
                .font(.subheadline)
                .foregroundStyle(DIColor.textPrimary)
        }
    }

    private var addCodeCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Have another invitation code?")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: DISpacing.sm) {
                    TextField("Invitation code", text: $inviteCode)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.join)
                        .onSubmit { redeem() }
                    Button(action: redeem) {
                        if model.isRedeeming { ProgressView() } else { Text("Join") }
                    }
                    .buttonStyle(.bordered)
                    .disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isRedeeming)
                }
                if let inviteError = model.inviteError {
                    Text(verbatim: inviteError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func failureCard(_ message: String) -> some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text(message)
                    .font(.subheadline)
                Button("Try again") { Task { await model.refresh() } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var accountCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Button("Sign out") { Task { await model.signOut() } }
                    .buttonStyle(.bordered)
                // Apple requires an account made in the app to be deletable
                // inside it, and a member should not have to hunt for it.
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    if model.isDeleting {
                        ProgressView()
                    } else {
                        Text("Delete my account")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(model.isDeleting)
                Text("Deleting removes your sign-in and your place in every group. Nothing the silsila published is affected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Delete your account?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await model.deleteAccount() } }
            Button("Keep my account", role: .cancel) {}
        } message: {
            Text("Your sign-in and your group memberships are removed. An administrator would have to add you again.")
        }
    }
}
