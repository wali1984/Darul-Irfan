import SwiftUI
import AuthenticationServices

@MainActor
struct OurSheikhEntryView: View {
    let service: MemberGroupService
    let dependencies: AppDependencies
    @State private var identity: SheikhVisitorIdentity?
    @State private var profile = SheikhVisitorProfile()
    @State private var group: MemberGroup?
    @State private var busy = true
    @State private var locating = false
    @State private var error: String?
    @State private var notices = HalqahNoticesModel()
    @State private var offerNotices = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let group {
                GroupDetailView(group: group, service: service, dependencies: dependencies)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Join Daily Zikr").diInterfaceFont(.title2, weight: .bold)
                        TextField("Name", text: $profile.name).textContentType(.name)
                        TextField("City", text: $profile.city).textContentType(.addressCity)
                        Button("Use my location") { Task { await suggestLocation() } }
                            .disabled(busy || locating)
                        if locating { ProgressView() }
                        Picker("Country", selection: $profile.countryCode) {
                            Text("Select country").tag("")
                            ForEach(Locale.isoRegionCodes.sorted(by: { country($0) < country($1) }), id: \.self) { code in
                                Text(verbatim: country(code)).tag(code)
                            }
                        }
                        TextField("Email (optional)", text: $profile.email)
                            .textContentType(.emailAddress).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            Task { await signIn(result) }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 48)
                        .disabled(busy || locating)
                        if let error { Text(verbatim: error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                        if busy { ProgressView() }
                        Button("Join Daily Zikr") { Task { await join() } }
                            .buttonStyle(DIPrimaryButtonStyle())
                            .disabled(busy || identity == nil || profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || profile.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || profile.countryCode.isEmpty)
                        if identity == nil && !busy {
                            Button("Retry") { Task { await load() } }
                        }
                    }
                    .disabled(busy)
                    .textFieldStyle(.roundedBorder)
                    .padding(24)
                    .diGlassPanel(cornerRadius: 26)
                    .overlay(RoundedRectangle(cornerRadius: 26).stroke(DIColor.goldGlow.opacity(0.45), lineWidth: 1))
                    .padding(16)
                }
                .background(DIColor.background)
                .navigationTitle("Our Sheikh")
            }
        }
        .task { await load() }
        .onDisappear { saveDraft() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveDraft() }
        }
        .task(id: "\(group?.id ?? "")-\(scenePhase)") {
            guard group != nil, scenePhase == .active else { return }
            notices.platform = dependencies.officialPlatform
            await notices.follow()
            if !HalqahNoticeChoice.isTurnedOff,
               !UserDefaults.standard.bool(forKey: "halqah.notices.asked"),
               await NotificationPermission.current() == .notAsked {
                UserDefaults.standard.set(true, forKey: "halqah.notices.asked")
                offerNotices = true
            }
        }
        .alert("Turn on Halqah notifications?", isPresented: $offerNotices) {
            Button("Turn on") { Task { await notices.set(true) } }
            Button("Not now", role: .cancel) { }
        } message: {
            Text("Your Halqah's posts, zikr and meetings will be shown on this phone.")
        }
    }

    private func country(_ code: String) -> String { locale.localizedString(forRegionCode: code) ?? code }

    private func saveDraft() {
        guard group == nil, let identity, profile != identity.profile else { return }
        do { try SheikhVisitorStore.saveDraft(profile, matching: identity.guestSecret) }
        catch { self.error = error.localizedDescription }
    }

    private func signIn(_ result: Result<ASAuthorization, Error>) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let token = credential.identityToken else { throw MemberGroupError.signInRejected }
            let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            _ = try await service.signIn(identityToken: token, displayName: name)
            if profile.name.isEmpty, let name { profile.name = name }
            if profile.email.isEmpty, let email = credential.email { profile.email = email }
            if let existing = try await service.groups().groups.first(where: { $0.id == "our-sheikh" }) { group = existing }
        } catch let failure as ASAuthorizationError where failure.code == .canceled { }
        catch { self.error = error.localizedDescription }
    }

    private func suggestLocation() async {
        locating = true; error = nil
        let previousCity = profile.city
        let previousCountry = profile.countryCode
        defer { locating = false }
        do {
            let place = try await dependencies.location.currentPlace()
            // A late location response must not overwrite manual edits.
            if profile.city == previousCity { profile.city = place.name }
            if profile.countryCode == previousCountry, let code = place.countryCode,
               Locale.isoRegionCodes.contains(code.uppercased()) { profile.countryCode = code.uppercased() }
        } catch { self.error = String(localized: "Location unavailable. Enter your city and country manually.") }
    }

    private func load() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            // Existing members/admins enter with authoritative server roles.
            if await service.isSignedIn, let existing = try await service.groups().groups.first(where: { $0.id == "our-sheikh" }) {
                group = existing
                return
            }
            let saved = try SheikhVisitorStore.loadOrCreate()
            identity = saved; profile = saved.profile
            let currentMember = await service.memberID
            if saved.canResume(as: currentMember) { await join() }
        } catch { self.error = error.localizedDescription }
    }

    private func join() async {
        guard var saved = identity else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            saved.profile = profile
            try SheikhVisitorStore.save(saved)
            let previousMember = await service.memberID
            let joiningAsGuest = previousMember == nil || (saved.admittedAsGuest == true && previousMember == saved.admittedMemberID)
            let admittedMember = try await service.joinOurSheikh(name: profile.name, city: profile.city, countryCode: profile.countryCode,
                email: profile.email, guestSecret: saved.guestSecret)
            saved.admitted = true
            saved.admittedMemberID = admittedMember
            saved.admittedAsGuest = joiningAsGuest
            try SheikhVisitorStore.save(saved)
            identity = saved
            guard let joined = try await service.groups().groups.first(where: { $0.id == "our-sheikh" }) else { throw MemberGroupError.requestFailed }
            group = joined
        } catch { self.error = error.localizedDescription }
    }
}
