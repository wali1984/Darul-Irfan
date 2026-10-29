import AuthenticationServices
import SwiftUI
import UIKit
import UserNotifications

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
    /// Everyone who has signed in, for the Super admin's dashboard; the
    /// server sends it to no one else.
    var signedIn: Int?
    var memberID: String?
    var isDeleting = false
    var isRedeeming = false
    /// Shown under the code field only; a failed code is not a screen-level
    /// failure, and must not throw the member out of the sign-in card.
    var inviteError: String?

    /// The member's Halqah notices on this phone: on, off, or blocked in
    /// iOS Settings.
    enum Notices: Equatable { case on, off, blocked }
    var notices: Notices = .off
    var isChangingNotices = false
    /// Asked once, after joining, whether to show the Halqah's notices here.
    var offerNotices = false
    /// Registers the phone for the notices; set by the page.
    var platform: OfficialPlatformService?
    private static var registeredThisRun = false
    private static let askedKey = "halqah.notices.asked"

    /// The member's own name, as their Halqah's admins and the meeting room
    /// show it.
    var displayName: String?
    var isSavingName = false
    var nameError: String?

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
            signedIn = list.signedIn
            phase = .ready
            displayName = (try? await service.profile())?.displayName
            // Not waited for: the token can take a few seconds to come, and
            // the page (and pull to refresh) should not.
            Task { await self.followNotices() }
        } catch MemberGroupError.notSignedIn {
            groups = []
            signedIn = nil
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
                await offerNoticesOnce()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Redeems an administrator's invitation code. On success the member is
    /// already in their group, so the list is simply reloaded. `name` is how
    /// a member who joins by code is known to their Halqah's admins.
    func redeemInvite(_ rawCode: String, name: String? = nil) async {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        isRedeeming = true
        inviteError = nil
        defer { isRedeeming = false }
        do {
            let given = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            memberID = try await service.redeemInvite(code: code, displayName: given?.isEmpty == false ? given : nil)
            await refresh()
            await offerNoticesOnce()
        } catch {
            inviteError = error.localizedDescription
        }
    }

    func signOut() async {
        await service.signOut()
        groups = []
        signedIn = nil
        memberID = nil
        displayName = nil
        notices = .off
        phase = .signedOut
    }

    func rename(_ raw: String) async {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isSavingName = true
        nameError = nil
        defer { isSavingName = false }
        do {
            displayName = try await service.rename(to: name).displayName
        } catch {
            nameError = error.localizedDescription
        }
    }

    // MARK: Halqah notices

    /// Turns the member's Halqah notices on or off on this phone. Off keeps
    /// them signed in and keeps any official alerts.
    func setNotices(_ on: Bool) async {
        isChangingNotices = true
        defer { isChangingNotices = false }
        if on {
            HalqahNoticeChoice.isTurnedOff = false
            if await NotificationPermission.current() == .notAsked {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            }
            Self.registeredThisRun = false
            await followNotices()
        } else {
            HalqahNoticeChoice.isTurnedOff = true
            notices = .off
            if let installation = SecureInstallationIdentity.load() {
                try? await service.unlinkNotifications(installationID: installation)
            }
        }
    }

    /// Keeps this phone set up for the member's Halqah notices while they
    /// want them and iOS allows them. They used to arrive only on phones that
    /// had also switched on official alerts, so most members heard nothing.
    private func followNotices() async {
        guard !HalqahNoticeChoice.isTurnedOff else {
            notices = .off
            return
        }
        switch await NotificationPermission.current() {
        case .allowed:
            notices = .on
            if !Self.registeredThisRun, let platform, let token = await APNSTokenWatcher.shared.token(),
               (try? await platform.registerForHalqahNotices(token: token)) != nil {
                Self.registeredThisRun = true
            }
            await service.linkNotifications(installationID: SecureInstallationIdentity.loadOrCreate())
        case .notAsked:
            notices = .off
        case .denied:
            notices = .blocked
        }
    }

    /// After joining a Halqah: ask once whether to show its notices here.
    private func offerNoticesOnce() async {
        guard !groups.isEmpty, !HalqahNoticeChoice.isTurnedOff,
              !UserDefaults.standard.bool(forKey: Self.askedKey),
              await NotificationPermission.current() == .notAsked else { return }
        UserDefaults.standard.set(true, forKey: Self.askedKey)
        offerNotices = true
    }

    func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await service.deleteAccount()
            groups = []
            signedIn = nil
            memberID = nil
            displayName = nil
            notices = .off
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
    /// The name a member joining by code gives.
    @State private var joinName = ""
    /// The member's name as they edit it in the account card.
    @State private var nameDraft = ""
    @State private var isShowingHowItWorks = true
    @State private var editing: HalqahEdit?
    @State private var retiring: MemberGroup?
    @State private var retireError: String?
    @FocusState private var isCodeFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The symbol circles beside card headings, grown with the text.
    @ScaledMetric(relativeTo: .headline) private var symbolBox: CGFloat = 38

    /// A Halqah being made (nil group) or edited, by the Super admin.
    private struct HalqahEdit: Identifiable {
        var group: MemberGroup?
        var id: String { group?.id ?? "new" }
    }

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
                    // The Super admin's dashboard says their role; an
                    // Administrator or Admin sees theirs on its own card.
                    if model.role == .superadmin {
                        superAdminDashboard
                    } else if model.role != .member {
                        roleCard
                    }
                    if model.groups.isEmpty {
                        awaitingApprovalCard
                    } else {
                        groupList
                        noticesCard
                    }
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
        .task {
            model.platform = dependencies?.officialPlatform
            await model.start()
        }
        .refreshable { await model.refresh() }
        .onAppear { if nameDraft.isEmpty { nameDraft = model.displayName ?? "" } }
        .onChange(of: model.displayName) { _, name in nameDraft = name ?? "" }
        .alert("Turn on Halqah notifications?", isPresented: $model.offerNotices) {
            Button("Turn on") { Task { await model.setNotices(true) } }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Your Halqah's posts, zikr and meetings will be shown on this phone.")
        }
        .sheet(item: $editing, onDismiss: { Task { await model.refresh() } }) { edit in
            NavigationStack { HalqahEditor(service: model.service, halqah: edit.group) }
        }
        .confirmationDialog(
            "Retire this Halqah?",
            isPresented: Binding(get: { retiring != nil }, set: { if !$0 { retiring = nil } }),
            titleVisibility: .visible,
            presenting: retiring
        ) { group in
            Button("Retire \(group.name)", role: .destructive) {
                Task {
                    do {
                        try await model.service.retireHalqah(group.id)
                        retireError = nil
                    } catch {
                        retireError = error.localizedDescription
                    }
                    await model.refresh()
                }
            }
        } message: { _ in
            Text("It disappears for everyone. Its people, posts and history are kept.")
        }
    }

    // MARK: Super admin

    /// The Super admin's command centre: every Halqah at a glance, from what
    /// the list already holds, and the tools only they have.
    private var superAdminDashboard: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            HalqahGlassHeader(isLive: liveZikrCount + liveMeetingCount > 0) {
                VStack(alignment: .leading, spacing: DISpacing.md) {
                    VStack(alignment: .leading, spacing: DISpacing.sm) {
                        HalqahRoleBadge(role: .superadmin, onGlass: true)
                        Text(roleSummary)
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    dashboardStats
                }
            }
            .diAppear()
            Button {
                editing = HalqahEdit(group: nil)
            } label: {
                HalqahTileLabel(
                    titleKey: "New Halqah",
                    subtitle: Text("Starts empty. Add its first Administrator."),
                    systemImage: "plus.circle.fill",
                    axis: .horizontal
                )
            }
            .buttonStyle(HalqahTileButtonStyle())
            .halqahTileAccessibility(
                titleKey: "New Halqah",
                value: Text("Starts empty. Add its first Administrator."),
                hintKey: "Makes a new Halqah."
            )
            .diAppear(delay: 0.05)
            HalqahTilePair {
                NavigationLink {
                    MemberDirectoryView(service: model.service, halqahs: model.groups)
                } label: {
                    HalqahTileLabel(
                        titleKey: "Everyone who has signed in",
                        subtitle: Text("Place anyone in any Halqah"),
                        systemImage: "person.3.sequence.fill",
                        showsChevron: true
                    )
                }
                .buttonStyle(HalqahTileButtonStyle())
                .halqahTileAccessibility(
                    titleKey: "Everyone who has signed in",
                    value: Text("Place anyone in any Halqah"),
                    hintKey: "Opens everyone who has signed in."
                )
            } trailing: {
                NavigationLink {
                    DailyMediaManagerView(service: model.service)
                } label: {
                    HalqahTileLabel(
                        titleKey: "Today's pictures",
                        subtitle: Text("Pictures for the Today page"),
                        systemImage: "photo.stack.fill",
                        tint: DIColor.accent,
                        showsChevron: true
                    )
                }
                .buttonStyle(HalqahTileButtonStyle())
                .halqahTileAccessibility(
                    titleKey: "Today's pictures",
                    value: Text("Pictures for the Today page"),
                    hintKey: "Opens the pictures for the Today page."
                )
            }
            .diAppear(delay: 0.1)
            Text("Tap ⋯ on a Halqah, or press and hold it, to rename or retire it.")
                .font(.caption)
                .foregroundStyle(DIColor.textMuted)
            if let retireError {
                Text(verbatim: retireError).font(.footnote).foregroundStyle(DIColor.danger)
            }
        }
    }

    /// The dashboard's figures, all from the Halqah list the page already
    /// loaded: in one row while they fit, else two by two, else one by one.
    private var dashboardStats: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DISpacing.sm) {
                peopleStats
                liveStats
            }
            VStack(spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) { peopleStats }
                HStack(spacing: DISpacing.sm) { liveStats }
            }
            VStack(spacing: DISpacing.sm) {
                peopleStats
                liveStats
            }
        }
    }

    /// The Halqahs, and everyone who has signed in (sent to the Super admin
    /// only; an older server sends no count, and then it is not shown).
    @ViewBuilder
    private var peopleStats: some View {
        HalqahStat(value: model.groups.count, labelKey: "Halqahs", systemImage: "person.3.fill")
        if let signedIn = model.signedIn {
            HalqahStat(value: signedIn, labelKey: "Signed in", systemImage: "person.crop.circle.badge.checkmark")
        }
    }

    @ViewBuilder
    private var liveStats: some View {
        HalqahStat(value: liveZikrCount, labelKey: "Live zikr", systemImage: "dot.radiowaves.left.and.right", isLive: liveZikrCount > 0)
        HalqahStat(value: liveMeetingCount, labelKey: "Live meetings", systemImage: "video.fill", isLive: liveMeetingCount > 0)
    }

    private var liveZikrCount: Int {
        model.groups.filter { $0.isLive == true && $0.liveKind != "meeting" }.count
    }

    private var liveMeetingCount: Int {
        model.groups.filter { $0.isLive == true && $0.liveKind == "meeting" }.count
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            HStack(spacing: DISpacing.md) {
                cardSymbol("lock.shield.fill")
                Text("Members only")
                    .font(.headline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text("These groups are for members of Silsila Naqshbandia Owaisiah. Enter the invitation code an administrator gave you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // How the member is known to the Halqah's admins, in the
            // attendance and in the meeting room; Apple gives no name to
            // someone who joins by code.
            TextField("Your name", text: $joinName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)
                .submitLabel(.next)
                .onSubmit { isCodeFocused = true }
            Text("Your name is shown to your Halqah's admins and in the meeting room.")
                .font(.caption)
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
                .tint(DIColor.primary)
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
                    // The name tells an administrator who you are; the
                    // email is how the server recognises its own admins.
                    // Nothing is sent to anyone at that address.
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await model.completeSignIn(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 48)
                .accessibilityLabel("Sign in with Apple to see your private group")
            }
        }
        .halqahCard()
    }

    /// A card's symbol in an emerald circle, beside its heading.
    private func cardSymbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.headline)
            .foregroundStyle(DIColor.onPrimary)
            .frame(width: symbolBox, height: symbolBox)
            .background(Circle().fill(DIGradient.emerald))
            .accessibilityHidden(true)
    }

    /// How the groups work, in the order a member meets it. Open by default
    /// until the member is in a group, then folded away.
    private var howItWorksCard: some View {
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
        .halqahCard(tint: DIColor.accent)
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
                .background(Circle().fill(DIGradient.emerald))
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
        // A second code is added to this account, which keeps its name.
        let name = model.phase == .signedOut ? joinName : nil
        Task {
            await model.redeemInvite(code, name: name)
            if model.inviteError == nil { inviteCode = "" }
        }
    }

    private var trimmedNameDraft: String { nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func saveName() {
        let name = trimmedNameDraft
        guard !name.isEmpty, name != model.displayName else { return }
        Task { await model.rename(name) }
    }

    /// The member's Halqah notices on this phone: posts, zikr and meetings.
    /// A tile with the same switch as ever; its bell says the state at a glance.
    private var noticesCard: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            Toggle(isOn: Binding(
                get: { model.notices == .on },
                set: { on in Task { await model.setNotices(on) } }
            )) {
                HStack(spacing: DISpacing.md) {
                    Image(systemName: noticesSymbol)
                        .font(.headline)
                        .foregroundStyle(model.notices == .on ? DIColor.onPrimary : DIColor.primary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: symbolBox, height: symbolBox)
                        .background {
                            if model.notices == .on {
                                Circle().fill(DIGradient.emerald)
                            } else {
                                Circle().fill(DIColor.primary.opacity(0.12))
                            }
                        }
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Halqah notifications")
                            .font(.subheadline.weight(.semibold))
                        Text("Posts, zikr and meetings from your Halqah, on this phone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(DIColor.primary)
            .disabled(model.isChangingNotices)
            if model.notices == .blocked {
                Text("Notifications are off for Darul Irfan. Allow them in iOS Settings to receive Halqah notifications.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.bordered)
            }
        }
        .halqahCard(tint: DIColor.accent)
    }

    private var noticesSymbol: String {
        switch model.notices {
        case .on: "bell.badge.fill"
        case .off: "bell.fill"
        case .blocked: "bell.slash.fill"
        }
    }

    private var awaitingApprovalCard: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            HStack(spacing: DISpacing.md) {
                cardSymbol("hourglass")
                Text("Waiting to be added")
                    .font(.headline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
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
                .padding(DISpacing.sm)
                .background(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous).fill(DIColor.sandstone.opacity(0.6)))
            }
        }
        .halqahCard()
    }

    private var groupList: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            DISectionHeader(titleKey: "Halqahs", systemImage: "person.3")
            ForEach(model.groups) { group in
                NavigationLink {
                    GroupDetailView(group: group, service: model.service, dependencies: dependencies)
                } label: {
                    halqahRow(group)
                }
                .buttonStyle(HalqahTileButtonStyle())
                // The Super admin's actions on a Halqah sit behind ⋯ rather
                // than as buttons on every card, and in the press-and-hold
                // menu as before.
                .overlay(alignment: .topTrailing) {
                    if model.role == .superadmin {
                        manageMenu(for: group)
                    }
                }
                .contextMenu {
                    if model.role == .superadmin {
                        Button("Rename or describe", systemImage: "pencil") { editing = HalqahEdit(group: group) }
                        Button("Retire this Halqah", systemImage: "archivebox", role: .destructive) { retiring = group }
                    }
                }
                .diScrollReveal()
            }
        }
    }

    /// One Halqah: its emblem, name and description, whether it is live, and
    /// the viewer's role in it.
    private func halqahRow(_ group: MemberGroup) -> some View {
        let managed = model.role == .superadmin
        let layout = typeSize.halqahRowLayout()
        return layout {
            HalqahMonogram(name: group.name, isLive: group.isLive == true)
            VStack(alignment: .leading, spacing: DISpacing.xs) {
                Text(LocalizedStringKey(group.name))
                    .font(.headline)
                    .foregroundStyle(DIColor.textPrimary)
                if let description = group.description {
                    Text(verbatim: description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if group.isLive == true || listRole(of: group) != nil {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: DISpacing.xs) { halqahChips(group) }
                        VStack(alignment: .leading, spacing: DISpacing.xs) { halqahChips(group) }
                    }
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !managed {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DIColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(DISpacing.md)
        // Room at the trailing edge for the Super admin's ⋯ menu.
        .padding(.trailing, managed ? DISpacing.xl : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HalqahGlassSurface(tint: group.isLive == true ? DIColor.primary : DIColor.accent))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func halqahChips(_ group: MemberGroup) -> some View {
        if group.isLive == true {
            HalqahLiveChip(liveIsMeeting: group.liveKind == "meeting")
        }
        if let role = listRole(of: group) {
            HalqahRoleBadge(role: role.role, accessibilityKey: role.spoken)
        }
    }

    /// The viewer's role in a Halqah as the list has always shown it: an
    /// Administrator, or an Admin (also when an older server sends no role
    /// but says they manage it). Members and the Super admin show none here.
    private func listRole(of group: MemberGroup) -> (role: GroupRole, spoken: LocalizedStringKey)? {
        if group.myRole == .administrator {
            return (.administrator, "You are an Administrator of this Halqah")
        }
        if group.myRole == .admin || (group.myRole == nil && group.canManage == true) {
            return (.admin, "You are an Admin of this Halqah")
        }
        return nil
    }

    /// The Super admin's two actions on one Halqah, the same as pressing and
    /// holding it.
    private func manageMenu(for group: MemberGroup) -> some View {
        Menu {
            Button("Rename or describe", systemImage: "pencil") { editing = HalqahEdit(group: group) }
            Button("Retire this Halqah", systemImage: "archivebox", role: .destructive) { retiring = group }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DIColor.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Manage \(group.name)"))
    }

    /// An Administrator's or Admin's role, said once at the top: its badge
    /// symbol, and what the role may do.
    private var roleCard: some View {
        let role = GroupRole(rawValue: model.role.rawValue) ?? .member
        return HStack(alignment: .top, spacing: DISpacing.md) {
            Image(systemName: role.badgeSymbol)
                .font(.headline)
                .foregroundStyle(DIColor.goldGlow)
                .frame(width: symbolBox, height: symbolBox)
                .background(Circle().fill(DIGradient.emerald))
                .accessibilityHidden(true)
            Text(roleSummary)
                .font(.subheadline)
                .foregroundStyle(DIColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .halqahCard()
        .accessibilityElement(children: .combine)
        .diAppear()
    }

    private var roleSummary: LocalizedStringKey {
        switch model.role {
        case .superadmin: "Super admin: everything, in every Halqah. You make Halqahs and place anyone in any of them."
        case .administrator: "Administrator: you run your Halqah, its people and its Admins, and appoint Administrators."
        case .admin, .member: "Admin: you run your Halqah - posts, zikr, meetings and people - and can make other Admins."
        }
    }

    private var addCodeCard: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            HStack(spacing: DISpacing.md) {
                cardSymbol("key.fill")
                Text("Have another invitation code?")
                    .font(.subheadline.weight(.semibold))
            }
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
                .tint(DIColor.primary)
                .disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isRedeeming)
            }
            if let inviteError = model.inviteError {
                Text(verbatim: inviteError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .halqahCard(tint: DIColor.accent)
    }

    private func failureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            Text(message)
                .font(.subheadline)
            Button("Try again") { Task { await model.refresh() } }
                .buttonStyle(.bordered)
        }
        .halqahCard(tint: DIColor.danger)
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            if model.phase == .ready {
                HStack(spacing: DISpacing.md) {
                    accountMonogram
                    Text("Your name")
                        .font(.subheadline.weight(.semibold))
                }
                HStack(spacing: DISpacing.sm) {
                    TextField("Your name", text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.name)
                        .submitLabel(.done)
                        .onSubmit(saveName)
                    Button("Save", action: saveName)
                        .buttonStyle(.bordered)
                        .tint(DIColor.primary)
                        .disabled(model.isSavingName || trimmedNameDraft.isEmpty || trimmedNameDraft == (model.displayName ?? ""))
                }
                Text("Your name is shown to your Halqah's admins and in the meeting room.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let nameError = model.nameError {
                    Text(verbatim: nameError)
                        .font(.footnote)
                        .foregroundStyle(DIColor.danger)
                }
                Divider()
            }
            Button {
                Task { await model.signOut() }
            } label: {
                accountRow("Sign out", systemImage: "rectangle.portrait.and.arrow.right", tint: DIColor.primary, mirrors: true)
            }
            .buttonStyle(HalqahTileButtonStyle())
            // Apple requires an account made in the app to be deletable
            // inside it, and a member should not have to hunt for it.
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                if model.isDeleting {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    accountRow("Delete my account", systemImage: "trash", tint: DIColor.danger)
                }
            }
            .buttonStyle(HalqahTileButtonStyle())
            .disabled(model.isDeleting)
            Text("Deleting removes your sign-in and your place in every group. Nothing the silsila published is affected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .halqahCard()
        .confirmationDialog("Delete your account?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await model.deleteAccount() } }
            Button("Keep my account", role: .cancel) {}
        } message: {
            Text("Your sign-in and your group memberships are removed. An administrator would have to add you again.")
        }
    }

    /// The member's initials, from the name they gave; a person while they
    /// have given none.
    private var accountMonogram: some View {
        let initials = (model.displayName ?? "")
            .split(separator: " ")
            .prefix(2)
            .compactMap { word in word.first.map { String($0).uppercased() } }
            .joined()
        return ZStack {
            Circle().fill(DIGradient.emerald)
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.headline)
            } else {
                Text(verbatim: initials)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .foregroundStyle(DIColor.onPrimary)
        .frame(width: symbolBox, height: symbolBox)
        .accessibilityHidden(true)
    }

    /// An account action as a row: its symbol in a circle, then its name.
    /// `mirrors` turns an arrow to point the way Urdu reads.
    private func accountRow(_ titleKey: LocalizedStringKey, systemImage: String, tint: Color, mirrors: Bool = false) -> some View {
        HStack(spacing: DISpacing.md) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .flipsForRightToLeftLayoutDirection(mirrors)
                .frame(width: symbolBox, height: symbolBox)
                .background(Circle().fill(tint.opacity(0.12)))
                .accessibilityHidden(true)
            Text(titleKey)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
