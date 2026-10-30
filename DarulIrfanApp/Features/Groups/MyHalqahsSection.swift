import AuthenticationServices
import SwiftUI
import UIKit

/// My Halqahs: the member's private groups at the top of the Halqah tab, so a
/// Halqah is two taps from launch, and on the groups page a notification
/// falls back to.
///
/// Signed out: the join card (name, invitation code, Sign in with Apple),
/// with "How private groups work" folded. Signed in: the Super admin's
/// dashboard on top for the Super admin (an Administrator's or Admin's role
/// for them), each Halqah as a hero card with a live row and Join while its
/// zikr or a meeting is live, or "Waiting to be added"; "Have another
/// invitation code?"; and the Halqah notifications switch.
@MainActor
struct MyHalqahsSection: View {
    @Bindable var model: GroupsModel
    var dependencies: AppDependencies? = nil
    /// Keeps "How private groups work" for a member already in a Halqah (the
    /// groups page); the tab offers it only until then.
    var explainsWhenJoined = false

    @State private var inviteCode = ""
    /// The name a member joining by code gives.
    @State private var joinName = ""
    @State private var isShowingHowItWorks = false
    @State private var isAddingCode = false
    @State private var editing: HalqahEdit?
    @State private var retiring: MemberGroup?
    @State private var retireError: String?
    @FocusState private var isCodeFocused: Bool
    /// The symbol circles beside card headings, grown with the text.
    @ScaledMetric(relativeTo: .headline) private var symbolBox: CGFloat = 38

    /// A Halqah being made (nil group) or edited, by the Super admin.
    private struct HalqahEdit: Identifiable {
        var group: MemberGroup?
        var id: String { group?.id ?? "new" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            HalqahSectionLabel(titleKey: "My Halqahs")
            content
        }
        .alert("Turn on Halqah notifications?", isPresented: $model.offerNotices) {
            Button("Turn on") { Task { await model.setNotices(true) } }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Your Halqah's posts, zikr and meetings will be shown on this phone.")
        }
        .sheet(item: $editing, onDismiss: { Task { await model.refresh(quietly: true) } }) { edit in
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
                    await model.refresh(quietly: true)
                }
            }
        } message: { _ in
            Text("It disappears for everyone. Its people, posts and history are kept.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .signedOut:
            signInCard
            howItWorksCard
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, DISpacing.lg)
        case .ready:
            readyContent
        case .failed(let message):
            failureCard(message)
            howItWorksCard
        }
    }

    @ViewBuilder
    private var readyContent: some View {
        // The Super admin's dashboard says their role; an Administrator or
        // Admin sees theirs on its own card.
        if model.role == .superadmin {
            superAdminDashboard
        } else if model.role != .member {
            roleCard
        }
        if model.groups.isEmpty {
            awaitingApprovalCard
        } else {
            groupList
        }
        // Another code (a second group, or an admin role) adds to this same
        // account.
        addCodeRow
        if !model.groups.isEmpty {
            noticesCard
        }
        if model.groups.isEmpty || explainsWhenJoined {
            howItWorksCard
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

    // MARK: Signed out

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

            // The code is the primary way in: it needs nothing from Apple,
            // so it works the same on every platform, and admission stays an
            // administrator's decision.
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
        .myHalqahsPanel()
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

    /// How the groups work, in the order a member meets it: folded, one tap
    /// away, so the join card leads.
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
        .myHalqahsPanel()
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
            if model.inviteError == nil {
                inviteCode = ""
                isAddingCode = false
            }
        }
    }

    // MARK: Signed in

    /// The member's Halqah notices on this phone: posts, zikr and meetings.
    /// The same switch as Settings > Notifications; its bell says the state
    /// at a glance.
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
        .myHalqahsPanel()
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
        .myHalqahsPanel()
    }

    /// Each Halqah as a hero card. The whole card opens the Halqah; while
    /// its zikr or a meeting is live, the card's live row says so beside
    /// Join, and the Halqah's page joins it.
    private var groupList: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            ForEach(model.groups) { group in
                NavigationLink {
                    GroupDetailView(group: group, service: model.service, dependencies: dependencies)
                } label: {
                    HalqahHeroCardLabel(
                        group: group,
                        role: listRole(of: group)?.role,
                        roleSpoken: listRole(of: group)?.spoken,
                        leavesRoomForMenu: model.role == .superadmin
                    )
                }
                .buttonStyle(HalqahTileButtonStyle())
                // The Super admin's actions on a Halqah sit behind the menu
                // rather than as buttons on every card, and in the
                // press-and-hold menu as before.
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
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(DISpacing.xs)
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
        .myHalqahsPanel()
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

    /// "Have another invitation code?" as one row, as the board draws it;
    /// the code field opens under it when tapped.
    private var addCodeRow: some View {
        VStack(alignment: .leading, spacing: DISpacing.sm) {
            Button {
                isAddingCode.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isAddingCode ? "minus" : "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DIColor.primary)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text("Have another invitation code?")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(DIColor.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isAddingCode {
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
        }
        .padding(.horizontal, DISpacing.md)
        .padding(.bottom, isAddingCode ? DISpacing.md : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .diGlassPanel(cornerRadius: 22)
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
}

// MARK: - Hero card

/// One Halqah as the board draws it: the emerald hero with drifting light
/// and a slowly turning star, the Halqah's name and what it is, the viewer's
/// role, and, while its zikr or a meeting is live, a row with Join. The card
/// opens the Halqah, whose page joins the session (sessions end only when an
/// admin ends them; nothing here ends one).
struct HalqahHeroCardLabel: View {
    let group: MemberGroup
    /// The viewer's role in it, when the list shows one, and what VoiceOver
    /// says for it.
    var role: GroupRole? = nil
    var roleSpoken: LocalizedStringKey? = nil
    /// Room at the trailing edge for the Super admin's menu.
    var leavesRoomForMenu = false

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title2) private var iconSide: CGFloat = 48

    private static let joinGold = LinearGradient(
        colors: [Color(hex: 0xFFE9A8), Color(hex: 0xE0B75F)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if group.isLive == true {
                liveRow
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { HalqahHeroBackdrop(isLive: group.isLive == true) }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        let layout = typeSize.halqahRowLayout(spacing: 12)
        return layout {
            Image(systemName: "person.3.fill")
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(width: iconSide, height: iconSide)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(group.name))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.white)
                if let description = group.description, !description.isEmpty {
                    Text(verbatim: description)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                if let role {
                    HalqahRoleBadge(role: role, onGlass: true, accessibilityKey: roleSpoken)
                        .padding(.top, DISpacing.xs)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !leavesRoomForMenu && !typeSize.isAccessibilitySize {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .accessibilityHidden(true)
            }
        }
        .padding(.trailing, leavesRoomForMenu ? DISpacing.xl : 0)
    }

    /// While live: the red light, what is live, and Join in gold.
    private var liveRow: some View {
        HStack(spacing: 10) {
            DILivePulse(color: Color(hex: 0xFF5C5C), size: 9)
            Text(group.liveKind == "meeting" ? "Meeting live" : "Zikr live")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.white)
            Spacer(minLength: DISpacing.sm)
            Text("Join")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(hex: 0x064B34))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(Self.joinGold))
                .diShimmer()
                .shadow(color: DIColor.goldGlow.opacity(0.5), radius: 8)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }
}

/// The hero card's surface: the shared emerald hero with its aurora, the
/// Silsila's star turning slowly in its corner, and a gold edge.
private struct HalqahHeroBackdrop: View {
    var isLive: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        ZStack {
            DIHeroBackground(cornerRadius: 28)
            Color.clear
                .overlay(alignment: .topTrailing) {
                    HalqahTurningStar(color: DIColor.goldGlow, lineWidth: 1.6, period: 90)
                        .frame(width: 220, height: 220)
                        .opacity(0.16)
                        .offset(x: 70, y: -60)
                }
                .clipShape(shape)
            shape
                .strokeBorder(Color(hex: 0xE0B75F).opacity(isLive ? 0.85 : 0.6), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension View {
    /// A card of My Halqahs, on the redesign's glass.
    func myHalqahsPanel() -> some View {
        self
            .padding(DISpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .diGlassPanel(cornerRadius: 24)
    }
}
