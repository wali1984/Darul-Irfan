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

    /// The member's Halqah notices on this phone: on, off, or blocked in
    /// iOS Settings.
    typealias Notices = HalqahNoticesModel.Status

    let service: MemberGroupService
    /// The Halqah notices switch. The Halqah tab hands it to Settings >
    /// Notifications, so both show the same state.
    let noticesModel: HalqahNoticesModel
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

    /// Asked once, after joining, whether to show the Halqah's notices here.
    var offerNotices = false
    private static let askedKey = "halqah.notices.asked"

    /// The member's own name, as their Halqah's admins and the meeting room
    /// show it.
    var displayName: String?
    var isSavingName = false
    var nameError: String?

    /// Whether the Halqah tab has shown the groups yet (see `appear`).
    @ObservationIgnored private var hasAppeared = false

    init() {
        let service = MemberGroupService()
        self.service = service
        noticesModel = HalqahNoticesModel(service: service)
    }

    /// The member's Halqah notices on this phone.
    var notices: Notices { noticesModel.status }
    var isChangingNotices: Bool { noticesModel.isChanging }

    /// Registers the phone for the notices; set by the page.
    var platform: OfficialPlatformService? {
        get { noticesModel.platform }
        set { noticesModel.platform = newValue }
    }

    /// Signed in on this phone as far as the page knows: the groups loaded,
    /// or failed to, which keeps the account's controls in reach.
    var showsAccount: Bool {
        switch phase {
        case .ready, .failed: return true
        case .signedOut, .loading: return false
        }
    }

    func start() async {
        guard await service.isSignedIn else {
            phase = .signedOut
            return
        }
        await refresh()
    }

    /// For the Halqah tab, which shows the groups at its root. The first
    /// appearance loads them; each return checks again quietly, so the top
    /// of the tab neither empties nor jumps every time it is shown.
    func appear() async {
        guard hasAppeared else {
            hasAppeared = true
            await start()
            return
        }
        await checkAgain()
    }

    /// Checks again without emptying the page: signed out stays signed out
    /// with no spinner, and a loaded list stays while it is checked.
    func checkAgain() async {
        guard await service.isSignedIn else {
            groups = []
            signedIn = nil
            phase = .signedOut
            return
        }
        await refresh(quietly: true)
    }

    /// Loads the member's groups. `quietly` keeps a loaded list on screen
    /// while it is checked, and keeps it when the check fails; otherwise the
    /// page shows its spinner and any failure, as it always has.
    func refresh(quietly: Bool = false) async {
        let keepsList = quietly && phase == .ready
        if !keepsList { phase = .loading }
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
            Task { await self.noticesModel.follow() }
        } catch MemberGroupError.notSignedIn {
            groups = []
            signedIn = nil
            phase = .signedOut
        } catch {
            if !keepsList { phase = .failed(error.localizedDescription) }
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
        noticesModel.reset()
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
        await noticesModel.set(on)
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
            noticesModel.reset()
            phase = .signedOut
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

/// The private groups on a page of their own: where a Halqah notification
/// lands when its Halqah cannot be shown (signed out, or no longer in it).
/// The Halqah tab shows the same sections at its root.
@MainActor
struct GroupsHomeView: View {
    var dependencies: AppDependencies? = nil
    @State private var model = GroupsModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                MyHalqahsSection(model: model, dependencies: dependencies, explainsWhenJoined: true)
                if model.showsAccount {
                    HalqahAccountSection(model: model)
                }
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
    }
}
